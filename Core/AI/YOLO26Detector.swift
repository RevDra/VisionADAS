import Foundation
import CoreML
import Vision
import CoreGraphics
import CoreVideo

public class YOLO26Detector {
    
    private var visionModel: VNCoreMLModel?
    private var rawMLModel: MLModel?
    
    // COCO Target classes: car, motorcycle/scooter, bus, truck, bicycle
    private let targetLabels: Set<String> = ["car", "truck", "bus", "motorcycle", "bicycle"]
    private let confidenceThreshold: Float = 0.35
    
    public init() {
        setupModel()
    }
    
    // MARK: - Model Initialization
    
    private func setupModel() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all // Force Apple Neural Engine (ANE)
        
        var coreMLModel: MLModel?
        
        // 1. In compiled iOS apps, Xcode compiles .mlpackage into .mlmodelc
        let possibleNames = ["yolo26", "yolo26n", "model", "VisionADAS"]
        for name in possibleNames {
            if let compiledURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                do {
                    coreMLModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
                    print("[YOLO26Detector] Successfully loaded compiled model: \(name).mlmodelc")
                    break
                } catch {
                    print("[YOLO26Detector] Error loading \(name).mlmodelc: \(error)")
                }
            }
        }
        
        // 2. Fallback: on-device compile if raw .mlpackage is present
        if coreMLModel == nil {
            for name in possibleNames {
                if let packageURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                    do {
                        let compiledURL = try MLModel.compileModel(at: packageURL)
                        coreMLModel = try MLModel(contentsOf: compiledURL, configuration: configuration)
                        print("[YOLO26Detector] Compiled and loaded on-device: \(name).mlpackage")
                        break
                    } catch {
                        print("[YOLO26Detector] Error compiling \(name).mlpackage: \(error)")
                    }
                }
            }
        }
        
        guard let model = coreMLModel else {
            print("[YOLO26Detector] FATAL: Neither yolo26.mlmodelc nor yolo26n.mlmodelc found in bundle!")
            return
        }
        
        self.rawMLModel = model
        
        do {
            self.visionModel = try VNCoreMLModel(for: model)
            print("[YOLO26Detector] VNCoreMLModel initialized on ANE.")
        } catch {
            print("[YOLO26Detector] Error creating VNCoreMLModel: \(error)")
        }
    }
    
    // MARK: - Detection Pipeline
    
    public func detect(pixelBuffer: CVPixelBuffer, completion: @escaping ([Detection]) -> Void) {
        guard let visionModel = visionModel else {
            completion([])
            return
        }
        
        let request = VNCoreMLRequest(model: visionModel) { [weak self] req, error in
            guard let self = self, error == nil else {
                completion([])
                return
            }
            
            var detections: [Detection] = []
            
            // Branch A: Standard Vision Recognized Objects
            if let observations = req.results as? [VNRecognizedObjectObservation] {
                for obs in observations {
                    guard let topLabel = obs.labels.first else { continue }
                    let label = topLabel.identifier.lowercased()
                    let confidence = topLabel.confidence
                    
                    if self.targetLabels.contains(label) && confidence >= self.confidenceThreshold {
                        let boundingBox = ROICropUtility.fullPipeline(visionRect: obs.boundingBox)
                        let bottomY = ROICropUtility.bottomYInFullFrame(visionRect: obs.boundingBox)
                        
                        detections.append(Detection(
                            label: label,
                            confidence: confidence,
                            boundingBox: boundingBox,
                            bottomY: bottomY
                        ))
                    }
                }
            }
            // Branch B: Raw MultiArray Tensor Output (NMS-free / End-to-End head)
            else if let featureObservations = req.results as? [VNCoreMLFeatureValueObservation],
                    let multiArray = featureObservations.first?.featureValue.multiArrayValue {
                detections = self.parseNMSFreeTensor(multiArray: multiArray)
            }
            
            // Sort closest first (largest bottomY)
            detections.sort { $0.bottomY > $1.bottomY }
            completion(detections)
        }
        
        request.imageCropAndScaleOption = .scaleFill
        
        // Feed full camera frame into YOLO so targets anywhere in view (like the indoor scooter) are detected
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        
        do {
            try handler.perform([request])
        } catch {
            print("[YOLO26Detector] Handler perform failed: \(error)")
            completion([])
        }
    }
    
    // MARK: - Tensor Parser
    
    private func parseNMSFreeTensor(multiArray: MLMultiArray) -> [Detection] {
        var results: [Detection] = []
        let shape = multiArray.shape.map { $0.intValue }
        guard shape.count >= 2 else { return [] }
        
        let numDetections: Int
        let numFeatures: Int
        let isTransposed: Bool
        
        if shape.count == 3 {
            if shape[1] <= 300 && shape[2] >= 6 {
                numDetections = shape[1]
                numFeatures = shape[2]
                isTransposed = false
            } else if shape[1] >= 6 && shape[2] <= 300 {
                numFeatures = shape[1]
                numDetections = shape[2]
                isTransposed = true
            } else {
                numDetections = shape[1]
                numFeatures = shape[2]
                isTransposed = false
            }
        } else {
            numDetections = shape[0]
            numFeatures = shape[1]
            isTransposed = false
        }
        
        let cocoVehicleClasses: [Int: String] = [
            1: "bicycle",
            2: "car",
            3: "motorcycle",
            5: "bus",
            7: "truck"
        ]
        
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
        
        for i in 0..<numDetections {
            let conf: Float
            let classId: Int
            let x1, y1, x2, y2: CGFloat
            
            if !isTransposed {
                let offset = i * numFeatures
                conf = ptr[offset + 4]
                guard conf >= confidenceThreshold else { continue }
                classId = Int(ptr[offset + 5])
                x1 = CGFloat(ptr[offset + 0])
                y1 = CGFloat(ptr[offset + 1])
                x2 = CGFloat(ptr[offset + 2])
                y2 = CGFloat(ptr[offset + 3])
            } else {
                conf = ptr[4 * numDetections + i]
                guard conf >= confidenceThreshold else { continue }
                classId = Int(ptr[5 * numDetections + i])
                x1 = CGFloat(ptr[0 * numDetections + i])
                y1 = CGFloat(ptr[1 * numDetections + i])
                x2 = CGFloat(ptr[2 * numDetections + i])
                y2 = CGFloat(ptr[3 * numDetections + i])
            }
            
            guard let label = cocoVehicleClasses[classId], targetLabels.contains(label) else { continue }
            
            // Coordinates in [0, 1] normalized space
            let w = max(0, x2 - x1)
            let h = max(0, y2 - y1)
            let box = CGRect(x: x1, y: y1, width: w, height: h)
            let bottomY = y2
            
            results.append(Detection(
                label: label,
                confidence: conf,
                boundingBox: box,
                bottomY: bottomY
            ))
        }
        
        return results
    }
}