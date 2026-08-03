import AppKit
import Foundation

@MainActor
public enum BonsplitTabBarHitRegionRegistry {
  private static let registeredViews = NSHashTable<NSView>.weakObjects()

  static func register(_ view: NSView) {
    registeredViews.add(view)
  }

  static func unregister(_ view: NSView) {
    registeredViews.remove(view)
  }

  private static func snapshot() -> [NSView] {
    registeredViews.allObjects
  }

  private static func isVisibleInHierarchy(_ view: NSView) -> Bool {
    var current: NSView? = view
    while let candidate = current {
      guard !candidate.isHidden, candidate.alphaValue > 0 else { return false }
      current = candidate.superview
    }
    return true
  }

  public static func containsWindowPoint(_ windowPoint: CGPoint, in window: NSWindow) -> Bool {
    let epsilon = max(0.5, 1.0 / max(1.0, window.backingScaleFactor))
    for view in snapshot() {
      guard view.window === window, isVisibleInHierarchy(view) else { continue }
      let frameInWindow = view.convert(view.bounds, to: nil).insetBy(dx: -epsilon, dy: -epsilon)
      if frameInWindow.contains(windowPoint) {
        return true
      }
    }
    return false
  }
}

@MainActor
public protocol BonsplitTabItemHitRegionProviding: AnyObject {
  func containsBonsplitTabItemHit(localPoint: NSPoint) -> Bool
}

@MainActor
public enum BonsplitTabItemHitRegionRegistry {
  private static let registeredViews = NSHashTable<NSView>.weakObjects()

  static func register(_ view: NSView) {
    registeredViews.add(view)
  }

  static func unregister(_ view: NSView) {
    registeredViews.remove(view)
  }

  private static func snapshot() -> [NSView] {
    registeredViews.allObjects
  }

  private static func isVisibleInHierarchy(_ view: NSView) -> Bool {
    var current: NSView? = view
    while let candidate = current {
      guard !candidate.isHidden, candidate.alphaValue > 0 else { return false }
      current = candidate.superview
    }
    return true
  }

  public static func containsWindowPoint(_ windowPoint: CGPoint, in window: NSWindow) -> Bool {
    for view in snapshot() {
      guard view.window === window,
        isVisibleInHierarchy(view),
        let provider = view as? BonsplitTabItemHitRegionProviding
      else { continue }
      let localPoint = view.convert(windowPoint, from: nil)
      if provider.containsBonsplitTabItemHit(localPoint: localPoint) {
        return true
      }
    }
    return false
  }
}

enum BonsplitTabItemHitTesting {
  // Hit-test rect is intentionally larger than visual chrome. Do not bump
  // visible tab padding/width to fix drag affordance; see cmux #4290 / #4433.
  static let horizontalSlop: CGFloat = 10
  static let verticalSlop: CGFloat = 6

  static func containsTabLaneHit(
    localPoint: NSPoint,
    tabFrames: [CGRect],
    bounds: NSRect
  ) -> Bool {
    guard bounds.insetBy(dx: 0, dy: -verticalSlop).contains(localPoint) else {
      return false
    }
    return tabFrames.contains { frame in
      localPoint.x >= frame.minX - horizontalSlop
        && localPoint.x <= frame.maxX + horizontalSlop
    }
  }
}

enum TabBarStyling {
  struct SplitActionSystemImage: Equatable {
    let name: String
    let rotationDegrees: Double
    let pointSize: CGFloat
  }

  static let maximumSplitButtonLaneWidthFraction: CGFloat = 0.25
  static let minimumFullyVisibleSplitButtonCount = 5
  static let splitButtonScrollFadeWidth: CGFloat = 12
  static let splitActionButtonReservedWidth: CGFloat = 22
  static let splitButtonsSpacing: CGFloat = 4
  static let splitButtonsLeadingPadding: CGFloat = 6
  static let splitButtonsTrailingPadding: CGFloat = 8

  static var splitButtonsBackdropWidth: CGFloat {
    splitButtonsBackdropWidth(buttonCount: BonsplitConfiguration.SplitActionButton.defaults.count)
  }

  static func splitButtonsBackdropWidth(buttonCount: Int) -> CGFloat {
    guard buttonCount > 0 else { return 0 }
    return splitButtonsLeadingPadding
      + splitButtonsTrailingPadding
      + (CGFloat(buttonCount) * splitActionButtonReservedWidth)
      + (CGFloat(max(0, buttonCount - 1)) * splitButtonsSpacing)
  }

  static func minimumVisibleSplitButtonLaneWidth(buttonCount: Int) -> CGFloat {
    splitButtonsBackdropWidth(
      buttonCount: min(max(0, buttonCount), minimumFullyVisibleSplitButtonCount)
    )
  }

