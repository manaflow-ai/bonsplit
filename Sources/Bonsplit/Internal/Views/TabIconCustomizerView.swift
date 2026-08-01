import AppKit
import SwiftUI

struct TabIconCustomizerView: View {
    private static let columns = Array(
        repeating: GridItem(.flexible(minimum: 32), spacing: 6),
        count: 10
    )

    let tabTitle: String
    let fallbackIconName: String?
    let baseBackgroundHex: String?
    let appearance: BonsplitConfiguration.Appearance
    let onApply: (_ iconOverride: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var iconName: String
    @State private var searchText = ""

    init(
        tabTitle: String,
        fallbackIconName: String?,
        baseBackgroundHex: String?,
        appearance: BonsplitConfiguration.Appearance,
        iconOverride: String?,
        onApply: @escaping (_ iconOverride: String?) -> Void
    ) {
        self.tabTitle = tabTitle
        self.fallbackIconName = fallbackIconName
        self.baseBackgroundHex = baseBackgroundHex
        self.appearance = appearance
        self.onApply = onApply
        _iconName = State(initialValue: iconOverride ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(localized("tabIcon.title", defaultValue: "Tab Icon"))
                .font(.headline)

            preview

            TextField(
                localized("tabIcon.search", defaultValue: "Search icons"),
                text: $searchText
            )
            .textFieldStyle(.roundedBorder)
            .accessibilityIdentifier("bonsplit.tabIcon.search")

            ScrollView {
                if filteredIcons.isEmpty {
                    Text(localized("tabIcon.noMatches", defaultValue: "No matching icons"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    LazyVGrid(columns: Self.columns, spacing: 6) {
                        ForEach(filteredIcons, id: \.self) { icon in
                            iconButton(icon)
                        }
                    }
                    .padding(2)
                }
            }
            .frame(height: 250)

            VStack(alignment: .leading, spacing: 6) {
                Text(localized("tabIcon.symbolNameLabel", defaultValue: "SF Symbol"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField(
                    localized("tabIcon.symbolName", defaultValue: "SF Symbol name"),
                    text: $iconName
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("bonsplit.tabIcon.symbolName")

                if !isIconValid {
                    Text(localized(
                        "tabIcon.invalid",
                        defaultValue: "This symbol is not available."
                    ))
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }

            HStack {
                Button(localized("tabIcon.useDefault", defaultValue: "Use Default")) {
                    iconName = ""
                }
                .disabled(iconOverride == nil)

                Spacer()

                Button(localized("tabIcon.cancel", defaultValue: "Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(localized("tabIcon.save", defaultValue: "Save")) {
                    onApply(iconOverride)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isIconValid)
                .accessibilityIdentifier("bonsplit.tabIcon.save")
            }
        }
        .padding(20)
        .frame(width: 540)
        .accessibilityIdentifier("bonsplit.tabIcon.customizer")
    }

    private var preview: some View {
        HStack(spacing: 8) {
            Image(systemName: previewIconName)
                .frame(width: 16, height: 16)
            Text(tabTitle)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(TabBarColors.tabText(
            for: appearance,
            backgroundHex: baseBackgroundHex,
            isSelected: true
        ))
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(TabBarColors.tabBackground(
                    for: appearance,
                    backgroundHex: baseBackgroundHex,
                    isSelected: true,
                    isHovered: false
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        )
        .accessibilityLabel(localized("tabIcon.preview", defaultValue: "Preview"))
    }

    private func iconButton(_ icon: String) -> some View {
        Button {
            iconName = icon
        } label: {
            Image(systemName: icon)
                .frame(maxWidth: .infinity, minHeight: 32)
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
            format: localized("tabIcon.useIcon", defaultValue: "Use %@ icon"),
            icon
        ))
        .help(icon)
    }

    private var filteredIcons: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return TabIconCatalog.availableNames }
        return TabIconCatalog.availableNames.filter {
            $0.localizedCaseInsensitiveContains(query)
        }
    }

    private var trimmedIconName: String {
        iconName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var iconOverride: String? {
        trimmedIconName.isEmpty ? nil : trimmedIconName
    }

    private var isIconValid: Bool {
        guard let iconOverride else { return true }
        return NSImage(systemSymbolName: iconOverride, accessibilityDescription: nil) != nil
    }

    private var previewIconName: String {
        if let iconOverride, isIconValid {
            return iconOverride
        }
        if let fallbackIconName,
           NSImage(systemSymbolName: fallbackIconName, accessibilityDescription: nil) != nil {
            return fallbackIconName
        }
        return "doc.text"
    }

    private func localized(_ key: String, defaultValue: String) -> String {
        Bundle.module.localizedString(forKey: key, value: defaultValue, table: nil)
    }
}
