import AppKit
import QuartzCore

enum TabControlShortcutHintDebugSettings {
    static let xKey = "shortcutHintPaneTabXOffset"
    static let yKey = "shortcutHintPaneTabYOffset"
    static let alwaysShowKey = "shortcutHintAlwaysShow"
    static let defaultX = 0.0
    static let defaultY = 0.0
    static let defaultAlwaysShow = false
    static let range: ClosedRange<Double> = -20...20

    static func clamped(_ value: Double) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

@MainActor
enum TabControlShortcutHintStyle {
    static let fontSize: CGFloat = 9
    static let nsFontWeight: NSFont.Weight = .semibold
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 2
    static let strokeOpacity = 0.30
    static let strokeWidth: CGFloat = 0.8
    static let shadowOpacity = 0.22
    static let shadowRadius: CGFloat = 2
    static let shadowX: CGFloat = 0
    static let shadowY: CGFloat = 1

    static let measurementFont: NSFont = {
        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: nsFontWeight)
        return baseFont.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: fontSize) } ?? baseFont
    }()
    static let measurementAttributes: [NSAttributedString.Key: Any] = [
        .font: measurementFont
    ]
}

enum TabItemStyling {
    static func iconSaturation(hasRasterIcon: Bool, tabSaturation: Double) -> Double {
        hasRasterIcon ? 1.0 : tabSaturation
    }

    static func shouldShowHoverBackground(isHovered: Bool, isSelected: Bool) -> Bool {
        isHovered && !isSelected
    }

    static func tabWidthRange(for appearance: BonsplitConfiguration.Appearance) -> ClosedRange<CGFloat> {
        let minimum = max(1, TabBarMetrics.tabMinWidth)
        let maximum = max(minimum, appearance.tabMaxWidth)
        return minimum...maximum
    }

    /// Natural width of the ⌃/⌘ shortcut-hint pill for `label`. The standard tab
    /// strip overlays this pill without reserving width, but icon-only pinned
    /// browser tabs (which have no close button to overlay) still reserve it so
    /// holding the modifier never resizes the pinned chip.
    @MainActor
    static func shortcutHintWidth(for label: String) -> CGFloat {
        let textWidth = (label as NSString).size(withAttributes: TabControlShortcutHintStyle.measurementAttributes).width
        return ceil(textWidth) + (TabControlShortcutHintStyle.horizontalPadding * 2)
    }

    /// Width of a tab's trailing accessory slot.
    ///
    /// The slot reserves only the close-button (`accessorySlotSize`) width and
    /// never widens for the keyboard-shortcut hint. The ⌃/⌘ digit pill overlays
    /// this same slot (it is mutually exclusive with the close button and
    /// non-interactive), rendering at its natural size within the tab's trailing
    /// padding instead of pushing layout. Two consequences, both intended:
    ///   1. A tab carrying a ⌃/⌘ digit is exactly as wide as one without, so the
    ///      hint feature no longer makes tabs wider.
    ///   2. The reserved width is a constant, independent of `isFocused`,
    ///      `tabShortcutHintsEnabled`, the label, and the debug `xOffset`, so the
    ///      tab bar never shifts when a pane gains/loses focus or ⌃/⌘ is held.
    /// The parameters are accepted so the call site can pass the live state, but
    /// none of them may affect the result.
    static func reservedShortcutHintSlotWidth(
        shortcutHintLabel: String?,
        tabShortcutHintsEnabled: Bool,
        isFocused: Bool,
        accessorySlotSize: CGFloat,
        xOffset: Double
    ) -> CGFloat {
        // Deliberately ignores every hint/focus input: the pill overlays the
        // accessory slot, so the reserved layout width is always just the
        // close-button size. See the doc comment above.
        _ = (shortcutHintLabel, tabShortcutHintsEnabled, isFocused, xOffset)
        return accessorySlotSize
    }

