import SwiftUI

// Composants de la librairie Figma (toggles, onglets segmentés, tuiles, curseur…).
// Toutes les pages de réglages les utilisent : ne pas recréer de styles ad hoc.

/// Interrupteur Figma : capsule 48×26, bleu accent quand actif.
struct TeslaToggle: View {
    @Binding var isOn: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        Capsule()
            .fill(isOn ? Theme.accent : palette.outline)
            .frame(width: 48, height: 26)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(.white).padding(3).shadow(color: .black.opacity(0.15), radius: 1, y: 1)
            }
            .animation(.easeInOut(duration: 0.18), value: isOn)
            .contentShape(Rectangle())
            .onTapGesture { isOn.toggle() }
            .accessibilityAddTraits(.isButton)
    }
}

/// Titre de bloc : « Titre ⓘ ……… Lien » (lien bleu à droite, ex. « Affichage »).
struct SettingsTitle: View {
    let title: String
    var info = false
    var link: String? = nil
    var linkAction: () -> Void = {}
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(TeslaFont.ui(16, .semibold)).foregroundStyle(palette.textPrimary)
            if info {
                Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
            }
            Spacer()
            if let link {
                Button(link, action: linkAction)
                    .font(TeslaFont.ui(14, .semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
            }
        }
    }
}

/// Ligne interrupteur + titre + description optionnelle.
struct ToggleRow: View {
    let title: String
    var description: String? = nil
    var info = false
    var link: String? = nil
    @Binding var isOn: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            TeslaToggle(isOn: $isOn).padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(TeslaFont.ui(16, .semibold)).foregroundStyle(palette.textPrimary)
                    if info {
                        Image(systemName: "info.circle").font(.system(size: 12)).foregroundStyle(palette.textSecondary)
                    }
                }
                if let description {
                    Text(description).font(TeslaFont.ui(14)).foregroundStyle(palette.textSecondary)
                }
            }
            Spacer()
            if let link {
                Text(link).font(TeslaFont.ui(14, .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .frame(minHeight: 44)
    }
}

/// Onglets segmentés Figma (Off / On / Auto…) : cadre gris, segment actif blanc.
struct TeslaSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value
    var icon: String? = nil       // SF Symbol affiché devant le 1er segment
    var height: CGFloat = 54
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option.value == selection
                Button {
                    selection = option.value
                } label: {
                    HStack(spacing: 6) {
                        if index == 0, let icon { Image(systemName: icon).font(.system(size: 15)) }
                        Text(option.label).font(TeslaFont.ui(15))
                    }
                    .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(selected ? (colorScheme == .dark ? palette.inactive.opacity(0.6) : .white) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if index < options.count - 1 {
                    Rectangle().fill(palette.outline).frame(width: 1)
                }
            }
        }
        .frame(height: height)
        .background(palette.panelSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.outline, lineWidth: 1))
        .animation(.easeInOut(duration: 0.15), value: selection)
    }
}

/// Tuile carrée avec icône + libellé (ex. « Rabattre rétros », « Boîte à gants »).
struct TileButton: View {
    let title: String
    var systemImage: String? = nil
    var asset: String? = nil
    var isActive = false
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Group {
                    if let asset {
                        Image(asset).renderingMode(.template).resizable().scaledToFit()
                    } else if let systemImage {
                        Image(systemName: systemImage).resizable().scaledToFit()
                    }
                }
                .frame(width: 26, height: 26)
                Text(title).font(TeslaFont.ui(13)).multilineTextAlignment(.center).lineLimit(2)
            }
            .foregroundStyle(isActive ? Theme.accent : palette.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(palette.panelSecondary.opacity(0.35))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Rangée de tuiles collées dans un cadre commun (comme le Figma).
struct TileRow<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 1) { content }
            .background(palette.outline)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.outline, lineWidth: 1))
    }
}

/// Bouton plein bleu (« Antibrouillard AV », « Auto »). Grisé quand inactif.
struct AccentButton: View {
    let title: String
    var systemImage: String? = nil
    var isOn = true
    var width: CGFloat? = nil
    let action: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage).font(.system(size: 17)) }
                Text(title).font(TeslaFont.ui(15, .semibold))
            }
            .foregroundStyle(isOn ? .white : palette.textSecondary)
            .frame(width: width, height: 54)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .background(isOn ? Theme.accent : palette.panelSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }
}

