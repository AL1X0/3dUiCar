import SwiftUI

struct StatusBarView: View {
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    init() {}

    var body: some View {
        HStack(spacing: 16) {
            // Lock status icon
            Image(systemName: vehicle.locked ? "lock.fill" : "lock.open.fill")

            // Current time updated every minute
            TimelineView(.everyMinute) { timeline in
                Text(timeline.date.formatted(Date.FormatStyle().hour().minute()))
            }

            // Outside temperature
            if let temp = vehicle.outsideTempC {
                Text("\(Int(temp)) °C")
            }

            // Profile indicator
            HStack(spacing: 6) {
                Image(systemName: "person.fill")
                Text("Profil")
            }

            Spacer()

            // Location source indicator
            Image(systemName: "location.fill")
                .foregroundStyle(vehicle.locationSource != .none ? Theme.accent : palette.inactive)

            // OBD connection indicator
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundStyle(vehicle.obdConnected ? Theme.teal : palette.inactive)

            // Passenger airbag badge
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.yellow)

                Text("AIRBAG\nPASSAGER OFF")
                    .font(.system(size: 8, weight: .bold))
                    .lineLimit(2)
                    .lineSpacing(-1)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
        }
        .font(TeslaFont.ui(14, .medium))
        .foregroundStyle(palette.textPrimary)
        .padding(.horizontal, 20)
        .frame(height: 44)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 4, x: 2, y: 4)
    }
}