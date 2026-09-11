import SwiftUI

public struct ADASHUDView: View {
    public let hostSpeedKmh: Double
    public let leadState: LeadVehicleState?
    public let leadId: UUID?
    public let detections: [Detection]
    public let viewSize: CGSize
    
    @State private var isPulsing: Bool = false
    
    public init(
        hostSpeedKmh: Double,
        leadState: LeadVehicleState?,
        leadId: UUID?,
        detections: [Detection],
        viewSize: CGSize
    ) {
        self.hostSpeedKmh = hostSpeedKmh
        self.leadState = leadState
        self.leadId = leadId
        self.detections = detections
        self.viewSize = viewSize
    }
    
    public var body: some View {
        ZStack {
            // MARK: - 1. Vehicle Bounding Boxes & Floating Tags
            ForEach(detections) { detection in
                let isLead = (detection.id == leadId && leadState != nil)
                let rect = screenRect(for: detection.boundingBox, in: viewSize)
                let color = boxColor(isLead: isLead)
                let width: CGFloat = isLead ? 3.0 : 1.2
                
                // Detection Bounding Box
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: width)
                    .frame(width: max(10, rect.width), height: max(10, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(isLead ? 0.95 : 0.45)
                
                // ONLY the in-lane Lead Vehicle receives the floating tag
                if isLead, let state = leadState {
                    HStack(spacing: 5) {
                        Text(String(format: "%.0fm", state.distance))
                            .fontWeight(.bold)
                        Text("|")
                            .opacity(0.6)
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
                    .position(x: rect.midX, y: max(26, rect.minY - 18))
                }
            }
            
            // MARK: - 2. Restored Original Clean Typography Banner
            VStack {
                HStack(spacing: 32) {
                    // LEAD DISTANCE
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
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        } else {
                            Text("-- m")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    
                    Divider()
                        .frame(height: 34)
                        .background(Color.white.opacity(0.2))
                    
                    // LEAD SPEED
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
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.cyan.opacity(0.8))
                            }
                        } else {
                            Text("-- km/h")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    
                    Divider()
                        .frame(height: 34)
                        .background(Color.white.opacity(0.2))
                    
                    // TIME HEADWAY
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
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(headwayColor(headway: headway))
                            }
                        } else {
                            Text("-- s")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(0.65))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                )
                .padding(.top, 14)
                
                Spacer()
            }
            
            // MARK: - 3. Forward Collision Warning Alert
            if isCriticalDanger {
                ZStack {
                    RadialGradient(
                        gradient: Gradient(colors: [Color.clear, Color.red.opacity(isPulsing ? 0.7 : 0.2)]),
                        center: .center,
                        startRadius: viewSize.width * 0.25,
                        endRadius: viewSize.width * 0.6
                    )
                    .ignoresSafeArea()
                    
                    VStack(spacing: 8) {
                        Text("⚠️ BRAKE")
                            .font(.system(size: 58, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .red, radius: 16)
                    }
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
    
    private var isCriticalDanger: Bool {
        guard let state = leadState, hostSpeedKmh > 25.0 else { return false }
        if let ttc = state.timeToCollision, ttc < 1.8 { return true }
        return false
    }
    
    private func boxColor(isLead: Bool) -> Color {
        guard isLead, let state = leadState else {
            return Color.green.opacity(0.5) // Adjacent lane vehicles
        }
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