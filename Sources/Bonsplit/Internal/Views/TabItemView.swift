import SwiftUI
import AppKit
import QuartzCore

enum TabControlShortcutHintAnimation {
    static let visibility: Animation = .easeOut(duration: 0.12)
}

extension View {
    func tabControlShortcutHintVisibilityAnimation<Value: Equatable>(value: Value) -> some View {
        animation(TabControlShortcutHintAnimation.visibility, value: value)
    }

    func tabBarButtonAnimationsDisabled() -> some View {
        transaction { transaction in
            transaction.animation = nil
        }
    }

    /// Imposes a minimum width on the tab row only when `minWidth` is non-nil.
    ///
    /// Used by the tab strip's fill mode to force the horizontal `ScrollView` to hand
    /// the row the full viewport width so SwiftUI can distribute slack across flexible
    /// tabs. Passing `nil` returns the view untouched, preserving the fixed-width layout
    /// byte-for-byte.
    @ViewBuilder
    func tabRowFillMinWidth(_ minWidth: CGFloat?) -> some View {
        if let minWidth {
            frame(minWidth: minWidth, alignment: .leading)
        } else {
            self
        }
    }

    @ViewBuilder
    func tabGeometryDebugFrame(_ onFrame: @escaping (CGRect) -> Void) -> some View {
#if DEBUG
        if TabGeometryDebugLog.isEnabled {
            background(
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear {
                            onFrame(frame)
                        }
                        .onChange(of: frame) { _, newFrame in
                            onFrame(newFrame)
                        }
                }
            )
        } else {
            self
        }
#else
        self
#endif
    }

    @ViewBuilder
    func tabGeometryDebugOnAppear(_ action: @escaping () -> Void) -> some View {
#if DEBUG
        if TabGeometryDebugLog.isEnabled {
            onAppear(perform: action)
        } else {
            self
        }
#else
        self
#endif
    }

    @ViewBuilder
    func tabGeometryDebugOnChange<Value: Equatable>(
        of value: Value,
        perform action: @escaping (Value) -> Void
    ) -> some View {
#if DEBUG
        if TabGeometryDebugLog.isEnabled {
            onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self
        }
#else
        self
#endif
    }
}

private enum TabControlShortcutHintDebugSettings {
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

enum TabControlShortcutHintStyle {
    static let fontSize: CGFloat = 9
    static let fontWeight: Font.Weight = .semibold
    static let nsFontWeight: NSFont.Weight = .semibold
    static let fontDesign: Font.Design = .rounded
    static let foregroundColor = Color.primary
    static let horizontalPadding: CGFloat = 6
    static let verticalPadding: CGFloat = 2
    static let strokeOpacity = 0.30
    static let strokeWidth: CGFloat = 0.8
    static let shadowOpacity = 0.22
    static let shadowRadius: CGFloat = 2
    static let shadowX: CGFloat = 0
    static let shadowY: CGFloat = 1

    static let font: Font = .system(size: fontSize, weight: fontWeight, design: fontDesign)
    static let measurementFont: NSFont = {
        let baseFont = NSFont.systemFont(ofSize: fontSize, weight: nsFontWeight)
        return baseFont.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: fontSize) } ?? baseFont
    }()
    static let measurementAttributes: [NSAttributedString.Key: Any] = [
        .font: measurementFont
    ]
}

struct TabControlShortcutHintPillBackground: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.regularMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        Color.white.opacity(TabControlShortcutHintStyle.strokeOpacity),
                        lineWidth: TabControlShortcutHintStyle.strokeWidth
                    )
            )
            .shadow(
                color: Color.black.opacity(TabControlShortcutHintStyle.shadowOpacity),
                radius: TabControlShortcutHintStyle.shadowRadius,
                x: TabControlShortcutHintStyle.shadowX,
                y: TabControlShortcutHintStyle.shadowY
            )
    }
}

struct TabControlShortcutHintPill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(TabControlShortcutHintStyle.font)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundColor(TabControlShortcutHintStyle.foregroundColor)
            .padding(.horizontal, TabControlShortcutHintStyle.horizontalPadding)
            .padding(.vertical, TabControlShortcutHintStyle.verticalPadding)
            .background(TabControlShortcutHintPillBackground())
    }
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

