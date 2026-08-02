import SwiftUI

struct TabColorPickerView: View {
    let tabTitle: String
    let onApply: (_ colorHex: String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var color: Color

    init(
        tabTitle: String,
        initialColorHex: String?,
        onApply: @escaping (_ colorHex: String) -> Void
    ) {
        self.tabTitle = tabTitle
        self.onApply = onApply
        _color = State(
            initialValue: TabAppearanceColor.color(hex: initialColorHex)
                ?? Color(nsColor: .controlAccentColor)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("tabColor.customTitle", defaultValue: "Custom Tab Color"))
                .font(.headline)

            HStack(spacing: 10) {
                Text(tabTitle)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(railColor)
                    .frame(width: TabBarMetrics.tabColorRailWidth)
            }

            ColorPicker(
                localized("tabColor.color", defaultValue: "Color"),
                selection: $color,
                supportsOpacity: false
            )
            .accessibilityIdentifier("bonsplit.tabColor.picker")

            HStack {
                Spacer()

                Button(localized("tabColor.cancel", defaultValue: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(localized("tabColor.apply", defaultValue: "Apply")) {
                    guard let hex = TabAppearanceColor.hex(from: color) else { return }
                    onApply(hex)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("bonsplit.tabColor.apply")
            }
        }
        .padding(20)
        .frame(width: 360)
        .accessibilityIdentifier("bonsplit.tabColor.customizer")
    }

    private var railColor: Color {
        guard let hex = TabAppearanceColor.hex(from: color),
              let railColor = TabAppearanceColor.railNSColor(hex: hex) else {
            return color
        }
        return Color(nsColor: railColor)
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        Bundle.module.localizedString(forKey: key, value: defaultValue, table: nil)
    }
}
