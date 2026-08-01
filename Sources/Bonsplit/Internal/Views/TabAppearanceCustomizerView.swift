import AppKit
import SwiftUI

struct TabAppearanceCustomizerView: View {
    private static let suggestedIcons = [
        "terminal.fill",
        "globe",
        "folder.fill",
        "doc.text.fill",
        "bolt.fill",
        "star.fill",
        "paintbrush.fill",
        "checkmark.circle.fill",
    ]

    let tabTitle: String
    let fallbackIconName: String?
    let baseBackgroundHex: String?
    let appearance: BonsplitConfiguration.Appearance
    let onApply: (_ iconOverride: String?, _ backgroundHexOverride: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var iconName: String
    @State private var usesCustomBackground: Bool
    @State private var backgroundColor: Color

    init(
        tabTitle: String,
        fallbackIconName: String?,
        baseBackgroundHex: String?,
        appearance: BonsplitConfiguration.Appearance,
        iconOverride: String?,
        backgroundHexOverride: String?,
        onApply: @escaping (_ iconOverride: String?, _ backgroundHexOverride: String?) -> Void
    ) {
        self.tabTitle = tabTitle
        self.fallbackIconName = fallbackIconName
        self.baseBackgroundHex = baseBackgroundHex
        self.appearance = appearance
        self.onApply = onApply
        _iconName = State(initialValue: iconOverride ?? "")
        _usesCustomBackground = State(initialValue: backgroundHexOverride != nil)
        _backgroundColor = State(
            initialValue: TabAppearanceColor.color(hex: backgroundHexOverride)
                ?? TabAppearanceColor.color(hex: baseBackgroundHex)
                ?? Color(nsColor: .controlAccentColor)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localized("tabAppearance.title", defaultValue: "Customize Tab"))
                .font(.headline)

            preview

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        ForEach(Self.suggestedIcons, id: \.self) { icon in
                            suggestedIconButton(icon)
                        }
                    }

                    TextField(
                        localized("tabAppearance.iconName", defaultValue: "SF Symbol name"),
                        text: $iconName
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("bonsplit.tabAppearance.iconName")

                    if !isIconValid {
                        Text(localized(
                            "tabAppearance.invalidIcon",
                            defaultValue: "This symbol is not available."
                        ))
                        .font(.caption)
                        .foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label(
                    localized("tabAppearance.icon", defaultValue: "Icon"),
                    systemImage: "app.dashed"
                )
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        localized(
                            "tabAppearance.useCustomBackground",
                            defaultValue: "Use custom background"
                        ),
                        isOn: $usesCustomBackground
                    )

                    ColorPicker(
                        localized("tabAppearance.backgroundColor", defaultValue: "Background color"),
                        selection: $backgroundColor,
                        supportsOpacity: true
                    )
                    .disabled(!usesCustomBackground)
                    .accessibilityIdentifier("bonsplit.tabAppearance.backgroundColor")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label(
                    localized("tabAppearance.background", defaultValue: "Background"),
                    systemImage: "paintpalette"
                )
            }

            HStack {
                Button(localized("tabAppearance.reset", defaultValue: "Reset")) {
                    iconName = ""
                    usesCustomBackground = false
                }
                .disabled(iconOverride == nil && !usesCustomBackground)

                Spacer()

                Button(localized("tabAppearance.cancel", defaultValue: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(localized("tabAppearance.save", defaultValue: "Save")) {
                    onApply(iconOverride, backgroundHexOverride)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
                .accessibilityIdentifier("bonsplit.tabAppearance.save")
            }
        }
        .padding(20)
        .frame(width: 420)
        .accessibilityIdentifier("bonsplit.tabAppearance.customizer")
    }

    private var preview: some View {
        HStack(spacing: 8) {
            Image(systemName: previewIconName)
                .frame(width: 16, height: 16)
            Text(tabTitle)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(previewForeground)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(previewBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        )
        .accessibilityLabel(localized("tabAppearance.preview", defaultValue: "Preview"))
    }

    private func suggestedIconButton(_ icon: String) -> some View {
        Button {
            iconName = icon
        } label: {
            Image(systemName: icon)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(iconOverride == icon ? Color.accentColor.opacity(0.18) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(iconOverride == icon ? Color.accentColor : .clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(
            format: localized("tabAppearance.useIcon", defaultValue: "Use %@ icon"),
            icon
        ))
        .help(icon)
    }

    private var trimmedIconName: String {
        iconName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var iconOverride: String? {
        trimmedIconName.isEmpty ? nil : trimmedIconName
    }

    private var backgroundHexOverride: String? {
        guard usesCustomBackground else { return nil }
        return TabAppearanceColor.hex(from: backgroundColor)
    }

    private var isIconValid: Bool {
        guard let iconOverride else { return true }
        return NSImage(systemSymbolName: iconOverride, accessibilityDescription: nil) != nil
    }

    private var canSave: Bool {
        isIconValid && (!usesCustomBackground || backgroundHexOverride != nil)
    }

    private var previewIconName: String {
        guard let iconOverride else { return fallbackIconName ?? "doc.text" }
        return isIconValid ? iconOverride : "questionmark.square.dashed"
    }

    private var previewBackground: Color {
        TabBarColors.tabBackground(
            for: appearance,
            backgroundHex: previewBackgroundHex,
            isSelected: true,
            isHovered: false
        )
    }

    private var previewForeground: Color {
        TabBarColors.tabText(
            for: appearance,
            backgroundHex: previewBackgroundHex,
            isSelected: true
        )
    }

    private var previewBackgroundHex: String? {
        usesCustomBackground ? backgroundHexOverride : baseBackgroundHex
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        Bundle.module.localizedString(forKey: key, value: defaultValue, table: nil)
    }
}