    static func resolvedFaviconImage(existing: NSImage?, incomingData: Data?) -> NSImage? {
        guard let incomingData else { return nil }
        if let decoded = NSImage(data: incomingData) {
            // Favicon bitmaps must never be treated as template/tintable symbols.
            decoded.isTemplate = false
            return decoded
        }
        return existing
    }

    /// Host-defined tab kind identifier for browser surfaces. Pinned browser tabs
    /// collapse to an icon-only chip (favicon only) to mirror pinned tabs in macOS
    /// browsers, freeing tab-bar space for long-lived utility pages.
    static let browserTabKind = "browser"

    /// Whether a tab should render in the compact icon-only style reserved for
    /// pinned browser surfaces. Terminal and other kinds keep their titled layout
    /// when pinned because they have no distinguishing favicon to collapse to.
    static func isIconOnlyPinned(isPinned: Bool, kind: String?) -> Bool {
        isPinned && kind == browserTabKind
    }

    /// Fixed width for an icon-only pinned browser tab: the favicon slot plus the
    /// tab's symmetric horizontal padding and a little breathing room, so the tab
    /// shrinks to roughly a square chip hugging its icon.
    static func pinnedIconOnlyWidth(iconSlotSize: CGFloat, horizontalPadding: CGFloat) -> CGFloat {
        let icon = max(1, iconSlotSize)
        let padding = max(0, horizontalPadding)
        return ceil(icon + padding * 2 + 6)
    }

    /// Icon-only pinned width that also reserves room for the control-shortcut hint
    /// pill when one can be shown, so holding the modifier never resizes the tab.
    /// Pass `reservedShortcutHintWidth == nil` when the tab has no hint to reserve.
    static func pinnedIconOnlyWidth(
        iconSlotSize: CGFloat,
        horizontalPadding: CGFloat,
        reservedShortcutHintWidth: CGFloat?
    ) -> CGFloat {
        let base = pinnedIconOnlyWidth(iconSlotSize: iconSlotSize, horizontalPadding: horizontalPadding)
        guard let reservedShortcutHintWidth else { return base }
        let reserved = ceil(max(0, reservedShortcutHintWidth) + max(0, horizontalPadding) * 2)
        return max(base, reserved)
    }
}


final class TabLoadingSpinnerLayerView: NSView {
    static let rotationAnimationKey = "tabLoadingSpinnerRotation"
    static let rotationDuration: CFTimeInterval = 0.9
    private static let arcStrokeEnd: CGFloat = 0.28