  static func splitActionSystemImage(for name: String) -> SplitActionSystemImage {
    if NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
      return SplitActionSystemImage(name: name, rotationDegrees: 0, pointSize: 12)
    }
    if name == "ellipsis.vertical" {
      return SplitActionSystemImage(name: "ellipsis", rotationDegrees: 90, pointSize: 10.5)
    }
    return SplitActionSystemImage(name: "questionmark.circle", rotationDegrees: 0, pointSize: 12)
  }

  static func splitButtonBackdropSolidSurfaceWidth(
    effectSolidWidth: CGFloat,
    visibleLaneWidth: CGFloat,
    solidSurfaceWidthAdjustment: CGFloat
  ) -> CGFloat {
    let adjustedLaneWidth = max(0, visibleLaneWidth + solidSurfaceWidthAdjustment)
    return max(max(0, effectSolidWidth), adjustedLaneWidth)
  }

  static func splitButtonContentOcclusionWidth(
    visibleLaneWidth: CGFloat,
    contentOcclusionFraction: CGFloat
  ) -> CGFloat {
    max(0, visibleLaneWidth) * min(max(0, contentOcclusionFraction), 1)
  }

  static func splitButtonScrollAffordances(
    scrollOffset: CGFloat,
    contentWidth: CGFloat,
    viewportWidth: CGFloat
  ) -> (left: Bool, right: Bool) {
    let overflowThreshold: CGFloat = 1
    let maxOffset = max(0, contentWidth - viewportWidth)
    return (
      left: scrollOffset > overflowThreshold,
      right: scrollOffset < maxOffset - overflowThreshold
    )
  }

  static func imageDataShouldRenderAsTemplate(_ data: Data) -> Bool {
    let text = String(decoding: data.prefix(4096), as: UTF8.self)
    let lowercased = text.lowercased()
    return lowercased.contains("<svg") && lowercased.contains("currentcolor")
  }

  @MainActor
  static func splitActionButtonImage(from data: Data) -> NSImage? {
    SplitActionButtonImageCache.shared.image(for: data)
  }

  static func selectedTabFrame(
    selectedTabId: UUID?,
    tabFrames: [UUID: CGRect]
  ) -> CGRect? {
    guard let selectedTabId else { return nil }
    return tabFrames[selectedTabId]
  }

  static func separatorSegments(
    totalWidth: CGFloat,
    gap: ClosedRange<CGFloat>?
  ) -> (left: CGFloat, right: CGFloat) {
    let clampedTotal = max(0, totalWidth)
    guard let gap else {
      return (left: clampedTotal, right: 0)
    }

    let start = min(max(gap.lowerBound, 0), clampedTotal)
    let end = min(max(gap.upperBound, 0), clampedTotal)
    let normalizedStart = min(start, end)
    let normalizedEnd = max(start, end)
    let left = max(0, normalizedStart)
    let right = max(0, clampedTotal - normalizedEnd)
    return (left: left, right: right)
  }

  static func trailingTabContentInset(
    showSplitButtons: Bool,
    isMinimalMode: Bool,
    buttonCount: Int = BonsplitConfiguration.SplitActionButton.defaults.count
  ) -> CGFloat {
    guard showSplitButtons, buttonCount > 0 else { return 0 }

    // In minimal mode the split buttons fade in on hover as an overlay. Reserving that
    // width in the scroll content leaves a dead NSClipView strip when the buttons are
    // hidden, so clicks there never reach the tab-bar chrome.
    return isMinimalMode ? 0 : splitButtonsBackdropWidth(buttonCount: buttonCount)
  }

  static func shouldKeepLeadingAligned(
    contentWidth: CGFloat,
    containerWidth: CGFloat
  ) -> Bool {
    let overflowThreshold: CGFloat = 1
    return contentWidth <= containerWidth + overflowThreshold
  }

}

struct TabBarLayout: Equatable {
  let barHeight: CGFloat
  let availableWidth: CGFloat
  let tabContentWidthExcludingSplitButtonLane: CGFloat?
  let splitButtonCount: Int
  let splitButtonLaneVisible: Bool
  let reservesSplitButtonLane: Bool
  let measuredSplitButtonLaneWidth: CGFloat

  init(
    tabBarHeight: CGFloat,
    availableWidth: CGFloat = 0,
    tabContentWidthExcludingSplitButtonLane: CGFloat? = nil,
    splitButtonCount: Int,
    splitButtonLaneVisible: Bool,
    reservesSplitButtonLane: Bool,
    measuredSplitButtonLaneWidth: CGFloat = 0
  ) {
    self.barHeight = max(1, tabBarHeight)
    self.availableWidth = max(0, availableWidth)
    self.tabContentWidthExcludingSplitButtonLane = tabContentWidthExcludingSplitButtonLane.map {
      max(0, $0)
    }
    self.splitButtonCount = max(0, splitButtonCount)
    self.splitButtonLaneVisible = splitButtonLaneVisible
    self.reservesSplitButtonLane = reservesSplitButtonLane
    self.measuredSplitButtonLaneWidth =
      self.splitButtonCount > 0
      ? max(0, measuredSplitButtonLaneWidth)
      : 0
  }

  var minimumSplitButtonLaneWidth: CGFloat {
    TabBarStyling.splitButtonsBackdropWidth(buttonCount: splitButtonCount)
  }

  var fullSplitButtonLaneWidth: CGFloat {
    max(minimumSplitButtonLaneWidth, measuredSplitButtonLaneWidth)
  }

  var maximumSplitButtonLaneWidth: CGFloat {
    guard availableWidth > 0 else { return 0 }
    let fractionLimit = availableWidth * TabBarStyling.maximumSplitButtonLaneWidthFraction
    return max(
      fractionLimit,
      trailingWhitespaceBeforeSplitButtonLane,
      TabBarStyling.minimumVisibleSplitButtonLaneWidth(buttonCount: splitButtonCount)
    )
  }

  var trailingWhitespaceBeforeSplitButtonLane: CGFloat {
    guard availableWidth > 0,
      let tabContentWidthExcludingSplitButtonLane,
      tabContentWidthExcludingSplitButtonLane > 0
    else {
      return 0
    }
    return max(0, availableWidth - tabContentWidthExcludingSplitButtonLane)
  }

  var visibleSplitButtonLaneWidth: CGFloat {
    min(fullSplitButtonLaneWidth, maximumSplitButtonLaneWidth)
  }

  var splitButtonLaneOverflowsViewport: Bool {
    fullSplitButtonLaneWidth > visibleSplitButtonLaneWidth + 1
  }

  var trailingTabContentInset: CGFloat {
    reservesSplitButtonLane ? visibleSplitButtonLaneWidth : 0
  }

  var splitActionButtonHeight: CGFloat {
    barHeight
  }

  func selectedSeparatorGap(
    selectedTabFrame: CGRect?,
    totalWidth: CGFloat
  ) -> ClosedRange<CGFloat>? {
    guard let selectedTabFrame, totalWidth > 0 else { return nil }

    let minX = min(max(selectedTabFrame.minX, 0), totalWidth)
    let maxX = min(max(selectedTabFrame.maxX, 0), totalWidth)
    guard maxX > minX else { return nil }
    return minX...maxX
  }

  func selectedIndicatorFrame(
    selectedTabFrame: CGRect?,
    totalWidth: CGFloat
  ) -> CGRect? {
    guard
      let gap = selectedSeparatorGap(
        selectedTabFrame: selectedTabFrame,
        totalWidth: totalWidth
      )
    else { return nil }

    let minX = gap.lowerBound
    let maxX = gap.upperBound
    let width = max(0, maxX - minX - TabBarMetrics.activeIndicatorTrailingInset)
    guard width > 0 else { return nil }

    return CGRect(
      x: minX,
      y: 0,
      width: width,
      height: TabBarMetrics.activeIndicatorHeight
    )
  }
}

struct TabBarActionLaneGeometry: Equatable {
  let buttonViewportWidth: CGFloat
  let contentFadeWidth: CGFloat
  let contentOcclusionWidth: CGFloat
  let backgroundFadeWidth: CGFloat
  let backgroundSolidWidth: CGFloat
  let separatorFadeWidth: CGFloat
  let backgroundFadeRampStartFraction: CGFloat

