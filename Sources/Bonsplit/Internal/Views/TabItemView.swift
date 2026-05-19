import SwiftUI
import AppKit

enum TabControlShortcutHintAnimation {
    static let visibility: Animation = .easeOut(duration: 0.12)
}

extension View {
    func tabControlShortcutHintVisibilityAnimation<Value: Equatable>(value: Value) -> some View {
        animation(TabControlShortcutHintAnimation.visibility, value: value)
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

enum TabItemStyling {
    static func iconSaturation(hasRasterIcon: Bool, tabSaturation: Double) -> Double {
        hasRasterIcon ? 1.0 : tabSaturation
    }

    static func shouldShowHoverBackground(isHovered: Bool, isSelected: Bool) -> Bool {
        isHovered && !isSelected
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
}

private struct InlineTabRenameField: NSViewRepresentable {
    let initialTitle: String
    let fontSize: CGFloat
    let textColor: NSColor
    let height: CGFloat
    let onTextChange: (String) -> Void
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    fileprivate final class InlineRenameTextField: NSTextField {
        override class var cellClass: AnyClass? {
            get { InlineRenameTextFieldCell.self }
            set {}
        }
    }

    fileprivate final class InlineRenameTextFieldCell: NSTextFieldCell {
        override func drawingRect(forBounds rect: NSRect) -> NSRect {
            textRect(forBounds: rect)
        }

        override func edit(
            withFrame rect: NSRect,
            in controlView: NSView,
            editor textObj: NSText,
            delegate: Any?,
            event: NSEvent?
        ) {
            super.edit(
                withFrame: textRect(forBounds: rect),
                in: controlView,
                editor: textObj,
                delegate: delegate,
                event: event
            )
        }

        override func select(
            withFrame rect: NSRect,
            in controlView: NSView,
            editor textObj: NSText,
            delegate: Any?,
            start selStart: Int,
            length selLength: Int
        ) {
            super.select(
                withFrame: textRect(forBounds: rect),
                in: controlView,
                editor: textObj,
                delegate: delegate,
                start: selStart,
                length: selLength
            )
        }

        private func textRect(forBounds rect: NSRect) -> NSRect {
            guard let font else {
                let fallback = super.drawingRect(forBounds: rect)
                return NSRect(x: rect.minX, y: fallback.minY, width: rect.width, height: fallback.height)
            }

            let lineHeight = min(max(1, ceil(font.boundingRectForFont.height)), max(1, rect.height))
            let lineY = rect.minY + floor((rect.height - lineHeight) / 2)
            return NSRect(x: rect.minX, y: lineY, width: rect.width, height: lineHeight)
        }
    }

    fileprivate final class InlineRenameHostView: NSView {
        let field: InlineRenameTextField
        var contentHeight: CGFloat {
            didSet {
                invalidateIntrinsicContentSize()
                needsLayout = true
            }
        }
        var onAttachToWindow: ((NSTextField) -> Void)?
        private var didRequestInitialFocus = false

        init(field: InlineRenameTextField, contentHeight: CGFloat) {
            self.field = field
            self.contentHeight = contentHeight
            super.init(frame: .zero)
            addSubview(field)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: contentHeight)
        }

        override func layout() {
            super.layout()
            field.frame = bounds
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !didRequestInitialFocus else { return }
            didRequestInitialFocus = true
            onAttachToWindow?(field)
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: InlineTabRenameField
        var didFinish = false
        private var outsideClickMonitor: Any?

        init(parent: InlineTabRenameField) {
            self.parent = parent
        }

        deinit {
            removeOutsideClickMonitor()
        }

        func attach(to field: NSTextField) {
            installOutsideClickMonitor(for: field)
            configureFieldEditor(for: field)
        }

        func configureFieldEditor(for field: NSTextField) {
            guard let fieldEditor = field.currentEditor() as? NSTextView else { return }
            fieldEditor.textContainerInset = .zero
            fieldEditor.textContainer?.lineFragmentPadding = 0
            fieldEditor.font = field.font
            fieldEditor.textColor = .clear
            fieldEditor.insertionPointColor = parent.textColor
            fieldEditor.selectedTextAttributes = [
                .foregroundColor: NSColor.clear,
                .backgroundColor: NSColor.selectedTextBackgroundColor.withAlphaComponent(0.42),
            ]
        }

        func finishCommit(_ title: String) {
            guard !didFinish else { return }
            didFinish = true
            removeOutsideClickMonitor()
            parent.onCommit(title)
        }

        func finishCancel() {
            guard !didFinish else { return }
            didFinish = true
            removeOutsideClickMonitor()
            parent.onCancel()
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            finishCommit(field.stringValue)
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.onTextChange(field.stringValue)
            configureFieldEditor(for: field)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                guard !textView.hasMarkedText() else { return false }
                finishCommit(textView.string)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                guard !textView.hasMarkedText() else { return false }
                finishCancel()
                return true
            default:
                return false
            }
        }

        private func installOutsideClickMonitor(for field: NSTextField) {
            guard outsideClickMonitor == nil else { return }
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self, weak field] event in
                guard let self, let field, !self.didFinish else { return event }
                guard !self.event(event, isInside: field) else { return event }

                self.finishCommit(field.stringValue)
                field.window?.makeFirstResponder(nil)
                return event
            }
        }

        private func removeOutsideClickMonitor() {
            if let outsideClickMonitor {
                NSEvent.removeMonitor(outsideClickMonitor)
                self.outsideClickMonitor = nil
            }
        }

        private func event(_ event: NSEvent, isInside field: NSTextField) -> Bool {
            guard let window = field.window, event.window === window else { return false }
            let point = field.convert(event.locationInWindow, from: nil)
            return field.bounds.contains(point)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    fileprivate func makeNSView(context: Context) -> InlineRenameHostView {
        let field = InlineRenameTextField(string: initialTitle)
        field.delegate = context.coordinator
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = .clear
        field.lineBreakMode = .byTruncatingTail
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.setAccessibilityIdentifier("paneTab.inlineRenameField")
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let host = InlineRenameHostView(field: field, contentHeight: height)
        host.onAttachToWindow = { [coordinator = context.coordinator] field in
            guard !coordinator.didFinish else { return }
            coordinator.attach(to: field)
            field.selectText(nil)
            coordinator.configureFieldEditor(for: field)
        }

        return host
    }

    fileprivate func updateNSView(_ host: InlineRenameHostView, context: Context) {
        context.coordinator.parent = self
        let field = host.field
        field.font = .systemFont(ofSize: fontSize)
        field.textColor = .clear
        host.contentHeight = height
        context.coordinator.configureFieldEditor(for: field)
        if field.currentEditor() == nil, field.stringValue != initialTitle {
            field.stringValue = initialTitle
        }
    }
}

/// Individual tab view with icon, title, close button, and dirty indicator
struct TabItemView: View {
    let tab: TabItem
    let isSelected: Bool
    let isInlineRenaming: Bool
    let showsZoomIndicator: Bool
    let appearance: BonsplitConfiguration.Appearance
    let saturation: Double
    let trailingSeparatorBottomInset: CGFloat
    let controlShortcutDigit: Int?
    let allowsShortcutHints: Bool
    let showsControlShortcutHint: Bool
    let shortcutModifierSymbol: String
    let contextMenuState: TabContextMenuState
    let onSelect: () -> Void
    let onClose: () -> Void
    let onZoomToggle: () -> Void
    let onInlineRenameRequest: () -> Void
    let onInlineRenameCommit: (String, String) -> Void
    let onInlineRenameCancel: () -> Void
    let onContextAction: (TabContextAction) -> Void
    let onMoveDestination: (String) -> Void

    @State private var isHovered = false
    @State private var isCloseHovered = false
    @State private var isZoomHovered = false
    @State private var showGlobeFallback = true
    @State private var globeFallbackWorkItem: DispatchWorkItem?
    @State private var lastIsLoadingObserved = false
    @State private var lastLoadingStoppedAt: Date?
    @State private var renderedFaviconData: Data?
    @State private var renderedFaviconImage: NSImage?
    @State private var inlineRenameInitialTitle: String?
    @State private var inlineRenameDraftTitle: String?
    @AppStorage(TabControlShortcutHintDebugSettings.xKey) private var controlShortcutHintXOffset = TabControlShortcutHintDebugSettings.defaultX
    @AppStorage(TabControlShortcutHintDebugSettings.yKey) private var controlShortcutHintYOffset = TabControlShortcutHintDebugSettings.defaultY
    @AppStorage(TabControlShortcutHintDebugSettings.alwaysShowKey) private var alwaysShowShortcutHints = TabControlShortcutHintDebugSettings.defaultAlwaysShow

    var body: some View {
        HStack(spacing: 0) {
            // Icon + title block uses the standard spacing, but keep the close affordance tight.
            HStack(spacing: TabBarMetrics.contentSpacing) {
                let iconSlotSize = TabBarMetrics.iconSize
                let iconTint = isSelected
                    ? TabBarColors.activeText(for: appearance)
                    : TabBarColors.inactiveText(for: appearance)
                let faviconImage = renderedFaviconImage ?? tab.iconImageData.flatMap { NSImage(data: $0) }

                Group {
                    if tab.isLoading {
                        // Slightly smaller than the icon slot so it reads cleaner at tab scale.
                        TabLoadingSpinner(size: iconSlotSize * 0.86, color: iconTint)
                    } else if let image = faviconImage {
                        FaviconIconView(image: image)
                            .frame(width: iconSlotSize, height: iconSlotSize, alignment: .center)
                            .clipped()
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

                if isInlineRenaming {
                    titleLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .leading) {
                            InlineTabRenameField(
                                initialTitle: inlineRenameInitialTitle ?? tab.title,
                                fontSize: appearance.tabTitleFontSize,
                                textColor: titleTextNSColor,
                                height: titleLineHeight,
                                onTextChange: { inlineRenameDraftTitle = $0 },
                                onCommit: { title in
                                    let initialTitle = inlineRenameInitialTitle ?? tab.title
                                    inlineRenameInitialTitle = nil
                                    inlineRenameDraftTitle = nil
                                    onInlineRenameCommit(title, initialTitle)
                                },
                                onCancel: {
                                    inlineRenameInitialTitle = nil
                                    inlineRenameDraftTitle = nil
                                    onInlineRenameCancel()
                                }
                            )
                            .frame(minWidth: 44, maxWidth: .infinity, minHeight: titleLineHeight, maxHeight: titleLineHeight)
                        }
                        .onAppear {
                            inlineRenameInitialTitle = tab.title
                            inlineRenameDraftTitle = tab.title
                        }
                        .onDisappear {
                            inlineRenameInitialTitle = nil
                            inlineRenameDraftTitle = nil
                        }
                        .layoutPriority(1)
                } else {
                    titleLabel
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
                        isZoomHovered = hovering
                    }
                    .saturation(saturation)
                    .accessibilityLabel("Exit zoom")
                }
            }

            Spacer(minLength: 0)

            // Close button / dirty indicator / shortcut hint share the same trailing slot.
            trailingAccessory
        }
        .padding(.horizontal, TabBarMetrics.tabHorizontalPadding)
        .frame(
            minWidth: TabBarMetrics.tabMinWidth,
            maxWidth: TabBarMetrics.tabMaxWidth,
            minHeight: tabHeight,
            maxHeight: tabHeight
        )
        .background(tabBackground.saturation(saturation))
        .tabControlShortcutHintVisibilityAnimation(value: showsShortcutHint)
        .contentShape(Rectangle())
        // Middle click to close (macOS convention).
        // Uses an AppKit event monitor so it doesn't interfere with left click selection or drag/reorder.
        .background(MiddleClickMonitorView(onMiddleClick: {
            guard !tab.isPinned else { return }
            onClose()
        }))
        .background(TabContextMenuPresenter(
            snapshot: TabContextMenuSnapshot(tabId: tab.id, state: contextMenuState),
            onContextAction: onContextAction,
            onMoveDestination: onMoveDestination
        ))
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onInlineRenameRequest()
            }
        )
        .onHover { hovering in
            // Keep icon rendering stable while hovering; only accessory/background elements animate.
            isHovered = hovering
        }
        .accessibilityElement(children: isInlineRenaming ? .contain : .combine)
        .accessibilityLabel(tab.title)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .safeHelp(tab.title)
    }