    private let trackLayer = CAShapeLayer()
    private let arcContainerLayer = CALayer()
    private let arcLayer = CAShapeLayer()
    private var spinnerSize: CGFloat = 0
    private var spinnerColor: NSColor = .labelColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: spinnerSize, height: spinnerSize)
    }

    func configure(size: CGFloat, color: NSColor) {
        let resolvedSize = max(1, size)
        let sizeChanged = abs(spinnerSize - resolvedSize) > 0.001
        spinnerSize = resolvedSize
        spinnerColor = color

        updateColors()
        updateGeometry()

        if sizeChanged {
            invalidateIntrinsicContentSize()
        }
        if window != nil {
            startAnimating()
        }
    }

    override func layout() {
        super.layout()
        updateGeometry()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopAnimating()
        } else {
            startAnimating()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    private func setupLayers() {
        guard let layer else { return }
        layer.masksToBounds = false

        trackLayer.fillColor = nil
        arcLayer.fillColor = nil
        arcLayer.strokeStart = 0
        arcLayer.strokeEnd = Self.arcStrokeEnd
        arcLayer.lineCap = .round

        arcContainerLayer.addSublayer(arcLayer)
        layer.addSublayer(trackLayer)
        layer.addSublayer(arcContainerLayer)
    }

    private func updateGeometry() {
        let diameter = max(1, min(spinnerSize, bounds.width, bounds.height))
        let frame = CGRect(
            x: (bounds.width - diameter) * 0.5,
            y: (bounds.height - diameter) * 0.5,
            width: diameter,
            height: diameter
        )
        let lineWidth = max(1.6, spinnerSize * 0.14)
        let pathRect = CGRect(origin: .zero, size: frame.size).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5)
        let path = CGPath(ellipseIn: pathRect, transform: nil)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.frame = frame
        trackLayer.lineWidth = lineWidth
        trackLayer.path = path
        arcContainerLayer.frame = frame
        arcLayer.frame = CGRect(origin: .zero, size: frame.size)
        arcLayer.lineWidth = lineWidth
        arcLayer.path = path
        CATransaction.commit()
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        trackLayer.strokeColor = resolvedCGColor(spinnerColor, alphaMultiplier: 0.20)
        arcLayer.strokeColor = resolvedCGColor(spinnerColor, alphaMultiplier: 1.0)
        CATransaction.commit()
    }

    private func resolvedCGColor(_ color: NSColor, alphaMultiplier: CGFloat) -> CGColor {
        var resolved = color
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(NSColorSpace.sRGB) ?? color
        }
        let alpha = resolved.alphaComponent * alphaMultiplier
        return resolved.withAlphaComponent(alpha).cgColor
    }

    private func startAnimating() {
        guard arcContainerLayer.animation(forKey: Self.rotationAnimationKey) == nil else { return }
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.fromValue = 0
        animation.toValue = CGFloat.pi * 2
        animation.duration = Self.rotationDuration
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.isRemovedOnCompletion = false
        arcContainerLayer.add(animation, forKey: Self.rotationAnimationKey)
    }

    private func stopAnimating() {
        arcContainerLayer.removeAnimation(forKey: Self.rotationAnimationKey)
    }

    var activeRotationAnimationForTesting: CAAnimation? {
        arcContainerLayer.animation(forKey: Self.rotationAnimationKey)
    }

    var arcStrokeEndForTesting: CGFloat {
        arcLayer.strokeEnd
    }

    var ringWidthForTesting: CGFloat {
        arcLayer.lineWidth
    }

    var arcStrokeColorForTesting: CGColor? {
        arcLayer.strokeColor
    }
}


@MainActor
enum TabContextMenuBuilder {
    private static let forkConversationSeparatorIdentifier = NSUserInterfaceItemIdentifier(
        "Bonsplit.TabContextMenu.ForkConversationSeparator"
    )
    private static let forkConversationItemIdentifier = NSUserInterfaceItemIdentifier(
        "Bonsplit.TabContextMenu.ForkConversation"
    )
    private static let forkConversationSubmenuIdentifier = NSUserInterfaceItemIdentifier(
        "Bonsplit.TabContextMenu.ForkConversationSubmenu"
    )