/// Individual tab view with icon, title, close button, and dirty indicator
struct TabItemView: View {
    let tab: TabItem
    let isSelected: Bool
    let showsZoomIndicator: Bool
    let appearance: BonsplitConfiguration.Appearance
    /// When true, the tab drops its fixed maximum width and grows to fill the slack
    /// the enclosing tab strip distributes (see ``BonsplitConfiguration/Appearance/tabWidthMode``).
    let fillsWidth: Bool
    let saturation: Double
    let trailingSeparatorBottomInset: CGFloat
    let controlShortcutDigit: Int?
    /// Whether tab keyboard-shortcut hints are enabled at all (a global setting,
    /// independent of which pane is focused). Drives the reserved hint-slot width.
    let tabShortcutHintsEnabled: Bool
    /// Whether this tab's pane is focused. Gates hint *visibility*, never width.
    let isFocused: Bool
    let showsControlShortcutHint: Bool
    let shortcutModifierSymbol: String
    let allowsClose: Bool
    let allowsContextMenu: Bool
    let contextMenuState: TabContextMenuState
    let moveDestinationsProvider: () -> [TabContextMoveDestination]
    let forkConversationOpenAvailabilityProvider: () -> Bool?
    let onSelect: () -> Void
    let onClose: (TabCloseRequestSource) -> Void
    let onZoomToggle: () -> Void
    let onContextAction: (TabContextAction) -> Void
    let onMoveDestination: (String) -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false
    @State private var isZoomHovered = false
    @State private var isAudioHovered = false
    @State private var showGlobeFallback = true
    @State private var globeFallbackWorkItem: DispatchWorkItem?
    @State private var lastIsLoadingObserved = false
    @State private var lastLoadingStoppedAt: Date?
    @State private var renderedFaviconData: Data?
    @State private var renderedFaviconImage: NSImage?
#if DEBUG
    @State private var debugLastIconFrame: CGRect?
    @State private var debugLastTitleFrame: CGRect?
    @State private var debugLastTabFrame: CGRect?
    @State private var debugLastTitle: String?
    @State private var debugLastIcon: String?
    @State private var debugLastIconAsset: String?
    @State private var debugLastIsLoading: Bool?
#endif
    @AppStorage(TabControlShortcutHintDebugSettings.xKey) private var controlShortcutHintXOffset = TabControlShortcutHintDebugSettings.defaultX
    @AppStorage(TabControlShortcutHintDebugSettings.yKey) private var controlShortcutHintYOffset = TabControlShortcutHintDebugSettings.defaultY
    @AppStorage(TabControlShortcutHintDebugSettings.alwaysShowKey) private var alwaysShowShortcutHints = TabControlShortcutHintDebugSettings.defaultAlwaysShow

