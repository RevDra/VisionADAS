import SwiftUI

// MARK: - 1. Dynamic 3D Adaptive Lane Carpet

public struct LaneCarpetView: View {
    public let leadVehicle: TrackedVehicle?
    public let detectedLane: DetectedLane?
    public let vpXNormalized: Double
    public let vpYNormalized: Double
    public let viewSize: CGSize
    public let state: LeadVehicleState?
    
    // xADAS Neon Colors
    private let neonGreen = Color(red: 0.0, green: 1.0, blue: 0.35)
    private let neonAmber = Color(red: 1.0, green: 0.7, blue: 0.0)
    private let neonRed = Color(red: 1.0, green: 0.09, blue: 0.27)
    
    private var carpetColor: Color {
        guard let state = state else { return neonGreen }
        if let ttc = state.timeToCollision, ttc < 1.5 { return neonRed }
        if let headway = state.headwaySeconds {
            if headway < 1.5 { return neonRed }
            if headway <= 2.2 { return neonAmber }
        }
        return neonGreen
    }
    
    public init(
        leadVehicle: TrackedVehicle?,
        detectedLane: DetectedLane?,
        vpXNormalized: Double,
        vpYNormalized: Double,
        viewSize: CGSize,
        state: LeadVehicleState?
    ) {
        self.leadVehicle = leadVehicle
        self.detectedLane = detectedLane
        self.vpXNormalized = vpXNormalized
        self.vpYNormalized = vpYNormalized
        self.viewSize = viewSize
        self.state = state
    }
    
    public var body: some View {
        let paths = generatePaths()
        let clipY = leadVehicle.map { viewSize.height * min(CGFloat($0.detection.bottomY), 0.78) } ?? (viewSize.height * vpYNormalized)
        
        ZStack {
            // 1. Fill Gradient
            paths.full
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            carpetColor.opacity(0.20),
                            carpetColor.opacity(0.70)
                        ]),
                        startPoint: UnitPoint(x: 0.5, y: clipY / viewSize.height),
                        endPoint: UnitPoint(x: 0.5, y: 0.85)
                    )
                )
            
            // 2. Crisp Neon Boundary Lines with Glow
            paths.left
                .stroke(carpetColor, lineWidth: 3.5)
                .shadow(color: carpetColor.opacity(0.85), radius: 6)
                
            paths.right
                .stroke(carpetColor, lineWidth: 3.5)
                .shadow(color: carpetColor.opacity(0.85), radius: 6)
            
            // 3. Perspective Depth Chevrons
            Path { path in
                for (l, r) in paths.steps {
                    let cx = (l.x + r.x) / 2
                    let cy = (l.y + r.y) / 2 - 6
                    path.move(to: l)
                    path.addLine(to: CGPoint(x: cx, y: cy))
                    path.addLine(to: r)
                }
            }
            .stroke(carpetColor.opacity(0.5), lineWidth: 2.0)
        }
    }
    
    private func generatePaths() -> (left: Path, right: Path, full: Path, steps: [(CGPoint, CGPoint)]) {
        let bottomY = viewSize.height * 0.85
        let clipY = leadVehicle.map { viewSize.height * min(CGFloat($0.detection.bottomY), 0.78) } ?? (viewSize.height * vpYNormalized)
        
        var leftPoints = [CGPoint]()
        var rightPoints = [CGPoint]()
        
        if let lane = detectedLane, lane.isValid {
            // Draw real road lane
            for p in lane.leftBoundary {
                let py = p.y * viewSize.height
                if py >= clipY && py <= bottomY {
                    leftPoints.append(CGPoint(x: p.x * viewSize.width, y: py))
                }
            }
            for p in lane.rightBoundary {
                let py = p.y * viewSize.height
                if py >= clipY && py <= bottomY {
                    rightPoints.append(CGPoint(x: p.x * viewSize.width, y: py))
                }
            }
        } else {
            // Fallback: Dynamic Vanishing Point funnel
            let topCenterX = viewSize.width * vpXNormalized
            let topHalfWidth = viewSize.width * 0.06
            let bottomCenterX = viewSize.width * 0.5
            let bottomHalfWidth = viewSize.width * 0.24
            
            let topLeft = CGPoint(x: topCenterX - topHalfWidth, y: clipY)
            let topRight = CGPoint(x: topCenterX + topHalfWidth, y: clipY)
            let bottomLeft = CGPoint(x: bottomCenterX - bottomHalfWidth, y: bottomY)
            let bottomRight = CGPoint(x: bottomCenterX + bottomHalfWidth, y: bottomY)
            
            let steps = 10
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let omt = 1.0 - t
                let midY = (clipY + bottomY) / 2
                let ctrlLeft = CGPoint(x: (topLeft.x + bottomLeft.x) / 2 - 15, y: midY)
                let ctrlRight = CGPoint(x: (topRight.x + bottomRight.x) / 2 + 15, y: midY)
                
                let lx = (omt * omt * topLeft.x) + (2 * omt * t * ctrlLeft.x) + (t * t * bottomLeft.x)
                let ly = (omt * omt * topLeft.y) + (2 * omt * t * ctrlLeft.y) + (t * t * bottomLeft.y)
                leftPoints.append(CGPoint(x: lx, y: ly))
                
                let rx = (omt * omt * topRight.x) + (2 * omt * t * ctrlRight.x) + (t * t * bottomRight.x)
                let ry = (omt * omt * topRight.y) + (2 * omt * t * ctrlRight.y) + (t * t * bottomRight.y)
                rightPoints.append(CGPoint(x: rx, y: ry))
            }
        }
        
        var leftPath = Path()
        if let first = leftPoints.first {
            leftPath.move(to: first)
            for p in leftPoints.dropFirst() { leftPath.addLine(to: p) }
        }
        
        var rightPath = Path()
        if let first = rightPoints.first {
            rightPath.move(to: first)
            for p in rightPoints.dropFirst() { rightPath.addLine(to: p) }
        }
        
        var fullPath = leftPath
        if let lastL = leftPoints.last, let lastR = rightPoints.last, let firstR = rightPoints.first {
            fullPath.addLine(to: lastR)
            for p in rightPoints.reversed().dropFirst() {
                fullPath.addLine(to: p)
            }
            if let firstL = leftPoints.first {
                fullPath.addLine(to: firstL)
            }
        }
        fullPath.closeSubpath()
        
        // Depth Chevrons (non-linear spacing)
        var stepsList = [(CGPoint, CGPoint)]()
        let numSteps = 5
        for i in 1..<numSteps {
            let t = pow(CGFloat(i) / CGFloat(numSteps), 1.5)
            let idxL = Int(CGFloat(leftPoints.count - 1) * t)
            let idxR = Int(CGFloat(rightPoints.count - 1) * t)
            if idxL >= 0 && idxL < leftPoints.count && idxR >= 0 && idxR < rightPoints.count {
                stepsList.append((leftPoints[idxL], rightPoints[idxR]))
            }
        }
        
        return (leftPath, rightPath, fullPath, stepsList)
    }
}

