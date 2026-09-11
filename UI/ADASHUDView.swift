import SwiftUI

public struct ADASHUDView: View {
    public let hostSpeedKmh: Double
    public let leadState: LeadVehicleState?
    public let detections: [Detection]
    public let viewSize: CGSize
    
    @State private var isPulsing: Bool = false
    
    public init(
        hostSpeedKmh: Double,
        leadState: LeadVehicleState?,
        detections: [Detection],
        viewSize: CGSize
    ) {
        self.hostSpeedKmh = hostSpeedKmh
        self.leadState = leadState
        self.detections = detections
        self.viewSize = viewSize
    }
    
    public var body: some View {
        ZStack {
            // MARK: - 1. Bounding Boxes & Floating Tags
            ForEach(Array(detections.enumerated()), id: \.element.id) { index, detection in
                let isLead = (leadState != nil && index == 0 && isInsideLane(detection.boundingBox))
                let rect = screenRect(for: detection.boundingBox, in: viewSize)
                let color = boxColor(isLead: isLead)
                let width: CGFloat = isLead ? 3.5 : 1.5
                
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: width)
                    .frame(width: max(10, rect.width), height: max(10, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                
                if isLead, let state = leadState {
                    HStack(spacing: 6) {
                        Text(String(format: "%.0fm", state.distance))
                            .fontWeight(.black)
                        Text("•")
                            .opacity(0.6)
                        Text(String(format: "%.0f km/h", state.absoluteSpeedKmh))
                            .fontWeight(.bold)
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.8))
                            .overlay(Capsule().stroke(color, lineWidth: 1.5))
                    )
                    .position(x: rect.midX, y: max(28, rect.minY - 18))
                }
            }
            
            // MARK: - 2. Streamlined Highway Telemetry Banner (No Host Speed)
            VStack {
                HStack(spacing: 36) {
                    // LEAD DISTANCE
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEAD DISTANCE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        if let state = leadState {
                            Text(String(format: "%.0f", state.distance))
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(.white) +
                            Text(" m").font(.system(size: 16, weight: .bold)).foregroundColor(.white.opacity(0.8))
                        } else {
                            Text("-- m")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    
                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.2))
                    
                    // LEAD SPEED
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEAD SPEED")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        if let state = leadState {
                            Text(String(format: "%.0f", state.absoluteSpeedKmh))
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(.cyan) +
                            Text(" km/h").font(.system(size: 14, weight: .bold)).foregroundColor(.cyan.opacity(0.8))
                        } else {
                            Text("-- km/h")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    
                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.2))
                    
                    // TIME HEADWAY
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TIME HEADWAY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        if let headway = leadState?.headwaySeconds {
                            Text(String(format: "%.1f", headway))
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(headwayColor(headway: headway)) +
                            Text(" s").font(.system(size: 16, weight: .bold)).foregroundColor(headwayColor(headway: headway))
                        } else {
                            Text("-- s")
                                .font(.system(size: 32, weight: .black, design: .rounded))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.black.opacity(0.7))
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
            
            // MARK: - 3. Forward Collision Warning Alert
            if isCriticalDanger {
                ZStack {
                    RadialGradient(
                        gradient: Gradient(colors: [Color.clear, Color.red.opacity(isPulsing ? 0.7 : 0.25)]),
                        center: .center,
                        startRadius: viewSize.width * 0.25,
                        endRadius: viewSize.width * 0.65
                    )
                    .ignoresSafeArea()
                    
                    VStack(spacing: 8) {
                        Text("⚠️ BRAKE")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
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
    
    private func isInsideLane(_ box: CGRect) -> Bool {
        return box.midX >= 0.32 && box.midX <= 0.68
    }
    
    private var isCriticalDanger: Bool {
        guard let state = leadState, hostSpeedKmh > 25.0 else { return false }
        if let ttc = state.timeToCollision, ttc < 1.8 { return true }
        return false
    }
    
    private func boxColor(isLead: Bool) -> Color {
        guard isLead, let state = leadState else { return Color.green.opacity(0.5) }
        if isCriticalDanger { return .red }
        if let headway = state.headwaySeconds {
            if headway > 2.2 { return .green }
            if headway >= 1.4 { return .orange }
            return .red
        }
        return .green
    }
    
    private func headwayColor(headway: Double) -> Color {
        if headway > 2.2 { return .green }
        if headway >= 1.4 { return .orange }
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