    var body: some View {
        tabContent
        .padding(.horizontal, TabBarMetrics.tabHorizontalPadding)
        .frame(
            minWidth: frameMinWidth,
            // In fill mode the tab becomes flexible so the tab strip can distribute
            // slack equally across tabs; the fixed upper bound only applies otherwise.
            // Pinned browser tabs pin both bounds to a compact icon-only width.
            maxWidth: frameMaxWidth,
            minHeight: tabHeight,
            maxHeight: tabHeight,
            alignment: isIconOnlyPinned ? .center : .leading
        )
        // Fixed mode: size each tab to its own content and ignore the width the
        // tab strip would otherwise propose. Without this the flexible `maxWidth`
        // frame lets SwiftUI distribute slack equally across tabs, so a single
        // long-titled tab drags every other tab wider (and over-truncates short
        // titles). Fill mode keeps the flexible behavior so tabs share the strip.
        // Icon-only pinned tabs always size to their fixed compact width.
        .fixedSize(horizontal: isIconOnlyPinned || !fillsWidth, vertical: false)
        .background(tabBackground.saturation(saturation))
        .tabControlShortcutHintVisibilityAnimation(value: showsShortcutHint)
        .contentShape(Rectangle().inset(by: -BonsplitTabItemHitTesting.horizontalSlop))
        // Middle click to close (macOS convention).
        // Uses an AppKit event monitor so it doesn't interfere with left click selection or drag/reorder.
        .background(MiddleClickMonitorView(onMiddleClick: {
            guard allowsClose, !tab.isPinned else { return }
            onClose(.middleClick)
        }))
        .background {
            if allowsContextMenu {
                TabContextMenuPresenter(
                    snapshot: TabContextMenuSnapshot(
                        tabId: tab.id,
                        state: contextMenuState,
                        moveDestinationsProvider: moveDestinationsProvider,
                        forkConversationOpenAvailabilityProvider: forkConversationOpenAvailabilityProvider
                    ),
                    onContextAction: onContextAction,
                    onMoveDestination: onMoveDestination
                )
            }
        }
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onZoomToggle()
            }
        )
        .onHover { hovering in
            withTransaction(Transaction(animation: nil)) {
                isHovered = hovering
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(tab.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .safeHelp(tab.title)
        .tabGeometryDebugFrame { frame in
            debugRecordTabFrame(frame)
        }
        .tabGeometryDebugOnAppear {
            debugRecordInitialStateSnapshot()
        }
        .tabGeometryDebugOnChange(of: tab.title) { newValue in
            debugRecordTitleStateChange(newValue)
        }
        .tabGeometryDebugOnChange(of: tab.icon) { newValue in
            debugRecordIconStateChange(newValue)
        }
        .tabGeometryDebugOnChange(of: tab.iconAsset) { newValue in
            debugRecordIconAssetStateChange(newValue)
        }
        .tabGeometryDebugOnChange(of: tab.isLoading) { newValue in
            debugRecordIsLoadingStateChange(newValue)
        }
    }

    /// Whether this tab renders in the compact icon-only style reserved for pinned
    /// browser surfaces (favicon only, no title or trailing affordances).
    private var isIconOnlyPinned: Bool {
        TabItemStyling.isIconOnlyPinned(isPinned: tab.isPinned, kind: tab.kind)
    }

    private func debugRecordTabFrame(_ frame: CGRect) {
#if DEBUG
        guard debugFrameChanged(debugLastTabFrame, frame) else { return }
        debugLastTabFrame = frame
#endif
    }

    private func debugRecordGeometry(which: String, frame: CGRect) {
#if DEBUG
        switch which {
        case "icon":
            guard debugFrameChanged(debugLastIconFrame, frame) else { return }
            debugLastIconFrame = frame
        case "title":
            guard debugFrameChanged(debugLastTitleFrame, frame) else { return }
            debugLastTitleFrame = frame
        default:
            return
        }
        TabGeometryDebugLog.geometry(
            tabId: tab.id,
            which: which,
            frame: frame,
            tabWidth: debugLastTabFrame?.width,
            tab: tab,
            isSelected: isSelected,
            showsShortcutHint: showsShortcutHint
        )
#endif
    }

    private func debugRecordInitialStateSnapshot() {
#if DEBUG
        debugLastTitle = tab.title
        debugLastIcon = tab.icon
        debugLastIconAsset = tab.iconAsset
        debugLastIsLoading = tab.isLoading
#endif
    }

    private func debugRecordTitleStateChange(_ newValue: String) {
#if DEBUG
        let oldValue = debugLastTitle ?? tab.title
        guard oldValue != newValue else { return }
        debugLastTitle = newValue
        debugRecordStateChange(field: "title", oldValue: oldValue, newValue: newValue)
#endif
    }

    private func debugRecordIconStateChange(_ newValue: String?) {
#if DEBUG
        let oldValue = debugLastIcon
        guard oldValue != newValue else { return }
        debugLastIcon = newValue
        debugRecordStateChange(
            field: "icon",
            oldValue: TabGeometryDebugLog.optional(oldValue),
            newValue: TabGeometryDebugLog.optional(newValue)
        )
#endif
    }

    private func debugRecordIconAssetStateChange(_ newValue: String?) {
#if DEBUG
        let oldValue = debugLastIconAsset
        guard oldValue != newValue else { return }
        debugLastIconAsset = newValue
        debugRecordStateChange(
            field: "iconAsset",
            oldValue: TabGeometryDebugLog.optional(oldValue),
            newValue: TabGeometryDebugLog.optional(newValue)
        )
#endif
    }

    private func debugRecordIsLoadingStateChange(_ newValue: Bool) {
#if DEBUG
        let oldValue = debugLastIsLoading
        guard oldValue != newValue else { return }
        debugLastIsLoading = newValue
        debugRecordStateChange(
            field: "loading",
            oldValue: TabGeometryDebugLog.optional(oldValue),
            newValue: String(newValue)
        )
#endif
    }

    private func debugRecordStateChange(field: String, oldValue: String, newValue: String) {
#if DEBUG
        TabGeometryDebugLog.stateChange(
            tabId: tab.id,
            field: field,
            oldValue: oldValue,
            newValue: newValue,
            tab: tab,
            isSelected: isSelected,
            showsShortcutHint: showsShortcutHint
        )
#endif
    }

    private func debugFrameChanged(_ oldFrame: CGRect?, _ newFrame: CGRect) -> Bool {
#if DEBUG
        guard let oldFrame else { return true }
        return abs(oldFrame.origin.x - newFrame.origin.x) > 0.01 ||
            abs(oldFrame.origin.y - newFrame.origin.y) > 0.01 ||
            abs(oldFrame.width - newFrame.width) > 0.01
#else
        return false
#endif
    }

    @ViewBuilder
    private var tabContent: some View {
        if isIconOnlyPinned {
            iconOnlyContent
        } else {
            standardContent
        }
    }

    /// Standard titled tab layout: leading icon, title, optional audio/zoom
    /// affordances, and the trailing close/pin/dirty accessory.
    @ViewBuilder
    private var standardContent: some View {
        HStack(spacing: 0) {
            // Icon + title block uses the standard spacing, but keep the close affordance tight.
            HStack(spacing: scaledContentSpacing) {
                leadingIcon

                Text(tab.title)
                    .font(.system(size: appearance.tabTitleFontSize))
                    .lineLimit(1)
                    .foregroundStyle(
                        isSelected
                            ? TabBarColors.activeText(for: appearance)
                            : TabBarColors.inactiveText(for: appearance)
                    )
                    .saturation(saturation)
                    .tabGeometryDebugFrame { frame in
                        debugRecordGeometry(which: "title", frame: frame)
                    }

                if tab.showsRemoteIndicator {
                    Image(systemName: "network")
                        .font(.system(size: accessoryFontSize, weight: .semibold))
                        .foregroundStyle(
                            (isSelected
                                ? TabBarColors.activeText(for: appearance)
                                : TabBarColors.inactiveText(for: appearance))
                                .opacity(0.78)
                        )
                        .saturation(saturation)
                        .accessibilityHidden(true)
                }

                // Chrome/Safari-style audio affordance: a speaker glyph appears
                // when the tab is producing audible audio (click to mute) or has
                // been muted (click to unmute). Reuses the existing
                // `.toggleAudioMute` context action so the host owns the mute
                // route. Hidden when the tab is neither playing nor muted.
                if tab.isAudioMuted || tab.isAudioPlaying {
                    let isMuted = tab.isAudioMuted
                    let audioLabel = Bundle.module.localizedString(
                        forKey: isMuted ? "tabContext.unmuteTab" : "tabContext.muteTab",
                        value: isMuted ? "Unmute Tab" : "Mute Tab",
                        table: nil
                    )
                    Button {
                        onContextAction(.toggleAudioMute)
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: accessoryFontSize, weight: .semibold))
                            .foregroundStyle(
                                isAudioHovered
                                    ? (isSelected
                                        ? TabBarColors.activeText(for: appearance)
                                        : TabBarColors.inactiveText(for: appearance))
                                    : (isSelected
                                        ? TabBarColors.activeText(for: appearance)
                                        : TabBarColors.inactiveText(for: appearance))
                                        .opacity(0.78)
                            )
                            .frame(width: accessorySlotSize, height: accessorySlotSize)
                            .background(
                                Circle()
                                    .fill(
                                        isAudioHovered
                                            ? TabBarColors.hoveredTabBackground(for: appearance)
                                            : .clear
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withTransaction(Transaction(animation: nil)) {
                            isAudioHovered = hovering
                        }
                    }
                    .saturation(saturation)
                    .safeHelp(audioLabel)
                    .accessibilityLabel(audioLabel)
                    .tabBarButtonAnimationsDisabled()
                }

                if showsZoomIndicator {
                    Button {
                        onZoomToggle()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: accessoryFontSize, weight: .semibold))
                            .foregroundStyle(
                                isZoomHovered
                                    ? TabBarColors.activeText(for: appearance)
                                    : TabBarColors.inactiveText(for: appearance)
                            )
                            .frame(width: accessorySlotSize, height: accessorySlotSize)
                            .background(
                                Circle()
                                    .fill(
                                        isZoomHovered
                                            ? TabBarColors.hoveredTabBackground(for: appearance)
                                            : .clear
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        withTransaction(Transaction(animation: nil)) {
                            isZoomHovered = hovering
                        }
                    }
                    .saturation(saturation)
                    .accessibilityLabel("Exit zoom")
                    .tabBarButtonAnimationsDisabled()
                }
            }

            if fillsWidth {
                // Fill mode stretches each tab to share the strip width, so a
                // flexible spacer pushes the close button to the trailing edge.
                Spacer(minLength: 0)
            } else {
                // Fixed mode hugs each tab to its content. A greedy spacer here
                // would inflate the tab's ideal width so the `maxWidth` clamp
                // resolves to the maximum, leaving a large empty gap on short
                // titles (e.g. "~"). A fixed gap keeps the close button off the
                // title while letting the tab size to its content.
                Color.clear.frame(width: scaledContentSpacing)
            }

            // Close button / dirty indicator / shortcut hint share the same trailing slot.
            trailingAccessory
        }
    }

    /// Compact pinned-browser layout: a centered favicon with a small status badge
    /// overlay for audio/unread/dirty activity. The full title stays reachable via
    /// the tab tooltip and accessibility label. When the tab-shortcut modifier is
    /// held, the favicon crossfades to the modifier+number hint pill so number-based
    /// selection stays discoverable (mirrors the standard layout's trailing slot).
    @ViewBuilder
    private var iconOnlyContent: some View {
        ZStack {
            leadingIcon
                .overlay(alignment: .topTrailing) {
                    pinnedActivityBadge
                        .offset(x: 3, y: -2)
                }
                .opacity(showsShortcutHint ? 0 : 1)
                // Suppress the audio badge's tap target while the hint pill is shown.
                .allowsHitTesting(!showsShortcutHint)

            if let shortcutHintLabel {
                TabControlShortcutHintPill(text: shortcutHintLabel)
                    .opacity(showsShortcutHint ? 1 : 0)
                    .allowsHitTesting(false)
            }
        }
        .tabControlShortcutHintVisibilityAnimation(value: showsShortcutHint)
    }

    /// Leading favicon / loading spinner / symbol icon. Shared by the standard and
    /// icon-only layouts so favicon state handling stays in one place.
    @ViewBuilder
    private var leadingIcon: some View {
        let iconSlotSize = scaledIconSize
        let iconTintColor = isSelected
            ? TabBarColors.nsColorActiveText(for: appearance)
            : TabBarColors.nsColorInactiveText(for: appearance)
        let iconTint = Color(nsColor: iconTintColor)
        let faviconImage = renderedFaviconImage ?? tab.iconImageData.flatMap { NSImage(data: $0) }

        Group {
            if tab.isLoading {
                // Slightly smaller than the icon slot so it reads cleaner at tab scale.
                TabLoadingSpinner(size: iconSlotSize * 0.86, color: iconTintColor)
            } else if let image = faviconImage {
                FaviconIconView(image: image)
                    .frame(width: iconSlotSize, height: iconSlotSize, alignment: .center)
                    .clipped()
            } else if let iconAsset = tab.iconAsset {
                Image(iconAsset, bundle: .main)
                    .resizable()
                    .scaledToFit()
                    .frame(width: compactMarkSize, height: compactMarkSize, alignment: .center)
            } else if let iconName = tab.icon {
                if iconName == "globe", !showGlobeFallback {
                    // Avoid a distracting "globe -> favicon" flash: show a neutral placeholder
                    // briefly while the favicon fetch finishes. If no favicon arrives, we
                    // reveal the globe after a short delay.
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(iconTint.opacity(0.25), lineWidth: 1)
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: glyphSize(for: iconName)))
                        .foregroundStyle(iconTint)
                }
            }
        }
        // Keep downloaded favicon bitmaps in full color even for inactive tab bars.
        .saturation(TabItemStyling.iconSaturation(hasRasterIcon: faviconImage != nil, tabSaturation: saturation))
        .transaction { tx in
            // Prevent incidental parent animations from briefly fading icon content.
            tx.animation = nil
        }
        .frame(width: iconSlotSize, height: iconSlotSize, alignment: .center)
        .tabGeometryDebugFrame { frame in
            debugRecordGeometry(which: "icon", frame: frame)
        }
        .onAppear {
            updateRenderedFaviconImage()
            updateGlobeFallback()
        }
        .onDisappear {
            globeFallbackWorkItem?.cancel()
            globeFallbackWorkItem = nil
        }
        .onChange(of: tab.isLoading) { _ in updateGlobeFallback() }
        .onChange(of: tab.iconImageData) { _ in
            updateRenderedFaviconImage()
            updateGlobeFallback()
        }
        .onChange(of: tab.icon) { _ in updateGlobeFallback() }
    }

    /// Small corner badge for icon-only pinned tabs, preserving the audio/unread/
    /// dirty signals that the collapsed layout otherwise hides. A single slot keeps
    /// the chip uncluttered: audio takes priority, then unread, then dirty. The audio
    /// badge stays click-to-mute (same `.toggleAudioMute` route as the standard
    /// layout); the unread/dirty dots are non-interactive indicators.
    @ViewBuilder
    private var pinnedActivityBadge: some View {
        if !tab.isLoading {
            if tab.isAudioMuted || tab.isAudioPlaying {
                let isMuted = tab.isAudioMuted
                let audioLabel = Bundle.module.localizedString(
                    forKey: isMuted ? "tabContext.unmuteTab" : "tabContext.muteTab",
                    value: isMuted ? "Unmute Tab" : "Mute Tab",
                    table: nil
                )
                Button {
                    onContextAction(.toggleAudioMute)
                } label: {
                    Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: max(6, accessoryFontSize - 4), weight: .semibold))
                        .foregroundStyle(
                            isSelected
                                ? TabBarColors.activeText(for: appearance)
                                : TabBarColors.inactiveText(for: appearance)
                        )
                        .padding(2)
                        .background(
                            Circle().fill(TabBarColors.activeTabBackground(for: appearance))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .saturation(saturation)
                .safeHelp(audioLabel)
                .accessibilityLabel(audioLabel)
                .tabBarButtonAnimationsDisabled()
            } else if tab.showsNotificationBadge {
                Circle()
                    .fill(TabBarColors.notificationBadge(for: appearance))
                    .frame(width: TabBarMetrics.notificationBadgeSize, height: TabBarMetrics.notificationBadgeSize)
                    .allowsHitTesting(false)
            } else if tab.isDirty {
                Circle()
                    .fill(TabBarColors.dirtyIndicator(for: appearance))
                    .frame(width: TabBarMetrics.dirtyIndicatorSize, height: TabBarMetrics.dirtyIndicatorSize)
                    .saturation(saturation)
                    .allowsHitTesting(false)
            }
        }
    }

    /// Lower width bound: a compact icon-only width for pinned browser tabs,
    /// otherwise the standard minimum visual width.
    private var frameMinWidth: CGFloat {
        isIconOnlyPinned ? pinnedIconOnlyWidth : tabWidthRange.lowerBound
    }

    /// Upper width bound: pinned browser tabs are pinned to the compact width;
    /// fill mode stays flexible; fixed mode clamps to the configured maximum.
    private var frameMaxWidth: CGFloat {
        if isIconOnlyPinned { return pinnedIconOnlyWidth }
        return fillsWidth ? .infinity : tabWidthRange.upperBound
    }

    /// Fixed compact width used for icon-only pinned browser tabs. When the tab can
    /// show a control-shortcut hint, the width also reserves room for the hint pill so
    /// holding the modifier never changes the tab's width (avoids tab-bar layout shift,
    /// mirroring the standard layout's always-reserved hint slot).
    private var pinnedIconOnlyWidth: CGFloat {
        let reservedHint: CGFloat? = {
            guard allowsShortcutHints, let shortcutHintLabel else { return nil }
            return TabItemStyling.shortcutHintWidth(for: shortcutHintLabel)
        }()
        return TabItemStyling.pinnedIconOnlyWidth(
            iconSlotSize: scaledIconSize,
            horizontalPadding: TabBarMetrics.tabHorizontalPadding,
            reservedShortcutHintWidth: reservedHint
        )
    }

    /// Scale factor of the configured tab title font relative to the default.
    ///
    /// Icons and close/pin affordances are multiplied by this so they grow and
    /// shrink together with the tab title font size instead of staying pinned to
    /// the default-size constants.
    private var fontScale: CGFloat {
        max(0.1, appearance.tabTitleFontSize / TabBarMetrics.titleFontSize)
    }

    /// Leading-icon slot size, scaled to the configured tab title font.
    private var scaledIconSize: CGFloat {
        TabBarMetrics.iconSize * fontScale
    }

    /// Close / pin glyph size, scaled to the configured tab title font.
    private var scaledCloseIconSize: CGFloat {
        TabBarMetrics.closeIconSize * fontScale
    }

    /// Optical mark size for compact glyphs and host-provided asset icons.
    private var compactMarkSize: CGFloat {
        max(10, TabBarMetrics.iconSize - 2.5) * fontScale
    }

    /// Spacing between the leading icon and the title, scaled to the font.
    private var scaledContentSpacing: CGFloat {
        TabBarMetrics.contentSpacing * fontScale
    }

    private func glyphSize(for iconName: String) -> CGFloat {
        // `terminal.fill` reads visually heavier than most symbols at the same point size.
        // Keep the base sizes hardcoded to avoid cross-glyph layout shifts, then scale to the font.
        if iconName == "terminal.fill" || iconName == "terminal" || iconName == "globe" {
            return compactMarkSize
        }
        return scaledIconSize
    }

    private var shortcutHintLabel: String? {
        guard let controlShortcutDigit else { return nil }
        return "\(shortcutModifierSymbol)\(controlShortcutDigit)"
    }

    /// Hints are only ever shown on the focused pane; gating on focus here keeps
    /// hint visibility scoped to the focused pane while leaving width untouched.
    private var allowsShortcutHints: Bool {
        isFocused && tabShortcutHintsEnabled
    }

    private var showsShortcutHint: Bool {
        allowsShortcutHints && (showsControlShortcutHint || alwaysShowShortcutHints) && shortcutHintLabel != nil
    }

    private var tabWidthRange: ClosedRange<CGFloat> {
        TabItemStyling.tabWidthRange(for: appearance)
    }

    private var shortcutHintSlotWidth: CGFloat {
        // Reserve the wider shortcut-hint width whenever hints are enabled and
        // this tab has a digit, regardless of focus or modifier-hold. Both focus
        // and modifier-hold change the pill's opacity, not the measured width, so
        // the tab bar never shifts when a pane is focused or ⌃/⌘ is held.
        TabItemStyling.reservedShortcutHintSlotWidth(
            shortcutHintLabel: shortcutHintLabel,
            tabShortcutHintsEnabled: tabShortcutHintsEnabled,
            isFocused: isFocused,
            accessorySlotSize: accessorySlotSize,
            xOffset: controlShortcutHintXOffset
        )
    }

    private var accessoryFontSize: CGFloat {
        max(8, appearance.tabTitleFontSize - 2)
    }

    private var accessorySlotSize: CGFloat {
        // Keep accessory affordances readable when the tab title font is increased.
        min(tabHeight, max(TabBarMetrics.closeButtonSize, ceil(accessoryFontSize + 4)))
    }

    private var tabHeight: CGFloat {
        max(1, appearance.tabBarHeight)
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        ZStack(alignment: .center) {
            if let shortcutHintLabel {
                TabControlShortcutHintPill(text: shortcutHintLabel)
                    .offset(
                        x: TabControlShortcutHintDebugSettings.clamped(controlShortcutHintXOffset),
                        y: TabControlShortcutHintDebugSettings.clamped(controlShortcutHintYOffset)
                    )
                    .opacity(showsShortcutHint ? 1 : 0)
                    .allowsHitTesting(false)
            }

            closeOrDirtyIndicator
                .opacity(showsShortcutHint ? 0 : 1)
                .allowsHitTesting(!showsShortcutHint)
        }
        .frame(width: shortcutHintSlotWidth, height: accessorySlotSize, alignment: .center)
        .tabControlShortcutHintVisibilityAnimation(value: showsShortcutHint)
    }

    private func updateGlobeFallback() {
        // Track load transitions so we can avoid an "empty placeholder -> globe" flash on brand-new tabs.
        if lastIsLoadingObserved && !tab.isLoading {
            lastLoadingStoppedAt = Date()
        }
        lastIsLoadingObserved = tab.isLoading

        globeFallbackWorkItem?.cancel()
        globeFallbackWorkItem = nil

        // Only delay the globe fallback right after a navigation completes, when a favicon is likely to
        // arrive soon. Otherwise (e.g. a brand-new tab), show the globe immediately.
        let recentlyStoppedLoading: Bool = {
            guard let t = lastLoadingStoppedAt else { return false }
            return Date().timeIntervalSince(t) < 1.5
        }()
        let shouldDelayGlobe = (tab.icon == "globe") && (tab.iconImageData == nil) && !tab.isLoading && recentlyStoppedLoading
        if !shouldDelayGlobe {
            showGlobeFallback = true
            return
        }

        showGlobeFallback = false
        let work = DispatchWorkItem {
            showGlobeFallback = true
        }
        globeFallbackWorkItem = work
        // Give favicon fetches a little longer before showing the globe fallback to reduce brief flashes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.90, execute: work)
    }

    private func updateRenderedFaviconImage() {
        guard renderedFaviconData != tab.iconImageData ||
                (renderedFaviconImage == nil && tab.iconImageData != nil) else { return }
        renderedFaviconData = tab.iconImageData
        renderedFaviconImage = TabItemStyling.resolvedFaviconImage(
            existing: renderedFaviconImage,
            incomingData: tab.iconImageData
        )
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if tab.isLoading { parts.append("Loading") }
        if tab.isPinned { parts.append("Pinned") }
        if tab.showsNotificationBadge { parts.append("Unread") }
        if tab.isDirty { parts.append("Modified") }
        if tab.isAudioMuted {
            parts.append(Bundle.module.localizedString(forKey: "tabContext.audioMutedAccessibility", value: "Muted", table: nil))
        }
        if tab.showsRemoteIndicator {
            parts.append(Bundle.module.localizedString(forKey: "tabContext.remoteConnectedAccessibility", value: "Connected over SSH", table: nil))
        }
        if showsZoomIndicator { parts.append("Zoomed") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Tab Background

    @ViewBuilder
    private var tabBackground: some View {
        ZStack(alignment: .top) {
            if isSelected {
                Rectangle()
                    .fill(TabBarColors.activeTabBackground(for: appearance))
            } else if TabItemStyling.shouldShowHoverBackground(isHovered: isHovered, isSelected: isSelected) {
                Rectangle()
                    .fill(TabBarColors.hoveredTabBackground(for: appearance))
            } else {
                Color.clear
            }

            // Right border separator
            HStack {
                Spacer()
                Rectangle()
                    .fill(TabBarColors.separator(for: appearance))
                    .frame(width: 1)
                    .padding(.bottom, max(0, trailingSeparatorBottomInset))
            }
        }
    }

    // MARK: - Close Button / Dirty Indicator

    @ViewBuilder
    private var closeOrDirtyIndicator: some View {
        ZStack {
            // Dirty indicator (shown when dirty and not hovering, hidden for selected tab)
            if (!isSelected && !isHovered && !isCloseHovered) && (tab.isDirty || tab.showsNotificationBadge) {
                HStack(spacing: 2) {
                    if tab.showsNotificationBadge {
                        Circle()
                            .fill(TabBarColors.notificationBadge(for: appearance))
                            .frame(width: TabBarMetrics.notificationBadgeSize, height: TabBarMetrics.notificationBadgeSize)
                    }
                    if tab.isDirty {
                        Circle()
                            .fill(TabBarColors.dirtyIndicator(for: appearance))
                            .frame(width: TabBarMetrics.dirtyIndicatorSize, height: TabBarMetrics.dirtyIndicatorSize)
                            .saturation(saturation)
                    }
                }
            }

            if tab.isPinned {
                if isSelected || isHovered || isCloseHovered || (!tab.isDirty && !tab.showsNotificationBadge) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: scaledCloseIconSize, weight: .semibold))
                        .foregroundStyle(TabBarColors.inactiveText(for: appearance))
                        .frame(width: accessorySlotSize, height: accessorySlotSize)
                        .saturation(saturation)
                }
            } else if allowsClose && (isSelected || isHovered || isCloseHovered) {
                // Close button (always visible on active tab, shown on hover for others)
                Button {
                    onClose(.closeButton)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: scaledCloseIconSize, weight: .semibold))
                        .foregroundStyle(
                            isCloseHovered
                                ? TabBarColors.activeText(for: appearance)
                                : TabBarColors.inactiveText(for: appearance)
                        )
                        .frame(width: accessorySlotSize, height: accessorySlotSize)
                        .background(
                            Circle()
                                .fill(
                                    isCloseHovered
                                        ? TabBarColors.hoveredTabBackground(for: appearance)
                                        : .clear
                                )
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withTransaction(Transaction(animation: nil)) {
                        isCloseHovered = hovering
                    }
                }
                .saturation(saturation)
            }
        }
        .frame(width: accessorySlotSize, height: accessorySlotSize)
        .tabBarButtonAnimationsDisabled()
    }
}

