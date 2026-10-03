import Foundation

public final class LeadKalmanFilter {
    
    private var state: [Double] = [0.0, 0.0, 0.0] // [distance, v_rel, a_rel]
    private var P: [[Double]] = [
        [10.0, 0.0, 0.0],
        [0.0, 5.0, 0.0],
        [0.0, 0.0, 2.0]
    ]
    
    private var lastTimestamp: TimeInterval?
    private var consecutiveMisses: Int = 0
    private let maxCoastingFrames: Int = 10
    private var updatesCount: Int = 0
    private var prevRawDistance: Double = 0.0
    
    public init() {}
    
    public func reset() {
        self.state = [0.0, 0.0, 0.0]
        self.P = [
            [10.0, 0.0, 0.0],
            [0.0, 5.0, 0.0],
            [0.0, 0.0, 2.0]
        ]
        self.lastTimestamp = nil
        self.consecutiveMisses = 0
        self.updatesCount = 0
        self.prevRawDistance = 0.0
    }
    
    public func computeR(distance: Double) -> Double {
        return max(0.5, 0.002 * pow(distance, 2.0))
    }
    
    @discardableResult
    public func update(
        measuredDistance: Double,
        hostSpeedKmh: Double,
        timestamp: TimeInterval
    ) -> LeadVehicleState {
        consecutiveMisses = 0
        updatesCount += 1
        
        let hostSpeedMs = hostSpeedKmh / 3.6
        let dt: Double
        if let lastT = lastTimestamp {
            dt = min(0.3, max(0.01, timestamp - lastT))
        } else {
            dt = 0.033
            self.state[0] = measuredDistance
            self.prevRawDistance = measuredDistance
        }
        self.lastTimestamp = timestamp
        
        // Frame 2: Seed relative velocity directly to prevent stationary cars inheriting host speed
        if updatesCount == 2 && dt > 0.01 {
            let instantVRel = (measuredDistance - prevRawDistance) / dt
            if hostSpeedMs > (15.0 / 3.6) && abs(instantVRel - (-hostSpeedMs)) < 2.0 {
                self.state[1] = -hostSpeedMs
            } else {
                self.state[1] = max(-hostSpeedMs - 4.0, min(12.0, instantVRel))
            }
        }
        self.prevRawDistance = measuredDistance
        
        // Predict
        let dt2 = dt * dt
        let predDist = state[0] + (state[1] * dt) + (0.5 * state[2] * dt2)
        let predVel  = max(-hostSpeedMs - 4.0, min(14.0, state[1] + (state[2] * dt)))
        let predAcc  = state[2]
        let predState = [predDist, predVel, predAcc]
        
        let Q: [[Double]] = [
            [0.5 * pow(dt, 4), 0.0, 0.0],
            [0.0, pow(dt, 2) * 1.5, 0.0],
            [0.0, 0.0, 1.2]
        ]
        
        let F: [[Double]] = [
            [1.0, dt, 0.5 * dt2],
            [0.0, 1.0, dt],
            [0.0, 0.0, 1.0]
        ]
        
        var predP = matAdd(matMul(matMul(F, P), matTranspose(F)), Q)
        
        // Update
        let y = measuredDistance - predState[0]
        let R = computeR(distance: measuredDistance)
        let S = predP[0][0] + R
        let invS = 1.0 / S
        let K = [predP[0][0] * invS, predP[1][0] * invS, predP[2][0] * invS]
        
        state[0] = predState[0] + (K[0] * y)
        state[1] = max(-hostSpeedMs - 4.0, min(14.0, predState[1] + (K[1] * y)))
        state[2] = predState[2] + (K[2] * y)
        
        for j in 0..<3 {
            predP[0][j] -= K[0] * predP[0][j]
            predP[1][j] -= K[1] * predP[0][j]
            predP[2][j] -= K[2] * predP[0][j]
        }
        P = predP
        
        return buildOutputState(hostSpeedKmh: hostSpeedKmh)
    }
    
    public func coast(timestamp: TimeInterval, hostSpeedKmh: Double) -> LeadVehicleState? {
        consecutiveMisses += 1
        guard consecutiveMisses <= maxCoastingFrames, let lastT = lastTimestamp else {
            reset()
            return nil
        }
        
        let dt = min(0.3, max(0.01, timestamp - lastT))
        self.lastTimestamp = timestamp
        state[0] = max(0.0, state[0] + (state[1] * dt))
        
        return buildOutputState(hostSpeedKmh: hostSpeedKmh)
    }
    
    private func buildOutputState(hostSpeedKmh: Double) -> LeadVehicleState {
        let rawTargetSpeedKmh = hostSpeedKmh + (state[1] * 3.6)
        
        // Stationary lock: If target speed is <= 7 km/h, snap to 0.0
        let isStationary = rawTargetSpeedKmh <= 7.0
        let absoluteSpeedKmh = isStationary ? 0.0 : rawTargetSpeedKmh
        
        let ttc: Double? = state[1] < -0.8 ? (state[0] / -state[1]) : nil
        let hostSpeedMs = hostSpeedKmh / 3.6
        let headway: Double? = hostSpeedKmh > 5.0 ? (state[0] / hostSpeedMs) : nil
        
        return LeadVehicleState(
            distance: max(0.0, state[0]),
            relativeVelocity: state[1],
            relativeAcceleration: state[2],
            absoluteSpeedKmh: absoluteSpeedKmh,
            timeToCollision: ttc,
            headwaySeconds: headway,
            isStationary: isStationary
        )
    }
    
    public var currentDistance: Double {
        return state[0]
    }
    
    private func matMul(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
        var C = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
        for i in 0..<3 {
            for j in 0..<3 {
                for k in 0..<3 { C[i][j] += A[i][k] * B[k][j] }
            }
        }
        return C
    }
    private func matTranspose(_ A: [[Double]]) -> [[Double]] {
        return [[A[0][0], A[1][0], A[2][0]], [A[0][1], A[1][1], A[2][1]], [A[0][2], A[1][2], A[2][2]]]
    }
    private func matAdd(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] {
        var C = Array(repeating: Array(repeating: 0.0, count: 3), count: 3)
        for i in 0..<3 { for j in 0..<3 { C[i][j] = A[i][j] + B[i][j] } }
        return C
    }
}