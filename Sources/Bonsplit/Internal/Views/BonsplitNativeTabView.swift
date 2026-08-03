import AppKit
import QuartzCore
import UniformTypeIdentifiers

@MainActor
final class BonsplitNativeTabView: NSView, NSDraggingSource {
  typealias Sleep = @Sendable (Duration) async throws -> Void

  private weak var pane: PaneState?
  private weak var controller: BonsplitController?
  private var tab: TabItem?
  private var tabIndex = 0
  private var isSelected = false
  private var isFocused = false
  private var showsZoomIndicator = false
  private var shortcutDigit: Int?
  private var shortcutModifierSymbol = "⌃"
  private var shortcutHintRequested = false

  private let imageView = NSImageView()
  private let iconPlaceholder = NSView()
  private let spinner = TabLoadingSpinnerLayerView()
  private let titleLabel = NSTextField(labelWithString: "")
  private let remoteImageView = NSImageView()
  private let audioButton = BonsplitTabAccessoryButton()
  private let zoomButton = BonsplitTabAccessoryButton()
  private let statusDots = BonsplitTabStatusDotsView()
  private let pinImageView = NSImageView()
  private let closeButton = BonsplitTabAccessoryButton()
  private let shortcutHintView = BonsplitShortcutHintView()

  private var trackingArea: NSTrackingArea?
  private var isHovered = false
  private var dragStarted = false
  private var dragGeneration: Int?
  private var mouseDownPoint = NSPoint.zero
  private var renderedFaviconData: Data?
  private var renderedFaviconImage: NSImage?
  private var showGlobeFallback = true
  private var lastObservedLoading = false
  private var lastLoadingStoppedAt: ContinuousClock.Instant?
  private var globeFallbackTask: Task<Void, Never>?
  private let fallbackSleep: Sleep

  private(set) var preferredNaturalWidth: CGFloat = TabBarMetrics.tabMinWidth
  var closeVisibleForTesting: Bool { !closeButton.isHidden }
  var pinVisibleForTesting: Bool { !pinImageView.isHidden }
  var statusVisibleForTesting: Bool { !statusDots.isHidden }
  var audioVisibleForTesting: Bool { !audioButton.isHidden }
  var remoteVisibleForTesting: Bool { !remoteImageView.isHidden }
  var zoomVisibleForTesting: Bool { !zoomButton.isHidden }
  var shortcutHintVisibleForTesting: Bool { !shortcutHintView.isHidden }
  var shortcutHintTextForTesting: String { shortcutHintView.text }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override init(frame frameRect: NSRect) {
    fallbackSleep = { duration in
      try await ContinuousClock().sleep(for: duration)
    }
    super.init(frame: frameRect)
    setUpViews()
  }