  init(
    layout: TabBarLayout,
    effect: BonsplitConfiguration.Appearance.SplitButtonBackdropEffect,
    masksTabContent: Bool
  ) {
    self.buttonViewportWidth = layout.visibleSplitButtonLaneWidth
    self.contentFadeWidth = masksTabContent ? effect.contentFadeWidth : 0
    if masksTabContent {
      let fractionalOcclusionWidth = TabBarStyling.splitButtonContentOcclusionWidth(
        visibleLaneWidth: layout.visibleSplitButtonLaneWidth,
        contentOcclusionFraction: effect.contentOcclusionFraction
      )
      self.contentOcclusionWidth =
        layout.splitButtonLaneOverflowsViewport
        ? layout.visibleSplitButtonLaneWidth
        : fractionalOcclusionWidth
    } else {
      self.contentOcclusionWidth = 0
    }
    self.backgroundFadeWidth = max(0, effect.fadeWidth)
    let solidSurfaceWidthAdjustment =
      layout.splitButtonLaneOverflowsViewport
      ? max(0, effect.solidSurfaceWidthAdjustment)
      : effect.solidSurfaceWidthAdjustment
    self.backgroundSolidWidth = TabBarStyling.splitButtonBackdropSolidSurfaceWidth(
      effectSolidWidth: effect.solidWidth,
      visibleLaneWidth: layout.visibleSplitButtonLaneWidth,
      solidSurfaceWidthAdjustment: solidSurfaceWidthAdjustment
    )
    let rampStart = min(max(0, effect.fadeRampStartFraction), 0.95)
    self.backgroundFadeRampStartFraction = rampStart
    let defaultSeparatorFadeWidth = self.backgroundFadeWidth
    self.separatorFadeWidth = min(
      defaultSeparatorFadeWidth,
      effect.separatorFadeWidth ?? defaultSeparatorFadeWidth
    )
  }

  var separatorTotalWidth: CGFloat {
    separatorFadeWidth + backgroundSolidWidth
  }

  func backgroundFadeFrame(totalWidth: CGFloat, height: CGFloat) -> CGRect {
    let width = max(0, backgroundFadeWidth)
    return CGRect(
      x: totalWidth - backgroundSolidWidth - width,
      y: 0,
      width: width,
      height: height
    )
  }

  func backgroundSolidFrame(totalWidth: CGFloat, height: CGFloat) -> CGRect {
    let width = max(0, backgroundSolidWidth)
    return CGRect(
      x: totalWidth - width,
      y: 0,
      width: width,
      height: height
    )
  }

  func separatorFadeFrame(totalWidth: CGFloat, height: CGFloat) -> CGRect {
    let width = max(0, separatorFadeWidth)
    return CGRect(
      x: totalWidth - backgroundSolidWidth - width,
      y: height - 1,
      width: width,
      height: 1
    )
  }

  func separatorSolidFrame(totalWidth: CGFloat, height: CGFloat) -> CGRect {
    let solid = backgroundSolidFrame(totalWidth: totalWidth, height: height)
    return CGRect(x: solid.minX, y: height - 1, width: solid.width, height: 1)
  }

  func separatorCoverageFrame(totalWidth: CGFloat, height: CGFloat) -> CGRect {
    let width = separatorTotalWidth
    return CGRect(x: totalWidth - width, y: height - 1, width: width, height: 1)
  }

  func fallbackSeparatorMaskFrame(
    totalWidth: CGFloat,
    height: CGFloat,
    selectedSeparatorGap: ClosedRange<CGFloat>?
  ) -> CGRect? {
    guard let selectedSeparatorGap else { return nil }
    let coverage = separatorCoverageFrame(totalWidth: totalWidth, height: height)
    let start = max(coverage.minX, selectedSeparatorGap.lowerBound)
    let end = min(coverage.maxX, selectedSeparatorGap.upperBound)
    guard end > start else { return nil }
    return CGRect(x: start, y: height - 1, width: end - start, height: 1)
  }
}

struct TabBarChromeSnapshot {
  let layout: TabBarLayout
  let actionLaneGeometry: TabBarActionLaneGeometry
  let barColor: NSColor
  let actionLaneWidth: CGFloat
  let paintsActionLaneSurface: Bool
  let masksTabContentUnderActionLane: Bool
  let contentFadeWidth: CGFloat
  let contentOcclusionWidth: CGFloat
  let actionLaneSeparatorFadeWidth: CGFloat
  let backdropFadeWidth: CGFloat
  let backdropSolidWidth: CGFloat
  let backdropFadeRampStartFraction: CGFloat
  let backdropLeadingColor: NSColor
  let backdropTrailingColor: NSColor

  var drawsActionLaneSeparator: Bool {
    paintsActionLaneSurface || masksTabContentUnderActionLane
  }

  var backdropVisibleFadeWidth: CGFloat {
    backdropFadeWidth * (1 - backdropFadeRampStartFraction)
  }

  var actionLaneSeparatorSolidWidth: CGFloat {
    actionLaneGeometry.backgroundSolidWidth
  }

  init(
    appearance: BonsplitConfiguration.Appearance,
    layout: TabBarLayout,
    isFocused: Bool,
    shouldShowSplitButtons: Bool,
    fadeColorStyle: Int
  ) {
    self.layout = layout

    let baseBarColor = TabBarColors.nsColorBarBackground(for: appearance)
    self.barColor =
      appearance.usesSharedBackdrop || isFocused
      ? baseBarColor
      : baseBarColor.withAlphaComponent(baseBarColor.alphaComponent * 0.95)

    let effect = Self.splitButtonBackdropEffect(
      for: appearance,
      fadeColorStyle: fadeColorStyle
    )
    let targetColor = Self.buttonBackdropColor(
      for: appearance,
      focused: isFocused,
      style: effect.style
    )
    let colors = Self.splitButtonBackdropColors(
      from: barColor,
      to: targetColor,
      leadingOpacity: effect.leadingOpacity,
      trailingOpacity: effect.trailingOpacity,
      usesSharedBackdrop: appearance.usesSharedBackdrop
    )

    let canUseActionLaneChrome = shouldShowSplitButtons && effect.style != .hidden
    self.paintsActionLaneSurface =
      canUseActionLaneChrome
      && TabBarColors.shouldPaintSplitButtonBackdrop(for: appearance)
    self.masksTabContentUnderActionLane = canUseActionLaneChrome && effect.masksTabContent
    let geometry = TabBarActionLaneGeometry(
      layout: layout,
      effect: effect,
      masksTabContent: masksTabContentUnderActionLane
    )
    self.actionLaneGeometry = geometry
    self.actionLaneWidth = geometry.buttonViewportWidth
    self.contentFadeWidth = geometry.contentFadeWidth
    self.contentOcclusionWidth = geometry.contentOcclusionWidth
    self.backdropFadeWidth = geometry.backgroundFadeWidth
    self.backdropSolidWidth = geometry.backgroundSolidWidth
    self.backdropFadeRampStartFraction = min(max(0, effect.fadeRampStartFraction), 0.95)
    self.actionLaneSeparatorFadeWidth = geometry.separatorFadeWidth
    self.backdropLeadingColor = colors.leading
    self.backdropTrailingColor = colors.trailing
  }

