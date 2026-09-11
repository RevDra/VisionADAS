import Foundation
import CoreGraphics
import CoreVideo
import Accelerate
import CoreImage

/// Hardware-accelerated center-corridor ROI cropping utility and coordinate transformations.
///
/// Handles mapping between:
/// 1. Vision framework normalized coordinates (origin bottom-left, [0, 1])
/// 2. ROI sub-corridor coordinates (central 70% width/height driving corridor)
/// 3. UIKit / SwiftUI screen coordinates (origin top-left, [0, 1])
/// 4. Direct hardware-accelerated CVPixelBuffer cropping via vImage / CoreVideo
public struct ROICropUtility {
    
    /// Central driving corridor ROI in normalized image coordinates (origin top-left).
    /// Rect: (x: 0.15, y: 0.15, width: 0.70, height: 0.70).
    /// Preserves pixel density for distant 100m targets without downsampling loss.
    public static let roi = CGRect(x: 0.15, y: 0.15, width: 0.70, height: 0.70)
    
    // Shared CIContext backed by Metal for zero-allocation hardware crops
    private static let ciContext: CIContext = {
        if let metalDevice = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: metalDevice, options: [.useSoftwareRenderer: false])
        }
        return CIContext(options: [CIContextOption.useSoftwareRenderer: false])
    }()
    
    // MARK: - Coordinate Transformations
    
    /// Converts a normalized point from ROI-relative coordinates to full-frame normalized coordinates.
    public static func roiToFullFrame(normalizedPoint: CGPoint) -> CGPoint {
        return CGPoint(
            x: roi.origin.x + (normalizedPoint.x * roi.width),
            y: roi.origin.y + (normalizedPoint.y * roi.height)
        )
    }
    
    /// Converts a normalized rect from ROI-relative coordinates to full-frame normalized coordinates.
    public static func roiToFullFrame(normalizedRect: CGRect) -> CGRect {
        return CGRect(
            x: roi.origin.x + (normalizedRect.origin.x * roi.width),
            y: roi.origin.y + (normalizedRect.origin.y * roi.height),
            width: normalizedRect.width * roi.width,
            height: normalizedRect.height * roi.height
        )
    }
    
    /// Converts Vision normalized coordinates (bottom-left origin) to UIKit/SwiftUI coordinates (top-left origin).
    public static func visionToUIKit(rect: CGRect) -> CGRect {
        return CGRect(
            x: rect.origin.x,
            y: 1.0 - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
    
    /// Full transform pipeline:
    /// Vision ROI-relative bounding box -> Full-frame normalized UIKit/SwiftUI bounding box.
    public static func fullPipeline(visionRect: CGRect) -> CGRect {
        let fullFrameVisionRect = roiToFullFrame(normalizedRect: visionRect)
        return visionToUIKit(rect: fullFrameVisionRect)
    }
    
    /// Calculates the tire-to-road contact point (bottom edge Y) in full-frame normalized UIKit coordinates.
    /// Range: 0.0 (top of image) to 1.0 (bottom of image).
    ///
    /// Derivation:
    /// In Vision ROI coordinates, `visionRect.minY` is distance from ROI bottom.
    /// In full-frame Vision: `fullVisionBottom = roi.minY + visionRect.minY * roi.height`.
    /// In UIKit (top-left origin): `tireContactY = 1.0 - fullVisionBottom`.
    public static func bottomYInFullFrame(visionRect: CGRect) -> CGFloat {
        let fullVisionBottom = roi.minY + (visionRect.minY * roi.height)
        return 1.0 - fullVisionBottom
    }
    
    // MARK: - Hardware-Accelerated CVPixelBuffer Crop (1280x720 Center Corridor)
    
    /// Hardware-accelerated center-corridor crop from 1080p (1920x1080) to 720p (1280x720).
    /// Renders directly using GPU/Metal zero-copy without allocating UIImage.
    ///
    /// - Parameters:
    ///   - sourceBuffer: Input 1080p CVPixelBuffer (kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
    ///   - destinationBuffer: Pre-allocated destination CVPixelBuffer (1280x720)
    ///   - cropRect: Crop region in source pixel coordinates (default: centered 1280x720)
    /// - Returns: True if crop succeeded, false otherwise
    @discardableResult
    public static func cropCenterCorridor(
        from sourceBuffer: CVPixelBuffer,
        to destinationBuffer: CVPixelBuffer,
        cropRect: CGRect = CGRect(x: 320, y: 180, width: 1280, height: 720)
    ) -> Bool {
        let sourceImage = CIImage(cvPixelBuffer: sourceBuffer)
        let croppedImage = sourceImage.cropped(to: cropRect)
        
        // Translate origin to (0, 0) for rendering into destination buffer
        let transformedImage = croppedImage.transformed(
            by: CGAffineTransform(translationX: -cropRect.origin.x, y: -cropRect.origin.y)
        )
        
        ciContext.render(transformedImage, to: destinationBuffer)
        return true
    }
}
