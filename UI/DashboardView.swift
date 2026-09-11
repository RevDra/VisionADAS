import SwiftUI
import AVFoundation
import CoreMedia

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
                    leadId: viewModel.leadDetectionId,
                    detections: viewModel.detections,
                    viewSize: geometry.size
                )
            }
            .onAppear { viewModel.startSystems() }
            .onDisappear { viewModel.stopSystems() }
        }
    }
}

public final class ADASViewModel: ObservableObject {
    
    @Published public private(set) var detections: [Detection] = []
    @Published public private(set) var leadState: LeadVehicleState? = nil
    @Published public private(set) var leadDetectionId: UUID? = nil
    @Published public private(set) var hostSpeedKmh: Double = 0.0
    @Published public private(set) var droppedFrameCount: Int = 0
    
    public let cameraManager = CameraManager()
    private let motionManager = MotionManager()
    private let gpsManager = GPSManager()
    
    private let detector = YOLO26Detector()
    private let kalmanFilter = LeadKalmanFilter()
    private let vpTracker = VanishingPointTracker()
    
    private let processingQueue = DispatchQueue(label: "com.visionadas.pipeline", qos: .userInteractive)
    
    public var captureSession: AVCaptureSession {
        return cameraManager.captureSession
    }
    
    public init() {
        setupPipeline()
    }
    
    private func setupPipeline() {
        try? cameraManager.setupCamera()
        
        cameraManager.onFrameAvailable = { [weak self] pixelBuffer, presentationTimestamp in
            guard let self = self else { return }
            self.processingQueue.async {
                self.processFrame(pixelBuffer: pixelBuffer, presentationTimestamp: presentationTimestamp)
            }
        }
    }

    private func processFrame(pixelBuffer: CVPixelBuffer, presentationTimestamp: CMTime) {
        let timestampSec = CMTimeGetSeconds(presentationTimestamp)
        let hostSpeed = self.gpsManager.currentSpeedKmh
        let pitchRad = self.motionManager.pitchRadians
        
        self.detector.detect(pixelBuffer: pixelBuffer) { [weak self] detectedVehicles in
            guard let self = self else { return }
            
            self.vpTracker.update(
            currentPitchRad: pitchRad,
            distantDetections: detectedVehicles,
            hostSpeedKmh: hostSpeed
            )

            var updatedLeadState: LeadVehicleState? = nil
            var confirmedLeadId: UUID? = nil
            
            // 1. Perspective Lane Filter: Trapezoidal driving corridor converging to horizon
            let inLaneVehicles = detectedVehicles.filter { det in
                return self.isInsideHostLane(det.boundingBox)
            }
            
            // 2. Select closest vehicle directly in our driving lane
            if let candidate = inLaneVehicles.first {
                let anchoredDistance = GroundPlaneProjector.estimateAnchoredDistance(
                    boxHeightNorm: Double(candidate.boundingBox.height),
                    bottomYNorm: Double(candidate.bottomY),
                    vpY: self.vpTracker.vpY,
                    label: candidate.label
                )
            
                if abs(anchoredDistance - self.kalmanFilter.currentDistance) > 14.0 {
                    self.kalmanFilter.reset()
                }
            
                let state = self.kalmanFilter.update(
                    measuredDistance: anchoredDistance,
                    hostSpeedKmh: hostSpeed,
                    timestamp: timestampSec
                )
                
                // Highway ADAS rule: Ignore stationary cars as lead vehicle
                if state.isStationary && hostSpeed > 10.0 {
                    updatedLeadState = nil
                    confirmedLeadId = nil
                } else {
                    updatedLeadState = state
                    confirmedLeadId = candidate.id
                }
            } else {
                updatedLeadState = self.kalmanFilter.coast(
                    timestamp: timestampSec,
                    hostSpeedKmh: hostSpeed
                )
            }
            
            DispatchQueue.main.async {
                self.detections = detectedVehicles
                self.leadState = updatedLeadState
                self.leadDetectionId = confirmedLeadId
                self.hostSpeedKmh = hostSpeed
                self.droppedFrameCount = self.cameraManager.droppedFrames
            }
            
            self.cameraManager.finishProcessing()
        }
    }
    
    /// True trapezoidal perspective lane corridor
    private func isInsideHostLane(_ box: CGRect) -> Bool {
        let y = box.maxY
        let t = max(0.0, min(1.0, (y - 0.49) / (0.80 - 0.49)))
        let halfWidth = 0.08 + (0.20 * t) // 0.08 at horizon -> 0.28 at bumper
        return abs(box.midX - 0.50) <= halfWidth
    }
    
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