  private static func splitButtonBackdropEffect(
    for appearance: BonsplitConfiguration.Appearance,
    fadeColorStyle: Int
  ) -> BonsplitConfiguration.Appearance.SplitButtonBackdropEffect {
    if let effect = appearance.splitButtonBackdropEffect {
      return effect
    }
    if let style = appearance.splitButtonBackdropStyle {
      return .init(style: style)
    }
    if let debugStyle = BonsplitConfiguration.Appearance.SplitButtonBackdropStyle(
      rawValue: fadeColorStyle)
    {
      return .init(
        style: debugStyle,
        fadeWidth: 136,
        solidWidth: 2,
        fadeRampStartFraction: 0.80,
        leadingOpacity: 0,
        trailingOpacity: 0.80,
        masksTabContent: false
      )
    }
    return .default
  }

  private static func buttonBackdropColor(
    for appearance: BonsplitConfiguration.Appearance,
    focused: Bool,
    style: BonsplitConfiguration.Appearance.SplitButtonBackdropStyle
  ) -> NSColor {
    if appearance.usesSharedBackdrop {
      return TabBarColors.nsColorSplitButtonBackdropOccludingSurface(for: appearance)
    }

    switch style {
    case .opaquePaneBackground:
      return TabBarColors.nsColorPaneBackground(for: appearance).withAlphaComponent(1.0)
    case .opaqueBarBackground:
      return TabBarColors.nsColorBarBackground(for: appearance).withAlphaComponent(1.0)
    case .windowBackground:
      return NSColor.windowBackgroundColor.withAlphaComponent(1.0)
    case .controlBackground:
      return NSColor.controlBackgroundColor.withAlphaComponent(1.0)
    case .precompositedBarBackground:
      let chrome = TabBarColors.nsColorBarBackground(for: appearance)
      let winBg = NSColor.windowBackgroundColor
      guard let fg = chrome.usingColorSpace(.sRGB),
        let bk = winBg.usingColorSpace(.sRGB)
      else {
        return chrome.withAlphaComponent(1.0)
      }
      let a: CGFloat = focused ? fg.alphaComponent : fg.alphaComponent * 0.95
      let oneMinusA = 1.0 - a
      let r = fg.redComponent * a + bk.redComponent * oneMinusA
      let g = fg.greenComponent * a + bk.greenComponent * oneMinusA
      let b = fg.blueComponent * a + bk.blueComponent * oneMinusA
      return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    case .translucentChrome:
      let backdrop = TabBarColors.nsColorSplitButtonBackdropSurface(for: appearance)
      let alpha = focused ? backdrop.alphaComponent : backdrop.alphaComponent * 0.95
      return backdrop.withAlphaComponent(alpha)
    case .hidden:
      return .clear
    case .precompositedPaneBackground:
      return TabBarColors.nsColorSplitButtonBackdrop(for: appearance, focused: focused)
    }
  }

  private static func blendedSurfaceColor(
    from base: NSColor,
    to target: NSColor,
    amount: CGFloat
  ) -> NSColor {
    let clampedAmount = min(max(amount, 0), 1)
    let source = base.usingColorSpace(.sRGB) ?? base
    let destination = target.usingColorSpace(.sRGB) ?? target
    let inverse = 1 - clampedAmount
    return NSColor(
      red: source.redComponent * inverse + destination.redComponent * clampedAmount,
      green: source.greenComponent * inverse + destination.greenComponent * clampedAmount,
      blue: source.blueComponent * inverse + destination.blueComponent * clampedAmount,
      alpha: source.alphaComponent * inverse + destination.alphaComponent * clampedAmount
    )
  }

  private static func splitButtonBackdropColors(
    from base: NSColor,
    to target: NSColor,
    leadingOpacity: CGFloat,
    trailingOpacity: CGFloat,
    usesSharedBackdrop: Bool
  ) -> (leading: NSColor, trailing: NSColor) {
    if usesSharedBackdrop {
      return (
        alphaOnlySurfaceColor(target, opacity: leadingOpacity),
        alphaOnlySurfaceColor(target, opacity: trailingOpacity)
      )
    }

    return (
      blendedSurfaceColor(from: base, to: target, amount: leadingOpacity),
      blendedSurfaceColor(from: base, to: target, amount: trailingOpacity)
    )
  }

  private static func alphaOnlySurfaceColor(
    _ color: NSColor,
    opacity: CGFloat
  ) -> NSColor {
    let clampedOpacity = min(max(opacity, 0), 1)
    guard let source = color.usingColorSpace(.sRGB) else {
      return color.withAlphaComponent(color.alphaComponent * clampedOpacity)
    }
    return NSColor(
      red: source.redComponent,
      green: source.greenComponent,
      blue: source.blueComponent,
      alpha: source.alphaComponent * clampedOpacity
    )
  }
}

struct TabContextMenuState {
  let isPinned: Bool
  let isUnread: Bool
  let isBrowser: Bool
  let isAudioMuted: Bool
  let isTerminal: Bool
  let hasCustomTitle: Bool
  let canCloseToLeft: Bool
  let canCloseToRight: Bool
  let canCloseOthers: Bool
  let canMoveToNewWorkspace: Bool
  let canMoveToLeftPane: Bool
  let canMoveToRightPane: Bool
  let forkConversationDefaultAction: TabContextAction
  let isZoomed: Bool
  let isFullWidthTabMode: Bool
  let hasSplits: Bool
  let shortcuts: [TabContextAction: BonsplitKeyboardShortcut]
  var canDisconnectRemote: Bool = false

  var canMarkAsUnread: Bool {
    !isUnread
  }

  var canMarkAsRead: Bool {
    isUnread
  }