// MARK: - 2. HUD Container

/// Vivid, high-visibility ADAS Heads-Up Display for highway driving.
public struct ADASHUDView: View {
    
    public let hostSpeedKmh: Double
    public let leadState: LeadVehicleState?
    public let leadTrackId: Int?
    public let trackedVehicles: [TrackedVehicle]
    public let activeLeadVehicle: TrackedVehicle?
    public let vpXNormalized: Double
    public let vpYNormalized: Double
    public let detectedLane: DetectedLane?
    public let viewSize: CGSize
    
    @State private var isPulsing: Bool = false
    
    public init(
        hostSpeedKmh: Double,
        leadState: LeadVehicleState?,
        leadTrackId: Int?,
        trackedVehicles: [TrackedVehicle],
        activeLeadVehicle: TrackedVehicle?,
        vpXNormalized: Double,
        vpYNormalized: Double,
        detectedLane: DetectedLane?,
        viewSize: CGSize
    ) {
        self.hostSpeedKmh = hostSpeedKmh
        self.leadState = leadState
        self.leadTrackId = leadTrackId
        self.trackedVehicles = trackedVehicles
        self.activeLeadVehicle = activeLeadVehicle
        self.vpXNormalized = vpXNormalized
        self.vpYNormalized = vpYNormalized
        self.detectedLane = detectedLane
        self.viewSize = viewSize
    }
    
