import Foundation
import CoreGraphics

// MARK: - Shared ADAS Types

/// Filtered kinematics state for a tracked vehicle from the Kalman filter.
public struct LeadVehicleState {
    public let distance: Double              // meters
    public let relativeVelocity: Double      // m/s (negative = approaching)
    public let relativeAcceleration: Double  // m/s²
    public let absoluteSpeedKmh: Double      // km/h (0 if snapped stationary)
    public let timeToCollision: Double?      // seconds, nil if not closing
    public let headwaySeconds: Double?       // seconds, nil if host stationary
    public let isStationary: Bool            // true if target speed < 7 km/h
}

/// A single YOLO object detection in normalized UIKit coordinates.
public struct Detection: Identifiable {
    public let id = UUID()
    public let label: String
    public let confidence: Float
    /// Bounding box in full-frame normalized coordinates (origin top-left, 0..1)
    public let boundingBox: CGRect
    /// Bottom edge Y in full-frame normalized coords (0=top, 1=bottom) — tire contact point
    public let bottomY: CGFloat
}

// MARK: - Ground Plane Projector

/// Openpilot-inspired monocular distance estimator using dual projection:
///
/// 1. **Ground contact projection** (VP-anchored): Accurate for far-field (>35m),
///    uses tire-to-road contact point relative to the optical vanishing point.
///    $d_{\text{ground}} = \frac{h_{\text{cam}} \cdot f_y}{\Delta y}$
///
/// 2. **Scale-invariant box height projection**: Accurate for near-field (<20m),
///    uses known real-world vehicle height and apparent pixel height.
///    $d_{\text{height}} = \frac{H_{\text{vehicle}} \cdot f_y}{h_{\text{box}}}$
///
/// The two estimates are blended adaptively across the 15m–40m transition zone.
/// Maximum distance clamped to 85m to prevent asymptotic jumps near the horizon.
public struct GroundPlaneProjector {
    
    /// Camera mount height above road surface (meters)
    public static let cameraHeightM: Double = 1.30
    
    /// Effective focal length in pixels for 1080p iPhone 1x lens
    public static let focalLengthPx: Double = 1450.0
    
    /// Distance bounds
    public static let minDistance: Double = 3.0
    public static let maxDistance: Double = 85.0
    
    /// Typical real-world vehicle heights for scale-invariant projection
    public static func targetHeight(for label: String) -> Double {
        switch label.lowercased() {
        case "truck", "bus": return 2.40  // meters
        default:             return 1.48  // sedan / hatchback
        }
    }
    
    /// Dual-projection anchored distance estimation.
    ///
    /// Blends ground-contact and box-height projections adaptively:
    /// - Near range (d < 15m): 100% box-height (stable, scale-invariant)
    /// - Mid range (15m–40m): linear blend transition
    /// - Far range (d > 40m): 100% ground-contact (sub-pixel box height unreliable)
    ///
    /// - Parameters:
    ///   - boxHeightNorm: Bounding box height in normalized [0, 1] image coordinates
    ///   - bottomYNorm: Tire contact point Y in normalized UIKit coordinates (0=top, 1=bottom)
    ///   - vpY: Current vanishing point Y in pixel coordinates (from OnlineCalibrator)
    ///   - label: Vehicle class label ("car", "truck", "bus") for height lookup
    ///   - frameHeight: Video frame height in pixels (default 1080)
    /// - Returns: Estimated distance in meters, clamped to [3.0, 85.0]
    public static func estimateAnchoredDistance(
        boxHeightNorm: Double,
        bottomYNorm: Double,
        vpY: Double,
        label: String = "car",
        frameHeight: Double = 1080.0
    ) -> Double {
        let yBottomPx = bottomYNorm * frameHeight
        let deltaY = yBottomPx - vpY
        
        // Target is at or above the vanishing point — maximum range
        guard deltaY > 4.0 else {
            return maxDistance
        }
        
        // 1. Ground contact projection relative to vanishing point
        let dGround = (cameraHeightM * focalLengthPx) / deltaY
        
        // 2. Scale-invariant box height projection
        let boxHeightPx = max(6.0, boxHeightNorm * frameHeight)
        let vehicleHeight = targetHeight(for: label)
        let dHeight = (vehicleHeight * focalLengthPx) / boxHeightPx
        
        // 3. Adaptive blend: box-height dominates near-field, ground-contact dominates far-field
        // Blend parameter t: 0.0 at d≤15m (pure box-height), 1.0 at d≥40m (pure ground-contact)
        let t = max(0.0, min(1.0, (dHeight - 15.0) / 25.0))
        let fused = ((1.0 - t) * dHeight) + (t * dGround)
        
        return min(maxDistance, max(minDistance, fused))
    }
}