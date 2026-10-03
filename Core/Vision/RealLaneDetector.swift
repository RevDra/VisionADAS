import Foundation
import CoreGraphics
import CoreVideo

public struct DetectedLane {
    public let leftBoundary: [CGPoint]   // Normalized (0...1) screen points
    public let rightBoundary: [CGPoint]  // Normalized (0...1) screen points
    public let isValid: Bool
    public let confidence: Double
}

/// A high-performance classical computer vision lane detector that operates on the
/// zero-copy Y/Luminance plane of the CVPixelBuffer.
/// It uses dynamic thresholding, sliding windows, and least-squares polynomial curve fitting.
public final class RealLaneDetector {
    
    // Polynomial coefficients: x = a*y^2 + b*y + c
    private var leftCoeffs: (a: Double, b: Double, c: Double)?
    private var rightCoeffs: (a: Double, b: Double, c: Double)?
    
    private var missingFrames = 0
    private let maxCoastFrames = 15
    private let alpha = 0.25 // EMA alpha for temporal bridging
    
    public init() {}
    
    public func detect(pixelBuffer: CVPixelBuffer, vpYNorm: Double) -> DetectedLane? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
        
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        // Define Region of Interest (ROI)
        // From slightly below VP down to hood (e.g. 0.85)
        let startY = Int(Double(height) * min(max(vpYNorm + 0.02, 0.3), 0.7))
        let endY = Int(Double(height) * 0.85)
        
        guard endY > startY else { return nil }
        
        // 1. Histogram to find base centers
        let bottomHalfStartY = startY + (endY - startY) / 2
        var histogram = [Int](repeating: 0, count: width)
        
        // Very basic thresholding and vertical gradient approximation
        for y in bottomHalfStartY..<endY {
            let rowOffset = y * bytesPerRow
            for x in 1..<(width - 1) {
                let px = Int(buffer[rowOffset + x])
                // Simple intensity threshold for white/yellow markings
                if px > 160 {
                    let left = Int(buffer[rowOffset + x - 1])
                    let right = Int(buffer[rowOffset + x + 1])
                    // Simple horizontal edge detection
                    if abs(px - left) > 20 || abs(px - right) > 20 {
                        histogram[x] += 1
                    }
                }
            }
        }
        
        let midX = width / 2
        var leftBaseX = -1
        var rightBaseX = -1
        var leftMax = 0
        var rightMax = 0
        
        for x in 0..<midX {
            if histogram[x] > leftMax {
                leftMax = histogram[x]
                leftBaseX = x
            }
        }
        
        for x in midX..<width {
            if histogram[x] > rightMax {
                rightMax = histogram[x]
                rightBaseX = x
            }
        }
        
        // 2. Sliding Windows
        var leftPoints = [CGPoint]()
        var rightPoints = [CGPoint]()
        
        let numWindows = 8
        let windowHeight = (endY - startY) / numWindows
        let margin = Int(Double(width) * 0.08)
        let minPix = 10
        
        var currentLeftX = leftBaseX
        var currentRightX = rightBaseX
        
        for window in 0..<numWindows {
            let winYLow = endY - (window + 1) * windowHeight
            let winYHigh = endY - window * windowHeight
            
            var goodLeft = [CGPoint]()
            var goodRight = [CGPoint]()
            
            if currentLeftX != -1 {
                let winXLowLeft = max(0, currentLeftX - margin)
                let winXHighLeft = min(width, currentLeftX + margin)
                
                for y in winYLow..<winYHigh {
                    let rowOffset = y * bytesPerRow
                    for x in winXLowLeft..<winXHighLeft {
                        if buffer[rowOffset + x] > 160 {
                            goodLeft.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                        }
                    }
                }
                leftPoints.append(contentsOf: goodLeft)
                if goodLeft.count > minPix {
                    currentLeftX = Int(goodLeft.map { $0.x }.reduce(0, +) / CGFloat(goodLeft.count))
                }
            }
            
            if currentRightX != -1 {
                let winXLowRight = max(0, currentRightX - margin)
                let winXHighRight = min(width, currentRightX + margin)
                
                for y in winYLow..<winYHigh {
                    let rowOffset = y * bytesPerRow
                    for x in winXLowRight..<winXHighRight {
                        if buffer[rowOffset + x] > 160 {
                            goodRight.append(CGPoint(x: CGFloat(x), y: CGFloat(y)))
                        }
                    }
                }
                rightPoints.append(contentsOf: goodRight)
                if goodRight.count > minPix {
                    currentRightX = Int(goodRight.map { $0.x }.reduce(0, +) / CGFloat(goodRight.count))
                }
            }
        }
        
