import Foundation
import CoreGraphics

public struct LeadVehicleState {
    public let distance: Double
    public let relativeVelocity: Double
    public let relativeAcceleration: Double
    public let absoluteSpeedKmh: Double
    public let timeToCollision: Double?
    public let headwaySeconds: Double?
    public let isStationary: Bool
}

public struct Detection: Identifiable {
    public let id = UUID()
    public let label: String
    public let confidence: Float
    public let boundingBox: CGRect
    public let bottomY: CGFloat
}

public struct GroundPlaneProjector {
    public static let cameraHeightM: Double = 1.30
    public static let focalLengthPx: Double = 1450.0
    public static let horizonYPx: Double = 530.0
    
    public static let minDistance: Double = 3.0
    public static let maxDistance: Double = 85.0 // Reliable on-device vision ceiling
    
    public static func estimateDistance(
        bottomY: Double,
        frameHeight: Double = 1080.0
    ) -> Double {
        let yBottomPixel = bottomY * frameHeight
        let deltaY = yBottomPixel - horizonYPx
        
        // Guard: Objects within 8px of horizon are at the visual horizon limit
        guard deltaY > 8.0 else {
            return maxDistance
        }
        
        let distance = (cameraHeightM * focalLengthPx) / deltaY
        return min(maxDistance, max(minDistance, distance))
    }
}