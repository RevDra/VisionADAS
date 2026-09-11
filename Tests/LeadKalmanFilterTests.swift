import XCTest
@testable import VisionADAS

final class LeadKalmanFilterTests: XCTestCase {
    
    var filter: LeadKalmanFilter!
    
    override func setUp() {
        super.setUp()
        filter = LeadKalmanFilter()
    }
    
    override func tearDown() {
        filter = nil
        super.tearDown()
    }
    
    func testInitialState() {
        let state = filter.update(measuredDistance: 30.0, hostSpeedKmh: 60.0, timestamp: 0.0)
        XCTAssertEqual(state.distance, 30.0, accuracy: 2.0)
    }
    
    func testConvergence() {
        var t = 0.0
        for _ in 0..<10 {
            _ = filter.update(measuredDistance: 30.0, hostSpeedKmh: 60.0, timestamp: t)
            t += 0.033
        }
        let finalState = filter.update(measuredDistance: 30.0, hostSpeedKmh: 60.0, timestamp: t)
        XCTAssertEqual(finalState.distance, 30.0, accuracy: 1.0)
    }
    
    func testVelocityEstimation() {
        var t = 0.0
        var dist = 50.0
        var state: LeadVehicleState!
        for _ in 0..<10 {
            state = filter.update(measuredDistance: dist, hostSpeedKmh: 60.0, timestamp: t)
            dist -= 0.5 // Approaching at ~15 m/s
            t += 0.033
        }
        XCTAssertTrue(state.relativeVelocity < -1.0) // Negative velocity
    }
    
    func testMeasurementNoiseScaling() {
        let r10 = filter.testR(distance: 10.0)
        let r50 = filter.testR(distance: 50.0)
        let r100 = filter.testR(distance: 100.0)
        
        XCTAssertTrue(r10 < r50)
        XCTAssertTrue(r50 < r100)
    }
    
    func testSpeedDeadzone() {
        // Host speed is 0, relative velocity is slightly negative
        _ = filter.update(measuredDistance: 10.0, hostSpeedKmh: 0.0, timestamp: 0.0)
        let state = filter.update(measuredDistance: 9.9, hostSpeedKmh: 0.0, timestamp: 0.1)
        
        // absoluteSpeedKmh should be clamped to 0 since it is < 5 km/h
        XCTAssertEqual(state.absoluteSpeedKmh, 0.0)
    }
    
    func testTTCCalculation() {
        _ = filter.update(measuredDistance: 30.0, hostSpeedKmh: 60.0, timestamp: 0.0)
        let state = filter.update(measuredDistance: 28.0, hostSpeedKmh: 60.0, timestamp: 0.1)
        
        XCTAssertNotNil(state.timeToCollision)
        if let ttc = state.timeToCollision {
            XCTAssertTrue(ttc > 0)
        }
    }
    
    func testHeadwayCalculation() {
        _ = filter.update(measuredDistance: 30.0, hostSpeedKmh: 60.0, timestamp: 0.0)
        let state = filter.update(measuredDistance: 30.0, hostSpeedKmh: 60.0, timestamp: 0.1)
        
        XCTAssertNotNil(state.headwaySeconds)
        if let headway = state.headwaySeconds {
            // 60 km/h = 16.67 m/s. 30m / 16.67 m/s ≈ 1.8s
            XCTAssertEqual(headway, 1.8, accuracy: 0.1)
        }
    }
    
    func testCoastingThroughOcclusion() {
        _ = filter.update(measuredDistance: 30.0, hostSpeedKmh: 60.0, timestamp: 0.0)
        _ = filter.update(measuredDistance: 29.5, hostSpeedKmh: 60.0, timestamp: 0.033)
        
        // Coasting for 3 frames
        let coastState = filter.coast(timestamp: 0.066, hostSpeedKmh: 60.0)
        XCTAssertNotNil(coastState)
        XCTAssertTrue(coastState!.distance < 30.0)
    }
    
    func testReset() {
        _ = filter.update(measuredDistance: 30.0, hostSpeedKmh: 60.0, timestamp: 0.0)
        filter.reset()
        let state = filter.testState()
        XCTAssertEqual(state[0], 0.0)
        XCTAssertEqual(state[1], 0.0)
        XCTAssertEqual(state[2], 0.0)
    }
}
