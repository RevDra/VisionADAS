import Foundation
import CoreML
import Vision
import CoreGraphics
import CoreVideo

/// High-performance CoreML detector wrapper for YOLO26n targeting the Apple Neural Engine (ANE).
///
/// Features:
/// - Priority ANE execution via `MLModelConfiguration.computeUnits = .all`
/// - Hardware-accelerated ROI cropping via `VNCoreMLRequest.regionOfInterest`
/// - `.scaleFill` image scaling to match model aspect ratio without letterboxing artifacts
/// - Filters for vehicular targets: `car`, `truck`, `bus`, `motorcycle` (confidence > 0.40)
/// - Supports both standard Vision Object Recognition outputs and NMS-free multi-array tensors
/// - Zero-copy execution directly from CVPixelBuffer without UIImage wrappers
public class YOLO26Detector {
    
    private var visionModel: VNCoreMLModel?
    private var rawMLModel: MLModel?
    
    /// Target classes for ADAS detection
    private let targetLabels: Set<String> = ["car", "truck", "bus", "motorcycle"]
    private let confidenceThreshold: Float = 0.40
    
    public init() {
        setupModel()
    }
    
    // MARK: - Model Initialization
    
    private func setupModel() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all // Offload heavily to Apple Neural Engine (ANE)
        
        var coreMLModel: MLModel?
        
        // 1. Check for compiled .mlmodel bundle in app bundle
        if let compiledURL = Bundle.main.url(forResource: "model", withExtension: "mlmodel") {
            do {
                coreMLModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
            } catch {
                print("[YOLO26Detector] Error loading model.mlmodel: \(error)")
            }
        }
        
        // 2. Fallback: Check for raw .mlpackage and compile on-device
        if coreMLModel == nil, let packageURL = Bundle.main.url(forResource: "yolo26n", withExtension: "mlpackage") {
            do {
                let compiledURL = try MLModel.compileModel(at: packageURL)
                coreMLModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
            } catch {
                print("[YOLO26Detector] Error compiling yolo26n.mlpackage: \(error)")
            }
        }
        
        guard let model = coreMLModel else {
            print("[YOLO26Detector] Notice: Model file 'yolo26n' not found in bundle. Detection will return empty until model is linked.")
            return
        }
        
        self.rawMLModel = model
        
        do {
            self.visionModel = try VNCoreMLModel(for: model)
        } catch {
            print("[YOLO26Detector] Error creating VNCoreMLModel: \(error)")
        }
    }
    
    // MARK: - Detection Pipeline
    
    /// Performs vehicle detection on the provided zero-copy `CVPixelBuffer`.
    ///
    /// - Parameters:
    ///   - pixelBuffer: Hardware NV12 (BiPlanarFullRange) video frame.
    ///   - completion: Callback executed on caller's queue with detected vehicles sorted nearest-first.
    public func detect(pixelBuffer: CVPixelBuffer, completion: @escaping ([Detection]) -> Void) {
        guard let visionModel = visionModel else {
            completion([])
            return
        }
        
        let request = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            guard let self = self, error == nil else {
                completion([])
                return
            }
            
            var detections: [Detection] = []
            
            // Branch A: Standard Vision Object Recognition Observation
            if let observations = request.results as? [VNRecognizedObjectObservation] {
                for obs in observations {
                    guard let topLabel = obs.labels.first else { continue }
                    
                    let label = topLabel.identifier.lowercased()
                    let confidence = topLabel.confidence
                    
                    if self.targetLabels.contains(label) && confidence >= self.confidenceThreshold {
                        let boundingBox = ROICropUtility.fullPipeline(visionRect: obs.boundingBox)
                        let bottomY = ROICropUtility.bottomYInFullFrame(visionRect: obs.boundingBox)
                        
                        let detection = Detection(
                            label: label,
                            confidence: confidence,
                            boundingBox: boundingBox,
                            bottomY: bottomY
                        )
                        detections.append(detection)
                    }
                }
            }
            // Branch B: NMS-Free End-to-End CoreML MultiArray Tensor Output
            // Format: [1, num_detections, 6] where item is [x1, y1, x2, y2, score, class_id]
            else if let featureObservations = request.results as? [VNCoreMLFeatureValueObservation],
                    let multiArray = featureObservations.first?.featureValue.multiArrayValue {
                detections = self.parseNMSFreeTensor(multiArray: multiArray)
            }
            
            // Sort detections by bottomY descending: largest bottomY is lowest in the image (closest vehicle)
            detections.sort { $0.bottomY > $1.bottomY }
            
            completion(detections)
        }
        
        // ScaleFill ensures no letterbox downsampling within the ROI corridor
        request.imageCropAndScaleOption = .scaleFill
        
        // Restrict processing to the center driving corridor
        request.regionOfInterest = ROICropUtility.roi
        
        // Execute synchronously on the camera processing serial queue
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("[YOLO26Detector] Handler perform failed: \(error)")
            completion([])
        }
    }
    
    // MARK: - NMS-Free Tensor Parser
    
    /// Parses raw output tensor from an NMS-free end-to-end YOLO model.
    /// Supports tensor shape [1, N, 6] where items are [x_min, y_min, x_max, y_max, conf, class_id].
    private func parseNMSFreeTensor(multiArray: MLMultiArray) -> [Detection] {
        var results: [Detection] = []
        let shape = multiArray.shape.map { $0.intValue }
        
        guard shape.count >= 2 else { return [] }
        let numDetections = shape[shape.count - 2]
        let numFeatures = shape[shape.count - 1]
        guard numFeatures >= 6 else { return [] }
        
        let cocoVehicleClasses: [Int: String] = [
            2: "car",
            3: "motorcycle",
            5: "bus",
            7: "truck"
        ]
        
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
        
        for i in 0..<numDetections {
            let offset = i * numFeatures
            let conf = ptr[offset + 4]
            guard conf >= confidenceThreshold else { continue }
            
            let classId = Int(ptr[offset + 5])
            guard let label = cocoVehicleClasses[classId], targetLabels.contains(label) else { continue }
            
            // Normalized ROI coordinates [0, 1]
            let x1 = CGFloat(ptr[offset + 0])
            let y1 = CGFloat(ptr[offset + 1])
            let x2 = CGFloat(ptr[offset + 2])
            let y2 = CGFloat(ptr[offset + 3])
            
            let roiVisionRect = CGRect(x: x1, y: y1, width: max(0, x2 - x1), height: max(0, y2 - y1))
            let boundingBox = ROICropUtility.fullPipeline(visionRect: roiVisionRect)
            let bottomY = ROICropUtility.bottomYInFullFrame(visionRect: roiVisionRect)
            
            results.append(Detection(
                label: label,
                confidence: conf,
                boundingBox: boundingBox,
                bottomY: bottomY
            ))
        }
        
        return results
    }
}
