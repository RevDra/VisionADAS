import SwiftUI
import AVFoundation
import CoreMedia

/// Central dashboard container combining real-time camera preview and HUD overlays.
/// Follows MVVM architecture with strict separation between Camera capture, ML inference,
/// Kinematics processing, and SwiftUI rendering.
public struct DashboardView: View {
    
    @StateObject private var viewModel = ADASViewModel()
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Layer 1: Hardware-accelerated camera preview
                CameraPreviewView(session: viewModel.captureSession)
                    .ignoresSafeArea()
                
                // Layer 2: Real-time ADAS HUD overlay
                ADASHUDView(
                    hostSpeedKmh: viewModel.hostSpeedKmh,
                    leadState: viewModel.leadState,
                    detections: viewModel.detections,
                    viewSize: geometry.size
                )
            }
            .onAppear {
                viewModel.startSystems()
            }
            .onDisappear {
                viewModel.stopSystems()
            }
        }
    }
}

// MARK: - ADAS View Model (MVVM Orchestrator)

/// Coordinates the end-to-end vision, sensor, kinematics, and UI pipeline.
///
/// Ensures all heavy computation (YOLO inference, ray-casting, Kalman matrix updates)
/// runs asynchronously on a high-priority serial queue (`.userInteractive`), while
/// published UI state changes are cleanly dispatched to the `@MainActor`.
public final class ADASViewModel: ObservableObject {
    
    // Published UI State
    @Published public private(set) var detections: [Detection] = []
    @Published public private(set) var leadState: LeadVehicleState? = nil
    @Published public private(set) var hostSpeedKmh: Double = 0.0
    @Published public private(set) var droppedFrameCount: Int = 0
    
    // Pipeline Subsystems
    public let cameraManager = CameraManager()
    private let motionManager = MotionManager()
    private let gpsManager = GPSManager()
    
    // Core Vision & Kinematics Engines
    private let detector = YOLO26Detector()
    private let kalmanFilter = LeadKalmanFilter()
    
    // Dedicated high-priority serial queue for zero-latency frame processing
    private let processingQueue = DispatchQueue(
        label: "com.visionadas.pipeline",
        qos: .userInteractive
    )
    
    public var captureSession: AVCaptureSession {
        return cameraManager.captureSession
    }
    
    public init() {
        setupPipeline()
    }
    
    // MARK: - Pipeline Wiring
    
    private func setupPipeline() {
        do {
            try cameraManager.setupCamera()
        } catch {
            print("[ADASViewModel] Camera configuration failed: \(error.localizedDescription)")
        }
        
        // Zero-copy frame delivery callback
        cameraManager.onFrameAvailable = { [weak self] pixelBuffer, presentationTimestamp in
            guard let self = self else { return }
            
            self.processingQueue.async {
                self.processFrame(
                    pixelBuffer: pixelBuffer,
                    presentationTimestamp: presentationTimestamp
                )
            }
        }
    }
    
    /// Executes the detection -> projection -> filtering cycle on the processing queue.
    private func processFrame(pixelBuffer: CVPixelBuffer, presentationTimestamp: CMTime) {
        let timestampSec = CMTimeGetSeconds(presentationTimestamp)
        
        // 1. Thread-safe snapshot of sensor telemetry
        let hostSpeed = self.gpsManager.currentSpeedKmh
        let pitchRad = self.motionManager.pitchRadians
        
        // 2. Run YOLO26 inference (ANE accelerated)
        self.detector.detect(pixelBuffer: pixelBuffer) { [weak self] detectedVehicles in
            guard let self = self else { return }
            
            var updatedLeadState: LeadVehicleState? = nil
            
            // 3. Kinematics: Ground-Plane Ray Casting & Kalman Tracking
            if let leadDetection = detectedVehicles.first {
                // Monocular tire-to-road contact point distance projection
                let projectedDistance = GroundPlaneProjector.estimateDistance(
                    bottomY: Double(leadDetection.bottomY),
                    pitchRad: pitchRad
                )
                
                // 3-state discrete Kalman filter update
                updatedLeadState = self.kalmanFilter.update(
                    measuredDistance: projectedDistance,
                    hostSpeedKmh: hostSpeed,
                    timestamp: timestampSec
                )
            } else {
                // Coast previous track through momentary occlusion (e.g. wiper sweep)
                updatedLeadState = self.kalmanFilter.coast(
                    timestamp: timestampSec,
                    hostSpeedKmh: hostSpeed
                )
            }
            
            // 4. Dispatch updated state to MainActor for SwiftUI
            DispatchQueue.main.async {
                self.detections = detectedVehicles
                self.leadState = updatedLeadState
                self.hostSpeedKmh = hostSpeed
                self.droppedFrameCount = self.cameraManager.droppedFrames
            }
            
            // 5. Release frame buffer back to AVFoundation ISP pool
            self.cameraManager.finishProcessing()
        }
    }
    
    // MARK: - Lifecycle Management
    
    public func startSystems() {
        cameraManager.startSession()
        motionManager.startUpdates()
        gpsManager.requestAuthorization()
        gpsManager.startTracking()
    }
    
    public func stopSystems() {
        cameraManager.stopSession()
        motionManager.stopUpdates()
        gpsManager.stopTracking()
        kalmanFilter.reset()
    }
}
