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
    // Optical & Mount Calibration
    public static let cameraHeightM: Double = 1.30
    public static let focalLengthPx: Double = 1450.0
    public static let horizonYPx: Double = 530.0
    
    public static let minDistance: Double = 3.0
    public static let maxDistance: Double = 85.0
    
    /// Estimated physical height by vehicle class
    public static func targetHeight(for label: String) -> Double {
        switch label.lowercased() {
        case "truck", "bus":
            return 2.40 // Commercial vehicle rear profile
        default:
            return 1.48 // Standard sedan / crossover / hatchback
        }
    }
    
    /// Adaptive fusion of box-height and ground-plane contact estimators
    public static func estimateFusedDistance(
        boxHeightNormalized: Double,
        bottomYNormalized: Double,
        label: String = "car",
        frameHeight: Double = 1080.0
    ) -> Double {
        let boxHeightPx = max(6.0, boxHeightNormalized * frameHeight)
        let yBottomPixel = bottomYNormalized * frameHeight
        let deltaY = yBottomPixel - horizonYPx
        
        // 1. Box-height estimator (Immune to camera pitch angle and mount height)
        let hVehicle = targetHeight(for: label)
        let dHeight = (hVehicle * focalLengthPx) / boxHeightPx
        
        // 2. Ground-plane contact estimator
        let dGround: Double
        if deltaY > 8.0 {
            dGround = (cameraHeightM * focalLengthPx) / deltaY
        } else {
            dGround = maxDistance
        }
        
        // 3. Adaptive fusion weighting
        // dHeight < 15m -> t = 0.0 (100% box height)
        // dHeight > 40m -> t = 1.0 (100% ground contact)
        let t = max(0.0, min(1.0, (dHeight - 15.0) / 25.0))
        let fused = ((1.0 - t) * dHeight) + (t * dGround)
        
        return min(maxDistance, max(minDistance, fused))
    }
}