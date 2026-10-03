import Foundation
import CoreGraphics

/// Tracks optical vanishing point and manages ground plane calibration and lane funneling.
public class OnlineCalibrator {
    public let frameHeight: Double = 1080.0
    public let frameWidth: Double = 1920.0
    public let focalLengthY: Double = 1450.0

    public private(set) var vpX: Double = 960.0 // frameWidth * 0.50
    public private(set) var vpY: Double = 530.0
    
    public private(set) var calibrationPercent: Int = 0

    private var pitchBaseline: Double? = nil
    private var calibrationSamples: Int = 0
    private let sampleTarget: Int = 150

    public init() {}

    public var vpYNormalized: Double {
        return vpY / frameHeight
    }

    /// Updates the calibration state based on current vehicle kinematics and distant visual detections.
    public func update(currentPitchRad: Double, distantDetections: [Detection], hostSpeedKmh: Double) {
        // 1. Establish steady-state pitch baseline during cruise
        if hostSpeedKmh > 20.0 {
            if let baseline = pitchBaseline {
                pitchBaseline = 0.998 * baseline + 0.002 * currentPitchRad
            } else {
                pitchBaseline = currentPitchRad
            }

            // 6. Track calibration samples
            if calibrationSamples < sampleTarget {
                calibrationSamples += 1
                calibrationPercent = min(100, Int((Double(calibrationSamples) / Double(sampleTarget)) * 100.0))
            }
        }

        // 2. High-frequency suspension tilt compensation
        var dynamicVpY = 530.0
        if let baseline = pitchBaseline {
            let deltaPitch = currentPitchRad - baseline
            let pixelShift = focalLengthY * tan(deltaPitch)
            dynamicVpY += pixelShift
        }

        // 3. Vision ground truth anchor
        let anchorVehicle = distantDetections.filter { box in
            box.boundingBox.height < 0.05 && 
            box.boundingBox.midX >= 0.35 && 
            box.boundingBox.midX <= 0.65
        }.min(by: { $0.bottomY < $1.bottomY })
        
        if let anchor = anchorVehicle {
            let visualHorizonY = anchor.bottomY * frameHeight - 4.0
            dynamicVpY = 0.92 * dynamicVpY + 0.08 * visualHorizonY
        }

        // 4. Clamp vpY to safe range
        let minVpY = frameHeight * 0.42
        let maxVpY = frameHeight * 0.58
        let clampedY = max(minVpY, min(maxVpY, dynamicVpY))

        // 5. Smooth
        vpY = (1.0 - 0.05) * vpY + 0.05 * clampedY
    }

    /// Determines if a detected bounding box is inside the host lane funnel radiating from the VP.
    public func isInsideLaneFunnel(box: CGRect) -> Bool {
        let bottomYPx = box.maxY * frameHeight
        
        // Guard: bottomYPx must be > vpY (below horizon)
        guard bottomYPx > vpY else {
            return false
        }

        // Normalized distance from VP to bottom of frame
        var t = (bottomYPx - vpY) / (frameHeight * 0.82 - vpY)
        t = max(0.0, min(1.2, t))

        // 12% width at horizon → ~38% at hood
        let halfWidthNorm = 0.06 + 0.13 * t
        let vpXNorm = vpX / frameWidth

        let midX = box.midX
        
        // Vehicle center must be within vpXNorm ± halfWidthNorm
        return midX >= (vpXNorm - halfWidthNorm) && midX <= (vpXNorm + halfWidthNorm)
    }
}