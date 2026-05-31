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

    static func tabWidthRange(for appearance: BonsplitConfiguration.Appearance) -> ClosedRange<CGFloat> {
        let minimum = max(1, TabBarMetrics.tabMinWidth)
        let maximum = max(minimum, appearance.tabMaxWidth)
        return minimum...maximum
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

/// Individual tab view with icon, title, close button, and dirty indicator
struct TabItemView: View {
    let tab: TabItem
    let isSelected: Bool
    let showsZoomIndicator: Bool
    let appearance: BonsplitConfiguration.Appearance
    let saturation: Double
    let trailingSeparatorBottomInset: CGFloat
    let controlShortcutDigit: Int?
    let allowsShortcutHints: Bool
    let showsControlShortcutHint: Bool
    let shortcutModifierSymbol: String
    let allowsClose: Bool
    let contextMenuState: TabContextMenuState
    let moveDestinationsProvider: () -> [TabContextMoveDestination]
    let onSelect: () -> Void
    let onClose: (TabCloseRequestSource) -> Void
    let onZoomToggle: () -> Void
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
    @AppStorage(TabControlShortcutHintDebugSettings.xKey) private var controlShortcutHintXOffset = TabControlShortcutHintDebugSettings.defaultX
    @AppStorage(TabControlShortcutHintDebugSettings.yKey) private var controlShortcutHintYOffset = TabControlShortcutHintDebugSettings.defaultY
    @AppStorage(TabControlShortcutHintDebugSettings.alwaysShowKey) private var alwaysShowShortcutHints = TabControlShortcutHintDebugSettings.defaultAlwaysShow

    var body: some View {
        HStack(spacing: 0) {
            // Icon + title block uses the standard spacing, but keep the close affordance tight.
            HStack(spacing: scaledContentSpacing) {
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

                Text(tab.title)
                    .font(.system(size: appearance.tabTitleFontSize))
                    .lineLimit(1)
                    .foregroundStyle(
                        isSelected
                            ? TabBarColors.activeText(for: appearance)
                            : TabBarColors.inactiveText(for: appearance)
                    )
                    .saturation(saturation)

                if tab.isAudioMuted {
                    Image(systemName: "speaker.slash")
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

            Spacer(minLength: 0)

            // Close button / dirty indicator / shortcut hint share the same trailing slot.
            trailingAccessory
        }
        .padding(.horizontal, TabBarMetrics.tabHorizontalPadding)
        .frame(
            minWidth: tabWidthRange.lowerBound,
            maxWidth: tabWidthRange.upperBound,
            minHeight: tabHeight,
            maxHeight: tabHeight
        )
        .background(tabBackground.saturation(saturation))
        .tabControlShortcutHintVisibilityAnimation(value: showsShortcutHint)
        .contentShape(Rectangle().inset(by: -BonsplitTabItemHitTesting.horizontalSlop))
        // Middle click to close (macOS convention).
        // Uses an AppKit event monitor so it doesn't interfere with left click selection or drag/reorder.
        .background(MiddleClickMonitorView(onMiddleClick: {
            guard allowsClose, !tab.isPinned else { return }
            onClose(.middleClick)
        }))
        .background(TabContextMenuPresenter(
            snapshot: TabContextMenuSnapshot(
                tabId: tab.id,
                state: contextMenuState,
                moveDestinationsProvider: moveDestinationsProvider
            ),
            onContextAction: onContextAction,
            onMoveDestination: onMoveDestination
        ))
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

    /// Spacing between the leading icon and the title, scaled to the font.
    private var scaledContentSpacing: CGFloat {
        TabBarMetrics.contentSpacing * fontScale
    }

    private func glyphSize(for iconName: String) -> CGFloat {
        // `terminal.fill` reads visually heavier than most symbols at the same point size.
        // Keep the base sizes hardcoded to avoid cross-glyph layout shifts, then scale to the font.
        if iconName == "terminal.fill" || iconName == "terminal" || iconName == "globe" {
            return max(10, TabBarMetrics.iconSize - 2.5) * fontScale
        }
        return scaledIconSize
    }

    private var shortcutHintLabel: String? {
        guard let controlShortcutDigit else { return nil }
        return "\(shortcutModifierSymbol)\(controlShortcutDigit)"
    }

    private var showsShortcutHint: Bool {
        allowsShortcutHints && (showsControlShortcutHint || alwaysShowShortcutHints) && shortcutHintLabel != nil
    }

    private var tabWidthRange: ClosedRange<CGFloat> {
        TabItemStyling.tabWidthRange(for: appearance)
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
        if tab.isAudioMuted {
            parts.append(Bundle.module.localizedString(forKey: "tabContext.audioMutedAccessibility", value: "Muted", table: nil))
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
                state: state,
                target: target,
                to: menu
            )
            menu.addItem(forkConversationSubmenuItem(state: state, target: target))
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
        target: TabContextMenuActionTarget
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
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationRight ? .on : .off
        )
        addAction(
            title: localized("tabContext.forkConversation.left", defaultValue: "Left Split"),
            action: .forkConversationLeft,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationLeft ? .on : .off
        )
        addAction(
            title: localized("tabContext.forkConversation.top", defaultValue: "Top Split"),
            action: .forkConversationTop,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationTop ? .on : .off
        )
        addAction(
            title: localized("tabContext.forkConversation.bottom", defaultValue: "Bottom Split"),
            action: .forkConversationBottom,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationBottom ? .on : .off
        )
        submenu.addItem(.separator())
        addAction(
            title: localized("tabContext.forkConversation.newTab", defaultValue: "New Tab"),
            action: .forkConversationNewTab,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationNewTab ? .on : .off
        )
        addAction(
            title: localized("tabContext.forkConversation.newWorkspace", defaultValue: "New Workspace"),
            action: .forkConversationNewWorkspace,
            state: state,
            target: target,
            to: submenu,
            stateValue: defaultAction == .forkConversationNewWorkspace ? .on : .off
        )

        item.submenu = submenu
        item.isEnabled = true
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