  init(
    isPinned: Bool,
    isUnread: Bool,
    isBrowser: Bool,
    isAudioMuted: Bool,
    isTerminal: Bool,
    hasCustomTitle: Bool,
    canCloseToLeft: Bool,
    canCloseToRight: Bool,
    canCloseOthers: Bool,
    canMoveToNewWorkspace: Bool,
    canMoveToLeftPane: Bool,
    canMoveToRightPane: Bool,
    forkConversationDefaultAction: TabContextAction,
    isZoomed: Bool,
    isFullWidthTabMode: Bool = false,
    hasSplits: Bool,
    shortcuts: [TabContextAction: BonsplitKeyboardShortcut],
    canDisconnectRemote: Bool = false
  ) {
    self.isPinned = isPinned
    self.isUnread = isUnread
    self.isBrowser = isBrowser
    self.isAudioMuted = isAudioMuted
    self.isTerminal = isTerminal
    self.hasCustomTitle = hasCustomTitle
    self.canCloseToLeft = canCloseToLeft
    self.canCloseToRight = canCloseToRight
    self.canCloseOthers = canCloseOthers
    self.canMoveToNewWorkspace = canMoveToNewWorkspace
    self.canMoveToLeftPane = canMoveToLeftPane
    self.canMoveToRightPane = canMoveToRightPane
    self.forkConversationDefaultAction = forkConversationDefaultAction
    self.isZoomed = isZoomed
    self.isFullWidthTabMode = isFullWidthTabMode
    self.hasSplits = hasSplits
    self.shortcuts = shortcuts
    self.canDisconnectRemote = canDisconnectRemote
  }

  @MainActor
  init(
    tab: TabItem,
    index: Int,
    pane: PaneState,
    controller: BonsplitController,
    splitViewController: SplitViewController
  ) {
    let allowsCloseTabs = controller.configuration.allowCloseTabs
    let leftTabs = pane.tabs.prefix(index)
    let canCloseToLeft = allowsCloseTabs && leftTabs.contains(where: { !$0.isPinned })
    let canCloseToRight: Bool
    if (index + 1) < pane.tabs.count {
      canCloseToRight =
        allowsCloseTabs && pane.tabs.suffix(from: index + 1).contains(where: { !$0.isPinned })
    } else {
      canCloseToRight = false
    }
    let canCloseOthers =
      allowsCloseTabs
      && pane.tabs.enumerated().contains { itemIndex, item in
        itemIndex != index && !item.isPinned
      }
    self.init(
      isPinned: tab.isPinned,
      isUnread: tab.showsNotificationBadge,
      isBrowser: tab.kind == "browser",
      isAudioMuted: tab.isAudioMuted,
      isTerminal: tab.kind == "terminal",
      hasCustomTitle: tab.hasCustomTitle,
      canCloseToLeft: canCloseToLeft,
      canCloseToRight: canCloseToRight,
      canCloseOthers: canCloseOthers,
      canMoveToNewWorkspace: controller.allTabIds.count > 1,
      canMoveToLeftPane: controller.adjacentPane(to: pane.id, direction: .left) != nil,
      canMoveToRightPane: controller.adjacentPane(to: pane.id, direction: .right) != nil,
      forkConversationDefaultAction: controller.tabContextForkConversationDefaultActionProvider?(
        TabID(id: tab.id), pane.id) ?? .defaultForkConversationDestination,
      isZoomed: splitViewController.zoomedPaneId == pane.id,
      isFullWidthTabMode: pane.isFullWidthTabMode,
      hasSplits: splitViewController.rootNode.allPaneIds.count > 1,
      shortcuts: controller.contextMenuShortcuts,
      canDisconnectRemote: controller.tabContextDisconnectRemoteAvailabilityProvider?(
        TabID(id: tab.id), pane.id) ?? false
    )
  }
}

/// Tab bar view with scrollable tabs, drag/drop support, and split buttons

@MainActor
private final class SplitActionButtonImageCache {
  static let shared = SplitActionButtonImageCache()

  private let images = NSCache<NSData, NSImage>()
  private let invalidImageData = NSCache<NSData, NSNumber>()

  private init() {
    images.countLimit = 128
    images.totalCostLimit = 8 * 1024 * 1024
    invalidImageData.countLimit = 256
    invalidImageData.totalCostLimit = 512 * 1024
  }

  func image(for data: Data) -> NSImage? {
    let key = data as NSData
    if let image = images.object(forKey: key) {
      return image
    }
    if invalidImageData.object(forKey: key) != nil {
      return nil
    }

    guard let image = NSImage(data: data) else {
      invalidImageData.setObject(
        NSNumber(value: true),
        forKey: key,
        cost: max(1, min(data.count, 1024))
      )
      return nil
    }
    image.isTemplate = TabBarStyling.imageDataShouldRenderAsTemplate(data)

    images.setObject(image, forKey: key, cost: max(1, data.count))
    return image
  }
}

enum TabBarDragZoneView {
  enum HitRegion {
    case entireBounds
    case trailingEmptyChrome(tabFrames: [CGRect], reservedTrailingWidth: CGFloat)
    case registeredTrailingEmptyChrome(
      geometryRegistry: TabBarItemGeometryRegistry,
      tabIds: [UUID],
      reservedTrailingWidth: CGFloat
    )
  }
  final class DragNSView: NSView, TabBarItemGeometryObserving {
    var hitRegion = HitRegion.entireBounds {
      didSet {
        unregisterGeometryObserver(from: oldValue)
        registerGeometryObserver(from: hitRegion)
        invalidateWindowDragCursorRects()
      }
    }
    var hitTestEventTypeOverride: NSEvent.EventType?
    var isMinimalMode = false {
      didSet { invalidateWindowDragCursorRects() }
    }
    var isFocusedPane = false
    var onSingleClick: (() -> Bool)?
    var onDoubleClick: (() -> Bool)?
    var performWindowDrag: ((NSEvent) -> Bool)?
    private var pendingWindowDragEvent: NSEvent?
    private var pendingWindowDragStart: NSPoint?

    private static let windowDragStartDistanceSquared: CGFloat = 16

    isolated deinit {
      unregisterGeometryObserver(from: hitRegion)
    }

    // Must stay false so AppKit does not intercept mouseUp as part of its
    // own window-drag tracking. When AppKit steals mouseUp from the first
    // click, the second click of a double-click is registered as a fresh
    // clickCount=1 instead of 2, making new-tab double-clicks flaky. We
    // still support window dragging via the custom mouseDragged →
    // window.performDrag flow below. See `NonDraggableHostingView` in
    // The pane renderer uses the same exclusion rule for tab clicks.
    override var mouseDownCanMoveWindow: Bool { false }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      invalidateWindowDragCursorRects()
    }

    override func layout() {
      super.layout()
      invalidateWindowDragCursorRects()
    }

    func tabBarItemGeometryDidChange() {
      invalidateWindowDragCursorRects()
    }