  init(frame frameRect: NSRect, fallbackSleep: @escaping Sleep) {
    self.fallbackSleep = fallbackSleep
    super.init(frame: frameRect)
    setUpViews()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  isolated deinit {
    globeFallbackTask?.cancel()
  }

  private func setUpViews() {
    wantsLayer = true

    imageView.imageScaling = .scaleProportionallyDown
    iconPlaceholder.wantsLayer = true
    iconPlaceholder.layer?.cornerRadius = 3
    iconPlaceholder.layer?.borderWidth = 1

    titleLabel.lineBreakMode = .byTruncatingTail
    titleLabel.maximumNumberOfLines = 1

    remoteImageView.imageScaling = .scaleProportionallyDown
    remoteImageView.image = NSImage(
      systemSymbolName: "network",
      accessibilityDescription: nil
    )

    configureButton(closeButton, symbol: "xmark", action: #selector(closeTab))
    configureButton(audioButton, symbol: "speaker.wave.2.fill", action: #selector(toggleAudio))
    configureButton(
      zoomButton,
      symbol: "arrow.up.left.and.arrow.down.right",
      action: #selector(toggleZoom)
    )

    pinImageView.imageScaling = .scaleProportionallyDown
    pinImageView.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)

    for child in [
      imageView,
      iconPlaceholder,
      spinner,
      titleLabel,
      remoteImageView,
      audioButton,
      zoomButton,
      statusDots,
      pinImageView,
      closeButton,
      shortcutHintView,
    ] {
      addSubview(child)
    }
  }

  private func configureButton(_ button: NSButton, symbol: String, action: Selector) {
    button.bezelStyle = .inline
    button.isBordered = false
    button.imagePosition = .imageOnly
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    button.target = self
    button.action = action
  }

  func configure(
    tab: TabItem,
    index: Int,
    pane: PaneState,
    controller: BonsplitController,
    showsZoomIndicator: Bool,
    isFocused: Bool,
    shortcutDigit: Int?,
    showsShortcutHint: Bool,
    shortcutModifierSymbol: String
  ) {
    if lastObservedLoading, !tab.isLoading {
      lastLoadingStoppedAt = ContinuousClock.now
    }
    lastObservedLoading = tab.isLoading

    self.tab = tab
    tabIndex = index
    self.pane = pane
    self.controller = controller
    self.showsZoomIndicator = showsZoomIndicator
    self.isFocused = isFocused
    self.shortcutDigit = shortcutDigit
    self.shortcutModifierSymbol = shortcutModifierSymbol
    shortcutHintRequested = showsShortcutHint
    isSelected = pane.selectedTabId == tab.id

    updateRenderedFavicon(for: tab)
    updateGlobeFallback(for: tab)
    applyAppearance()
    updateAccessibility()
    updatePreferredNaturalWidth()
    syncChrome()
    needsDisplay = true
    needsLayout = true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
      owner: self
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    syncChrome()
    needsDisplay = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    syncChrome()
    needsDisplay = true
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard bounds.contains(point), let hit = super.hitTest(point) else { return nil }
    var candidate: NSView? = hit
    while let current = candidate, current !== self {
      if current is NSButton { return hit }
      candidate = current.superview
    }
    return self
  }

  override func mouseDown(with event: NSEvent) {
    guard controller?.isInteractive == true else { return }
    mouseDownPoint = convert(event.locationInWindow, from: nil)
    dragStarted = false
  }

  override func mouseDragged(with event: NSEvent) {
    guard !dragStarted, let tab, let pane, let controller,
      controller.isInteractive,
      controller.configuration.allowTabReordering
        || controller.configuration.allowCrossPaneTabMove
    else { return }
    let point = convert(event.locationInWindow, from: nil)
    guard hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) >= 3 else { return }
    dragStarted = true
    dragGeneration = controller.internalController.beginTabDrag(tab, from: pane.id)
    let transfer = TabTransferData(tab: tab, sourcePaneId: pane.id.id)
    guard let data = try? JSONEncoder().encode(transfer) else {
      finishDragState()
      return
    }
    let pasteboardItem = NSPasteboardItem()
    pasteboardItem.setData(
      data,
      forType: NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
    )
    let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
    draggingItem.setDraggingFrame(bounds, contents: bitmapImageRepForCachingDisplay(in: bounds))
    beginDraggingSession(with: [draggingItem], event: event, source: self)
  }

  override func mouseUp(with event: NSEvent) {
    guard !dragStarted, let tab, let pane, let controller, controller.isInteractive else { return }
    if event.clickCount == 2 {
      _ = controller.requestTabZoomToggle(for: TabID(id: tab.id), inPane: pane.id)
    } else {
      pane.selectTab(tab.id)
      controller.focusPane(pane.id)
    }
  }

  override func rightMouseDown(with event: NSEvent) {
    guard let tab, let pane, let controller,
      controller.isInteractive,
      controller.configuration.allowsTabContextMenu
    else { return }
    let state = TabContextMenuState(
      tab: tab,
      index: tabIndex,
      pane: pane,
      controller: controller,
      splitViewController: controller.internalController
    )
    let target = TabContextMenuActionTarget()
    target.onContextAction = { [weak controller] action in
      controller?.requestTabContextAction(action, for: TabID(id: tab.id), inPane: pane.id)
    }
    target.onMoveDestination = { [weak controller] id in
      controller?.requestTabMove(
        toDestination: id,
        for: TabID(id: tab.id),
        inPane: pane.id
      )
    }
    let snapshot = TabContextMenuSnapshot(
      tabId: tab.id,
      state: state,
      moveDestinationsProvider: {
        controller.tabContextMoveDestinationsProvider?(TabID(id: tab.id), pane.id) ?? []
      },
      forkConversationAvailabilityProvider: {
        controller.tabContextForkConversationAvailabilityProvider?(
          TabID(id: tab.id),
          pane.id
        ) ?? .hidden
      },
      forkConversationAvailabilityRefreshHandler: {
        await controller.tabContextForkConversationAvailabilityRefreshHandler?(
          TabID(id: tab.id),
          pane.id
        )
      }
    )
    NSMenu.popUpContextMenu(
      TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: target),
      with: event,
      for: self
    )
  }

