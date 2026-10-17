import SwiftUI

/// Vue du journal en direct pour la section Réglages › Journal.
/// Permet de filtrer par gravité et catégorie, d'exporter et de vider les logs.
struct LogsPage: View {
    @Environment(\.palette) private var palette
    private var store: LogStore { LogStore.shared }

    @State private var category: LogCategory? = nil
    @State private var minLevel: LogLevel = .info
    @State private var reportURL: URL? = nil

    private let levelOptions: [(value: LogLevel, label: String)] = [
        (.debug, "Tout"),
        (.info, "Infos"),
        (.warning, "Alertes"),
        (.error, "Erreurs")
    ]

    var body: some View {
        let filtered = Array(
            store.entries
                .filter { $0.level >= minLevel && (category == nil || $0.category == category) }
                .suffix(400)
        )

        VStack(alignment: .leading, spacing: 12) {
            // (1) Description
            Text("Le journal enregistre ce que fait l'app (Spotify, GPS iPhone, capteurs, OBD, performances). Partage-le pour signaler un problème.")
                .font(TeslaFont.ui(13))
                .foregroundStyle(palette.textSecondary)

            // (2) Actions
            HStack(spacing: 12) {
                AccentButton(title: "Partager le rapport", systemImage: "square.and.arrow.up", width: 240) {
                    reportURL = LogFile.shared.exportReport(header: Log.deviceHeader())
                }

                AccentButton(title: "Effacer", systemImage: "trash", isOn: false, width: 140) {
                    store.clear()
                    Log.info(.app, "Journal effacé")
                }

                if let reportURL {
                    ShareLink(item: reportURL) {
                        Label("Envoyer le fichier", systemImage: "paperplane.fill")
                            .font(TeslaFont.ui(15, .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }

                Spacer()
            }

            // (3) Filtres
            TeslaSegmented(options: levelOptions, selection: $minLevel, height: 44)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button {
                        category = nil
                    } label: {
                        Text("TOUTES")
                            .font(TeslaFont.ui(12, .semibold))
                            .foregroundStyle(category == nil ? .white : palette.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(category == nil ? Theme.accent : palette.panelSecondary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(TeslaPressStyle())

                    ForEach(LogCategory.allCases, id: \.self) { cat in
                        let isSelected = category == cat
                        Button {
                            category = cat
                        } label: {
                            Text(cat.rawValue.uppercased())
                                .font(TeslaFont.ui(12, .semibold))
                                .foregroundStyle(isSelected ? .white : palette.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? Theme.accent : palette.panelSecondary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(TeslaPressStyle())
                    }
                }
            }

            // (4) Compteur et Liste
            HStack {
                Text("\(filtered.count) lignes")
                    .font(TeslaFont.ui(11))
                    .foregroundStyle(palette.textSecondary)
                Spacer()
            }
            .padding(.top, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered) { e in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Log.timestamp.string(from: e.date))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(palette.textSecondary)

                                Text(e.level.tag)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(levelColor(for: e.level))

                                Text(e.category.rawValue)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.accent)

                                Text(e.message)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(palette.textPrimary)
                            }
                            .textSelection(.enabled)
                            .id(e.id)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(palette.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.outline.opacity(0.5), lineWidth: 1))
                .onChange(of: filtered.last?.id) { _, newID in
                    guard let newID else { return }
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .bottom)
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    private func levelColor(for level: LogLevel) -> Color {
        switch level {
        case .debug:
            return .gray
        case .info:
            return palette.textSecondary
        case .warning:
            return .orange
        case .error:
            return Theme.warningRed
        }
    }
}