    static func makeMenu(
        snapshot: TabContextMenuSnapshot,
        target: TabContextMenuActionTarget
    ) -> TabContextMenu {
        let state = snapshot.state
        let forkConversationAvailability = snapshot.forkConversationAvailabilityProvider()
        let forkConversationEnabled = forkConversationAvailability == .available
        let menu = TabContextMenu(
            snapshot: snapshot,
            forkConversationAvailability: forkConversationAvailability,
            actionTarget: target
        )

        addAction(
            title: localized("tabContext.renameTab", defaultValue: "Rename Tab…"),
            action: .rename,
            state: state,
            target: target,
            to: menu
        )

        if state.hasCustomTitle {
            addAction(
                title: localized("tabContext.removeCustomTabName", defaultValue: "Remove Custom Tab Name"),
                action: .clearName,
                state: state,
                target: target,
                to: menu
            )
        }

        menu.addItem(.separator())

        addAction(
            title: localized("tabContext.closeTabsToLeft", defaultValue: "Close Tabs to Left"),
            action: .closeToLeft,
            enabled: state.canCloseToLeft,
            state: state,
            target: target,
            to: menu
        )
        addAction(
            title: localized("tabContext.closeTabsToRight", defaultValue: "Close Tabs to Right"),
            action: .closeToRight,
            enabled: state.canCloseToRight,
            state: state,
            target: target,
            to: menu
        )
        addAction(
            title: localized("tabContext.closeOtherTabs", defaultValue: "Close Other Tabs"),
            action: .closeOthers,
            enabled: state.canCloseOthers,
            state: state,
            target: target,
            to: menu
        )

        menu.addItem(moveSubmenuItem(snapshot: snapshot, target: target))

        if state.isTerminal {
            addAction(
                title: localized("command.moveTabToLeftPane.title", defaultValue: "Move to Left Pane"),
                action: .moveToLeftPane,
                enabled: state.canMoveToLeftPane,
                state: state,
                target: target,
                to: menu
            )
            addAction(
                title: localized("command.moveTabToRightPane.title", defaultValue: "Move to Right Pane"),
                action: .moveToRightPane,
                enabled: state.canMoveToRightPane,
                state: state,
                target: target,
                to: menu
            )
        }

        if forkConversationAvailability != .hidden {
            let separator = NSMenuItem.separator()
            separator.identifier = forkConversationSeparatorIdentifier
            menu.addItem(separator)
            let forkConversationItem = addAction(
                title: forkConversationDefaultTitle(for: state.forkConversationDefaultAction),
                action: .forkConversation,
                enabled: forkConversationEnabled,
                state: state,
                target: target,
                to: menu
            )
            forkConversationItem.identifier = forkConversationItemIdentifier
            let forkConversationSubmenu = forkConversationSubmenuItem(
                state: state,
                target: target,
                enabled: forkConversationEnabled
            )
            forkConversationSubmenu.identifier = forkConversationSubmenuIdentifier
            menu.addItem(forkConversationSubmenu)
        }

        menu.addItem(.separator())

        addAction(
            title: localized("tabContext.newTerminalTabToRight", defaultValue: "New Terminal Tab to Right"),
            action: .newTerminalToRight,
            state: state,
            target: target,
            to: menu
        )
        addAction(
            title: localized("tabContext.newBrowserTabToRight", defaultValue: "New Browser Tab to Right"),
            action: .newBrowserToRight,
            state: state,
            target: target,
            to: menu
        )

        if state.isBrowser {
            menu.addItem(.separator())
            addAction(
                title: state.isAudioMuted
                    ? localized("tabContext.unmuteTab", defaultValue: "Unmute Tab")
                    : localized("tabContext.muteTab", defaultValue: "Mute Tab"),
                action: .toggleAudioMute,
                state: state,
                target: target,
                to: menu
            )
            addAction(
                title: localized("tabContext.reloadTab", defaultValue: "Reload Tab"),
                action: .reload,
                state: state,
                target: target,
                to: menu
            )
            addAction(
                title: localized("tabContext.duplicateTab", defaultValue: "Duplicate Tab"),
                action: .duplicate,
                state: state,
                target: target,
                to: menu
            )
        }

        if state.canDisconnectRemote {
            menu.addItem(.separator())
            addAction(
                title: localized("tabContext.disconnectRemote", defaultValue: "Disconnect SSH"),
                action: .disconnectRemote,
                state: state,
                target: target,
                to: menu
            )
        }

        menu.addItem(.separator())

        if state.hasSplits {
            addAction(
                title: state.isZoomed
                    ? localized("tabContext.exitZoom", defaultValue: "Exit Zoom")
                    : localized("tabContext.zoomPane", defaultValue: "Zoom Pane"),
                action: .toggleZoom,
                state: state,
                target: target,
                to: menu
            )
        }

        addAction(
            title: state.isFullWidthTabMode
                ? localized("tabContext.exitFullWidthTab", defaultValue: "Exit Full Width Tab")
                : localized("tabContext.enterFullWidthTab", defaultValue: "Full Width Tab"),
            action: .toggleFullWidthTab,
            state: state,
            target: target,
            to: menu
        )

        addAction(
            title: state.isPinned
                ? localized("tabContext.unpinTab", defaultValue: "Unpin Tab")
                : localized("tabContext.pinTab", defaultValue: "Pin Tab"),
            action: .togglePin,
            state: state,
            target: target,
            to: menu
        )

        if state.isUnread {
            addAction(
                title: localized("tabContext.markTabAsRead", defaultValue: "Mark Tab as Read"),
                action: .markAsRead,
                enabled: state.canMarkAsRead,
                state: state,
                target: target,
                to: menu
            )
        } else {
            addAction(
                title: localized("tabContext.markTabAsUnread", defaultValue: "Mark Tab as Unread"),
                action: .markAsUnread,
                enabled: state.canMarkAsUnread,
                state: state,
                target: target,
                to: menu
            )
        }

        menu.addItem(.separator())

        addAction(
            title: localized("command.copyIdentifiers.title", defaultValue: "Copy IDs"),
            action: .copyIdentifiers,
            state: state,
            target: target,
            to: menu
        )

        return menu
    }

