import SwiftUI

/// A perspective-correct 3D lane overlay (road carpet).
public struct LaneCarpetView: View {
    public let vpYNormalized: Double
    public let viewSize: CGSize
    
    public init(vpYNormalized: Double, viewSize: CGSize) {
        self.vpYNormalized = vpYNormalized
        self.viewSize = viewSize
    }
    
    public var body: some View {
        // Perspective Trapezoid Path
        Path { path in
            let vpX = viewSize.width * 0.5
            let vpY = viewSize.height * vpYNormalized
            let bottomY = viewSize.height * 0.82
            
            // Widths mapping to OnlineCalibrator logic (12% at horizon, 40% at hood/bumper)
            let topHalfWidth = viewSize.width * 0.06
            let bottomHalfWidth = viewSize.width * 0.20
            
            path.move(to: CGPoint(x: vpX - topHalfWidth, y: vpY))
            path.addLine(to: CGPoint(x: vpX + topHalfWidth, y: vpY))
            path.addLine(to: CGPoint(x: vpX + bottomHalfWidth, y: bottomY))
            path.addLine(to: CGPoint(x: vpX - bottomHalfWidth, y: bottomY))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.green.opacity(0.0),
                    Color.green.opacity(0.25)
                ]),
                startPoint: UnitPoint(x: 0.5, y: vpYNormalized),
                endPoint: UnitPoint(x: 0.5, y: 0.82)
            )
        )
        // Draw crisp edge lines for the lane boundaries
        .overlay(
            Path { path in
                let vpX = viewSize.width * 0.5
                let vpY = viewSize.height * vpYNormalized
                let bottomY = viewSize.height * 0.82
                let topHalfWidth = viewSize.width * 0.06
                let bottomHalfWidth = viewSize.width * 0.20
                
                // Left lane line
                path.move(to: CGPoint(x: vpX - topHalfWidth, y: vpY))
                path.addLine(to: CGPoint(x: vpX - bottomHalfWidth, y: bottomY))
                
                // Right lane line
                path.move(to: CGPoint(x: vpX + topHalfWidth, y: vpY))
                path.addLine(to: CGPoint(x: vpX + bottomHalfWidth, y: bottomY))
            }
            .stroke(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.1),
                        Color.cyan.opacity(0.6)
                    ]),
                    startPoint: UnitPoint(x: 0.5, y: vpYNormalized),
                    endPoint: UnitPoint(x: 0.5, y: 0.82)
                ),
                lineWidth: 2.0
            )
        )
    }
}

/// Clean, compact ADAS Heads-Up Display for highway driving.
///
/// Contains visual 3D lane overlay, tracked vehicle bounding boxes,
/// and dynamic typography mapping.
public struct ADASHUDView: View {
    
    public let hostSpeedKmh: Double
    public let leadState: LeadVehicleState?
    public let leadTrackId: Int?
    public let trackedVehicles: [TrackedVehicle]
    public let vpYNormalized: Double
    public let viewSize: CGSize
    
    @State private var isPulsing: Bool = false
    
    public init(
        hostSpeedKmh: Double,
        leadState: LeadVehicleState?,
        leadTrackId: Int?,
        trackedVehicles: [TrackedVehicle],
        vpYNormalized: Double,
        viewSize: CGSize
    ) {
        self.hostSpeedKmh = hostSpeedKmh
        self.leadState = leadState
        self.leadTrackId = leadTrackId
        self.trackedVehicles = trackedVehicles
        self.vpYNormalized = vpYNormalized
        self.viewSize = viewSize
    }
    
    public var body: some View {
        ZStack {
            // MARK: - 0. Visual 3D Road Carpet Overlay
            LaneCarpetView(vpYNormalized: vpYNormalized, viewSize: viewSize)
            
            // MARK: - 1. Vehicle Bounding Boxes & Floating Tags
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