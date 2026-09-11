import Foundation
import CoreML
import Vision
import CoreGraphics
import CoreVideo

public class YOLO26Detector {
    
    private var visionModel: VNCoreMLModel?
    private var rawMLModel: MLModel?
    
    // 4-wheelers only: Car, Truck, Bus
    private let targetLabels: Set<String> = ["car", "truck", "bus"]
    private let confidenceThreshold: Float = 0.42
    
    public init() {
        setupModel()
    }
    
    private func setupModel() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        
        var coreMLModel: MLModel?
        let possibleNames = ["yolo26", "yolo26n", "model"]
        
        for name in possibleNames {
            if let compiledURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                coreMLModel = try? MLModel(contentsOf: compiledURL, configuration: configuration)
                if coreMLModel != nil { break }
            }
        }
        
        if coreMLModel == nil {
            for name in possibleNames {
                if let packageURL = Bundle.main.url(forResource: name, withExtension: "mlpackage") {
                    if let compiledURL = try? MLModel.compileModel(at: packageURL) {
                        coreMLModel = try? MLModel(contentsOf: compiledURL, configuration: configuration)
                        if coreMLModel != nil { break }
                    }
                }
            }
        }
        
        guard let model = coreMLModel else {
            print("[YOLO26Detector] Error: Model not found in bundle.")
            return
        }
        
        self.rawMLModel = model
        self.visionModel = try? VNCoreMLModel(for: model)
    }
    
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
            
            if let observations = req.results as? [VNRecognizedObjectObservation] {
                for obs in observations {
                    guard let topLabel = obs.labels.first else { continue }
                    let label = topLabel.identifier.lowercased()
                    if self.targetLabels.contains(label) && topLabel.confidence >= self.confidenceThreshold {
                        let bottomY = 1.0 - obs.boundingBox.origin.y
                        
                        // Mask out hood/mirror zone (bottom 20% of view)
                        guard bottomY <= 0.80 else { continue }
                        
                        let box = CGRect(
                            x: obs.boundingBox.origin.x,
                            y: 1.0 - obs.boundingBox.origin.y - obs.boundingBox.height,
                            width: obs.boundingBox.width,
                            height: obs.boundingBox.height
                        )
                        detections.append(Detection(label: label, confidence: topLabel.confidence, boundingBox: box, bottomY: bottomY))
                    }
                }
            } else if let featureObservations = req.results as? [VNCoreMLFeatureValueObservation],
                      let multiArray = featureObservations.first?.featureValue.multiArrayValue {
                detections = self.parseYOLORawTensor(multiArray: multiArray)
            }
            
            // Sort closest first
            detections.sort { $0.bottomY > $1.bottomY }
            completion(detections)
        }
        
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
    
    private func parseYOLORawTensor(multiArray: MLMultiArray) -> [Detection] {
        let shape = multiArray.shape.map { $0.intValue }
        guard shape.count >= 2 else { return [] }
        
        let numChannels = shape[shape.count - 2]
        let numAnchors  = shape[shape.count - 1]
        guard numChannels >= 6 else { return [] }
        
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
        
        // 4-wheelers COCO indices: 2: car, 5: bus, 7: truck
        let vehicleClassChannels: [(channel: Int, label: String)] = [
            (4 + 2, "car"),
            (4 + 5, "bus"),
            (4 + 7, "truck")
        ]
        
        struct Candidate {
            let label: String
            let score: Float
            let box: CGRect
            let bottomY: CGFloat
        }
        var candidates: [Candidate] = []
        
        let cxHead = ptr
        let cyHead = ptr.advanced(by: 1 * numAnchors)
        let wHead  = ptr.advanced(by: 2 * numAnchors)
        let hHead  = ptr.advanced(by: 3 * numAnchors)
        
        for a in 0..<numAnchors {
            var bestScore: Float = 0.0
            var bestLabel = "car"
            
            for (ch, label) in vehicleClassChannels {
                let score = ptr[ch * numAnchors + a]
                if score > bestScore {
                    bestScore = score
                    bestLabel = label
                }
            }
            
            guard bestScore >= confidenceThreshold else { continue }
            
            let cx = CGFloat(cxHead[a]) / 640.0
            let cy = CGFloat(cyHead[a]) / 640.0
            let w  = CGFloat(wHead[a])  / 640.0
            let h  = CGFloat(hHead[a])  / 640.0
            
            let x1 = max(0.0, cx - (w / 2.0))
            let y1 = max(0.0, cy - (h / 2.0))
            let x2 = min(1.0, cx + (w / 2.0))
            let y2 = min(1.0, cy + (h / 2.0))
            
            guard x2 > x1 && y2 > y1 else { continue }
            guard y2 <= 0.80 else { continue } // Hood exclusion
            
            candidates.append(Candidate(
                label: bestLabel,
                score: bestScore,
                box: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1),
                bottomY: y2
            ))
        }
        
        candidates.sort { $0.score > $1.score }
        var kept: [Candidate] = []
        
        for cand in candidates {
            var overlap = false
            for k in kept {
                if iou(cand.box, k.box) > 0.45 {
                    overlap = true
                    break
                }
            }
            if !overlap {
                kept.append(cand)
                if kept.count >= 8 { break }
            }
        }
        
        return kept.map {
            Detection(label: $0.label, confidence: $0.score, boundingBox: $0.box, bottomY: $0.bottomY)
        }
    }
    
    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0.0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea
        return unionArea > 0 ? (intersectionArea / unionArea) : 0.0
    }
}