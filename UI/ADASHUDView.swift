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
                let lineWidth: CGFloat = isLead ? 3.0 : 1.2
                
                // Bounding Box
                RoundedRectangle(cornerRadius: 5)
                    .stroke(color, lineWidth: lineWidth)
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
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.75))
                            .overlay(Capsule().stroke(color.opacity(0.8), lineWidth: 1.5))
                    )
                    .position(x: rect.midX, y: max(24, rect.minY - 18))
                }
            }
            
            // MARK: - 2. Top Telemetry Banner (3 Columns)
            VStack {
                HStack(spacing: 28) {
                    // Column 1: LEAD DISTANCE
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEAD DISTANCE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        if let state = leadState {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.0f", state.distance))
                                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                Text("m")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        } else {
                            Text("-- m")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                    
                    Divider()
                        .frame(height: 32)
                        .background(Color.white.opacity(0.15))
                    
                    // Column 2: LEAD SPEED
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEAD SPEED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        if let state = leadState {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.0f", state.absoluteSpeedKmh))
                                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                                    .foregroundColor(.cyan)
                                Text("km/h")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.cyan.opacity(0.7))
                            }
                        } else {
                            Text("-- km/h")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                    
                    Divider()
                        .frame(height: 32)
                        .background(Color.white.opacity(0.15))
                    
                    // Column 3: TIME HEADWAY
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TIME HEADWAY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        if let headway = leadState?.headwaySeconds {
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(String(format: "%.1f", headway))
                                    .font(.system(size: 26, weight: .bold, design: .monospaced))
                                    .foregroundColor(headwayColor(headway: headway))
                                Text("s")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(headwayColor(headway: headway).opacity(0.7))
                            }
                        } else {
                            Text("-- s")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.65))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        )
                )
                .padding(.top, 12)
                
                Spacer()
            }
            
            // MARK: - 3. Vietnamese Highway Regulation Warning (Thông tư 31/2019/TT-BGTVT)
            VStack {
                Spacer()
                if let warning = safeDistanceWarning {
                    Text(warning)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.red.opacity(0.85))
                        )
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            
            // MARK: - 4. Forward Collision Warning (FCW) Alert
            if isCriticalDanger {
                ZStack {
                    RadialGradient(
                        gradient: Gradient(colors: [Color.clear, Color.red.opacity(isPulsing ? 0.7 : 0.2)]),
                        center: .center,
                        startRadius: viewSize.width * 0.25,
                        endRadius: viewSize.width * 0.6
                    )
                    .ignoresSafeArea()
                    
                    Text("⚠️ BRAKE")
                        .font(.system(size: 56, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .shadow(color: .red, radius: 16)
                        .scaleEffect(isPulsing ? 1.04 : 0.96)
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
    
    /// Vietnamese Highway Regulation (Thông tư 31/2019/TT-BGTVT) safe distance warning.
    /// Active only when host speed exceeds 60 km/h.
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
        guard isLead else { return Color.green.opacity(0.5) }
        if isCriticalDanger { return .red }
        if let headway = state.headwaySeconds {
            if headway > 2.4 { return .green }
            if headway >= 1.5 { return .orange }
            return .red
        }
        return .green
    }
    
    private func headwayColor(headway: Double) -> Color {
        if headway > 2.4 { return .green }
        if headway >= 1.5 { return .orange }
        return .red
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