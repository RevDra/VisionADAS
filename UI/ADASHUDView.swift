import SwiftUI

/// Clean, high-visibility automotive HUD (Heads-Up Display) inspired by Openpilot and Tesla vision.
///
/// Overlays:
/// - Top telemetry banner (Host speed, Lead distance, Time headway)
/// - Color-coded bounding box for lead & secondary vehicles
/// - Floating distance & speed tag above lead vehicle
/// - Forward Collision Warning (FCW) pulsing alert overlay
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
            // MARK: - 1. Vehicle Bounding Boxes & Floating Tags
            ForEach(Array(detections.enumerated()), id: \.element.id) { index, detection in
                let isLead = (index == 0)
                let rect = screenRect(for: detection.boundingBox, in: viewSize)
                let color = boxColor(isLead: isLead)
                let width = boxStrokeWidth(isLead: isLead)
                let isCritical = isLead && isCriticalDanger
                
                // Detection Bounding Box
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color, lineWidth: width)
                    .frame(width: max(10, rect.width), height: max(10, rect.height))
                    .position(x: rect.midX, y: rect.midY)
                    .opacity(isCritical ? (isPulsing ? 0.35 : 1.0) : 0.9)
                
                // Floating Telemetry Tag over Lead Vehicle
                if isLead, let state = leadState {
                    HStack(spacing: 4) {
                        Text(String(format: "%.1fm", state.distance))
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
                            .overlay(
                                Capsule()
                                    .stroke(color.opacity(0.8), lineWidth: 1.5)
                            )
                    )
                    // Position tag right above the top edge of the bounding box
                    .position(x: rect.midX, y: max(30, rect.minY - 20))
                }
            }
            
            // MARK: - 2. Top Telemetry Banner
            VStack {
                HStack(spacing: 32) {
                    // Host Speed (Cyan)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", hostSpeedKmh))
                            .font(.system(size: 44, weight: .black, design: .monospaced))
                            .foregroundColor(.cyan)
                        Text("km/h")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.cyan.opacity(0.8))
                    }
                    
                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.2))
                    
                    // Lead Vehicle Distance
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LEAD DISTANCE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        if let state = leadState {
                            Text(String(format: "%.1f m", state.distance))
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        } else {
                            Text("-- m")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                    
                    Divider()
                        .frame(height: 36)
                        .background(Color.white.opacity(0.2))
                    
                    // Time Headway
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TIME HEADWAY")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.6))
                        if let headway = leadState?.headwaySeconds {
                            Text(String(format: "%.1f s", headway))
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(headwayColor(headway: headway))
                        } else {
                            Text("-- s")
                                .font(.system(size: 26, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                        }
                    }
                }
                .padding(.horizontal, 28)
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
                .padding(.top, 16)
                
                Spacer()
            }
            
            // MARK: - 3. Forward Collision Warning (FCW) Full-Screen Alert
            if isCriticalDanger {
                ZStack {
                    // Vignette pulsing red perimeter
                    RadialGradient(
                        gradient: Gradient(colors: [Color.clear, Color.red.opacity(isPulsing ? 0.7 : 0.2)]),
                        center: .center,
                        startRadius: viewSize.width * 0.25,
                        endRadius: viewSize.width * 0.6
                    )
                    .ignoresSafeArea()
                    
                    VStack(spacing: 8) {
                        Text("⚠️ BRAKE")
                            .font(.system(size: 64, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .shadow(color: .red, radius: 16)
                        
                        if let ttc = leadState?.timeToCollision {
                            Text(String(format: "COLLISION IN %.1fs", ttc))
                                .font(.system(size: 18, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.black.opacity(0.7)))
                        }
                    }
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
    
    // MARK: - Safety Criteria & Styling
    
    /// Critical Danger condition: Active only when host vehicle is moving
    private var isCriticalDanger: Bool {
        guard let state = leadState, hostSpeedKmh > 10.0 else { return false }
        
        // Time To Collision critical (< 1.8s) while approaching
        if let ttc = state.timeToCollision, ttc < 1.8 {
            return true
        }
        // Clamping threshold only applies if host is moving fast (> 15 km/h)
        if state.distance < 4.0 && hostSpeedKmh > 15.0 {
            return true
        }
        return false
    }
    
    private func boxColor(isLead: Bool) -> Color {
        guard isLead, let state = leadState else {
            return Color.green.opacity(0.6) // Non-lead targets
        }
        
        // Critical danger: TTC < 1.8s or distance < 6m
        if isCriticalDanger {
            return .red
        }
        
        // Headway thresholds:
        // Green: Safe (Headway > 2.8s)
        // Orange: Caution (1.5s <= Headway <= 2.8s)
        // Red: Danger (Headway < 1.5s)
        if let headway = state.headwaySeconds {
            if headway > 2.8 {
                return .green
            } else if headway >= 1.5 {
                return .orange
            } else {
                return .red
            }
        }
        
        return .green
    }
    
    private func boxStrokeWidth(isLead: Bool) -> CGFloat {
        if !isLead { return 1.5 }
        if isCriticalDanger { return 4.0 }
        if let headway = leadState?.headwaySeconds, headway < 1.5 { return 3.5 }
        if let headway = leadState?.headwaySeconds, headway <= 2.8 { return 2.5 }
        return 2.0
    }
    
    private func headwayColor(headway: Double) -> Color {
        if headway > 2.8 { return .green }
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