    static func updateForkConversationAvailability(
        _ availability: TabContextForkConversationAvailability,
        in menu: NSMenu
    ) {
        let isVisible = availability != .hidden
        let isEnabled = availability == .available

        menu.items.first { $0.identifier == forkConversationSeparatorIdentifier }?.isHidden = !isVisible

        if let item = menu.items.first(where: { $0.identifier == forkConversationItemIdentifier }) {
            item.isHidden = !isVisible
            item.isEnabled = isEnabled
        }

        if let item = menu.items.first(where: { $0.identifier == forkConversationSubmenuIdentifier }) {
            item.isHidden = !isVisible
            item.isEnabled = isEnabled
            for destinationItem in item.submenu?.items ?? [] where !destinationItem.isSeparatorItem {
                destinationItem.isEnabled = isEnabled
            }
        }
    }

    private static func moveSubmenuItem(
        snapshot: TabContextMenuSnapshot,
        target: TabContextMenuActionTarget
    ) -> NSMenuItem {
        let state = snapshot.state
        let moveDestinations = snapshot.moveDestinationsProvider()
        let item = NSMenuItem(
            title: localized("tabContext.moveTab", defaultValue: "Move Tab"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        addAction(
            title: localized("command.moveTabToNewWorkspace.title", defaultValue: "Move Tab to New Workspace"),
            action: .moveToNewWorkspace,
            enabled: state.canMoveToNewWorkspace,
            state: state,
            target: target,
            to: submenu
        )
        for destination in moveDestinations {
            let destinationItem = NSMenuItem(
                title: destination.title,
                action: #selector(TabContextMenuActionTarget.performMoveDestination(_:)),
                keyEquivalent: ""
            )
            destinationItem.target = target
            destinationItem.representedObject = destination.id
            destinationItem.isEnabled = destination.isEnabled
            submenu.addItem(destinationItem)
        }
        item.submenu = submenu
        item.isEnabled = state.canMoveToNewWorkspace || !moveDestinations.isEmpty
        return item
    }

    private static func forkConversationSubmenuItem(
        state: TabContextMenuState,
        target: TabContextMenuActionTarget,
        enabled: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: localized("tabContext.forkConversationTo", defaultValue: "Fork Conversation To"),
            action: nil,
            keyEquivalent: ""
        )
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let defaultAction = state.forkConversationDefaultAction.isForkConversationDestination
            ? state.forkConversationDefaultAction
            : .defaultForkConversationDestination

        addAction(
            title: localized("tabContext.forkConversation.right", defaultValue: "Right Split"),
            action: .forkConversationRight,
            enabled: enabled,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationRight ? .on : .off
        )
        addAction(
            title: localized("tabContext.forkConversation.left", defaultValue: "Left Split"),
            action: .forkConversationLeft,
            enabled: enabled,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationLeft ? .on : .off
        )
        addAction(
            title: localized("tabContext.forkConversation.top", defaultValue: "Top Split"),
            action: .forkConversationTop,
            enabled: enabled,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationTop ? .on : .off
        )
        addAction(
            title: localized("tabContext.forkConversation.bottom", defaultValue: "Bottom Split"),
            action: .forkConversationBottom,
            enabled: enabled,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationBottom ? .on : .off
        )
        submenu.addItem(.separator())
        addAction(
            title: localized("tabContext.forkConversation.newTab", defaultValue: "New Tab"),
            action: .forkConversationNewTab,
            enabled: enabled,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationNewTab ? .on : .off
        )
        addAction(
            title: localized("tabContext.forkConversation.newWorkspace", defaultValue: "New Workspace"),
            action: .forkConversationNewWorkspace,
            enabled: enabled,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationNewWorkspace ? .on : .off
        )

        item.submenu = submenu
        item.isEnabled = enabled
        return item
    }

    private static func forkConversationDefaultTitle(for action: TabContextAction) -> String {
        switch action {
        case .forkConversationLeft:
            return localized(
                "tabContext.forkConversation.default.left",
                defaultValue: "Fork Conversation to the Left"
            )
        case .forkConversationTop:
            return localized(
                "tabContext.forkConversation.default.top",
                defaultValue: "Fork Conversation to the Top"
            )
        case .forkConversationBottom:
            return localized(
                "tabContext.forkConversation.default.bottom",
                defaultValue: "Fork Conversation to the Bottom"
            )
        case .forkConversationNewTab:
            return localized(
                "tabContext.forkConversation.default.newTab",
                defaultValue: "Fork Conversation to New Tab"
            )
        case .forkConversationNewWorkspace:
            return localized(
                "tabContext.forkConversation.default.newWorkspace",
                defaultValue: "Fork Conversation to New Workspace"
            )
        case .forkConversationRight,
             .forkConversation:
            return localized(
                "tabContext.forkConversation.default.right",
                defaultValue: "Fork Conversation to the Right"
            )
        case .rename,
             .clearName,
             .copyIdentifiers,
             .closeToLeft,
             .closeToRight,
             .closeOthers,
             .move,
             .moveToNewWorkspace,
             .moveToLeftPane,
             .moveToRightPane,
             .newTerminalToRight,
             .newBrowserToRight,
             .reload,
             .duplicate,
             .toggleAudioMute,
             .togglePin,
             .markAsRead,
             .markAsUnread,
             .toggleZoom,
             .toggleFullWidthTab,
             .disconnectRemote:
            assertionFailure("Non-fork action cannot be the default fork destination: \(action)")
            return localized(
                "tabContext.forkConversation.default.right",
                defaultValue: "Fork Conversation to the Right"
            )
        }
    }

    @discardableResult
    private static func addAction(
        title: String,
        action: TabContextAction,
        enabled: Bool = true,
        state: TabContextMenuState,
        target: TabContextMenuActionTarget,
        to menu: NSMenu,
        stateValue: NSControl.StateValue = .off
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(TabContextMenuActionTarget.performContextAction(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = action.rawValue
        item.isEnabled = enabled
        item.state = stateValue
        if let shortcut = state.shortcuts[action] {
            applyShortcut(shortcut, to: item)
        }
        menu.addItem(item)
        return item
    }

    private static func applyShortcut(_ shortcut: BonsplitKeyboardShortcut, to item: NSMenuItem) {
        item.keyEquivalent = shortcut.keyEquivalent
        item.keyEquivalentModifierMask = shortcut.modifierFlags
    }

    private static func localized(_ key: String, defaultValue: String) -> String {
        Bundle.module.localizedString(forKey: key, value: defaultValue, table: nil)
    }
}
