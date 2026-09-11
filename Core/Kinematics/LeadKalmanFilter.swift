import Foundation

/// 3-state discrete Kalman filter for lead vehicle distance, relative velocity, and acceleration tracking.
///
/// State vector x = [d, v_rel, a_rel]^T
/// - d: Distance to lead vehicle along longitudinal axis (meters)
/// - v_rel: Relative velocity in m/s (negative indicates closing in)
/// - a_rel: Relative acceleration in m/s²
///
/// Measurement noise covariance R scales quadratically with distance:
/// R = max(0.5, 0.0015 * pow(distance, 2.2))
/// This dampens pixel-level bounding-box jitter for distant targets (up to 100m)
/// by relying on kinematic momentum.
public final class LeadKalmanFilter {
    
    // State vector [d, v_rel, a_rel]
    private var state: [Double]
    
    // Error covariance matrix P (3x3)
    private var P: [[Double]]
    
    private var lastTimestamp: TimeInterval?
    
    // Coasting / dropout tolerance
    private var consecutiveMisses: Int = 0
    private let maxCoastingFrames: Int = 15 // Coast for ~0.5s at 30fps
    
    public init() {
        self.state = [0.0, 0.0, 0.0]
        self.P = [
            [10.0, 0.0, 0.0],
            [0.0, 5.0, 0.0],
            [0.0, 0.0, 2.0]
        ]
    }
    
    /// Resets the filter state (e.g., when a lead vehicle disappears or switches lanes).
    public func reset() {
        self.state = [0.0, 0.0, 0.0]
        self.P = [
            [10.0, 0.0, 0.0],
            [0.0, 5.0, 0.0],
            [0.0, 0.0, 2.0]
        ]
        self.lastTimestamp = nil
        self.consecutiveMisses = 0
    }
    
    /// Dynamic quadratic measurement noise scaling function.
    /// R(d) = max(0.5, 0.0015 * d^2.2)
    public func computeR(distance: Double) -> Double {
        return max(0.5, 0.0015 * pow(distance, 2.2))
    }
    
    /// Updates the Kalman filter with a new distance measurement.
    ///
    /// - Parameters:
    ///   - measuredDistance: Distance derived from ground-plane projection (meters).
    ///   - hostSpeedKmh: Current host vehicle GPS speed (km/h).
    ///   - timestamp: Video frame presentation timestamp (seconds).
    /// - Returns: Smoothed `LeadVehicleState` with derived TTC, headway, and absolute speed.
    public func update(
        measuredDistance: Double,
        hostSpeedKmh: Double,
        timestamp: TimeInterval
    ) -> LeadVehicleState {
        consecutiveMisses = 0
        
        let dt: Double
        if let lastT = lastTimestamp {
            // Guard against negative or huge dt during pause/resume
            dt = min(0.5, max(0.001, timestamp - lastT))
        } else {
            dt = 0.033 // Default to ~30 FPS on first frame
            self.state[0] = measuredDistance
        }
        self.lastTimestamp = timestamp
        
        // MARK: - 1. Predict Step
        // State transition matrix F:
        // | 1   dt   0.5*dt² |
        // | 0   1    dt      |
        // | 0   0    1       |
        let dt2 = dt * dt
        let predDist = state[0] + (state[1] * dt) + (0.5 * state[2] * dt2)
        let predVel  = state[1] + (state[2] * dt)
        let predAcc  = state[2]
        let predState = [predDist, predVel, predAcc]
        
        // Process noise matrix Q:
        // q_pos = 0.5 * dt⁴, q_vel = dt², q_acc = 1.0 (jerk uncertainty ~1 m/s³)
        let qPos = 0.5 * pow(dt, 4)
        let qVel = pow(dt, 2)
        let qAcc = 1.0
        let Q: [[Double]] = [
            [qPos, 0.0, 0.0],
            [0.0, qVel, 0.0],
            [0.0, 0.0, qAcc]
        ]
        
        // FP = F * P
        let FP00 = P[0][0] + (dt * P[1][0]) + (0.5 * dt2 * P[2][0])
        let FP01 = P[0][1] + (dt * P[1][1]) + (0.5 * dt2 * P[2][1])
        let FP02 = P[0][2] + (dt * P[1][2]) + (0.5 * dt2 * P[2][2])
        
        let FP10 = P[1][0] + (dt * P[2][0])
        let FP11 = P[1][1] + (dt * P[2][1])
        let FP12 = P[1][2] + (dt * P[2][2])
        
        let FP20 = P[2][0]
        let FP21 = P[2][1]
        let FP22 = P[2][2]
        
        // predP = (F * P) * F^T + Q
        var predP = [[Double]](repeating: [Double](repeating: 0.0, count: 3), count: 3)
        predP[0][0] = FP00 + (FP01 * dt) + (FP02 * 0.5 * dt2) + Q[0][0]
        predP[0][1] = FP01 + (FP02 * dt)                       + Q[0][1]
        predP[0][2] = FP02                                     + Q[0][2]
        
        predP[1][0] = FP10 + (FP11 * dt) + (FP12 * 0.5 * dt2) + Q[1][0]
        predP[1][1] = FP11 + (FP12 * dt)                       + Q[1][1]
        predP[1][2] = FP12                                     + Q[1][2]
        
        predP[2][0] = FP20 + (FP21 * dt) + (FP22 * 0.5 * dt2) + Q[2][0]
        predP[2][1] = FP21 + (FP22 * dt)                       + Q[2][1]
        predP[2][2] = FP22                                     + Q[2][2]
        
        // MARK: - 2. Update Step
        // Measurement matrix H = [1, 0, 0]
        // Innovation y = z - H * x_pred
        let y = measuredDistance - predState[0]
        
        // Innovation covariance S = H * predP * H^T + R
        let R = computeR(distance: measuredDistance)
        let S = predP[0][0] + R
        
        // Kalman gain K = predP * H^T * (1 / S)
        let invS = 1.0 / S
        let K0 = predP[0][0] * invS
        let K1 = predP[1][0] * invS
        let K2 = predP[2][0] * invS
        
        // Updated state = predState + K * y
        state[0] = predState[0] + (K0 * y)
        state[1] = predState[1] + (K1 * y)
        state[2] = predState[2] + (K2 * y)
        
        // Updated error covariance P = (I - K * H) * predP
        P[0][0] = (1.0 - K0) * predP[0][0]
        P[0][1] = (1.0 - K0) * predP[0][1]
        P[0][2] = (1.0 - K0) * predP[0][2]
        
        P[1][0] = predP[1][0] - (K1 * predP[0][0])
        P[1][1] = predP[1][1] - (K1 * predP[0][1])
        P[1][2] = predP[1][2] - (K1 * predP[0][2])
        
        P[2][0] = predP[2][0] - (K2 * predP[0][0])
        P[2][1] = predP[2][1] - (K2 * predP[0][1])
        P[2][2] = predP[2][2] - (K2 * predP[0][2])
        
        return buildOutputState(hostSpeedKmh: hostSpeedKmh)
    }
    