  override func otherMouseUp(with event: NSEvent) {
    guard event.buttonNumber == 2 else { return }
    closeTab()
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  func draggingSession(
    _ session: NSDraggingSession,
    sourceOperationMaskFor context: NSDraggingContext
  ) -> NSDragOperation {
    .move
  }

  func draggingSession(
    _ session: NSDraggingSession,
    endedAt screenPoint: NSPoint,
    operation: NSDragOperation
  ) {
    finishDragState()
    dragStarted = false
  }

  override func layout() {
    super.layout()
    guard let tab, let controller else { return }
    guard bounds.width > 0, bounds.height > 0 else {
      for subview in subviews {
        subview.frame = .zero
      }
      return
    }
    let appearance = controller.configuration.appearance
    let iconOnly = TabItemStyling.isIconOnlyPinned(isPinned: tab.isPinned, kind: tab.kind)
    let fontScale = max(0.1, appearance.tabTitleFontSize / TabBarMetrics.titleFontSize)
    let iconSize = TabBarMetrics.iconSize * fontScale
    let accessoryFontSize = max(8, appearance.tabTitleFontSize - 2)
    let accessorySize = min(
      max(1, bounds.height),
      max(TabBarMetrics.closeButtonSize, ceil(accessoryFontSize + 4))
    )
    let verticalIcon = (bounds.height - iconSize) * 0.5
    let padding = TabBarMetrics.tabHorizontalPadding

    if iconOnly {
      let iconFrame = NSRect(
        x: (bounds.width - iconSize) * 0.5,
        y: verticalIcon,
        width: iconSize,
        height: iconSize
      )
      imageView.frame = iconFrame
      iconPlaceholder.frame = iconFrame
      spinner.frame = iconFrame
      let hintSize = shortcutHintView.intrinsicContentSize
      shortcutHintView.frame = NSRect(
        x: (bounds.width - hintSize.width) * 0.5,
        y: (bounds.height - hintSize.height) * 0.5,
        width: hintSize.width,
        height: hintSize.height
      )
      let badgeSize = max(8, accessoryFontSize - 2)
      let badgeFrame = NSRect(
        x: iconFrame.maxX - badgeSize * 0.55,
        y: max(0, iconFrame.minY - 2),
        width: badgeSize,
        height: badgeSize
      )
      audioButton.frame = badgeFrame
      statusDots.frame = badgeFrame
      return
    }

    var leadingX = padding
    let hasLeadingIcon =
      tab.isLoading || resolvedImage(for: tab) != nil || showsPlaceholder(for: tab)
    if hasLeadingIcon {
      let iconFrame = NSRect(
        x: leadingX,
        y: verticalIcon,
        width: iconSize,
        height: iconSize
      )
      imageView.frame = iconFrame
      iconPlaceholder.frame = iconFrame
      spinner.frame = iconFrame
      leadingX += iconSize + (TabBarMetrics.contentSpacing * fontScale)
    }

    var trailingX = bounds.width - padding
    let trailingFrame = NSRect(
      x: trailingX - accessorySize,
      y: (bounds.height - accessorySize) * 0.5,
      width: accessorySize,
      height: accessorySize
    )
    closeButton.frame = trailingFrame
    let pinInset = min(2, accessorySize * 0.5)
    pinImageView.frame = trailingFrame.insetBy(dx: pinInset, dy: pinInset)
    statusDots.frame = trailingFrame
    let hintSize = shortcutHintView.intrinsicContentSize
    let xOffset = CGFloat(
      TabControlShortcutHintDebugSettings.clamped(
        UserDefaults.standard.double(forKey: TabControlShortcutHintDebugSettings.xKey)
      ))
    let yOffset = CGFloat(
      TabControlShortcutHintDebugSettings.clamped(
        UserDefaults.standard.double(forKey: TabControlShortcutHintDebugSettings.yKey)
      ))
    shortcutHintView.frame = NSRect(
      x: trailingFrame.midX - hintSize.width * 0.5 + xOffset,
      y: trailingFrame.midY - hintSize.height * 0.5 + yOffset,
      width: hintSize.width,
      height: hintSize.height
    )
    trailingX = trailingFrame.minX - (TabBarMetrics.contentSpacing * fontScale)

    if showsZoomIndicator {
      trailingX -= accessorySize
      zoomButton.frame = NSRect(
        x: trailingX,
        y: (bounds.height - accessorySize) * 0.5,
        width: accessorySize,
        height: accessorySize
      )
      trailingX -= TabBarMetrics.contentSpacing * fontScale
    }
    if tab.isAudioMuted || tab.isAudioPlaying {
      trailingX -= accessorySize
      audioButton.frame = NSRect(
        x: trailingX,
        y: (bounds.height - accessorySize) * 0.5,
        width: accessorySize,
        height: accessorySize
      )
      trailingX -= TabBarMetrics.contentSpacing * fontScale
    }
    if tab.showsRemoteIndicator {
      let remoteSize = max(8, accessoryFontSize)
      trailingX -= remoteSize
      remoteImageView.frame = NSRect(
        x: trailingX,
        y: (bounds.height - remoteSize) * 0.5,
        width: remoteSize,
        height: remoteSize
      )
      trailingX -= TabBarMetrics.contentSpacing * fontScale
    }
    titleLabel.frame = NSRect(
      x: leadingX,
      y: 0,
      width: max(0, trailingX - leadingX),
      height: bounds.height
    )
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let pane, let controller else { return }
    let appearance = controller.configuration.appearance
    if isSelected || isHovered {
      let color =
        isSelected
        ? TabBarColors.nsColorActiveTabBackground(for: appearance)
        : TabBarColors.nsColorHoveredTabBackground(for: appearance)
      color.setFill()
      bounds.fill()
    }
    TabBarColors.nsColorSeparator(for: appearance).setFill()
    let bottomInset =
      pane.tabs.indices.contains(tabIndex + 1)
        && pane.tabs[tabIndex + 1].id == pane.selectedTabId
      ? TabBarMetrics.selectedTabLeftSeparatorBottomInset
      : 0
    NSRect(
      x: max(0, bounds.width - 1),
      y: 0,
      width: 1,
      height: max(0, bounds.height - bottomInset)
    ).fill()
  }

  private func applyAppearance() {
    guard let tab, let controller else { return }
    let appearance = controller.configuration.appearance
    let textColor =
      isSelected
      ? TabBarColors.nsColorActiveText(for: appearance)
      : TabBarColors.nsColorInactiveText(for: appearance)
    titleLabel.stringValue = tab.title
    titleLabel.font = .systemFont(ofSize: appearance.tabTitleFontSize)
    titleLabel.textColor = textColor

    let fontScale = max(0.1, appearance.tabTitleFontSize / TabBarMetrics.titleFontSize)
    let iconSize = TabBarMetrics.iconSize * fontScale
    let icon = resolvedImage(for: tab)
    imageView.image = icon
    imageView.symbolConfiguration = .init(pointSize: iconSize, weight: .regular)
    imageView.contentTintColor = textColor
    iconPlaceholder.layer?.borderColor = textColor.withAlphaComponent(0.25).cgColor
    spinner.configure(size: iconSize * 0.86, color: textColor)

    let accessoryPointSize = max(8, appearance.tabTitleFontSize - 2)
    let symbolConfig = NSImage.SymbolConfiguration(
      pointSize: accessoryPointSize,
      weight: .semibold
    )
    for view in [remoteImageView, pinImageView] {
      view.symbolConfiguration = symbolConfig
      view.contentTintColor = textColor.withAlphaComponent(0.78)
    }
    for button in [audioButton, zoomButton, closeButton] {
      button.symbolConfiguration = symbolConfig
      button.contentTintColor = textColor.withAlphaComponent(0.78)
      button.hoverBackgroundColor = TabBarColors.nsColorHoveredTabBackground(for: appearance)
    }
    audioButton.image = NSImage(
      systemSymbolName: tab.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
      accessibilityDescription: nil
    )
    let iconOnly = TabItemStyling.isIconOnlyPinned(isPinned: tab.isPinned, kind: tab.kind)
    statusDots.configure(
      showsNotification: tab.showsNotificationBadge,
      showsDirty: tab.isDirty && (!iconOnly || !tab.showsNotificationBadge),
      notificationColor: TabBarColors.nsColorNotificationBadge(for: appearance),
      dirtyColor: TabBarColors.nsColorDirtyIndicator(for: appearance)
    )
    shortcutHintView.text = shortcutDigit.map { "\(shortcutModifierSymbol)\($0)" } ?? ""
    closeButton.toolTip = localized("tab.close", defaultValue: "Close Tab")
    audioButton.toolTip = localized(
      tab.isAudioMuted ? "tabContext.unmuteTab" : "tabContext.muteTab",
      defaultValue: tab.isAudioMuted ? "Unmute Tab" : "Mute Tab"
    )
    zoomButton.toolTip = localized("tabContext.exitZoom", defaultValue: "Exit Zoom")
    toolTip = tab.title
  }

  private func syncChrome() {
    guard let tab, let controller else { return }
    let iconOnly = TabItemStyling.isIconOnlyPinned(isPinned: tab.isPinned, kind: tab.kind)
    let hintsEnabled = isFocused && controller.internalController.tabShortcutHintsEnabled
    let alwaysShow = UserDefaults.standard.bool(
      forKey: TabControlShortcutHintDebugSettings.alwaysShowKey
    )
    let showsHint =
      shortcutDigit != nil
      && hintsEnabled
      && (shortcutHintRequested || alwaysShow)

    shortcutHintView.isHidden = !showsHint
    titleLabel.isHidden = iconOnly
    remoteImageView.isHidden = iconOnly || !tab.showsRemoteIndicator
    zoomButton.isHidden = iconOnly || !showsZoomIndicator

    let hasAudio = tab.isAudioMuted || tab.isAudioPlaying
    audioButton.isHidden = iconOnly ? (!hasAudio || tab.isLoading || showsHint) : !hasAudio

    let hasImage = resolvedImage(for: tab) != nil
    imageView.isHidden = showsHint || tab.isLoading || !hasImage
    spinner.isHidden = showsHint || !tab.isLoading
    iconPlaceholder.isHidden = showsHint || tab.isLoading || !showsPlaceholder(for: tab)

    let statusVisible =
      !isSelected && !isHovered
      && (tab.isDirty || tab.showsNotificationBadge)
    statusDots.isHidden =
      showsHint
      || tab.isLoading
      || (iconOnly ? hasAudio : !statusVisible)
    pinImageView.isHidden =
      iconOnly
      || showsHint
      || !tab.isPinned
      || (statusVisible && (tab.isDirty || tab.showsNotificationBadge))
    closeButton.isHidden =
      iconOnly
      || showsHint
      || tab.isPinned
      || !controller.configuration.allowCloseTabs
      || (!isSelected && !isHovered)
  }

  private func updatePreferredNaturalWidth() {
    guard let tab, let controller else { return }
    let appearance = controller.configuration.appearance
    let fontScale = max(0.1, appearance.tabTitleFontSize / TabBarMetrics.titleFontSize)
    let iconSize = TabBarMetrics.iconSize * fontScale
    let padding = TabBarMetrics.tabHorizontalPadding
    if TabItemStyling.isIconOnlyPinned(isPinned: tab.isPinned, kind: tab.kind) {
      let hintWidth: CGFloat? =
        isFocused
          && controller.internalController.tabShortcutHintsEnabled
          && shortcutDigit != nil
        ? TabItemStyling.shortcutHintWidth(
          for: "\(shortcutModifierSymbol)\(shortcutDigit ?? 0)"
        )
        : nil
      preferredNaturalWidth = TabItemStyling.pinnedIconOnlyWidth(
        iconSlotSize: iconSize,
        horizontalPadding: padding,
        reservedShortcutHintWidth: hintWidth
      )
      return
    }

    let titleWidth = (tab.title as NSString).size(withAttributes: [
      .font: NSFont.systemFont(ofSize: appearance.tabTitleFontSize)
    ]).width
    let spacing = TabBarMetrics.contentSpacing * fontScale
    let accessorySize = max(
      TabBarMetrics.closeButtonSize,
      ceil(max(8, appearance.tabTitleFontSize - 2) + 4)
    )
    var width = padding * 2 + titleWidth + spacing + accessorySize
    if tab.isLoading || resolvedImage(for: tab) != nil || showsPlaceholder(for: tab) {
      width += iconSize + spacing
    }
    if tab.showsRemoteIndicator { width += max(8, appearance.tabTitleFontSize - 2) + spacing }
    if tab.isAudioMuted || tab.isAudioPlaying { width += accessorySize + spacing }
    if showsZoomIndicator { width += accessorySize + spacing }
    let range = TabItemStyling.tabWidthRange(for: appearance)
    preferredNaturalWidth = min(max(range.lowerBound, ceil(width)), range.upperBound)
  }

  private func updateRenderedFavicon(for tab: TabItem) {
    guard
      renderedFaviconData != tab.iconImageData
        || (renderedFaviconImage == nil && tab.iconImageData != nil)
    else { return }
    renderedFaviconData = tab.iconImageData
    renderedFaviconImage = TabItemStyling.resolvedFaviconImage(
      existing: renderedFaviconImage,
      incomingData: tab.iconImageData
    )
  }

  private func updateGlobeFallback(for tab: TabItem) {
    globeFallbackTask?.cancel()
    globeFallbackTask = nil
    let recentlyStopped =
      lastLoadingStoppedAt.map {
        $0.duration(to: ContinuousClock.now) < .seconds(1.5)
      } ?? false
    let shouldDelay =
      tab.icon == "globe"
      && tab.iconImageData == nil
      && !tab.isLoading
      && recentlyStopped
    guard shouldDelay else {
      showGlobeFallback = true
      return
    }
    showGlobeFallback = false
    let tabID = tab.id
    globeFallbackTask = Task { @MainActor [weak self, fallbackSleep] in
      do {
        try await fallbackSleep(.milliseconds(900))
      } catch {
        return
      }
      guard !Task.isCancelled,
        let self,
        self.tab?.id == tabID,
        self.tab?.iconImageData == nil,
        self.tab?.icon == "globe",
        self.tab?.isLoading == false
      else { return }
      self.globeFallbackTask = nil
      self.showGlobeFallback = true
      self.applyAppearance()
      self.syncChrome()
      self.needsLayout = true
    }
  }

  private func resolvedImage(for tab: TabItem) -> NSImage? {
    if let renderedFaviconImage { return renderedFaviconImage }
    if let asset = tab.iconAsset, let image = NSImage(named: asset) { return image }
    guard let icon = tab.icon else { return nil }
    if icon == "globe", !showGlobeFallback { return nil }
    return NSImage(systemSymbolName: icon, accessibilityDescription: nil)
  }

  private func showsPlaceholder(for tab: TabItem) -> Bool {
    tab.icon == "globe"
      && !showGlobeFallback
      && tab.iconImageData == nil
      && !tab.isLoading
  }

  private func updateAccessibility() {
    guard let tab else { return }
    var statuses: [String] = []
    if tab.isLoading {
      statuses.append(localized("tab.accessibility.loading", defaultValue: "Loading"))
    }
    if tab.isPinned {
      statuses.append(localized("tab.accessibility.pinned", defaultValue: "Pinned"))
    }
    if tab.showsNotificationBadge {
      statuses.append(localized("tab.accessibility.unread", defaultValue: "Unread"))
    }
    if tab.isDirty {
      statuses.append(localized("tab.accessibility.modified", defaultValue: "Modified"))
    }
    if tab.isAudioMuted {
      statuses.append(localized("tabContext.audioMutedAccessibility", defaultValue: "Muted"))
    }
    if tab.showsRemoteIndicator {
      statuses.append(
        localized(
          "tabContext.remoteConnectedAccessibility",
          defaultValue: "Connected over SSH"
        ))
    }
    if showsZoomIndicator {
      statuses.append(localized("tab.accessibility.zoomed", defaultValue: "Zoomed"))
    }
    setAccessibilityElement(true)
    setAccessibilityRole(.button)
    setAccessibilityLabel(tab.title)
    setAccessibilityValue(statuses.joined(separator: ", "))
    setAccessibilitySelected(isSelected)
  }

  private func finishDragState() {
    guard let dragGeneration else { return }
    self.dragGeneration = nil
    controller?.internalController.cancelTabDragIfGenerationMatches(dragGeneration)
  }

  private func localized(_ key: String, defaultValue: String) -> String {
    Bundle.module.localizedString(forKey: key, value: defaultValue, table: nil)
  }

  @objc private func closeTab() {
    guard let tab, let pane, let controller,
      controller.isInteractive,
      controller.configuration.allowCloseTabs,
      !tab.isPinned
    else { return }
    controller.onTabCloseRequest?(TabID(id: tab.id), pane.id, .closeButton)
    _ = controller.closeTab(TabID(id: tab.id), inPane: pane.id)
  }

  @objc private func toggleAudio() {
    guard let tab, let pane, let controller, controller.isInteractive else { return }
    controller.requestTabContextAction(.toggleAudioMute, for: TabID(id: tab.id), inPane: pane.id)
  }

  @objc private func toggleZoom() {
    guard let tab, let pane, let controller, controller.isInteractive else { return }
    _ = controller.requestTabZoomToggle(for: TabID(id: tab.id), inPane: pane.id)
  }
}

@MainActor
private final class BonsplitTabAccessoryButton: NSButton {
  var hoverBackgroundColor: NSColor = .clear
  private var trackingArea: NSTrackingArea?
  private var hovering = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 6
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingArea { removeTrackingArea(trackingArea) }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
      owner: self
    )
    addTrackingArea(area)
    trackingArea = area
  }

  override func mouseEntered(with event: NSEvent) {
    hovering = true
    layer?.backgroundColor = hoverBackgroundColor.cgColor
  }

  override func mouseExited(with event: NSEvent) {
    hovering = false
    layer?.backgroundColor = NSColor.clear.cgColor
  }
}

