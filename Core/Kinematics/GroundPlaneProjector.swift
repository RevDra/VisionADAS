import Foundation
import CoreGraphics

/// Filtered state output from the Kalman filter
public struct LeadVehicleState {
    public let distance: Double        // meters
    public let relativeVelocity: Double // m/s (negative = approaching)
    public let relativeAcceleration: Double // m/s²
    public let absoluteSpeedKmh: Double // km/h
    public let timeToCollision: Double? // seconds, nil if not closing
    public let headwaySeconds: Double?  // seconds, nil if host stationary
}

/// A single object detection from YOLO inference
public struct Detection: Identifiable {
    public let id = UUID()
    public let label: String
    public let confidence: Float
    /// Bounding box in full-frame normalized coordinates (origin top-left, 0..1)
    public let boundingBox: CGRect
    /// Bottom edge Y in full-frame normalized coords (0=top, 1=bottom) — tire contact point
    public let bottomY: CGFloat
}

/// Ground-plane ray casting for monocular distance estimation.
public struct GroundPlaneProjector {
    public static let defaultCameraHeight: Double = 1.35 // meters
    public static let defaultFocalLengthPx: Double = 1450.0 // pixels
    public static let defaultHorizonY: Double = 540.0 // pixels in 1080p frame
    
    public static let minDistance: Double = 2.0
    public static let maxDistance: Double = 120.0
    
    /// Estimates distance to a target given its bottom edge Y coordinate and the camera's dynamic pitch.
    /// - Parameters:
    ///   - bottomY: Normalized bottom Y coordinate (0 = top, 1 = bottom)
    ///   - pitchRad: Dynamic camera pitch in radians
    ///   - frameHeight: Height of the image frame in pixels (default 1080.0)
    /// - Returns: Estimated distance in meters clamped to [2.0, 120.0]
    public static func estimateDistance(
        bottomY: Double,
        pitchRad: Double,
        frameHeight: Double = 1080.0
    ) -> Double {
        let yBottomPixel = bottomY * frameHeight
        let deltaY = yBottomPixel - defaultHorizonY
        let effectiveDeltaY = deltaY + (defaultFocalLengthPx * tan(pitchRad))
        
        if effectiveDeltaY <= 0 {
            return maxDistance
        }
        
        let distance = (defaultCameraHeight * defaultFocalLengthPx) / effectiveDeltaY
        return min(maxDistance, max(minDistance, distance))
    }
}