private struct TabLoadingSpinner: NSViewRepresentable {
    let size: CGFloat
    let color: NSColor

    func makeNSView(context: Context) -> TabLoadingSpinnerLayerView {
        let view = TabLoadingSpinnerLayerView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        view.configure(size: size, color: color)
        return view
    }

    func updateNSView(_ nsView: TabLoadingSpinnerLayerView, context: Context) {
        nsView.configure(size: size, color: color)
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

private struct FaviconIconView: NSViewRepresentable {
    let image: NSImage

    final class ContainerView: NSView {
        let imageView = NSImageView(frame: .zero)

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.masksToBounds = true
            imageView.imageScaling = .scaleProportionallyDown
            imageView.imageAlignment = .alignCenter
            imageView.animates = false
            imageView.contentTintColor = nil
            imageView.autoresizingMask = [.width, .height]
            addSubview(imageView)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var intrinsicContentSize: NSSize {
            .zero
        }

        override func layout() {
            super.layout()
            imageView.frame = bounds.integral
        }
    }

    func makeNSView(context: Context) -> ContainerView {
        ContainerView(frame: .zero)
    }

    func updateNSView(_ nsView: ContainerView, context: Context) {
        image.isTemplate = false
        if nsView.imageView.image !== image {
            nsView.imageView.image = image
        }
        nsView.imageView.contentTintColor = nil
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
        let coordinator = context.coordinator
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseUp]) { [weak coordinator] event in
            guard event.buttonNumber == 2 else { return event }
            guard let coordinator, let v = coordinator.view, let w = v.window else { return event }
            guard event.window === w else { return event }

            let p = v.convert(event.locationInWindow, from: nil)
            guard v.bounds.contains(p) else { return event }

            coordinator.onMiddleClick?()
            return nil // swallow so it doesn't also select the tab
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.onMiddleClick = onMiddleClick
    }
}

struct TabContextMenuSnapshot {
    let tabId: UUID
    let state: TabContextMenuState
    let moveDestinationsProvider: () -> [TabContextMoveDestination]
    let forkConversationOpenAvailabilityProvider: () -> Bool?
}

final class TabContextMenuActionTarget: NSObject {
    var onContextAction: ((TabContextAction) -> Void)?
    var onMoveDestination: ((String) -> Void)?

