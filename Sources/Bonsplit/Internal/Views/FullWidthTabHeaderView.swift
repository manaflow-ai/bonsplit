import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Header shown when a pane renders its selected tab as the full-width title.
struct FullWidthTabHeaderView: View {
    @Environment(BonsplitController.self) private var controller
    @Environment(SplitViewController.self) private var splitViewController

    @Bindable var pane: PaneState
    let isFocused: Bool

    @State private var dropTargetIndex: Int?
    @State private var dropLifecycle: TabDropLifecycle = .idle

    private var appearance: BonsplitConfiguration.Appearance {
        controller.configuration.appearance
    }

    private var selectedTab: TabItem? {
        pane.selectedTab ?? pane.tabs.first
    }

    private var selectedIndex: Int? {
        guard let selectedTab else { return nil }
        return pane.tabs.firstIndex(where: { $0.id == selectedTab.id })
    }

    private var saturation: Double {
        isFocused || splitViewController.dragSourcePaneId == pane.id ? 1.0 : 0.0
    }

    private var backgroundColor: Color {
        let baseBarColor = TabBarColors.nsColorBarBackground(for: appearance)
        let resolved = appearance.usesSharedBackdrop || isFocused
            ? baseBarColor
            : baseBarColor.withAlphaComponent(baseBarColor.alphaComponent * 0.95)
        return Color(nsColor: resolved)
    }

    private var appendDropTargetIndex: Int {
        pane.tabs.count
    }

    var body: some View {
        Group {
            if let selectedTab, let selectedIndex {
                headerContent(tab: selectedTab, index: selectedIndex)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: appearance.tabBarHeight)
                    .contentShape(Rectangle())
                    .background(
                        TabContextMenuPresenter(
                            snapshot: TabContextMenuSnapshot(
                                tabId: selectedTab.id,
                                state: TabContextMenuState(
                                    tab: selectedTab,
                                    index: selectedIndex,
                                    pane: pane,
                                    controller: controller,
                                    splitViewController: splitViewController
                                ),
                                moveDestinationsProvider: {
                                    controller.tabContextMoveDestinationsProvider?(TabID(id: selectedTab.id), pane.id) ?? []
                                }
                            ),
                            onContextAction: { action in
                                controller.requestTabContextAction(action, for: TabID(id: selectedTab.id), inPane: pane.id)
                            },
                            onMoveDestination: { destinationId in
                                controller.requestTabMove(toDestination: destinationId, for: TabID(id: selectedTab.id), inPane: pane.id)
                            }
                        )
                    )
                    .onDrag {
                        splitViewController.makeTabDragItemProvider(for: selectedTab, from: pane.id) {
                            clearDropState()
                        }
                    } preview: {
                        TabDragPreview(tab: selectedTab, appearance: appearance)
                    }
                    .onDrop(of: [.tabTransfer, .fileURL], delegate: TabDropDelegate(
                        targetIndex: appendDropTargetIndex,
                        pane: pane,
                        bonsplitController: controller,
                        controller: splitViewController,
                        dropTargetIndex: $dropTargetIndex,
                        dropLifecycle: $dropLifecycle
                    ))
            } else {
                Color.clear
            }
        }
        .frame(height: appearance.tabBarHeight)
        .background(backgroundColor)
        .overlay {
            if dropTargetIndex == appendDropTargetIndex {
                headerDropHighlight
                    .saturation(saturation)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(TabBarColors.separator(for: appearance))
                .frame(height: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withTransaction(Transaction(animation: nil)) {
                controller.focusPane(pane.id)
            }
        }
        .onChange(of: splitViewController.draggingTab) { _, newValue in
            if newValue == nil {
                clearDropState()
            }
        }
    }

    private func headerContent(tab: TabItem, index: Int) -> some View {
        ZStack {
            HStack(spacing: 8) {
                tabIcon(for: tab)

                Text(tab.title)
                    .font(.system(size: appearance.tabTitleFontSize + 2, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(
                        isFocused
                            ? TabBarColors.activeText(for: appearance)
                            : TabBarColors.inactiveText(for: appearance)
                    )
                    .saturation(saturation)
            }
            .padding(.horizontal, 44)
            .frame(maxWidth: .infinity, alignment: .center)

            if pane.tabs.count > 1 {
                HStack {
                    Spacer(minLength: 0)
                    Text("\(index + 1)/\(pane.tabs.count)")
                        .font(.system(size: max(9, appearance.tabTitleFontSize - 1), weight: .medium))
                        .foregroundStyle(TabBarColors.inactiveText(for: appearance))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(TabBarColors.hoveredTabBackground(for: appearance))
                        )
                        .saturation(saturation)
                }
                .padding(.trailing, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
    }

    private var headerDropHighlight: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(TabBarColors.dropIndicator(for: appearance).opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(TabBarColors.dropIndicator(for: appearance), lineWidth: 2)
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
    }

    @ViewBuilder
    private func tabIcon(for tab: TabItem) -> some View {
        let iconSize = max(14, appearance.tabTitleFontSize + 3)
        let iconTint = isFocused
            ? TabBarColors.activeText(for: appearance)
            : TabBarColors.inactiveText(for: appearance)

        if let imageData = tab.iconImageData, let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
        } else if let iconName = tab.icon {
            Image(systemName: iconName)
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: iconSize, height: iconSize)
                .saturation(saturation)
        }
    }

    private func clearDropState() {
        dropTargetIndex = nil
        dropLifecycle = .idle
    }
}
