import SwiftUI

// MARK: - 1. Dynamic 3D Adaptive Lane Carpet

public struct LaneCarpetView: View {
    public let leadVehicle: TrackedVehicle?
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
        vpXNormalized: Double,
        vpYNormalized: Double,
        viewSize: CGSize,
        state: LeadVehicleState?
    ) {
        self.leadVehicle = leadVehicle
        self.vpXNormalized = vpXNormalized
        self.vpYNormalized = vpYNormalized
        self.viewSize = viewSize
        self.state = state
    }
    
    public var body: some View {
        let geom = calculateGeometry()
        
        ZStack {
            // Fill Gradient
            CarpetShape(geom: geom)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            carpetColor.opacity(0.20),
                            carpetColor.opacity(0.65)
                        ]),
                        startPoint: UnitPoint(x: 0.5, y: geom.topY / viewSize.height),
                        endPoint: UnitPoint(x: 0.5, y: geom.bottomY / viewSize.height)
                    )
                )
            
            // Crisp Neon Boundary Lines with Glow
            CarpetBorders(geom: geom)
                .stroke(carpetColor, lineWidth: 3.5)
                .shadow(color: carpetColor.opacity(0.8), radius: 6)
            
            // Perspective Depth Chevrons
            CarpetChevrons(geom: geom)
                .stroke(carpetColor.opacity(0.5), lineWidth: 2.0)
        }
    }
    
    struct CarpetGeometry {
        let topY: CGFloat
        let topCenterX: CGFloat
        let topHalfWidth: CGFloat
        let bottomY: CGFloat
        let bottomCenterX: CGFloat
        let bottomHalfWidth: CGFloat
    }
    
    private func calculateGeometry() -> CarpetGeometry {
        let bottomY = viewSize.height * 0.85
        let bottomCenterX = viewSize.width * 0.5
        let bottomHalfWidth = viewSize.width * 0.24
        
        let topY: CGFloat
        let topCenterX: CGFloat
        let topHalfWidth: CGFloat
        
        if let lead = leadVehicle {
            // Anchor to the lead vehicle's tire-road contact line
            let leadBottomY = lead.detection.bottomY
            let leadMidX = lead.detection.boundingBox.midX
            let leadWidth = lead.detection.boundingBox.width
            
            topY = viewSize.height * min(CGFloat(leadBottomY), 0.78)
            topCenterX = viewSize.width * CGFloat(leadMidX)
            
            let screenLeadWidth = viewSize.width * CGFloat(leadWidth)
            topHalfWidth = max(viewSize.width * 0.04, screenLeadWidth * 0.55)
        } else {
            // Converge toward the dynamic vanishing point
            topY = viewSize.height * vpYNormalized
            topCenterX = viewSize.width * vpXNormalized
            topHalfWidth = viewSize.width * 0.06
        }
        
        return CarpetGeometry(
            topY: topY,
            topCenterX: topCenterX,
            topHalfWidth: topHalfWidth,
            bottomY: bottomY,
            bottomCenterX: bottomCenterX,
            bottomHalfWidth: bottomHalfWidth
        )
    }
}

// MARK: - Carpet Geometries

private struct CarpetShape: Shape {
    let geom: LaneCarpetView.CarpetGeometry
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let topLeft = CGPoint(x: geom.topCenterX - geom.topHalfWidth, y: geom.topY)
        let topRight = CGPoint(x: geom.topCenterX + geom.topHalfWidth, y: geom.topY)
        let bottomLeft = CGPoint(x: geom.bottomCenterX - geom.bottomHalfWidth, y: geom.bottomY)
        let bottomRight = CGPoint(x: geom.bottomCenterX + geom.bottomHalfWidth, y: geom.bottomY)
        
        let midY = (geom.topY + geom.bottomY) / 2
        let ctrlLeft = CGPoint(x: (topLeft.x + bottomLeft.x) / 2 - 15, y: midY)
        let ctrlRight = CGPoint(x: (topRight.x + bottomRight.x) / 2 + 15, y: midY)
        
        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addQuadCurve(to: bottomRight, control: ctrlRight)
        path.addLine(to: bottomLeft)
        path.addQuadCurve(to: topLeft, control: ctrlLeft)
        path.closeSubpath()
        
