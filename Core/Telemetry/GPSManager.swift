import Foundation
import CoreLocation
import Combine
import os

/// Real-time host vehicle speed provider (v_ego) using CoreLocation (iOS 17+).
///
/// Converts native GPS velocity (m/s) to km/h, enforces deadzone filtering,
/// and provides thread-safe synchronous access for the background ADAS pipeline.
public final class GPSManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    /// Published host speed in km/h for UI rendering
    @Published public private(set) var hostSpeedKmh: Double = 0.0
    /// Published stationary indicator
    @Published public private(set) var isStationary: Bool = true
    
    /// Thread-safe speed storage for the serial camera processing queue
    private let speedLock = OSAllocatedUnfairLock(initialState: 0.0)
    
    private let locationManager = CLLocationManager()
    private var updatesTask: Task<Void, Never>?
    private var isTracking = false
    
    public override init() {
        super.init()
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .automotiveNavigation
        locationManager.delegate = self
    }
    
    deinit {
        stopTracking()
    }
    
    /// Synchronous, thread-safe access to host speed (km/h).
    /// Safe to call from high-frequency background queues.
    public var currentSpeedKmh: Double {
        return speedLock.withLock { $0 }
    }
    
    /// Requests standard when-in-use location authorization.
    public func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Tracking Lifecycle
    
    /// Starts live GPS updates using iOS 17's modern AsyncSequence API.
    public func startTracking() {
        guard !isTracking else { return }
        isTracking = true
        
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                // iOS 17+ modern asynchronous stream optimized for automotive navigation
                let updates = CLLocationUpdate.liveUpdates(.automotiveNavigation)
                
                for try await update in updates {
                    guard !Task.isCancelled else { break }
                    
                    let speedMs = update.location?.speed ?? -1.0
                    // CLLocation speed is negative if velocity is invalid/undetermined
                    let validSpeedKmh = speedMs >= 0.0 ? (speedMs * 3.6) : 0.0
                    let stationary = update.stationary || validSpeedKmh < 1.0
                    
                    // Update atomic lock for background processing thread
                    self.speedLock.withLock { state in
                        state = validSpeedKmh
                    }
                    
                    // Dispatch updates to MainActor for SwiftUI
                    await MainActor.run {
                        self.hostSpeedKmh = validSpeedKmh
                        self.isStationary = stationary
                    }
                }
            } catch {
                print("[GPSManager] Location stream encountered an error: \(error.localizedDescription)")
            }
        }
    }
    
    /// Stops GPS tracking to preserve device battery.
    public func stopTracking() {
        guard isTracking else { return }
        updatesTask?.cancel()
        updatesTask = nil
        
        speedLock.withLock { state in
            state = 0.0
        }
        
        DispatchQueue.main.async {
            self.hostSpeedKmh = 0.0
            self.isStationary = true
        }
        
        isTracking = false
    }
    
    // Fallback delegate support for legacy / authorization change notification
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            startTracking()
        }
    }
}
