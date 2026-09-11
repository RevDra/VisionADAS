import XCTest
@testable import VisionADAS

final class GroundPlaneProjectorTests: XCTestCase {
    
    func testDistanceAtVariousPixelPositions() {
        // bottomY=0.7 (756px) -> delta_y = 216 -> dist = 1.35*1450/216 = 9.0625
        let dist1 = GroundPlaneProjector.estimateDistance(bottomY: 0.7, pitchRad: 0.0, frameHeight: 1080.0)
        XCTAssertEqual(dist1, 9.06, accuracy: 1.0)
        
        // bottomY=0.55 (594px) -> delta_y = 54 -> dist = 1.35*1450/54 = 36.25
        let dist2 = GroundPlaneProjector.estimateDistance(bottomY: 0.55, pitchRad: 0.0, frameHeight: 1080.0)
        XCTAssertEqual(dist2, 36.25, accuracy: 1.0)
        
        // bottomY=0.52 (561.6px) -> delta_y = 21.6 -> dist = 1.35*1450/21.6 = 90.625
        let dist3 = GroundPlaneProjector.estimateDistance(bottomY: 0.52, pitchRad: 0.0, frameHeight: 1080.0)
        XCTAssertEqual(dist3, 90.62, accuracy: 1.0)
    }
    
    func testHorizonClamp() {
        // At horizon
        let distAtHorizon = GroundPlaneProjector.estimateDistance(bottomY: 0.5, pitchRad: 0.0, frameHeight: 1080.0)
        XCTAssertEqual(distAtHorizon, 120.0)
        
        // Above horizon
        let distAbove = GroundPlaneProjector.estimateDistance(bottomY: 0.4, pitchRad: 0.0, frameHeight: 1080.0)
        XCTAssertEqual(distAbove, 120.0)
    }
    
    func testNearClamp() {
        // Very large bottomY -> very near
        let distNear = GroundPlaneProjector.estimateDistance(bottomY: 1.5, pitchRad: 0.0, frameHeight: 1080.0)
        XCTAssertEqual(distNear, 2.0) // Clamped to minDistance
    }
    
    func testPitchCompensation() {
        let baseDist = GroundPlaneProjector.estimateDistance(bottomY: 0.6, pitchRad: 0.0, frameHeight: 1080.0)
        let pitchUpDist = GroundPlaneProjector.estimateDistance(bottomY: 0.6, pitchRad: 0.05, frameHeight: 1080.0)
        let pitchDownDist = GroundPlaneProjector.estimateDistance(bottomY: 0.6, pitchRad: -0.05, frameHeight: 1080.0)
        
        XCTAssertNotEqual(baseDist, pitchUpDist)
        XCTAssertNotEqual(baseDist, pitchDownDist)
    }
    
    func testNegativeEffectiveDeltaY() {
        // If bottomY is very small and pitch is negative
        let dist = GroundPlaneProjector.estimateDistance(bottomY: 0.5, pitchRad: -0.1, frameHeight: 1080.0)
        XCTAssertEqual(dist, 120.0)
    }
}