    override func resetCursorRects() {
      super.resetCursorRects()
      for rect in windowDragCursorRectsForCurrentState() {
        addCursorRect(rect, cursor: .openHand)
      }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
      guard shouldCaptureHit(at: point) else { return nil }
      return self
    }

    override func mouseDown(with event: NSEvent) {
      #if DEBUG
        let point = convert(event.locationInWindow, from: nil)
        dlog(
          "tab.bar.dragZone.mouseDown isMinimal=\(isMinimalMode ? 1 : 0) "
            + "focused=\(isFocusedPane ? 1 : 0) clickCount=\(event.clickCount) "
            + "point=\(point.x.rounded()),\(point.y.rounded()) "
            + "bounds=\(bounds.width.rounded())x\(bounds.height.rounded())"
        )
      #endif
      guard let window = self.window else {
        super.mouseDown(with: event)
        return
      }

      if !isMinimalMode {
        clearPendingWindowDrag()
        if event.clickCount == 1 {
          if !isFocusedPane, onSingleClick?() == true {
            #if DEBUG
              dlog("tab.bar.dragZone.focusPane")
            #endif
          } else {
            #if DEBUG
              dlog(
                "tab.bar.dragZone.click skipped reason=standardSingleClick clickCount=\(event.clickCount)"
              )
            #endif
          }
          return
        }
        if event.clickCount >= 2 {
          if onDoubleClick?() == true {
            #if DEBUG
              dlog("tab.bar.dragZone.doubleClick action=newTab")
            #endif
            return
          }
        }
        #if DEBUG
          dlog(
            "tab.bar.dragZone.click skipped reason=standardUnhandledClick clickCount=\(event.clickCount)"
          )
        #endif
        return
      }

      if event.clickCount >= 2 {
        clearPendingWindowDrag()
        #if DEBUG
          dlog("tab.bar.dragZone.doubleClick action=titlebar")
        #endif
        performTitlebarDoubleClickAction(in: window)
        return
      }

      if !isFocusedPane, onSingleClick?() == true {
        clearPendingWindowDrag()
        #if DEBUG
          dlog("tab.bar.dragZone.focusPane")
        #endif
        return
      }

      pendingWindowDragEvent = event
      pendingWindowDragStart = event.locationInWindow
    }

    private func shouldCaptureHit(at point: NSPoint) -> Bool {
      guard bounds.contains(point) else { return false }
      if let window,
        BonsplitTabItemHitRegionRegistry.containsWindowPoint(convert(point, to: nil), in: window)
      {
        #if DEBUG
          dlog(
            "tab.bar.dragZone.hitTest capture=false reason=registeredTabItem "
              + "point=\(point.x.rounded()),\(point.y.rounded())"
          )
        #endif
        return false
      }
      switch hitRegion {
      case .entireBounds:
        return true
      case .trailingEmptyChrome(let tabFrames, let reservedTrailingWidth):
        guard isMouseDownOrDragCandidate else { return false }
        return shouldCaptureTrailingEmptyChrome(
          at: point,
          tabFrames: tabFrames,
          reservedTrailingWidth: reservedTrailingWidth
        )
      case .registeredTrailingEmptyChrome(
        let geometryRegistry, let tabIds, let reservedTrailingWidth):
        guard isMouseDownOrDragCandidate else { return false }
        return shouldCaptureTrailingEmptyChrome(
          at: point,
          tabFrames: geometryRegistry.frames(for: tabIds, in: self).values.map { $0 },
          reservedTrailingWidth: reservedTrailingWidth
        )
      }
    }

    private func shouldCaptureTrailingEmptyChrome(
      at point: NSPoint,
      tabFrames: [CGRect],
      reservedTrailingWidth: CGFloat
    ) -> Bool {
      let trailingLimit = bounds.maxX - max(0, reservedTrailingWidth)
      guard point.x < trailingLimit else { return false }
      let paddedFrames = tabFrames.map {
        $0.insetBy(dx: -BonsplitTabItemHitTesting.horizontalSlop, dy: -2)
      }
      guard !paddedFrames.contains(where: { $0.contains(point) }) else { return false }
      let startX = paddedFrames.map(\.maxX).max() ?? bounds.minX
      return point.x >= startX
    }

    func windowDragCursorRectsForCurrentState() -> [NSRect] {
      guard isMinimalMode, !bounds.isEmpty else { return [] }

      switch hitRegion {
      case .entireBounds:
        return [bounds]
      case .trailingEmptyChrome(let tabFrames, let reservedTrailingWidth):
        return trailingEmptyChromeCursorRects(
          tabFrames: tabFrames,
          reservedTrailingWidth: reservedTrailingWidth
        )
      case .registeredTrailingEmptyChrome(
        let geometryRegistry, let tabIds, let reservedTrailingWidth):
        return trailingEmptyChromeCursorRects(
          tabFrames: geometryRegistry.frames(for: tabIds, in: self).values.map { $0 },
          reservedTrailingWidth: reservedTrailingWidth
        )
      }
    }

    private func trailingEmptyChromeCursorRects(
      tabFrames: [CGRect],
      reservedTrailingWidth: CGFloat
    ) -> [NSRect] {
      let trailingLimit = bounds.maxX - max(0, reservedTrailingWidth)
      guard trailingLimit > bounds.minX else { return [] }

      let paddedFrames = tabFrames.map {
        $0.insetBy(dx: -BonsplitTabItemHitTesting.horizontalSlop, dy: -2)
      }
      let startX = max(bounds.minX, paddedFrames.map(\.maxX).max() ?? bounds.minX)
      guard trailingLimit > startX else { return [] }

      return [
        NSRect(
          x: startX,
          y: bounds.minY,
          width: trailingLimit - startX,
          height: bounds.height
        )
      ]
    }

    private func invalidateWindowDragCursorRects() {
      guard let window else { return }
      window.invalidateCursorRects(for: self)
    }

    private func registerGeometryObserver(from hitRegion: HitRegion) {
      guard case .registeredTrailingEmptyChrome(let registry, _, _) = hitRegion else { return }
      registry.registerObserver(self)
    }

    private func unregisterGeometryObserver(from hitRegion: HitRegion) {
      guard case .registeredTrailingEmptyChrome(let registry, _, _) = hitRegion else { return }
      registry.unregisterObserver(self)
    }

    private var isMouseDownOrDragCandidate: Bool {
      switch hitTestEventTypeOverride ?? NSApp.currentEvent?.type {
      case .leftMouseDown, .leftMouseDragged, .leftMouseUp:
        return true
      default:
        return false
      }
    }

