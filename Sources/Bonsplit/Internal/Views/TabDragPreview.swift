import SwiftUI

/// Preview shown during tab drag operations
struct TabDragPreview: View {
    let tab: TabItem
    let appearance: BonsplitConfiguration.Appearance

    var body: some View {
        HStack(spacing: TabBarMetrics.contentSpacing) {
            if let iconName = tab.resolvedIconName {
                Image(systemName: iconName)
                    .font(.system(size: TabBarMetrics.iconSize))
                    .foregroundStyle(TabBarColors.tabText(
                        for: appearance,
                        backgroundHex: tab.backgroundHex,
                        isSelected: true
                    ))
            }

            Text(tab.title)
                .font(.system(size: appearance.tabTitleFontSize))
                .lineLimit(1)
                .foregroundStyle(TabBarColors.tabText(
                    for: appearance,
                    backgroundHex: tab.backgroundHex,
                    isSelected: true
                ))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: TabBarMetrics.tabCornerRadius, style: .continuous)
                .fill(TabBarColors.tabBackground(
                    for: appearance,
                    backgroundHex: tab.backgroundHex,
                    isSelected: true,
                    isHovered: false
                ))
                .overlay(alignment: .leading) {
                    if let railColor = tab.colorHexOverride.flatMap({
                        TabAppearanceColor.railNSColor(hex: $0)
                    }) {
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: railColor).opacity(0.95))
                            .frame(width: 3)
                            .padding(.leading, 4)
                            .padding(.vertical, 5)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
        .opacity(0.9)
    }
}
