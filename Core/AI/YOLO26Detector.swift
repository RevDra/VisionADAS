import Foundation
import CoreML
import Vision
import CoreGraphics
import CoreVideo

/// High-performance CoreML detector wrapper for YOLO26n targeting the Apple Neural Engine (ANE).
///
/// Highway-optimized: detects only 4-wheelers (`car`, `truck`, `bus`).
/// Applies geometric exclusion mask to reject hood/wiper reflections (bottomY > 0.80).
public final class YOLO26Detector {
    
    private var visionModel: VNCoreMLModel?
    
    /// Highway 4-wheelers only — no motorcycles, bicycles, or pedestrians
    private let targetLabels: Set<String> = ["car", "truck", "bus"]
    private let confidenceThreshold: Float = 0.42
    
    /// Geometric exclusion: reject detections below this normalized Y threshold
    /// to eliminate vehicle hood, cowl, and wiper reflections
    private let hoodExclusionY: CGFloat = 0.80
    
    public init() {
        setupModel()
    }
    
    // MARK: - Model Initialization
    
    private func setupModel() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all // Offload to Apple Neural Engine
        
        var coreMLModel: MLModel?
        let possibleNames = ["yolo26", "yolo26n", "model"]
        
        // 1. Try compiled .mlmodelc bundles
        for name in possibleNames {
            if let compiledURL = Bundle.main.url(forResource: name, withExtension: "mlmodelc") {
                coreMLModel = try? MLModel(contentsOf: compiledURL, configuration: configuration)
                if coreMLModel != nil { break }
            }
        }
        
        // 2. Fallback: compile .mlpackage on-device
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
            print("[YOLO26Detector] Model not found in bundle.")
            return
        }
        
        self.visionModel = try? VNCoreMLModel(for: model)
    }
    
    // MARK: - Detection Pipeline
    
    /// Performs vehicle detection on a zero-copy CVPixelBuffer.
    /// Runs synchronously on caller's queue. Thread safe.
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
            
            // Branch A: Standard Vision recognized object observations
            if let observations = req.results as? [VNRecognizedObjectObservation] {
                for obs in observations {
                    guard let topLabel = obs.labels.first else { continue }
                    let label = topLabel.identifier.lowercased()
                    
                    guard self.targetLabels.contains(label),
                          topLabel.confidence >= self.confidenceThreshold else { continue }
                    
                    // Vision coords: origin bottom-left. bottomY in UIKit = 1.0 - vision.origin.y
                    let bottomY = 1.0 - obs.boundingBox.origin.y
                    
                    // Hood / wiper exclusion mask
                    guard bottomY <= self.hoodExclusionY else { continue }
                    
                    // Convert Vision (bottom-left origin) → UIKit (top-left origin)
                    let box = CGRect(
                        x: obs.boundingBox.origin.x,
                        y: 1.0 - obs.boundingBox.origin.y - obs.boundingBox.height,
                        width: obs.boundingBox.width,
                        height: obs.boundingBox.height
                    )
                    
                    detections.append(Detection(
                        label: label,
                        confidence: topLabel.confidence,
                        boundingBox: box,
                        bottomY: bottomY
                    ))
                }
            }
            // Branch B: NMS-free raw tensor output [channels, anchors]
            else if let featureObservations = req.results as? [VNCoreMLFeatureValueObservation],
                    let multiArray = featureObservations.first?.featureValue.multiArrayValue {
                detections = self.parseYOLORawTensor(multiArray: multiArray)
            }
            
            // Sort closest first (largest bottomY = nearest)
            detections.sort { $0.bottomY > $1.bottomY }
            completion(detections)
        }
        
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        try? handler.perform([request])
    }
    
    // MARK: - Raw Tensor Parser (NMS-free YOLO output)
    
    /// Parses [channels, anchors] format where channels = [cx, cy, w, h, cls0, cls1, ...]
    private func parseYOLORawTensor(multiArray: MLMultiArray) -> [Detection] {
        let shape = multiArray.shape.map { $0.intValue }
        guard shape.count >= 2 else { return [] }
        
        let numChannels = shape[shape.count - 2]
        let numAnchors  = shape[shape.count - 1]
        guard numChannels >= 6 else { return [] }
        
        let ptr = multiArray.dataPointer.bindMemory(to: Float.self, capacity: multiArray.count)
        
        // COCO class indices for highway 4-wheelers
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
            
            // Hood / wiper exclusion
            guard y2 <= hoodExclusionY else { continue }
            
            candidates.append(Candidate(
                label: bestLabel,
                score: bestScore,
                box: CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1),
                bottomY: y2
            ))
        }
        
        // Greedy NMS
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