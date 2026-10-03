import SwiftUI
import AVFoundation
import CoreMedia

/// Main dashboard container combining real-time camera preview with ADAS HUD overlay.
public struct DashboardView: View {
    @StateObject private var viewModel = ADASViewModel()
    
    public init() {}
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPreviewView(session: viewModel.captureSession)
                    .ignoresSafeArea()
                
                ADASHUDView(
                    hostSpeedKmh: viewModel.hostSpeedKmh,
                    leadState: viewModel.leadState,
                    leadTrackId: viewModel.leadTrackId,
                    trackedVehicles: viewModel.trackedVehicles,
                    activeLeadVehicle: viewModel.activeLeadVehicle,
                    vpXNormalized: viewModel.vpXNormalized,
                    vpYNormalized: viewModel.vpYNormalized,
                    viewSize: geometry.size
                )
            }
            .onAppear { viewModel.startSystems() }
            .onDisappear { viewModel.stopSystems() }
        }
    }
}

// MARK: - ADAS ViewModel (MVVM Pipeline Orchestrator)

/// Coordinates the end-to-end ADAS pipeline:
/// Camera → YOLO26 → Multi-Object Tracker → Lead Selection → HUD
///
/// All heavy computation runs on a dedicated `.userInteractive` serial queue.
/// UI state is published strictly via `@MainActor` dispatch.
public final class ADASViewModel: ObservableObject {
    
    // MARK: - Published UI State
    
    @Published public private(set) var trackedVehicles: [TrackedVehicle] = []
    @Published public private(set) var leadState: LeadVehicleState? = nil
    @Published public private(set) var leadTrackId: Int? = nil
    @Published public private(set) var activeLeadVehicle: TrackedVehicle? = nil
    @Published public private(set) var hostSpeedKmh: Double = 0.0
    @Published public private(set) var droppedFrameCount: Int = 0
    @Published public private(set) var vpXNormalized: Double = 0.5
    @Published public private(set) var vpYNormalized: Double = 530.0 / 1080.0
    
    // MARK: - Subsystems
    
    public let cameraManager = CameraManager()
    private let motionManager = MotionManager()
    private let gpsManager = GPSManager()
    
    // Core Vision & Kinematics Engines
    private let detector = YOLO26Detector()
    private let tracker = MultiObjectTracker()
    private let calibrator = OnlineCalibrator()
    
    // Dedicated serial queue for zero-latency frame processing
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
        try? cameraManager.setupCamera()
        
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
    
    /// Core per-frame ADAS pipeline executed on the processing serial queue.
    private func processFrame(pixelBuffer: CVPixelBuffer, presentationTimestamp: CMTime) {
        let timestampSec = CMTimeGetSeconds(presentationTimestamp)
        
        // Thread-safe sensor snapshots
        let hostSpeed = self.gpsManager.currentSpeedKmh
        let pitchRad = self.motionManager.pitchRadians
        
        // Step 1: YOLO26 vehicle detection (ANE inference)
        self.detector.detect(pixelBuffer: pixelBuffer) { [weak self] detectedVehicles in
            guard let self = self else { return }
            
            // Step 2: Update vanishing point calibration
            self.calibrator.update(
                currentPitchRad: pitchRad,
                distantDetections: detectedVehicles,
                hostSpeedKmh: hostSpeed
            )
            
            // Step 3: Multi-Object Tracker update
            let tracked = self.tracker.update(
                detections: detectedVehicles,
                hostSpeedKmh: hostSpeed,
                timestamp: timestampSec,
                vpY: self.calibrator.vpY,
                calibrator: self.calibrator
            )
            
            // Step 4: Lead vehicle selection
            let leadVehicle = self.tracker.selectLeadVehicle(hostSpeedKmh: hostSpeed)
            
            let updatedLeadState = leadVehicle?.state
            let updatedLeadTrackId = leadVehicle?.trackId
            let updatedVpXNorm = self.calibrator.vpXNormalized
            let updatedVpYNorm = self.calibrator.vpYNormalized
            
            // Step 5: Dispatch clean state to MainActor for SwiftUI rendering
            DispatchQueue.main.async {
                self.trackedVehicles = tracked
                self.activeLeadVehicle = leadVehicle
                self.leadState = updatedLeadState
                self.leadTrackId = updatedLeadTrackId
                self.hostSpeedKmh = hostSpeed
                self.droppedFrameCount = self.cameraManager.droppedFrames
                self.vpXNormalized = updatedVpXNorm
                self.vpYNormalized = updatedVpYNorm
            }
            
            // Release frame buffer back to AVFoundation ISP pool
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
    }
}