        // 3. Polynomial Curve Fitting
        let rawLeft = fitPolynomial(points: leftPoints)
        let rawRight = fitPolynomial(points: rightPoints)
        
        // 4. Temporal Smoothing (EMA)
        if let l = rawLeft, let r = rawRight {
            missingFrames = 0
            if let el = leftCoeffs {
                leftCoeffs = (
                    a: el.a * (1 - alpha) + l.a * alpha,
                    b: el.b * (1 - alpha) + l.b * alpha,
                    c: el.c * (1 - alpha) + l.c * alpha
                )
            } else {
                leftCoeffs = l
            }
            if let er = rightCoeffs {
                rightCoeffs = (
                    a: er.a * (1 - alpha) + r.a * alpha,
                    b: er.b * (1 - alpha) + r.b * alpha,
                    c: er.c * (1 - alpha) + r.c * alpha
                )
            } else {
                rightCoeffs = r
            }
        } else {
            missingFrames += 1
            if missingFrames > maxCoastFrames {
                leftCoeffs = nil
                rightCoeffs = nil
            }
        }
        
        guard let finalL = leftCoeffs, let finalR = rightCoeffs else { return nil }
        
        // 5. Output Data Generation
        var lb = [CGPoint]()
        var rb = [CGPoint]()
        let step = max(1, (endY - startY) / 20)
        
        for y in stride(from: startY, through: endY, by: step) {
            let yFloat = Double(y)
            let lx = finalL.a * yFloat * yFloat + finalL.b * yFloat + finalL.c
            let rx = finalR.a * yFloat * yFloat + finalR.b * yFloat + finalR.c
            lb.append(CGPoint(x: lx / Double(width), y: yFloat / Double(height)))
            rb.append(CGPoint(x: rx / Double(width), y: yFloat / Double(height)))
        }
        
        // Ensure the absolute end point is included for a clean polygon close
        if let lastL = lb.last, lastL.y != CGFloat(Double(endY) / Double(height)) {
            let yFloat = Double(endY)
            let lx = finalL.a * yFloat * yFloat + finalL.b * yFloat + finalL.c
            let rx = finalR.a * yFloat * yFloat + finalR.b * yFloat + finalR.c
            lb.append(CGPoint(x: lx / Double(width), y: yFloat / Double(height)))
            rb.append(CGPoint(x: rx / Double(width), y: yFloat / Double(height)))
        }
        
        return DetectedLane(leftBoundary: lb, rightBoundary: rb, isValid: true, confidence: 1.0)
    }
    
    /// Least-squares regression to fit a 2nd-degree polynomial (x = ay^2 + by + c)
    private func fitPolynomial(points: [CGPoint]) -> (a: Double, b: Double, c: Double)? {
        guard points.count >= 3 else { return nil }
        
        var sumY: Double = 0
        var sumY2: Double = 0
        var sumY3: Double = 0
        var sumY4: Double = 0
        var sumX: Double = 0
        var sumXY: Double = 0
        var sumXY2: Double = 0
        
        for p in points {
            let x = Double(p.x)
            let y = Double(p.y)
            let y2 = y * y
            
            sumY += y
            sumY2 += y2
            sumY3 += y2 * y
            sumY4 += y2 * y2
            sumX += x
            sumXY += x * y
            sumXY2 += x * y2
        }
        
        let n = Double(points.count)
        
        // Determinant of the coefficient matrix
        let det = sumY4 * (sumY2 * n - sumY * sumY)
                - sumY3 * (sumY3 * n - sumY * sumY2)
                + sumY2 * (sumY3 * sumY - sumY2 * sumY2)
        
        if abs(det) < 1e-10 { return nil } // Singular matrix
        
        let invDet = 1.0 / det
        
        let a = invDet * (
            sumXY2 * (sumY2 * n - sumY * sumY)
          - sumY3  * (sumXY * n - sumX * sumY)
          + sumY2  * (sumXY * sumY - sumX * sumY2)
        )
        
        let b = invDet * (
            sumY4  * (sumXY * n - sumX * sumY)
          - sumXY2 * (sumY3 * n - sumY * sumY2)
          + sumY2  * (sumY3 * sumX - sumXY * sumY2)
        )
        
        let c = invDet * (
            sumY4  * (sumY2 * sumX - sumY * sumXY)
          - sumY3  * (sumY3 * sumX - sumXY2 * sumY)
          + sumXY2 * (sumY3 * sumY - sumY2 * sumY2)
        )
        
        return (a, b, c)
    }
}
