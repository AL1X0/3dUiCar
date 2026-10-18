import SwiftUI

/// Jauges moteur façon CarPlay Ultra : compte-tours en arc et petites jauges rondes.
/// Vue séparée : le régime change à 20 Hz, seul ce bloc se redessine.
struct EngineGauges: View {
    @Environment(VehicleState.self) private var vehicle

    var body: some View {
        if let rpm = vehicle.rpm {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    Tachometer(rpm: rpm)
                    smallGauges
                }
                VStack(alignment: .leading, spacing: 12) {
                    Tachometer(rpm: rpm)
                    smallGauges
                }
            }
            .transition(.opacity)
        }
    }

    private var smallGauges: some View {
        HStack(spacing: 12) {
            if let oil = vehicle.oilTempC {
                RingGauge(value: oil, range: 40...150, warn: 125, label: "HUILE",
                          text: "\(Int(oil))°", icon: "oilcan.fill")
            }
            if let water = vehicle.coolantTempC {
                RingGauge(value: water, range: 40...130, warn: 110, label: "EAU",
                          text: "\(Int(water))°", icon: "thermometer.medium")
            }
            if let boost = vehicle.boostBar {
                RingGauge(value: boost, range: -1...1.6, warn: 1.5, label: "TURBO",
                          text: String(format: "%.1f", boost), icon: "fanblades.fill")
            }
        }
    }
}

/// Arc de 270° ouvert en bas, comme les cadrans CarPlay Ultra.
private let arcSpan = 0.75
private let arcStart = Angle.degrees(135)

private struct Tachometer: View {
    let rpm: Double
    @Environment(\.palette) private var palette

    private let maxRpm = 7000.0
    private let redline = 6500.0  // 1.5 EcoBoost Fiesta ST
    private let size: CGFloat = 128

    var body: some View {
        let frac = min(max(rpm / maxRpm, 0), 1)
        let inRed = rpm >= redline - 300
        ZStack {
            ZStack {
                arc(0, 1).stroke(palette.inactive.opacity(0.35), style: .init(lineWidth: 8, lineCap: .round))
                arc(redline / maxRpm, 1).stroke(Theme.warningRed.opacity(0.55), style: .init(lineWidth: 8, lineCap: .round))
                arc(0, frac)
                    .stroke(
                        AngularGradient(colors: [Theme.accent.opacity(0.6), Theme.accent, inRed ? Theme.warningRed : Theme.accent],
                                        center: .center, startAngle: arcStart, endAngle: arcStart + .degrees(270 * frac)),
                        style: .init(lineWidth: 8, lineCap: .round))
                    .shadow(color: (inRed ? Theme.warningRed : Theme.accent).opacity(0.7), radius: 6)
                    .animation(.interpolatingSpring(stiffness: 220, damping: 22), value: frac)
            }
            .padding(4)

            ForEach(0...7, id: \.self) { k in
                tick(k)
            }

            VStack(spacing: -2) {
                Text(String(format: "%.1f", rpm / 1000))
                    .font(TeslaFont.ui(30, .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(inRed ? Theme.warningRed : palette.textPrimary)
                Text("×1000 TR/MIN")
                    .font(TeslaFont.ui(9, .medium))
                    .tracking(1)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Régime moteur \(Int(rpm)) tours par minute")
    }

    private func arc(_ from: Double, _ to: Double) -> some Shape {
        Circle()
            .trim(from: from * arcSpan, to: max(from, to) * arcSpan)
            .rotation(arcStart)
    }

    private func tick(_ k: Int) -> some View {
        let f = Double(k) * 1000 / maxRpm
        return Capsule()
            .fill(Double(k) * 1000 >= redline - 500 ? Theme.warningRed : palette.textSecondary)
            .frame(width: 2, height: 6)
            .offset(y: -size / 2 + 17)
            .rotationEffect(arcStart + .degrees(90 + 270 * f))
    }
}

private struct RingGauge: View {
    let value: Double
    let range: ClosedRange<Double>
    let warn: Double
    let label: String
    let text: String
    let icon: String
    @Environment(\.palette) private var palette

    var body: some View {
        let frac = min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
        let hot = value >= warn
        let color = hot ? Theme.warningRed : Theme.accent
        VStack(spacing: 4) {
            ZStack {
                Circle().trim(from: 0, to: arcSpan).rotation(arcStart)
                    .stroke(palette.inactive.opacity(0.35), style: .init(lineWidth: 5, lineCap: .round))
                Circle().trim(from: 0, to: frac * arcSpan).rotation(arcStart)
                    .stroke(color, style: .init(lineWidth: 5, lineCap: .round))
                    .shadow(color: color.opacity(0.6), radius: 4)
                    .animation(.easeOut(duration: 0.4), value: frac)
                VStack(spacing: 0) {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.textSecondary)
                    Text(text)
                        .font(TeslaFont.ui(14, .semibold))
                        .monospacedDigit()
                        .foregroundStyle(hot ? Theme.warningRed : palette.textPrimary)
                }
            }
            .frame(width: 54, height: 54)
            Text(label)
                .font(TeslaFont.ui(9, .medium))
                .tracking(1)
                .foregroundStyle(palette.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(text)")
    }
}