    private func glyphSize(for iconName: String) -> CGFloat {
        // `terminal.fill` reads visually heavier than most symbols at the same point size.
        // Hardcode sizes to avoid cross-glyph layout shifts.
        if iconName == "terminal.fill" || iconName == "terminal" || iconName == "globe" {
            return max(10, TabBarMetrics.iconSize - 2.5)
        }
        return TabBarMetrics.iconSize
    }

    private var shortcutHintLabel: String? {
        guard let controlShortcutDigit else { return nil }
        return "\(shortcutModifierSymbol)\(controlShortcutDigit)"
    }

    private var showsShortcutHint: Bool {
        allowsShortcutHints && (showsControlShortcutHint || alwaysShowShortcutHints) && shortcutHintLabel != nil
    }

    private var shortcutHintSlotWidth: CGFloat {
        guard let label = shortcutHintLabel else {
            return accessorySlotSize
        }
        let positiveDebugInset = max(0, CGFloat(TabControlShortcutHintDebugSettings.clamped(controlShortcutHintXOffset))) + 2
        return max(accessorySlotSize, shortcutHintWidth(for: label) + positiveDebugInset)
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

    private var titleLineHeight: CGFloat {
        let font = NSFont.systemFont(ofSize: appearance.tabTitleFontSize)
        return max(1, ceil(font.boundingRectForFont.height))
    }

    private var displayedTitle: String {
        if isInlineRenaming {
            return inlineRenameDraftTitle ?? inlineRenameInitialTitle ?? tab.title
        }
        return tab.title
    }

    private var titleTextColor: Color {
        isSelected
            ? TabBarColors.activeText(for: appearance)
            : TabBarColors.inactiveText(for: appearance)
    }

    private var titleTextNSColor: NSColor {
        isSelected
            ? TabBarColors.nsColorActiveText(for: appearance)
            : TabBarColors.nsColorInactiveText(for: appearance)
    }

    private var titleLabel: some View {
        Text(displayedTitle)
            .font(.system(size: appearance.tabTitleFontSize))
            .lineLimit(1)
            .foregroundStyle(titleTextColor)
            .saturation(saturation)
    }

    private func shortcutHintWidth(for label: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: accessoryFontSize, weight: .semibold)
        let textWidth = (label as NSString).size(withAttributes: [.font: font]).width
        return ceil(textWidth) + 8
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        ZStack(alignment: .center) {
            if let shortcutHintLabel {
                Text(shortcutHintLabel)
                    .font(.system(size: accessoryFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(
                        isSelected
                            ? TabBarColors.activeText(for: appearance)
                            : TabBarColors.inactiveText(for: appearance)
                    )
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color.white.opacity(0.30), lineWidth: 0.8)
                            )
                            .shadow(color: Color.black.opacity(0.22), radius: 2, x: 0, y: 1)
                    )
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
        if showsZoomIndicator { parts.append("Zoomed") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Tab Background

    @ViewBuilder
    private var tabBackground: some View {
        ZStack(alignment: .top) {
            // Background fill (hover)
            if TabItemStyling.shouldShowHoverBackground(isHovered: isHovered, isSelected: isSelected) {
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
                        .font(.system(size: TabBarMetrics.closeIconSize, weight: .semibold))
                        .foregroundStyle(TabBarColors.inactiveText(for: appearance))
                        .frame(width: accessorySlotSize, height: accessorySlotSize)
                        .saturation(saturation)
                }
            } else if isSelected || isHovered || isCloseHovered {
                // Close button (always visible on active tab, shown on hover for others)
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: TabBarMetrics.closeIconSize, weight: .semibold))
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
                    isCloseHovered = hovering
                }
                .saturation(saturation)
            }
        }
        .frame(width: accessorySlotSize, height: accessorySlotSize)
        .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isHovered)
        .animation(.easeInOut(duration: TabBarMetrics.hoverDuration), value: isCloseHovered)
    }
}

