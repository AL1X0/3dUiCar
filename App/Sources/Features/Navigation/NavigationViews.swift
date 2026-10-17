import SwiftUI
import MapKit

fileprivate func formatDistance(_ m: Double) -> String {
    let dist = max(0, m)
    if dist < 1000 {
        let rounded = Int((dist / 10.0).rounded()) * 10
        return "\(rounded) m"
    } else {
        let km = dist / 1000.0
        return String(format: "%.1f km", locale: Locale(identifier: "fr_FR"), km)
    }
}

// MARK: - NavSearchBar

struct NavSearchBar: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(\.palette) private var palette
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        @Bindable var n = nav

        Group {
            if nav.phase != .searching {
                Button {
                    nav.beginSearch()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                        Text("Naviguer")
                            .font(TeslaFont.ui(17))
                        Spacer()
                    }
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 16)
                    .frame(width: 420, height: 54)
                    .background(palette.panel)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                }
                .buttonStyle(TeslaPressStyle())
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(palette.textSecondary)

                        TextField("Rechercher une destination", text: $n.query)
                            .font(TeslaFont.ui(17))
                            .foregroundStyle(palette.textPrimary)
                            .autocorrectionDisabled()
                            .focused($isFieldFocused)

                        Button {
                            nav.cancel()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(TeslaPressStyle())
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 54)

                    if let errorMessage = nav.errorMessage {
                        Text(errorMessage)
                            .font(TeslaFont.ui(14))
                            .foregroundStyle(Theme.warningRed)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !nav.suggestions.isEmpty {
                        Divider()
                        VStack(spacing: 0) {
                            let displayedSuggestions = Array(nav.suggestions.prefix(6))
                            ForEach(Array(displayedSuggestions.enumerated()), id: \.offset) { index, item in
                                Button {
                                    nav.select(item)
                                } label: {
                                    HStack(spacing: 14) {
                                        Image(systemName: "mappin.circle.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(Theme.accent)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.title)
                                                .font(TeslaFont.ui(16, .semibold))
                                                .foregroundStyle(palette.textPrimary)
                                                .lineLimit(1)
                                            if !item.subtitle.isEmpty {
                                                Text(item.subtitle)
                                                    .font(TeslaFont.ui(13))
                                                    .foregroundStyle(palette.textSecondary)
                                                    .lineLimit(1)
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(height: 56)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(TeslaPressStyle())

                                if index < displayedSuggestions.count - 1 {
                                    Divider()
                                }
                            }
                        }
                    }
                }
                .frame(width: 420)
                .background(palette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .onAppear {
                    isFieldFocused = true
                }
            }
        }
    }
}

// MARK: - RoutePreviewCard

struct RoutePreviewCard: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(\.palette) private var palette

    var body: some View {
        @Bindable var n = nav

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(nav.destination?.name ?? "Destination")
                    .font(TeslaFont.ui(22, .semibold))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)

                if let address = nav.destination?.placemark.title {
                    Text(address)
                        .font(TeslaFont.ui(14))
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(2)
                }
            }

            if nav.isCalculating {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 24)
                    Spacer()
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(nav.routes.enumerated()), id: \.offset) { index, route in
                        let isSelected = index == nav.selectedRouteIndex
                        let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))

                        Button {
                            n.selectedRouteIndex = index
                        } label: {
                            HStack(alignment: .center, spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text("\(minutes) min")
                                            .font(TeslaFont.ui(20, .semibold))
                                            .foregroundStyle(palette.textPrimary)

                                        Text(formatDistance(route.distance))
                                            .font(TeslaFont.ui(15))
                                            .foregroundStyle(palette.textSecondary)
                                    }
                                    if !route.name.isEmpty {
                                        Text(route.name)
                                            .font(TeslaFont.ui(13))
                                            .foregroundStyle(palette.textSecondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(isSelected ? palette.background : palette.panelSecondary.opacity(0.35))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? Theme.accent : palette.outline, lineWidth: isSelected ? 2 : 1)
                            )
                        }
                        .buttonStyle(TeslaPressStyle())
                    }
                }

                HStack(spacing: 12) {
                    AccentButton(title: "Démarrer", systemImage: "location.fill") {
                        nav.start()
                    }
                    AccentButton(title: "Annuler", isOn: false, width: 130) {
                        nav.cancel()
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

// MARK: - TurnBanner

struct TurnBanner: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: nav.maneuver.symbol)
                .font(.system(size: 46, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(formatDistance(nav.distanceToNextStep))
                    .font(TeslaFont.ui(30, .semibold))
                    .foregroundStyle(.white)

                Text(nav.currentStep?.instructions ?? "")
                    .font(TeslaFont.ui(17))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 420)
        .background(Color(hex: 0x1F1F1F))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}

// MARK: - TripETACard

struct TripETACard: View {
    @Environment(NavigationModel.self) private var nav
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nav.arrivalDate.formatted(.dateTime.hour().minute()))
                    .font(TeslaFont.ui(26, .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("Arrivée")
                    .font(TeslaFont.ui(12))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()

            VStack(alignment: .center, spacing: 2) {
                Text("\(max(0, Int(nav.remainingTime / 60))) min")
                    .font(TeslaFont.ui(20, .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("restantes")
                    .font(TeslaFont.ui(12))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()

            VStack(alignment: .center, spacing: 2) {
                Text(formatDistance(nav.remainingDistance))
                    .font(TeslaFont.ui(20, .semibold))
                    .foregroundStyle(palette.textPrimary)
                Text("restants")
                    .font(TeslaFont.ui(12))
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()

            Button {
                nav.stop()
            } label: {
                Circle()
                    .fill(Theme.warningRed)
                    .frame(width: 52, height: 52)
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                    }
            }
            .buttonStyle(TeslaPressStyle())
        }
        .padding(16)
        .frame(width: 420)
        .background(palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
    }
}