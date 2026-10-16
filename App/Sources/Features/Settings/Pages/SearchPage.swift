import SwiftUI

struct SearchPage: View {
    @Environment(AppSettings.self) private var settings
    @Environment(VehicleState.self) private var vehicle
    @Environment(\.palette) private var palette

    @State private var query = ""

    private var filteredSections: [SettingsSection] {
        let sections = SettingsSection.allCases.filter { $0 != .search }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sections }
        return sections.filter { $0.title.localizedStandardContains(trimmed) }
    }

    var body: some View {
        @Bindable var s = settings

        SettingsPage {
            SettingsSearchField(text: $query)

            SettingsCaption(text: "Fonctions mises en avant")

            ToggleRow(title: "Feux de route automatiques", isOn: $s.autoHighBeam)
            ToggleRow(title: "Mode démo", isOn: $s.demoMode)

            SettingsDivider()

            VStack(spacing: 0) {
                ForEach(filteredSections) { section in
                    Button {
                        settings.selectedSection = section
                    } label: {
                        HStack(spacing: 16) {
                            Image(section.icon)
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 20, height: 20)
                                .foregroundStyle(palette.textPrimary)

                            Text(section.title)
                                .font(TeslaFont.ui(16))
                                .foregroundStyle(palette.textPrimary)

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.textSecondary)
                        }
                        .frame(height: 48)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if section != filteredSections.last {
                        Rectangle()
                            .fill(palette.outline.opacity(0.5))
                            .frame(height: 1)
                    }
                }
            }
        }
    }
}