private struct TabLoadingSpinner: View {
    let size: CGFloat
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // 0.9s per revolution feels a bit snappier at tab-icon scale.
            let angle = (t.truncatingRemainder(dividingBy: 0.9) / 0.9) * 360.0

            ZStack {
                Circle()
                    .stroke(color.opacity(0.20), lineWidth: ringWidth)
                Circle()
                    .trim(from: 0.0, to: 0.28)
                    .stroke(color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(angle))
            }
            .frame(width: size, height: size)
        }
    }

    private var ringWidth: CGFloat {
        max(1.6, size * 0.14)
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
        let state = snapshot.state
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

        menu.addItem(moveSubmenuItem(state: state, target: target))

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
        state: TabContextMenuState,
        target: TabContextMenuActionTarget
    ) -> NSMenuItem {
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
        for destination in state.moveDestinations {
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
        item.isEnabled = state.canMoveToNewWorkspace || !state.moveDestinations.isEmpty
        return item
    }

    @discardableResult
    private static func addAction(
        title: String,
        action: TabContextAction,
        enabled: Bool = true,
        state: TabContextMenuState,
        target: TabContextMenuActionTarget,
        to menu: NSMenu
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(TabContextMenuActionTarget.performContextAction(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = action.rawValue
        item.isEnabled = enabled
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

private struct TabContextMenuPresenter: NSViewRepresentable {
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
            guard let coordinator, let view = coordinator.view, let window = view.window else { return event }
            guard event.window === window else { return event }

            let point = view.convert(event.locationInWindow, from: nil)
            guard view.bounds.contains(point) else { return event }

            guard event.type == .rightMouseDown || event.modifierFlags.contains(.control) else { return event }

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
