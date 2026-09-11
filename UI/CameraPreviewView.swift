import SwiftUI
import AVFoundation

/// A SwiftUI UIViewRepresentable view wrapping AVCaptureVideoPreviewLayer for zero-lag hardware camera preview.
public struct CameraPreviewView: UIViewRepresentable {
    
    public let session: AVCaptureSession
    
    public init(session: AVCaptureSession) {
        self.session = session
    }
    
    public func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        
        // Ensure initial connection orientation aligns with Landscape
        if let connection = view.previewLayer.connection {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(0) {
                    connection.videoRotationAngle = 0
                }
            } else {
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .landscapeRight
                }
            }
        }
        
        return view
    }
    
    public func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.previewLayer.frame = uiView.bounds
    }
}

/// Backing UIView whose CALayer is specialized as AVCaptureVideoPreviewLayer
public final class PreviewUIView: UIView {
    
    public override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    public var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}
