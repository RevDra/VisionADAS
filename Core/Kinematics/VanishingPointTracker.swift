import Foundation
import CoreGraphics

/// Dynamically calculates and tracks the optical Vanishing Point (Point of Infinity)
/// to serve as an invariant anchor for distance projection and lane perspective.
public final class VanishingPointTracker {
    
    // Default 1080p center
    public private(set) var vpX: Double = 960.0
    public private(set) var vpY: Double = 530.0
    
    private let focalLengthY: Double = 1450.0
    private let frameHeight: Double = 1080.0
    private let frameWidth: Double = 1920.0
    
    // Calibration baseline
    private var pitchBaseline: Double? = nil
    private let smoothingAlpha: Double = 0.05
    
    public init() {}
    
    /// Updates the vanishing point using IMU pitch dynamics and distant vehicle anchors.
    /// - Parameters:
    ///   - currentPitchRad: Raw pitch from CoreMotion in radians.
    ///   - distantDetections: Vehicles detected far down the road.
    ///   - hostSpeedKmh: Current vehicle speed.
    public func update(
        currentPitchRad: Double,
        distantDetections: [Detection],
        hostSpeedKmh: Double
    ) {
        // 1. Establish steady-state pitch baseline during cruise (> 20 km/h)
        if hostSpeedKmh > 20.0 {
            if let baseline = pitchBaseline {
                pitchBaseline = (0.998 * baseline) + (0.002 * currentPitchRad)
            } else {
                pitchBaseline = currentPitchRad
            }
        }
        
        // 2. High-frequency suspension tilt compensation (pitch delta)
        var dynamicVpY = 530.0
        if let baseline = pitchBaseline {
            let deltaPitch = currentPitchRad - baseline
            // Shifting optical horizon: dy = f_y * tan(delta_theta)
            let pixelShift = focalLengthY * tan(deltaPitch)
            dynamicVpY += pixelShift
        }
        
        // 3. Absolute vision ground truth anchor:
        // Distant vehicles (small bounding boxes) touch the ground at the vanishing horizon.
        let horizonCandidates = distantDetections.filter { det in
            det.boundingBox.height < 0.05 && det.boundingBox.midX > 0.35 && det.boundingBox.midX < 0.65
        }
        
        if let anchorVehicle = horizonCandidates.first {
            let visualHorizonY = Double(anchorVehicle.bottomY) * frameHeight - 4.0
            // Gently pull the tracker toward the physical ground truth
            dynamicVpY = (0.92 * dynamicVpY) + (0.08 * visualHorizonY)
        }
        
        // Clamp to safe vertical windshield range (42% to 58% of screen height)
        let minY = frameHeight * 0.42
        let maxY = frameHeight * 0.58
        let clampedY = max(minY, min(maxY, dynamicVpY))
        
        // Smooth transitions
        self.vpY = (1.0 - smoothingAlpha) * self.vpY + (smoothingAlpha * clampedY)
        self.vpX = frameWidth * 0.50
    }
    
    /// Calculates the dynamic lane corridor boundary at a given Y coordinate
    /// using rays radiating from the Vanishing Point.
    public func isInsideLane(box: CGRect) -> Bool {
        let bottomYPx = box.maxY * frameHeight
        guard bottomYPx > vpY else { return false }
        
        // Distance down from vanishing point (0.0 at horizon, 1.0 at bumper)
        let t = (bottomYPx - vpY) / (frameHeight * 0.82 - vpY)
        let clampedT = max(0.0, min(1.2, t))
        
        // Lane expands from 12% width at infinity to 38% width at hood
        let halfWidthNorm = 0.06 + (0.19 * clampedT)
        let vpXNorm = vpX / frameWidth
        
        return abs(box.midX - vpXNorm) <= halfWidthNorm
    }
}