    public var body: some View {
        ZStack {
            // MARK: Dynamic 3D Road Carpet Overlay
            LaneCarpetView(
                leadVehicle: activeLeadVehicle,
                detectedLane: detectedLane,
                vpXNormalized: vpXNormalized,
                vpYNormalized: vpYNormalized,
                viewSize: viewSize,
                state: leadState
            )
            
            // MARK: Vehicle Bounding Boxes & Floating Tags
            ForEach(trackedVehicles, id: \.trackId) { vehicle in
                let isLead = (vehicle.trackId == leadTrackId && leadState != nil)
                let rect = screenRect(for: vehicle.detection.boundingBox, in: viewSize)
                let color = boxColor(isLead: isLead, state: vehicle.state)
                let lineWidth: CGFloat = isLead ? 3.5 : 1.2
                
                // Bounding Box
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: lineWidth)
                    .shadow(color: isLead ? color.opacity(0.8) : .clear, radius: isLead ? 6 : 0)
                    .frame(width: max(8, rect.width), height: max(8, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(isLead ? 0.95 : 0.35)
                
                // Floating Tag — ONLY for the active Lead Vehicle
                if isLead, let state = leadState {
                    HStack(spacing: 4) {
                        Text(String(format: "%.0fm", state.distance))
                            .fontWeight(.bold)
                        Text("|")
                            .opacity(0.5)
                        Text(String(format: "%.0f km/h", state.absoluteSpeedKmh))
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.85))
                            .overlay(Capsule().stroke(color, lineWidth: 2))
                    )
                    .shadow(color: color.opacity(0.6), radius: 4)
                    .position(x: rect.midX, y: max(24, rect.minY - 22))
                }
            }
            
            // MARK: Top Telemetry Banner
            VStack {
                HStack(spacing: 28) {
                    // LEAD DISTANCE
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEAD DISTANCE")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white.opacity(0.65))
                        if let state = leadState {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.0f", state.distance))
                                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("m")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        } else {
                            Text("-- m")
                                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    
                    Divider()
                        .frame(height: 34)
                        .background(Color.white.opacity(0.2))
                    
                    // LEAD SPEED
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEAD SPEED")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white.opacity(0.65))
                        if let state = leadState {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.0f", state.absoluteSpeedKmh))
                                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                                    .foregroundColor(.cyan)
                                Text("km/h")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.cyan.opacity(0.8))
                            }
                        } else {
                            Text("-- km/h")
                                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    
                    Divider()
                        .frame(height: 34)
                        .background(Color.white.opacity(0.2))
                    
                    // TIME HEADWAY
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TIME HEADWAY")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white.opacity(0.65))
                        if let headway = leadState?.headwaySeconds {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", headway))
                                    .font(.system(size: 26, weight: .heavy, design: .monospaced))
                                    .foregroundColor(headwayColor(headway: headway))
                                Text("s")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(headwayColor(headway: headway).opacity(0.8))
                            }
                        } else {
                            Text("-- s")
                                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(0.75))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.15), lineWidth: 1)
                        )
                )
                .padding(.top, 14)
                
                Spacer()
            }
            
            // MARK: Vietnamese Highway Regulation Warning (Thông tư 31/2019/TT-BGTVT)
            VStack {
                Spacer()
                if let warning = safeDistanceWarning {
                    Text(warning)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.9))
                        )
                        .shadow(color: .red.opacity(0.5), radius: 6)
                        .padding(.bottom, 16)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            
            // MARK: Forward Collision Warning (FCW) Alert
            if isCriticalDanger {
                ZStack {
                    RadialGradient(
                        gradient: Gradient(colors: [Color.clear, Color.red.opacity(isPulsing ? 0.8 : 0.3)]),
                        center: .center,
                        startRadius: viewSize.width * 0.20,
                        endRadius: viewSize.width * 0.65
                    )
                    .ignoresSafeArea()
                    
                    Text("⚠️ BRAKE")
                        .font(.system(size: 64, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .red, radius: 20)
                        .scaleEffect(isPulsing ? 1.05 : 0.95)
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.25).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
    
    // MARK: - Safety Logic
    
    private var isCriticalDanger: Bool {
        guard let state = leadState, hostSpeedKmh > 25.0 else { return false }
        if let ttc = state.timeToCollision, ttc < 1.8 { return true }
        return false
    }
    
    private var safeDistanceWarning: String? {
        guard hostSpeedKmh > 60.0, let state = leadState else { return nil }
        
        let minimumDistance: Double
        if hostSpeedKmh > 100.0 {
            minimumDistance = 100.0
        } else if hostSpeedKmh > 80.0 {
            minimumDistance = 70.0
        } else {
            minimumDistance = 55.0
        }
        
        guard state.distance < minimumDistance else { return nil }
        
        return "GẦN HƠN QUY ĐỊNH (\(Int(state.distance))m / Tối thiểu \(Int(minimumDistance))m)"
    }
    
    // MARK: - Styling Helpers
    
    private func boxColor(isLead: Bool, state: LeadVehicleState) -> Color {
        guard isLead else { return Color(red: 0.0, green: 1.0, blue: 0.35).opacity(0.6) } // Faint neon green
        if isCriticalDanger { return Color(red: 1.0, green: 0.09, blue: 0.27) } // Neon Red
        if let headway = state.headwaySeconds {
            if headway > 2.2 { return Color(red: 0.0, green: 1.0, blue: 0.35) } // Neon Green
            if headway >= 1.5 { return Color(red: 1.0, green: 0.7, blue: 0.0) } // Neon Amber
            return Color(red: 1.0, green: 0.09, blue: 0.27) // Neon Red
        }
        return Color(red: 0.0, green: 1.0, blue: 0.35) // Neon Green
    }
    
    private func headwayColor(headway: Double) -> Color {
        if headway > 2.2 { return Color(red: 0.0, green: 1.0, blue: 0.35) }
        if headway >= 1.5 { return Color(red: 1.0, green: 0.7, blue: 0.0) }
        return Color(red: 1.0, green: 0.09, blue: 0.27)
    }
    
    private func screenRect(for normalizedBox: CGRect, in size: CGSize) -> CGRect {
        return CGRect(
            x: normalizedBox.minX * size.width,
            y: normalizedBox.minY * size.height,
            width: normalizedBox.width * size.width,
            height: normalizedBox.height * size.height
        )
    }
}