@MainActor
private final class BonsplitShortcutHintView: NSView {
  private let label = NSTextField(labelWithString: "")

  var text: String = "" {
    didSet {
      guard text != oldValue else { return }
      label.stringValue = text
      invalidateIntrinsicContentSize()
      needsLayout = true
      needsDisplay = true
    }
  }

  override var isFlipped: Bool { true }
  override var intrinsicContentSize: NSSize {
    let textSize = (text as NSString).size(
      withAttributes: TabControlShortcutHintStyle.measurementAttributes
    )
    return NSSize(
      width: ceil(textSize.width) + TabControlShortcutHintStyle.horizontalPadding * 2,
      height: ceil(textSize.height) + TabControlShortcutHintStyle.verticalPadding * 2
    )
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.cornerRadius = 5
    layer?.borderWidth = TabControlShortcutHintStyle.strokeWidth
    label.font = TabControlShortcutHintStyle.measurementFont
    label.alignment = .center
    label.textColor = .labelColor
    addSubview(label)
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateColors()
  }

  override func layout() {
    super.layout()
    label.frame = bounds
    updateColors()
  }

  private func updateColors() {
    layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.92).cgColor
    layer?.borderColor =
      NSColor.separatorColor.withAlphaComponent(
        TabControlShortcutHintStyle.strokeOpacity
      ).cgColor
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = Float(TabControlShortcutHintStyle.shadowOpacity)
    layer?.shadowRadius = TabControlShortcutHintStyle.shadowRadius
    layer?.shadowOffset = CGSize(
      width: TabControlShortcutHintStyle.shadowX,
      height: TabControlShortcutHintStyle.shadowY
    )
  }
}