        return path
    }
}

private struct CarpetBorders: Shape {
    let geom: LaneCarpetView.CarpetGeometry
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let topLeft = CGPoint(x: geom.topCenterX - geom.topHalfWidth, y: geom.topY)
        let topRight = CGPoint(x: geom.topCenterX + geom.topHalfWidth, y: geom.topY)
        let bottomLeft = CGPoint(x: geom.bottomCenterX - geom.bottomHalfWidth, y: geom.bottomY)
        let bottomRight = CGPoint(x: geom.bottomCenterX + geom.bottomHalfWidth, y: geom.bottomY)
        
        let midY = (geom.topY + geom.bottomY) / 2
        let ctrlLeft = CGPoint(x: (topLeft.x + bottomLeft.x) / 2 - 15, y: midY)
        let ctrlRight = CGPoint(x: (topRight.x + bottomRight.x) / 2 + 15, y: midY)
        
        // Left edge
        path.move(to: topLeft)
        path.addQuadCurve(to: bottomLeft, control: ctrlLeft)
        // Right edge
        path.move(to: topRight)
        path.addQuadCurve(to: bottomRight, control: ctrlRight)
        
        return path
    }
}

private struct CarpetChevrons: Shape {
    let geom: LaneCarpetView.CarpetGeometry
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 5
        
        let topLeft = CGPoint(x: geom.topCenterX - geom.topHalfWidth, y: geom.topY)
        let topRight = CGPoint(x: geom.topCenterX + geom.topHalfWidth, y: geom.topY)
        let bottomLeft = CGPoint(x: geom.bottomCenterX - geom.bottomHalfWidth, y: geom.bottomY)
        let bottomRight = CGPoint(x: geom.bottomCenterX + geom.bottomHalfWidth, y: geom.bottomY)
        
        let midY = (geom.topY + geom.bottomY) / 2
        let ctrlLeft = CGPoint(x: (topLeft.x + bottomLeft.x) / 2 - 15, y: midY)
        let ctrlRight = CGPoint(x: (topRight.x + bottomRight.x) / 2 + 15, y: midY)
        
        for i in 1..<steps {
            // Non-linear depth spacing
            let t = pow(CGFloat(i) / CGFloat(steps), 1.5)
            let omt = 1.0 - t
            
            // Quadratic bezier interpolation
            let lx = (omt * omt * topLeft.x) + (2 * omt * t * ctrlLeft.x) + (t * t * bottomLeft.x)
            let ly = (omt * omt * topLeft.y) + (2 * omt * t * ctrlLeft.y) + (t * t * bottomLeft.y)
            
            let rx = (omt * omt * topRight.x) + (2 * omt * t * ctrlRight.x) + (t * t * bottomRight.x)
            let ry = (omt * omt * topRight.y) + (2 * omt * t * ctrlRight.y) + (t * t * bottomRight.y)
            
            let cx = (lx + rx) / 2
            let cy = ly - 6 // Point chevron slightly up toward horizon
            
            path.move(to: CGPoint(x: lx, y: ly))
            path.addLine(to: CGPoint(x: cx, y: cy))
            path.addLine(to: CGPoint(x: rx, y: ry))
        }
        
        return path
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
        viewSize: CGSize
    ) {
        self.hostSpeedKmh = hostSpeedKmh
        self.leadState = leadState
        self.leadTrackId = leadTrackId
        self.trackedVehicles = trackedVehicles
        self.activeLeadVehicle = activeLeadVehicle
        self.vpXNormalized = vpXNormalized
        self.vpYNormalized = vpYNormalized
        self.viewSize = viewSize
    }
    
    public var body: some View {
        ZStack {
            // MARK: Dynamic 3D Road Carpet Overlay
            LaneCarpetView(
                leadVehicle: activeLeadVehicle,
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