    @objc func performContextAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let action = TabContextAction(rawValue: rawValue) else {
            return
        }
        onContextAction?(action)
    }

    @objc func performMoveDestination(_ sender: NSMenuItem) {
        guard let destinationId = sender.representedObject as? String else { return }
        onMoveDestination?(destinationId)
    }
}

enum TabContextMenuBuilder {
    static func makeMenu(
        snapshot: TabContextMenuSnapshot,
        target: TabContextMenuActionTarget
    ) -> NSMenu {
        var state = snapshot.state
        let canForkConversationAtOpen = snapshot.forkConversationOpenAvailabilityProvider()
        let forkConversationEnabled = canForkConversationAtOpen ?? state.canForkConversation
        state.canForkConversation = state.canForkConversation || forkConversationEnabled
        let menu = NSMenu()
        menu.autoenablesItems = false

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

        if state.canForkConversation {
            menu.addItem(.separator())
            addAction(
                title: localized("tabContext.forkConversation", defaultValue: "Fork Conversation"),
                action: .forkConversation,
                enabled: forkConversationEnabled,
                state: state,
                target: target,
                to: menu
            )
            menu.addItem(forkConversationSubmenuItem(
                state: state,
                target: target,
                enabled: forkConversationEnabled
            ))
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

    private static func applyShortcut(_ shortcut: KeyboardShortcut, to item: NSMenuItem) {
        item.keyEquivalent = String(shortcut.key.character).lowercased()
        item.keyEquivalentModifierMask = shortcut.modifiers.nsMenuModifierMask
    }

    private static func localized(_ key: String, defaultValue: String) -> String {
        Bundle.module.localizedString(forKey: key, value: defaultValue, table: nil)
    }
}

private extension EventModifiers {
    var nsMenuModifierMask: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) { flags.insert(.command) }
        if contains(.shift) { flags.insert(.shift) }
        if contains(.option) { flags.insert(.option) }
        if contains(.control) { flags.insert(.control) }
        return flags
    }
}