@MainActor
private final class BonsplitTabStatusDotsView: NSView {
  private var showsNotification = false
  private var showsDirty = false
  private var notificationColor = NSColor.systemBlue
  private var dirtyColor = NSColor.secondaryLabelColor

  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  func configure(
    showsNotification: Bool,
    showsDirty: Bool,
    notificationColor: NSColor,
    dirtyColor: NSColor
  ) {
    self.showsNotification = showsNotification
    self.showsDirty = showsDirty
    self.notificationColor = notificationColor
    self.dirtyColor = dirtyColor
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    let notificationSize = min(TabBarMetrics.notificationBadgeSize, bounds.height)
    let dirtySize = min(TabBarMetrics.dirtyIndicatorSize, bounds.height)
    let spacing: CGFloat = showsNotification && showsDirty ? 2 : 0
    let total =
      (showsNotification ? notificationSize : 0)
      + (showsDirty ? dirtySize : 0)
      + spacing
    var x = (bounds.width - total) * 0.5
    if showsNotification {
      notificationColor.setFill()
      NSBezierPath(
        ovalIn: NSRect(
          x: x,
          y: (bounds.height - notificationSize) * 0.5,
          width: notificationSize,
          height: notificationSize
        )
      ).fill()
      x += notificationSize + spacing
    }
    if showsDirty {
      dirtyColor.setFill()
      NSBezierPath(
        ovalIn: NSRect(
          x: x,
          y: (bounds.height - dirtySize) * 0.5,
          width: dirtySize,
          height: dirtySize
        )
      ).fill()
    }
  }
}