/// Curseur de luminosité Figma : piste fine + pastille soleil.
struct BrightnessSlider: View {
    @Binding var value: Double
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - 28
            ZStack(alignment: .leading) {
                Capsule().fill(palette.outline).frame(height: 2)
                Capsule().fill(palette.textPrimary).frame(width: max(0, w * value), height: 2)
                Image(systemName: "sun.max")
                    .font(.system(size: 18))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(palette.panel))
                    .offset(x: w * value)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                value = min(1, max(0, (g.location.x - 14) / w))
            })
        }
        .frame(height: 54)
        .padding(.horizontal, 16)
        .background(palette.panelSecondary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(palette.outline, lineWidth: 1))
    }
}

/// Champ de recherche gris du Figma.
struct SettingsSearchField: View {
    @Binding var text: String
    var placeholder = "Rechercher"
    @Environment(\.palette) private var palette

    var body: some View {
        HStack {
            Image("nav.search").renderingMode(.template).resizable().frame(width: 18, height: 18)
            TextField(placeholder, text: $text).font(TeslaFont.ui(15))
        }
        .foregroundStyle(palette.textSecondary)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(palette.panelSecondary)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(palette.outline, lineWidth: 1))
    }
}

/// Séparateur fin des sections.
struct SettingsDivider: View {
    @Environment(\.palette) private var palette
    var body: some View { Rectangle().fill(palette.outline).frame(height: 1).padding(.vertical, 8) }
}

/// Libellé de groupe en petites capitales (« FONCTIONS MISES EN AVANT »).
struct SettingsCaption: View {
    let text: String
    @Environment(\.palette) private var palette
    var body: some View {
        Text(text.uppercased()).font(TeslaFont.ui(11, .semibold)).foregroundStyle(palette.textSecondary)
    }
}

/// Ligne clé / valeur (ordinateur de bord, infos logiciel…).
struct InfoRow: View {
    let label: String
    let value: String
    @Environment(\.palette) private var palette
    var body: some View {
        HStack {
            Text(label).font(TeslaFont.ui(15)).foregroundStyle(palette.textSecondary)
            Spacer()
            Text(value).font(TeslaFont.ui(15, .semibold)).foregroundStyle(palette.textPrimary).monospacedDigit()
        }
        .frame(minHeight: 36)
    }
}

/// Mise en page standard d'une page de réglages : défilement + marges du Figma.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content }
                .padding(.horizontal, 32)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Glisser pour fermer

/// Direction dans laquelle on glisse un élément pour le fermer.
enum DismissDirection { case down, up, left }

private struct SwipeToDismiss: ViewModifier {
    let direction: DismissDirection
    let threshold: CGFloat
    let action: () -> Void
    @State private var drag: CGFloat = 0

    private func amount(_ t: CGSize) -> CGFloat {
        switch direction {
        case .down: max(0, t.height)
        case .up: max(0, -t.height)
        case .left: max(0, -t.width)
        }
    }

    func body(content: Content) -> some View {
        content
            .offset(x: direction == .left ? -drag : 0,
                    y: direction == .down ? drag : (direction == .up ? -drag : 0))
            .opacity(1 - Double(min(drag / (threshold * 3), 0.5)))
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { drag = amount($0.translation) }
                    .onEnded { value in
                        let predicted = amount(value.predictedEndTranslation)
                        if drag > threshold || predicted > threshold * 2 {
                            withAnimation(.spring(duration: 0.3)) { action() }
                        }
                        withAnimation(.spring(duration: 0.3)) { drag = 0 }
                    }
            )
    }
}

extension View {
    /// L'élément suit le doigt et se ferme au-delà du seuil (ou sur un geste rapide).
    func swipeToDismiss(_ direction: DismissDirection = .down, threshold: CGFloat = 70,
                        perform action: @escaping () -> Void) -> some View {
        modifier(SwipeToDismiss(direction: direction, threshold: threshold, action: action))
    }
}

/// Poignée visuelle indiquant qu'un panneau se ferme en glissant.
struct GrabHandle: View {
    @Environment(\.palette) private var palette
    var body: some View {
        Capsule().fill(palette.inactive).frame(width: 40, height: 5).padding(.vertical, 6)
    }
}
