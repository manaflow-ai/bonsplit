import SwiftUI

/// Preview shown during tab drag operations
struct TabDragPreview: View {
    let tab: TabItem
    let appearance: BonsplitConfiguration.Appearance

    @Environment(\.bonsplitZoomScale) private var zoomScale

    var body: some View {
        HStack(spacing: TabBarMetrics.contentSpacing(zoomScale)) {
            if let iconName = tab.icon {
                Image(systemName: iconName)
                    .font(.system(size: TabBarMetrics.iconSize(zoomScale)))
                    .foregroundStyle(TabBarColors.activeText(for: appearance))
            }

            Text(tab.title)
                .font(.system(size: TabBarMetrics.titleFontSize(zoomScale)))
                .lineLimit(1)
                .foregroundStyle(TabBarColors.activeText(for: appearance))
        }
        .padding(.horizontal, 12 * zoomScale)
        .padding(.vertical, 6 * zoomScale)
        .background(
            RoundedRectangle(cornerRadius: TabBarMetrics.tabCornerRadius, style: .continuous)
                .fill(TabBarColors.activeTabBackground(for: appearance))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
        .opacity(0.9)
    }
}
