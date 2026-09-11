import Foundation
import AVFoundation
import CoreImage
import os.log

/// Manages AVFoundation camera capture session for 1080p back camera video feed.
public class CameraManager: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    // MARK: - Properties
    
    public let captureSession = AVCaptureSession()
    
    @Published public var droppedFrames: Int = 0
    
    /// Closure invoked when a new frame is ready and inference is not running.
    public var onFrameAvailable: ((CVPixelBuffer, CMTime) -> Void)?
    
    /// Atomic flag to prevent buffer pool starvation.
    private var isProcessing = false
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let cameraQueue = DispatchQueue(label: "com.visionadas.camera", qos: .userInteractive)
    
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationCoordinatorObservation: NSKeyValueObservation?
    
    private let logger = OSLog(subsystem: "com.visionadas.app", category: "CameraManager")
    
    // MARK: - Setup
    
    /// Configures the camera capture session.
    public func setupCamera() throws {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        
        captureSession.sessionPreset = .hd1920x1080
        
        // 1. Find device
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.deviceUnavailable
        }
        
        // 2. Add input
        let videoInput = try AVCaptureDeviceInput(device: device)
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            throw CameraError.cannotAddInput
        }
        
        // 3. Add output
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        ]
        videoDataOutput.setSampleBufferDelegate(self, queue: cameraQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            throw CameraError.cannotAddOutput
        }
        
        // 4. Handle Rotation (iOS 17+)
        if #available(iOS 17.0, *) {
            rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
            if let connection = videoDataOutput.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(rotationCoordinator!.videoRotationAngleForHorizonLevelPreview) {
                    connection.videoRotationAngle = rotationCoordinator!.videoRotationAngleForHorizonLevelPreview
                }
                
                rotationCoordinatorObservation = rotationCoordinator!.observe(\.videoRotationAngleForHorizonLevelPreview, options: .new) { [weak connection] coordinator, change in
                    guard let connection = connection, let angle = change.newValue else { return }
                    if connection.isVideoRotationAngleSupported(angle) {
                        connection.videoRotationAngle = angle
                    }
                }
            }
        } else {
            if let connection = videoDataOutput.connection(with: .video), connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
    }
    
    // MARK: - Lifecycle
    
    /// Starts the capture session on a background thread.
    public func startSession() {
        guard !captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    /// Stops the capture session on a background thread.
    public func stopSession() {
        guard captureSession.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    
    /// Signals that processing for the current frame is done.
    public func finishProcessing() {
        isProcessing = false
    }
    
    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Atomic check to drop frames if currently processing inference
        guard !isProcessing else {
            return
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        isProcessing = true
        
        // Callback
        onFrameAvailable?(pixelBuffer, presentationTime)
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        DispatchQueue.main.async {
            self.droppedFrames += 1
        }
    }
    
    // MARK: - Errors
    
    public enum CameraError: Error {
        case deviceUnavailable
        case cannotAddInput
        case cannotAddOutput
    }
}