    override func mouseDragged(with event: NSEvent) {
      guard isMinimalMode,
        let window,
        let pendingEvent = pendingWindowDragEvent,
        let start = pendingWindowDragStart
      else {
        super.mouseDragged(with: event)
        return
      }

      let dx = event.locationInWindow.x - start.x
      let dy = event.locationInWindow.y - start.y
      guard dx * dx + dy * dy >= Self.windowDragStartDistanceSquared else {
        return
      }

      #if DEBUG
        dlog(
          "tab.bar.dragZone.dragStart " + "dx=\(dx.rounded()) dy=\(dy.rounded())"
        )
      #endif
      clearPendingWindowDrag()
      startWindowDrag(with: pendingEvent, in: window)
    }

    override func mouseUp(with event: NSEvent) {
      clearPendingWindowDrag()
      super.mouseUp(with: event)
    }

    private func clearPendingWindowDrag() {
      pendingWindowDragEvent = nil
      pendingWindowDragStart = nil
    }

    private func startWindowDrag(with event: NSEvent, in window: NSWindow) {
      if let performWindowDrag, performWindowDrag(event) {
        #if DEBUG
          dlog("tab.bar.dragZone.dragStart action=testHook")
        #endif
        return
      }
      let wasMovable = window.isMovable
      window.isMovable = true
      defer { window.isMovable = wasMovable }
      window.performDrag(with: event)
      #if DEBUG
        dlog("tab.bar.dragZone.dragStart action=windowPerformDrag")
      #endif
    }

    private func performTitlebarDoubleClickAction(in window: NSWindow) {
      let action =
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?[
          "AppleActionOnDoubleClick"] as? String
      switch action {
      case "Minimize": window.miniaturize(nil)
      default: window.zoom(nil)
      }
    }
  }
}

private struct TabControlShortcutStoredShortcut: Decodable {
  let key: String
  let command: Bool
  let shift: Bool
  let option: Bool
  let control: Bool

  init(
    key: String,
    command: Bool,
    shift: Bool,
    option: Bool,
    control: Bool
  ) {
    self.key = key
    self.command = command
    self.shift = shift
    self.option = option
    self.control = control
  }

  var modifierFlags: NSEvent.ModifierFlags {
    var flags: NSEvent.ModifierFlags = []
    if command { flags.insert(.command) }
    if shift { flags.insert(.shift) }
    if option { flags.insert(.option) }
    if control { flags.insert(.control) }
    return flags
  }

  var modifierSymbol: String {
    var parts: [String] = []
    if control { parts.append("⌃") }
    if option { parts.append("⌥") }
    if shift { parts.append("⇧") }
    if command { parts.append("⌘") }
    return parts.joined()
  }
}

private enum TabControlShortcutSettings {
  static let surfaceByNumberKey = "shortcut.selectSurfaceByNumber"
  static let defaultShortcut = TabControlShortcutStoredShortcut(
    key: "1",
    command: false,
    shift: false,
    option: false,
    control: true
  )

  static func surfaceByNumberShortcut(defaults: UserDefaults = .standard)
    -> TabControlShortcutStoredShortcut
  {
    guard let data = defaults.data(forKey: surfaceByNumberKey),
      let shortcut = try? JSONDecoder().decode(TabControlShortcutStoredShortcut.self, from: data)
    else {
      return defaultShortcut
    }
    return shortcut
  }
}

struct TabControlShortcutModifier: Equatable {
  let modifierFlags: NSEvent.ModifierFlags
  let symbol: String
}

enum TabControlShortcutHintPolicy {
  static let intentionalHoldDelay: TimeInterval = 0.30
  static let showHintsOnCommandHoldKey = "shortcutHintShowOnCommandHold"
  static let showHintsOnControlHoldKey = "shortcutHintShowOnControlHold"
  static let defaultShowHintsOnCommandHold = true
  static let defaultShowHintsOnControlHold = true

  static func showHintsOnCommandHoldEnabled(defaults: UserDefaults = .standard) -> Bool {
    guard defaults.object(forKey: showHintsOnCommandHoldKey) != nil else {
      return defaultShowHintsOnCommandHold
    }
    return defaults.bool(forKey: showHintsOnCommandHoldKey)
  }

  static func showHintsOnControlHoldEnabled(defaults: UserDefaults = .standard) -> Bool {
    guard defaults.object(forKey: showHintsOnControlHoldKey) != nil else {
      return defaultShowHintsOnControlHold
    }
    return defaults.bool(forKey: showHintsOnControlHoldKey)
  }

  static func configuredShortcutModifierSymbol(defaults: UserDefaults = .standard) -> String {
    TabControlShortcutSettings.surfaceByNumberShortcut(defaults: defaults).modifierSymbol
  }

  private static func triggerAllowsHintReveal(
    for modifierFlags: NSEvent.ModifierFlags,
    defaults: UserDefaults = .standard
  ) -> Bool {
    let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
      .subtracting([.numericPad, .function, .capsLock])
    switch flags {
    case [.command]:
      return showHintsOnCommandHoldEnabled(defaults: defaults)
    case [.control]:
      return showHintsOnControlHoldEnabled(defaults: defaults)
    default:
      return false
    }
  }

  static func hintModifier(
    for modifierFlags: NSEvent.ModifierFlags,
    defaults: UserDefaults = .standard
  ) -> TabControlShortcutModifier? {
    guard triggerAllowsHintReveal(for: modifierFlags, defaults: defaults) else { return nil }
    let shortcut = TabControlShortcutSettings.surfaceByNumberShortcut(defaults: defaults)
    return TabControlShortcutModifier(
      modifierFlags: shortcut.modifierFlags,
      symbol: shortcut.modifierSymbol
    )
  }

  static func isCurrentWindow(
    hostWindowNumber: Int?,
    hostWindowIsKey: Bool,
    eventWindowNumber: Int?,
    keyWindowNumber: Int?
  ) -> Bool {
    guard let hostWindowNumber, hostWindowIsKey else { return false }
    if let eventWindowNumber {
      return eventWindowNumber == hostWindowNumber
    }
    return keyWindowNumber == hostWindowNumber
  }

  static func shouldShowHints(
    for modifierFlags: NSEvent.ModifierFlags,
    hostWindowNumber: Int?,
    hostWindowIsKey: Bool,
    eventWindowNumber: Int?,
    keyWindowNumber: Int?,
    defaults: UserDefaults = .standard
  ) -> Bool {
    triggerAllowsHintReveal(for: modifierFlags, defaults: defaults)
      && isCurrentWindow(
        hostWindowNumber: hostWindowNumber,
        hostWindowIsKey: hostWindowIsKey,
        eventWindowNumber: eventWindowNumber,
        keyWindowNumber: keyWindowNumber
      )
  }
}

