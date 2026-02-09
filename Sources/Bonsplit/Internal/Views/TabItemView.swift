import SwiftUI

/// Individual tab view with icon, title, close button, and dirty indicator
struct TabItemView: View {
    let tab: TabItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false

    var body: some View {
        HStack(spacing: 0) {
            // Icon + title block uses the standard spacing, but keep the close affordance tight.
            HStack(spacing: TabBarMetrics.contentSpacing) {
                if let iconName = tab.icon {
                    let iconSize: CGFloat = {
                        // `terminal.fill` reads visually heavier than most symbols at the same point size.
                        // Keep other icons as-is, but slightly downsize terminal/browser icons.
                        if iconName == "terminal.fill" || iconName == "terminal" || iconName == "globe" {
                            return max(10, TabBarMetrics.iconSize - 2.5)
                        }
                        return TabBarMetrics.iconSize
                    }()
                    Image(systemName: iconName)
                        .font(.system(size: iconSize))
                        .foregroundStyle(isSelected ? TabBarColors.activeText : TabBarColors.inactiveText)
                }

                Text(tab.title)
                    .font(.system(size: TabBarMetrics.titleFontSize))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? TabBarColors.activeText : TabBarColors.inactiveText)
            }

            Spacer(minLength: 0)

            // Close button or dirty indicator
            closeOrDirtyIndicator
        }
        .padding(.horizontal, TabBarMetrics.tabHorizontalPadding)
        .offset(y: isSelected ? 0.5 : 0)
        .frame(
            minWidth: TabBarMetrics.tabMinWidth,
            maxWidth: TabBarMetrics.tabMaxWidth,
            minHeight: TabBarMetrics.tabHeight,
            maxHeight: TabBarMetrics.tabHeight
        )
        .padding(.bottom, isSelected ? 1 : 0)
        .background(tabBackground)
        .contentShape(Rectangle())
        // Middle click to close (macOS convention).
        // Uses an AppKit event monitor so it doesn't interfere with left click selection or drag/reorder.
        .background(MiddleClickMonitorView(onMiddleClick: onClose))
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: TabBarMetrics.hoverDuration)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityValue(tab.isDirty ? "Modified" : "")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Tab Background

    @ViewBuilder
    private var tabBackground: some View {
        ZStack(alignment: .top) {
            // Background fill
            if isSelected {
                Rectangle()
                    .fill(TabBarColors.activeTabBackground)
            } else if isHovered {
                Rectangle()
                    .fill(TabBarColors.hoveredTabBackground)
            } else {
                Color.clear
            }

            // Top accent indicator for selected tab
            if isSelected {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: TabBarMetrics.activeIndicatorHeight)
            }

            // Right border separator
            HStack {
                Spacer()
                Rectangle()
                    .fill(TabBarColors.separator)
                    .frame(width: 1)
            }
        }
    }

    // MARK: - Close Button / Dirty Indicator

    @ViewBuilder
    private var closeOrDirtyIndicator: some View {
        ZStack {
            // Dirty indicator (shown when dirty and not hovering)
            if tab.isDirty && !isHovered && !isCloseHovered {
                Circle()
                    .fill(TabBarColors.dirtyIndicator)
                    .frame(width: TabBarMetrics.dirtyIndicatorSize, height: TabBarMetrics.dirtyIndicatorSize)
            }

            // Close button (shown on hover)
            if isHovered || isCloseHovered {
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: TabBarMetrics.closeIconSize, weight: .semibold))
                        .foregroundStyle(isCloseHovered ? TabBarColors.activeText : TabBarColors.inactiveText)
                        .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
                        .background(
                            Circle()
                                .fill(isCloseHovered ? TabBarColors.hoveredTabBackground : .clear)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isCloseHovered = hovering
                }
            }
        }
        .frame(width: TabBarMetrics.closeButtonSize, height: TabBarMetrics.closeButtonSize)
        .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isHovered)
        .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isCloseHovered)
    }
}

private struct MiddleClickMonitorView: NSViewRepresentable {
    let onMiddleClick: () -> Void

    final class Coordinator {
        var onMiddleClick: (() -> Void)?
        weak var view: NSView?
        var monitor: Any?

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        context.coordinator.view = view
        context.coordinator.onMiddleClick = onMiddleClick

        // Monitor only middle clicks so we don't break drag/reorder or normal selection.
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp]) { event in
            guard event.buttonNumber == 2 else { return event }
            guard let v = context.coordinator.view, let w = v.window else { return event }
            guard event.window === w else { return event }

            let p = v.convert(event.locationInWindow, from: nil)
            guard v.bounds.contains(p) else { return event }

            context.coordinator.onMiddleClick?()
            return nil // swallow so it doesn't also select the tab
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onMiddleClick = onMiddleClick
    }
}
