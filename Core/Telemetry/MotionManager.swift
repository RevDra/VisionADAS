import Foundation
import CoreMotion
import Combine

/// 60Hz dynamic vehicle attitude and pitch tracker using CoreMotion.
///
/// Compensates for vehicle chassis squat (acceleration) and dive (braking),
/// which alters the camera optical axis relative to the road ground plane.
public final class MotionManager: ObservableObject {
    
    /// Published pitch for SwiftUI subscribers (in radians)
    @Published public private(set) var currentPitch: Double = 0.0
    
    /// Thread-safe direct reader for high-frequency camera processing queue
    private var _atomicPitch: Double = 0.0
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.visionadas.motion"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()
    
    /// Exponential Moving Average smoothing factor
    private let alpha: Double = 0.15
    private var isTracking = false
    
    public init() {
        lock.initialize(to: os_unfair_lock())
    }
    
    deinit {
        stopUpdates()
        lock.deallocate()
    }
    
    /// Synchronous, thread-safe pitch reading in radians.
    /// Safe to invoke from the 60fps camera processing serial queue.
    public var pitchRadians: Double {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _atomicPitch
    }
    
    // MARK: - Lifecycle
    
    /// Starts 60Hz device motion tracking using gravity-aligned reference frame.
    public func startUpdates() {
        guard !isTracking else { return }
        guard motionManager.isDeviceMotionAvailable else {
            print("[MotionManager] Device motion unavailable on this hardware.")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0 // 60 Hz
        
        // .xArbitraryZVertical uses gravity to establish true vertical Z-axis
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: motionQueue) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else { return }
            
            let rawPitch = motion.attitude.pitch
            
            // Apply Exponential Moving Average (EMA) filter
            os_unfair_lock_lock(self.lock)
            let smoothed = (self.alpha * rawPitch) + ((1.0 - self.alpha) * self._atomicPitch)
            self._atomicPitch = smoothed
            os_unfair_lock_unlock(self.lock)
            
            // Dispatch UI updates asynchronously to main thread
            DispatchQueue.main.async {
                self.currentPitch = smoothed
            }
        }
        
        isTracking = true
    }
    
    /// Stops motion updates to conserve battery.
    public func stopUpdates() {
        guard isTracking else { return }
        motionManager.stopDeviceMotionUpdates()
        motionQueue.cancelAllOperations()
        isTracking = false
    }
}