    /// Predicts state forward when no detection is found (kinematic coasting).
    /// Returns nil if occlusion lasts longer than `maxCoastingFrames`.
    public func coast(timestamp: TimeInterval, hostSpeedKmh: Double) -> LeadVehicleState? {
        consecutiveMisses += 1
        guard consecutiveMisses <= maxCoastingFrames, let lastT = lastTimestamp else {
            reset()
            return nil
        }
        
        let dt = min(0.5, max(0.001, timestamp - lastT))
        self.lastTimestamp = timestamp
        
        let dt2 = dt * dt
        state[0] = max(0.0, state[0] + (state[1] * dt) + (0.5 * state[2] * dt2))
        state[1] = state[1] + (state[2] * dt)
        
        return buildOutputState(hostSpeedKmh: hostSpeedKmh)
    }
    
    // MARK: - Output Derivation
    
    private func buildOutputState(hostSpeedKmh: Double) -> LeadVehicleState {
        // Target absolute speed in km/h = host_speed + (v_rel * 3.6)
        let rawTargetSpeedKmh = hostSpeedKmh + (state[1] * 3.6)
        // Deadzone clamp: if target speed < 5.0 km/h, snap to 0.0 (stopped car)
        let absoluteSpeedKmh = rawTargetSpeedKmh < 5.0 ? 0.0 : rawTargetSpeedKmh
        
        // Time-To-Collision (TTC): only valid when closing (v_rel < -0.5 m/s)
        let ttc: Double? = state[1] < -0.5 ? (state[0] / -state[1]) : nil
        
        // Time Headway: distance / v_ego (only valid when host vehicle is moving > 5 km/h)
        let hostSpeedMs = hostSpeedKmh / 3.6
        let headway: Double? = hostSpeedKmh > 5.0 ? (state[0] / hostSpeedMs) : nil
        
        return LeadVehicleState(
            distance: max(0.0, state[0]),
            relativeVelocity: state[1],
            relativeAcceleration: state[2],
            absoluteSpeedKmh: absoluteSpeedKmh,
            timeToCollision: ttc,
            headwaySeconds: headway
        )
    }
    
    // MARK: - Test Helpers
    
    internal func testState() -> [Double] { return state }
    internal func testR(distance: Double) -> Double { return computeR(distance: distance) }
}