/// Tracks an intentional modifier-key hold for the native tab shortcut hints.
/// AppKit owns the event monitors, while all mutable state stays on the main actor.
@MainActor
final class TabControlShortcutKeyMonitor {
  typealias Sleep = @Sendable (Duration) async throws -> Void

  private(set) var isShortcutHintVisible = false
  private(set) var shortcutModifierSymbol =
    TabControlShortcutHintPolicy.configuredShortcutModifierSymbol()
  var onChange: (() -> Void)?

  private weak var hostWindow: NSWindow?
  private var hostWindowDidBecomeKeyObserver: NSObjectProtocol?
  private var hostWindowDidResignKeyObserver: NSObjectProtocol?
  private var flagsMonitor: Any?
  private var keyDownMonitor: Any?
  private var resignObserver: NSObjectProtocol?
  private var pendingShowTask: Task<Void, Never>?
  private var pendingModifier: TabControlShortcutModifier?
  private let sleep: Sleep

  init(
    sleep: @escaping Sleep = { duration in
      try await ContinuousClock().sleep(for: duration)
    }
  ) {
    self.sleep = sleep
  }

  isolated deinit {
    stop()
  }

  func setHostWindow(_ window: NSWindow?) {
    guard hostWindow !== window else { return }
    removeHostWindowObservers()
    hostWindow = window
    guard let window else {
      cancelPendingHintShow(resetVisible: true)
      return
    }

    hostWindowDidBecomeKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didBecomeKeyNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.update(from: NSEvent.modifierFlags, eventWindow: nil)
      }
    }
    hostWindowDidResignKeyObserver = NotificationCenter.default.addObserver(
      forName: NSWindow.didResignKeyNotification,
      object: window,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.cancelPendingHintShow(resetVisible: true)
      }
    }
    update(from: NSEvent.modifierFlags, eventWindow: nil)
  }

  func start() {
    guard flagsMonitor == nil else {
      update(from: NSEvent.modifierFlags, eventWindow: nil)
      return
    }
    flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) {
      [weak self] event in
      let flags = event.modifierFlags
      let eventWindow = event.window
      Task { @MainActor [weak self] in
        self?.update(from: flags, eventWindow: eventWindow)
      }
      return event
    }
    keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
      [weak self] event in
      let eventWindow = event.window
      Task { @MainActor [weak self] in
        guard self?.isCurrentWindow(eventWindow: eventWindow) == true else { return }
        self?.cancelPendingHintShow(resetVisible: true)
      }
      return event
    }
    resignObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.cancelPendingHintShow(resetVisible: true)
      }
    }
    update(from: NSEvent.modifierFlags, eventWindow: nil)
  }

  func stop() {
    if let flagsMonitor {
      NSEvent.removeMonitor(flagsMonitor)
      self.flagsMonitor = nil
    }
    if let keyDownMonitor {
      NSEvent.removeMonitor(keyDownMonitor)
      self.keyDownMonitor = nil
    }
    if let resignObserver {
      NotificationCenter.default.removeObserver(resignObserver)
      self.resignObserver = nil
    }
    removeHostWindowObservers()
    hostWindow = nil
    cancelPendingHintShow(resetVisible: true)
  }

  private func isCurrentWindow(eventWindow: NSWindow?) -> Bool {
    TabControlShortcutHintPolicy.isCurrentWindow(
      hostWindowNumber: hostWindow?.windowNumber,
      hostWindowIsKey: hostWindow?.isKeyWindow ?? false,
      eventWindowNumber: eventWindow?.windowNumber,
      keyWindowNumber: NSApp.keyWindow?.windowNumber
    )
  }

  private func update(from modifierFlags: NSEvent.ModifierFlags, eventWindow: NSWindow?) {
    guard
      TabControlShortcutHintPolicy.shouldShowHints(
        for: modifierFlags,
        hostWindowNumber: hostWindow?.windowNumber,
        hostWindowIsKey: hostWindow?.isKeyWindow ?? false,
        eventWindowNumber: eventWindow?.windowNumber,
        keyWindowNumber: NSApp.keyWindow?.windowNumber
      ), let modifier = TabControlShortcutHintPolicy.hintModifier(for: modifierFlags)
    else {
      cancelPendingHintShow(resetVisible: true)
      return
    }
    if isShortcutHintVisible {
      setState(visible: true, symbol: modifier.symbol)
    } else {
      queueHintShow(for: modifier)
    }
  }

  private func queueHintShow(for modifier: TabControlShortcutModifier) {
    guard pendingModifier != modifier || pendingShowTask == nil else { return }
    pendingShowTask?.cancel()
    pendingModifier = modifier
    pendingShowTask = Task { @MainActor [weak self, sleep] in
      do {
        try await sleep(.milliseconds(300))
      } catch {
        return
      }
      guard !Task.isCancelled, let self else { return }
      self.pendingShowTask = nil
      self.pendingModifier = nil
      guard
        TabControlShortcutHintPolicy.shouldShowHints(
          for: NSEvent.modifierFlags,
          hostWindowNumber: self.hostWindow?.windowNumber,
          hostWindowIsKey: self.hostWindow?.isKeyWindow ?? false,
          eventWindowNumber: nil,
          keyWindowNumber: NSApp.keyWindow?.windowNumber
        ),
        let currentModifier = TabControlShortcutHintPolicy.hintModifier(
          for: NSEvent.modifierFlags
        )
      else { return }
      self.setState(visible: true, symbol: currentModifier.symbol)
    }
  }

  private func cancelPendingHintShow(resetVisible: Bool) {
    pendingShowTask?.cancel()
    pendingShowTask = nil
    pendingModifier = nil
    guard resetVisible else { return }
    setState(
      visible: false,
      symbol: TabControlShortcutHintPolicy.configuredShortcutModifierSymbol()
    )
  }

  private func setState(visible: Bool, symbol: String) {
    guard isShortcutHintVisible != visible || shortcutModifierSymbol != symbol else { return }
    isShortcutHintVisible = visible
    shortcutModifierSymbol = symbol
    onChange?()
  }

  private func removeHostWindowObservers() {
    if let hostWindowDidBecomeKeyObserver {
      NotificationCenter.default.removeObserver(hostWindowDidBecomeKeyObserver)
      self.hostWindowDidBecomeKeyObserver = nil
    }
    if let hostWindowDidResignKeyObserver {
      NotificationCenter.default.removeObserver(hostWindowDidResignKeyObserver)
      self.hostWindowDidResignKeyObserver = nil
    }
  }
}