struct TabContextMenuPresenter: NSViewRepresentable {
    let snapshot: TabContextMenuSnapshot
    let onContextAction: (TabContextAction) -> Void
    let onMoveDestination: (String) -> Void

    final class Coordinator {
        var snapshot: TabContextMenuSnapshot
        let actionTarget = TabContextMenuActionTarget()
        weak var view: NSView?
        var monitor: Any?

        init(snapshot: TabContextMenuSnapshot) {
            self.snapshot = snapshot
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        func presentMenu(at point: NSPoint, in view: NSView) {
            let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: actionTarget)
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(snapshot: snapshot)
        coordinator.actionTarget.onContextAction = onContextAction
        coordinator.actionTarget.onMoveDestination = onMoveDestination
        return coordinator
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor

        context.coordinator.view = view

        let coordinator = context.coordinator
        coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { [weak coordinator] event in
            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }
            guard let coordinator, let view = coordinator.view, let window = view.window else { return event }
            guard event.window === window else { return event }

            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else { return event }

            coordinator.presentMenu(at: point, in: view)
            return nil
        }

        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.view = nsView
        context.coordinator.snapshot = snapshot
        context.coordinator.actionTarget.onContextAction = onContextAction
        context.coordinator.actionTarget.onMoveDestination = onMoveDestination
    }
}
