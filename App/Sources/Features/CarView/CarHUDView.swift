import SwiftUI

struct CarHUDView: View {
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette
    @Environment(ESP32Source.self) private var esp32

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Row 1: Gear selector and fuel indicator
            HStack {
                gearSelectorText
                    .font(TeslaFont.ui(14, .semibold))
                    .tracking(6)
                if let g = esp32.manualGear, vehicle.gear == .drive {
                    Text("\(g)")
                        .font(TeslaFont.ui(14, .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.accent))
                }

                Spacer()

                HStack(spacing: 6) {
                    Text("\(Int(vehicle.fuelLevel * 100))%")
                        .font(TeslaFont.ui(13, .medium))
                        .foregroundColor(palette.textSecondary)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .strokeBorder(palette.textSecondary, lineWidth: 1)
                        Capsule()
                            .fill(palette.textPrimary)
                            .frame(width: max(0, min(34, 34 * CGFloat(vehicle.fuelLevel))))
                    }
                    .frame(width: 34, height: 12)
                    .clipShape(Capsule())

                    Image(systemName: "fuelpump.fill")
                        .font(.system(size: 12))
                        .foregroundColor(palette.textSecondary)
                }
            }

            // Row 2: Speed and speed limit (hidden in Park)
            if vehicle.gear != .park {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: -6) {
                        Text("\(Int(vehicle.speedKmh.rounded()))")
                            .font(TeslaFont.speed)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                            .foregroundColor(palette.textPrimary)
                            .animation(.easeOut(duration: 0.2), value: Int(vehicle.speedKmh))

                        Text("KM/H")
                            .font(TeslaFont.caption)
                            .foregroundColor(palette.textSecondary)
                    }

                    Spacer()

                    if let limit = vehicle.speedLimitKmh {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 56, height: 56)
                            Circle()
                                .strokeBorder(Theme.warningRed, lineWidth: 6)
                                .frame(width: 56, height: 56)
                            Text("\(limit)")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.black)
                        }
                    }
                }
            }

            // Row 3: Telltales column and blinker indicators
            VStack(alignment: .leading, spacing: 14) {
                if vehicle.blinkerLeft || vehicle.blinkerRight {
                    TimelineView(.periodic(from: .now, by: 1.0 / 3.0)) { context in
                        let isBlinkOn = Int(context.date.timeIntervalSinceReferenceDate * 3.0) % 2 == 0
                        HStack(spacing: 8) {
                            if vehicle.blinkerLeft {
                                Image(systemName: "arrowtriangle.left.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Theme.blinkerGreen)
                                    .opacity(isBlinkOn ? 1.0 : 0.0)
                            }
                            if vehicle.blinkerRight {
                                Image(systemName: "arrowtriangle.right.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(Theme.blinkerGreen)
                                    .opacity(isBlinkOn ? 1.0 : 0.0)
                            }
                        }
                    }
                }

                if vehicle.lowBeam {
                    Image(systemName: "headlight.low.beam.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.telltaleGreen)
                }

                if vehicle.highBeam {
                    Image(systemName: "headlight.high.beam.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.telltaleBlue)
                }

                if vehicle.fogLights {
                    Image(systemName: "headlight.fog.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.telltaleGreen)
                }

                if vehicle.seatbeltUnfastened {
                    Image(systemName: "figure.seated.seatbelt")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.warningRed)
                }

                if vehicle.gear == .park {
                    Image(systemName: "parkingsign.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(Theme.warningRed)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var gearSelectorText: Text {
        Gear.allCases.reduce(Text("")) { result, gear in
            let isCurrent = vehicle.gear == gear
            let letter = Text(gear.rawValue)
                .foregroundColor(isCurrent ? palette.textPrimary : palette.inactive)
                .fontWeight(isCurrent ? .bold : .semibold)
            return result + letter
        }
    }
}