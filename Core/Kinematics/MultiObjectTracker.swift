import Foundation
import CoreGraphics

public struct TrackedVehicle {
    public let trackId: Int
    public let detection: Detection   // latest matched detection
    public let state: LeadVehicleState // Kalman-filtered state
    public let hitCount: Int           // consecutive successful matches
    public let isInLane: Bool          // inside host lane funnel
    public let age: Int                // total frames since track creation
}

public class MultiObjectTracker {
    
    private class Track {
        let trackId: Int
        let kalmanFilter: LeadKalmanFilter
        var lastDetection: Detection
        var lastState: LeadVehicleState?
        var hitCount: Int = 1
        var missCount: Int = 0
        var age: Int = 1
        var isInLane: Bool = false
        var predictedBox: CGRect

        init(trackId: Int, kalmanFilter: LeadKalmanFilter, detection: Detection) {
            self.trackId = trackId
            self.kalmanFilter = kalmanFilter
            self.lastDetection = detection
            self.predictedBox = detection.boundingBox
        }
    }

    private var tracks: [Track] = []
    private var nextId: Int = 0
    
    private let iouThreshold: Double = 0.25
    private let maxMisses: Int = 12
    private let minHitsToConfirm: Int = 3

    public init() {}

    /// Main tracking loop to update tracked objects with new detections
    public func update(
        detections: [Detection],
        hostSpeedKmh: Double,
        timestamp: TimeInterval,
        vpY: Double,
        calibrator: OnlineCalibrator
    ) -> [TrackedVehicle] {
        
        // 1. Predict
        for track in tracks {
            // Simple velocity-based prediction matching previous box as-is for IoU overlap
            track.predictedBox = track.lastDetection.boundingBox
        }

        // 2. Match (Greedy IoU Assignment)
        var matches: [(trackIndex: Int, detectionIndex: Int, iou: Double)] = []
        for (tIdx, track) in tracks.enumerated() {
            for (dIdx, det) in detections.enumerated() {
                let overlap = iou(track.predictedBox, det.boundingBox)
                if overlap > iouThreshold {
                    matches.append((tIdx, dIdx, overlap))
                }
            }
        }
        
        // Descending IoU order
        matches.sort { $0.iou > $1.iou }

        var matchedTracks = Set<Int>()
        var matchedDetections = Set<Int>()
        var validMatches: [(trackIndex: Int, detectionIndex: Int)] = []

        for match in matches {
            if !matchedTracks.contains(match.trackIndex) && !matchedDetections.contains(match.detectionIndex) {
                validMatches.append((match.trackIndex, match.detectionIndex))
                matchedTracks.insert(match.trackIndex)
                matchedDetections.insert(match.detectionIndex)
            }
        }

        // 3. Update matched tracks
        for match in validMatches {
            let track = tracks[match.trackIndex]
            let det = detections[match.detectionIndex]

            let distance = GroundPlaneProjector.estimateAnchoredDistance(
                boxHeightNorm: Double(det.boundingBox.height),
                bottomYNorm: Double(det.bottomY),
                vpY: vpY,
                label: det.label
            )

            // Update dedicated Kalman filter (returns LeadVehicleState)
            let state = track.kalmanFilter.update(
                measuredDistance: distance,
                hostSpeedKmh: hostSpeedKmh,
                timestamp: timestamp
            )
            track.lastState = state
            
            // Update tracking counters and data
            track.lastDetection = det
            track.hitCount += 1
            track.missCount = 0
            track.age += 1
            track.isInLane = calibrator.isInsideLaneFunnel(box: det.boundingBox)
        }

        // 4. Coast unmatched tracks
        for tIdx in tracks.indices.reversed() {
            if !matchedTracks.contains(tIdx) {
                let track = tracks[tIdx]
                let coastedState = track.kalmanFilter.coast(
                    timestamp: timestamp,
                    hostSpeedKmh: hostSpeedKmh
                )
                track.lastState = coastedState
                
                track.missCount += 1
                track.hitCount = 0
                track.age += 1
                
                if track.missCount > maxMisses || coastedState == nil {
                    tracks.remove(at: tIdx)
                }
            }
        }

        // 5. Spawn new tracks from unmatched detections
        for (dIdx, det) in detections.enumerated() {
            if !matchedDetections.contains(dIdx) {
                let distance = GroundPlaneProjector.estimateAnchoredDistance(
                    boxHeightNorm: Double(det.boundingBox.height),
                    bottomYNorm: Double(det.bottomY),
                    vpY: vpY,
                    label: det.label
                )

                let kf = LeadKalmanFilter()
                let state = kf.update(
                    measuredDistance: distance,
                    hostSpeedKmh: hostSpeedKmh,
                    timestamp: timestamp
                )
                
                let newTrack = Track(trackId: nextId, kalmanFilter: kf, detection: det)
                newTrack.lastState = state
                newTrack.isInLane = calibrator.isInsideLaneFunnel(box: det.boundingBox)
                tracks.append(newTrack)
                nextId += 1
            }
        }

        // 6. Return confirmed tracks sorted by distance
        var confirmed: [TrackedVehicle] = []
        for track in tracks {
            if track.hitCount >= minHitsToConfirm || track.age > 5 {
                if let state = track.lastState {
                    let tv = TrackedVehicle(
                        trackId: track.trackId,
                        detection: track.lastDetection,
                        state: state,
                        hitCount: track.hitCount,
                        isInLane: track.isInLane,
                        age: track.age
                    )
                    confirmed.append(tv)
                }
            }
        }
        
        confirmed.sort { $0.state.distance < $1.state.distance }
        return confirmed
    }

    /// Selects the closest valid lead vehicle from currently tracked vehicles
    public func selectLeadVehicle(hostSpeedKmh: Double) -> TrackedVehicle? {
        var confirmed: [TrackedVehicle] = []
        
        for track in tracks {
            if track.hitCount >= minHitsToConfirm || track.age > 5 {
                if let state = track.lastState {
                    let tv = TrackedVehicle(
                        trackId: track.trackId,
                        detection: track.lastDetection,
                        state: state,
                        hitCount: track.hitCount,
                        isInLane: track.isInLane,
                        age: track.age
                    )
                    confirmed.append(tv)
                }
            }
        }
        
        confirmed.sort { $0.state.distance < $1.state.distance }
        
        return confirmed.first { tv in
            if hostSpeedKmh > 15.0 {
                return tv.isInLane && tv.state.absoluteSpeedKmh > 6.0 && tv.state.distance > 3.0
            } else {
                return tv.isInLane && tv.state.distance > 3.0
            }
        }
    }

    // MARK: - Private Helpers

    /// Computes Intersection over Union (IoU) of two bounding boxes.
    private func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let intersection = a.intersection(b)
        if intersection.isNull {
            return 0.0
        }
        
        let interArea = intersection.width * intersection.height
        let aArea = a.width * a.height
        let bArea = b.width * b.height
        let unionArea = aArea + bArea - interArea
        
        return unionArea > 0 ? Double(interArea / unionArea) : 0.0
    }
}
