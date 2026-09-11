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
    
    public static let minDistance: Double = 3.0
    public static let maxDistance: Double = 90.0
    
    public static func targetHeight(for label: String) -> Double {
        switch label.lowercased() {
        case "truck", "bus": return 2.40
        default: return 1.48
        }
    }
    
    /// Anchored Distance Projection:
    /// Distance is computed strictly relative to the Point of Infinity (vpY).
    public static func estimateAnchoredDistance(
        boxHeightNorm: Double,
        bottomYNorm: Double,
        vpY: Double,
        label: String = "car",
        frameHeight: Double = 1080.0
    ) -> Double {
        let yBottomPx = bottomYNorm * frameHeight
        let deltaY = yBottomPx - vpY
        
        // Point is at or above the point of infinity
        guard deltaY > 4.0 else {
            return maxDistance
        }
        
        // 1. Ground contact projection relative to VP
        let dGround = (cameraHeightM * focalLengthPx) / deltaY
        
        // 2. Scale-invariant box-height projection
        let boxHeightPx = max(6.0, boxHeightNorm * frameHeight)
        let dHeight = (targetHeight(for: label) * focalLengthPx) / boxHeightPx
        
        // 3. Distance blend: Box-height dominates near-field (<20m), VP-ground dominates far-field (>35m)
        let t = max(0.0, min(1.0, (dHeight - 15.0) / 25.0))
        let fused = ((1.0 - t) * dHeight) + (t * dGround)
        
        return min(maxDistance, max(minDistance, fused))
    }
}