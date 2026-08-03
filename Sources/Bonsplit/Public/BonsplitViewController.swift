import AppKit
import Observation
import QuartzCore
import UniformTypeIdentifiers

/// Receives pane drop-zone changes while a drag is above content supplied by a host.
@MainActor
public protocol BonsplitPaneDropZoneReceiving: AnyObject {
  func bonsplitPaneDropZoneDidChange(_ zone: DropZone?)
}

/// Lets a cached content controller update without losing its native view state.
@MainActor
public protocol BonsplitContentUpdating: AnyObject {
  func updateBonsplitContent(tab: Tab, pane: PaneID)
}

/// Native AppKit renderer for a ``BonsplitController`` split tree.
@MainActor
public final class BonsplitViewController: NSViewController {
  public typealias ContentProvider = @MainActor (Tab, PaneID) -> NSViewController
  public typealias EmptyPaneProvider = @MainActor (PaneID) -> NSViewController

  public let controller: BonsplitController

  private var contentProvider: ContentProvider
  private var emptyPaneProvider: EmptyPaneProvider
  private let rootHost = BonsplitRootHostView()
  private var nodeViews: [UUID: NSView] = [:]
  private var contentControllers: [UUID: NSViewController] = [:]
  private var emptyControllers: [PaneID: NSViewController] = [:]
  private var refreshTask: Task<Void, Never>?
  private var isRendering = false
  private var needsAnotherRender = false

  public init(
    controller: BonsplitController,
    content: @escaping ContentProvider,
    emptyPane: @escaping EmptyPaneProvider
  ) {
    self.controller = controller
    self.contentProvider = content
    self.emptyPaneProvider = emptyPane
    super.init(nibName: nil, bundle: nil)
  }

  public convenience init(
    controller: BonsplitController,
    content: @escaping ContentProvider
  ) {
    self.init(
      controller: controller,
      content: content,
      emptyPane: { _ in BonsplitDefaultEmptyPaneController() }
    )
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    refreshTask?.cancel()
  }

  public override func loadView() {
    rootHost.onLayout = { [weak controller] frame in
      controller?.setContainerFrame(frame)
    }
    view = rootHost
    observeAndRender()
  }

  public func updateProviders(
    content: @escaping ContentProvider,
    emptyPane: @escaping EmptyPaneProvider
  ) {
    contentProvider = content
    emptyPaneProvider = emptyPane
    reloadContent()
  }

  public func reloadContent() {
    removeCachedControllers(&contentControllers)
    removeCachedControllers(&emptyControllers)
    render()
  }

  /// Re-renders the split tree while preserving cached host controllers.
  /// Controllers conforming to ``BonsplitContentUpdating`` receive the latest
  /// tab and pane snapshots, so hosts can refresh appearance or unread state
  /// without tearing down terminal and browser content.
  public func refreshContent() {
    render()
  }

  private func removeCachedControllers<Key: Hashable>(
    _ controllers: inout [Key: NSViewController]
  ) {
    for child in controllers.values {
      child.view.removeFromSuperview()
      child.removeFromParent()
    }
    controllers.removeAll()
  }

  private func observeAndRender() {
    withObservationTracking {
      trackObservedState(controller.internalController.rootNode)
      _ = controller.configuration
      _ = controller.isInteractive
      _ = controller.tabShortcutHintsEnabled
      _ = controller.internalController.focusedPaneId
      _ = controller.internalController.zoomedPaneId
      render()
    } onChange: { [weak self] in
      Task { @MainActor [weak self] in
        self?.scheduleObservationRefresh()
      }
    }
  }

  private func scheduleObservationRefresh() {
    refreshTask?.cancel()
    refreshTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, !Task.isCancelled else { return }
      self.refreshTask = nil
      self.observeAndRender()
    }
  }

  private func trackObservedState(_ node: SplitNode) {
    switch node {
    case .pane(let pane):
      _ = pane.tabs
      _ = pane.selectedTabId
      _ = pane.isFullWidthTabMode
    case .split(let split):
      _ = split.orientation
      _ = split.dividerPosition
      _ = split.imposedFirstExtent
      _ = split.imposedEpoch
      _ = split.animationOrigin
      trackObservedState(split.first)
      trackObservedState(split.second)
    }
  }

  private func render() {
    guard isViewLoaded else { return }
    guard !isRendering else {
      needsAnotherRender = true
      return
    }
    isRendering = true
    defer {
      isRendering = false
      if needsAnotherRender {
        needsAnotherRender = false
        render()
      }
    }

    var liveNodeIDs = Set<UUID>()
    var liveTabIDs = Set<UUID>()
    var livePaneIDs = Set<PaneID>()
    let rootNode: SplitNode
    if let zoomed = controller.internalController.zoomedPaneId,
      let zoomedNode = controller.internalController.rootNode.findNode(containing: zoomed)
    {
      rootNode = zoomedNode
    } else {
      rootNode = controller.internalController.rootNode
    }
    let nativeRoot = makeView(
      for: rootNode,
      liveNodeIDs: &liveNodeIDs,
      liveTabIDs: &liveTabIDs,
      livePaneIDs: &livePaneIDs
    )
    rootHost.install(nativeRoot)

    for (id, staleView) in nodeViews where !liveNodeIDs.contains(id) {
      staleView.removeFromSuperview()
      nodeViews[id] = nil
    }
    for (id, child) in contentControllers where !liveTabIDs.contains(id) {
      child.view.removeFromSuperview()
      child.removeFromParent()
      contentControllers[id] = nil
    }
    for (id, child) in emptyControllers where !livePaneIDs.contains(id) {
      child.view.removeFromSuperview()
      child.removeFromParent()
      emptyControllers[id] = nil
    }
  }

  private func makeView(
    for node: SplitNode,
    liveNodeIDs: inout Set<UUID>,
    liveTabIDs: inout Set<UUID>,
    livePaneIDs: inout Set<PaneID>
  ) -> NSView {
    liveNodeIDs.insert(node.id)
    switch node {
    case .pane(let pane):
      livePaneIDs.insert(pane.id)
      let paneView = (nodeViews[node.id] as? BonsplitPaneView) ?? BonsplitPaneView()
      nodeViews[node.id] = paneView
      let selected = pane.selectedTab ?? pane.tabs.first
      let renderedTabs: [TabItem]
      if controller.configuration.contentViewLifecycle == .keepAllAlive {
        renderedTabs = pane.tabs
      } else {
        renderedTabs = selected.map { [$0] } ?? []
      }
      liveTabIDs.formUnion(renderedTabs.map(\.id))
      let renderedControllers = renderedTabs.map {
        ($0.id, controllerForContent(tab: $0, pane: pane.id))
      }
      let emptyController = selected == nil ? controllerForEmptyPane(pane.id) : nil
      paneView.configure(
        pane: pane,
        controller: controller,
        contentControllers: renderedControllers,
        selectedTabID: selected?.id,
        emptyController: emptyController
      )
      return paneView

    case .split(let split):
      let first = makeView(
        for: split.first,
        liveNodeIDs: &liveNodeIDs,
        liveTabIDs: &liveTabIDs,
        livePaneIDs: &livePaneIDs
      )
      let second = makeView(
        for: split.second,
        liveNodeIDs: &liveNodeIDs,
        liveTabIDs: &liveTabIDs,
        livePaneIDs: &livePaneIDs
      )
      let splitView = (nodeViews[node.id] as? BonsplitNativeSplitView) ?? BonsplitNativeSplitView()
      nodeViews[node.id] = splitView
      splitView.configure(
        state: split,
        controller: controller,
        first: first,
        second: second
      )
      return splitView
    }
  }

  private func controllerForContent(tab: TabItem, pane: PaneID) -> NSViewController {
    let publicTab = Tab(from: tab)
    if let cached = contentControllers[tab.id] {
      (cached as? BonsplitContentUpdating)?.updateBonsplitContent(tab: publicTab, pane: pane)
      return cached
    }
    let child = contentProvider(publicTab, pane)
    addChild(child)
    child.view.translatesAutoresizingMaskIntoConstraints = true
    child.view.autoresizingMask = [.width, .height]
    contentControllers[tab.id] = child
    return child
  }

  private func controllerForEmptyPane(_ pane: PaneID) -> NSViewController {
    if let cached = emptyControllers[pane] { return cached }
    let child = emptyPaneProvider(pane)
    addChild(child)
    child.view.translatesAutoresizingMaskIntoConstraints = true
    child.view.autoresizingMask = [.width, .height]
    emptyControllers[pane] = child
    return child
  }
}

@MainActor
private final class BonsplitRootHostView: NSView {
  private weak var installedView: NSView?
  var onLayout: ((CGRect) -> Void)?

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  func install(_ view: NSView) {
    guard installedView !== view else {
      view.frame = bounds
      return
    }
    installedView?.removeFromSuperview()
    installedView = view
    view.frame = bounds
    view.autoresizingMask = [.width, .height]
    addSubview(view)
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    installedView?.frame = bounds
    installedView?.needsLayout = true
    onLayout?(bounds)
  }

  override func layout() {
    super.layout()
    installedView?.frame = bounds
    onLayout?(bounds)
  }
}

@MainActor
private final class BonsplitDefaultEmptyPaneController: NSViewController {
  override func loadView() {
    let container = NSView()
    container.wantsLayer = true

    let image = NSImageView(
      image: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage())
    image.symbolConfiguration = .init(pointSize: 42, weight: .regular)
    image.contentTintColor = .tertiaryLabelColor
    image.translatesAutoresizingMaskIntoConstraints = false

    let label = NSTextField(
      labelWithString: Bundle.module.localizedString(
        forKey: "emptyPane.noOpenTabs",
        value: "No Open Tabs",
        table: nil
      ))
    label.font = .preferredFont(forTextStyle: .headline)
    label.textColor = .secondaryLabelColor
    label.alignment = .center
    label.translatesAutoresizingMaskIntoConstraints = false

    container.addSubview(image)
    container.addSubview(label)
    NSLayoutConstraint.activate([
      image.centerXAnchor.constraint(equalTo: container.centerXAnchor),
      image.centerYAnchor.constraint(equalTo: container.centerYAnchor, constant: -18),
      image.widthAnchor.constraint(equalToConstant: 48),
      image.heightAnchor.constraint(equalToConstant: 48),
      label.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 12),
      label.centerXAnchor.constraint(equalTo: container.centerXAnchor),
    ])
    view = container
  }
}

@MainActor
final class BonsplitNativeSplitView: NSSplitView, NSSplitViewDelegate, BonsplitManagedSplitView {
  typealias Sleep = @Sendable (Duration) async throws -> Void

  weak var bonsplitController: BonsplitController?
  var bonsplitSplitId: UUID? { state?.id }

  private weak var state: SplitState?
  private var isApplyingModelPosition = false
  private var didLayOut = false
  private var customThickness: CGFloat = 1
  private var hitExpansion: CGFloat = 5
  private let firstContainer = BonsplitSplitChildContainerView()
  private let secondContainer = BonsplitSplitChildContainerView()
  private var pendingModelApply: Task<Void, Never>?
  private var entryAnimationTask: Task<Void, Never>?
  private var pendingAnimationOrigin: SplitAnimationOrigin?
  private var isAnimatingEntry = false
  private var lastLayoutSize: NSSize?
  private var lastAppliedAvailable: CGFloat?
  private let animationSleep: Sleep

  var isAnimatingEntryForTesting: Bool { isAnimatingEntry }

  override var dividerThickness: CGFloat { customThickness }
  override var dividerColor: NSColor {
    guard let controller = bonsplitController else { return .separatorColor }
    return TabBarColors.nsColorSeparator(for: controller.configuration.appearance)
  }
  override var mouseDownCanMoveWindow: Bool { false }

  override init(frame frameRect: NSRect) {
    animationSleep = { duration in
      try await ContinuousClock().sleep(for: duration)
    }
    super.init(frame: frameRect)
    setUpSplitView()
  }

  init(frame frameRect: NSRect, animationSleep: @escaping Sleep) {
    self.animationSleep = animationSleep
    super.init(frame: frameRect)
    setUpSplitView()
  }

  private func setUpSplitView() {
    delegate = self
    dividerStyle = .thin
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.isOpaque = false
    addArrangedSubview(firstContainer)
    addArrangedSubview(secondContainer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  isolated deinit {
    pendingModelApply?.cancel()
    entryAnimationTask?.cancel()
  }

  func configure(
    state: SplitState,
    controller: BonsplitController,
    first: NSView,
    second: NSView
  ) {
    self.state = state
    bonsplitController = controller
    isVertical = state.orientation == .horizontal
    customThickness = TabBarMetrics.resolvedDividerThickness(
      controller.configuration.appearance.dividerThickness
    )
    hitExpansion = max(0, controller.configuration.appearance.dividerHitExpansion)
    isHidden = !controller.isInteractive
    firstContainer.install(first)
    secondContainer.install(second)
    if let origin = state.animationOrigin {
      state.animationOrigin = nil
      cancelEntryAnimation(revealContainers: true)
      pendingAnimationOrigin = origin
      let newContainer = origin == .fromFirst ? firstContainer : secondContainer
      if controller.configuration.appearance.enableAnimations,
        state.imposedFirstExtent == nil
      {
        newContainer.isHidden = true
        isAnimatingEntry = true
      }
    } else if isAnimatingEntry,
      !controller.configuration.appearance.enableAnimations
    {
      cancelEntryAnimation(revealContainers: true)
    }
    state.syncDividerNow = { [weak self] in
      self?.scheduleModelApply()
    }
    needsLayout = true
    needsDisplay = true
    window?.invalidateCursorRects(for: self)
    if didLayOut {
      scheduleModelApply()
    }
  }

  override func layout() {
    super.layout()
    let sizeChanged =
      lastLayoutSize == nil
      || abs((lastLayoutSize?.width ?? 0) - bounds.width) > 0.5
      || abs((lastLayoutSize?.height ?? 0) - bounds.height) > 0.5
    lastLayoutSize = bounds.size
    if !didLayOut, bounds.width > 0, bounds.height > 0 {
      didLayOut = true
      if pendingAnimationOrigin != nil {
        startPendingEntryAnimation()
      } else {
        applyModelPosition()
      }
    } else if sizeChanged {
      if isAnimatingEntry {
        cancelEntryAnimation(revealContainers: true)
        applyModelPosition()
        return
      }
      if state?.imposedFirstExtent != nil {
        scheduleModelApply()
      } else {
        applyModelPosition()
      }
    }
  }

  override func resetCursorRects() {
    let cursor = isVertical ? BonsplitDividerCursors.vertical : BonsplitDividerCursors.horizontal
    guard let cursor, arrangedSubviews.count > 1 else {
      super.resetCursorRects()
      return
    }
    for index in 0..<(arrangedSubviews.count - 1) {
      let first = arrangedSubviews[index].frame
      var rect =
        isVertical
        ? NSRect(x: first.maxX, y: 0, width: dividerThickness, height: bounds.height)
        : NSRect(x: 0, y: first.maxY, width: bounds.width, height: dividerThickness)
      rect = rect.insetBy(
        dx: isVertical ? -hitExpansion : 0,
        dy: isVertical ? 0 : -hitExpansion
      ).intersection(bounds)
      if !rect.isNull { addCursorRect(rect, cursor: cursor) }
    }
  }

  override func drawDivider(in rect: NSRect) {
    dividerColor.setFill()
    rect.fill()
  }

  override func mouseDown(with event: NSEvent) {
    let tracksDivider = arrangedSubviews.count > 1
    if tracksDivider { bonsplitController?.noteDividerDragSession(true) }
    defer { if tracksDivider { bonsplitController?.noteDividerDragSession(false) } }
    super.mouseDown(with: event)
  }

  private func applyModelPosition() {
    guard let state,
      arrangedSubviews.count == 2,
      !isAnimatingEntry,
      bonsplitController?.isDividerDragActive != true
    else { return }
    let total = isVertical ? bounds.width : bounds.height
    let available = max(0, total - dividerThickness)
    guard available > 0 else { return }
    let range = bonsplitController?.configuration.dividerPositionRange ?? 0...1
    let points =
      state.imposedFirstExtent
      ?? available * min(max(state.dividerPosition, range.lowerBound), range.upperBound)
    isApplyingModelPosition = true
    setPosition(min(max(points, 0), available), ofDividerAt: 0)
    isApplyingModelPosition = false
    lastAppliedAvailable = available
    if state.imposedFirstExtent != nil {
      let outcome =
        isVertical
        ? arrangedSubviews[0].frame.width
        : arrangedSubviews[0].frame.height
      let mirrored = outcome / available
      if abs(state.dividerPosition - mirrored) > 0.000_1 {
        state.dividerPosition = mirrored
      }
    }
  }

  private func scheduleModelApply() {
    guard pendingModelApply == nil else { return }
    pendingModelApply = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, !Task.isCancelled else { return }
      self.pendingModelApply = nil
      self.applyModelPosition()
    }
  }

  private func startPendingEntryAnimation() {
    guard let origin = pendingAnimationOrigin,
      let state,
      let controller = bonsplitController,
      arrangedSubviews.count == 2
    else { return }
    let total = isVertical ? bounds.width : bounds.height
    let available = max(0, total - dividerThickness)
    guard available > 0 else { return }

    pendingAnimationOrigin = nil
    let appearance = controller.configuration.appearance
    let range = controller.configuration.dividerPositionRange
    let targetRatio = min(max(state.dividerPosition, range.lowerBound), range.upperBound)
    let target = available * targetRatio
    let newContainer = origin == .fromFirst ? firstContainer : secondContainer
    let shouldAnimate =
      appearance.enableAnimations
      && appearance.animationDuration > 0
      && state.imposedFirstExtent == nil
    guard shouldAnimate else {
      isAnimatingEntry = false
      newContainer.isHidden = false
      applyModelPosition()
      return
    }

    isAnimatingEntry = true
    let start: CGFloat = origin == .fromFirst ? 0 : available
    setPositionForAnimation(start)
    newContainer.isHidden = false
    let duration = appearance.animationDuration
    entryAnimationTask?.cancel()
    entryAnimationTask = Task { @MainActor [weak self, animationSleep] in
      await Task.yield()
      guard let self, !Task.isCancelled else { return }
      let clock = ContinuousClock()
      let started = clock.now
      while !Task.isCancelled {
        let elapsed = Self.seconds(started.duration(to: clock.now))
        let progress = min(max(elapsed / duration, 0), 1)
        let eased = progress >= 1 ? 1 : 1 - pow(2, -10 * progress)
        self.setPositionForAnimation(start + (target - start) * eased)
        if progress >= 1 { break }
        do {
          try await animationSleep(.milliseconds(8))
        } catch {
          return
        }
      }
      guard !Task.isCancelled else { return }
      self.entryAnimationTask = nil
      self.isAnimatingEntry = false
      if state.imposedFirstExtent != nil {
        self.applyModelPosition()
      } else {
        state.dividerPosition = targetRatio
        self.setPositionForAnimation(target)
        self.lastAppliedAvailable = available
      }
      controller.notifyGeometryChange()
    }
  }

  private func setPositionForAnimation(_ points: CGFloat) {
    guard arrangedSubviews.count == 2 else {
      #if DEBUG
        BonsplitDebugCounters.recordArrangedSubviewUnderflow()
      #endif
      return
    }
    isApplyingModelPosition = true
    setPosition(round(points), ofDividerAt: 0)
    layoutSubtreeIfNeeded()
    isApplyingModelPosition = false
  }

  private func cancelEntryAnimation(revealContainers: Bool) {
    entryAnimationTask?.cancel()
    entryAnimationTask = nil
    pendingAnimationOrigin = nil
    isAnimatingEntry = false
    if revealContainers {
      firstContainer.isHidden = false
      secondContainer.isHidden = false
    }
  }

  private static func seconds(_ duration: Duration) -> Double {
    let components = duration.components
    return Double(components.seconds) + Double(components.attoseconds) / 1_000_000_000_000_000_000
  }

  func splitView(
    _ splitView: NSSplitView,
    constrainSplitPosition proposedPosition: CGFloat,
    ofSubviewAt dividerIndex: Int
  ) -> CGFloat {
    if isAnimatingEntry { return proposedPosition }
    guard let controller = bonsplitController else { return proposedPosition }
    let appearance = controller.configuration.appearance
    let total = isVertical ? bounds.width : bounds.height
    let available = max(0, total - dividerThickness)
    let minimum = isVertical ? appearance.minimumPaneWidth : appearance.minimumPaneHeight
    let fractionRange = controller.configuration.dividerPositionRange
    let lower = max(minimum, available * fractionRange.lowerBound)
    let upper = min(available - minimum, available * fractionRange.upperBound)
    guard upper >= lower else { return available * 0.5 }
    return min(max(proposedPosition, lower), upper)
  }

  func splitViewDidResizeSubviews(_ notification: Notification) {
    guard !isApplyingModelPosition,
      !isAnimatingEntry,
      let state,
      arrangedSubviews.count == 2
    else { return }
    let total = isVertical ? bounds.width : bounds.height
    let available = max(0, total - dividerThickness)
    guard available > 0 else { return }
    if bonsplitController?.isDividerDragActive == true {
      let points = isVertical ? arrangedSubviews[0].frame.width : arrangedSubviews[0].frame.height
      state.imposedFirstExtent = nil
      state.dividerPosition = min(max(points / available, 0), 1)
      bonsplitController?.notifyGeometryChange(isDragging: true)
    } else if state.imposedFirstExtent != nil {
      if lastAppliedAvailable == nil
        || abs((lastAppliedAvailable ?? 0) - available) > 0.01
      {
        scheduleModelApply()
      }
      bonsplitController?.notifyGeometryChange()
    } else {
      applyModelPosition()
      bonsplitController?.notifyGeometryChange()
    }
  }
}

@MainActor
private final class BonsplitSplitChildContainerView: NSView {
  private weak var installedView: NSView?

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }
  override var mouseDownCanMoveWindow: Bool { false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.isOpaque = false
    layer?.masksToBounds = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func install(_ view: NSView) {
    guard installedView !== view else {
      view.frame = bounds
      return
    }
    installedView?.removeFromSuperview()
    if view.superview != nil { view.removeFromSuperview() }
    installedView = view
    view.frame = bounds
    view.autoresizingMask = [.width, .height]
    addSubview(view)
  }

  override func layout() {
    super.layout()
    installedView?.frame = bounds
  }
}

@MainActor
final class BonsplitPaneView: NSView {
  private weak var pane: PaneState?
  private weak var controller: BonsplitController?
  private let tabBar = BonsplitNativeTabBarView()
  private let contentHost = BonsplitFlippedView()
  private let dropOverlay = BonsplitDropOverlayView()
  private weak var contentController: NSViewController?
  private var activeDropZone: DropZone?

  #if DEBUG
    var paneIDForTesting: PaneID? { pane?.id }

    func setDropZoneForTesting(_ zone: DropZone?) {
      setDropZone(zone)
    }
  #endif

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool { false }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    contentHost.wantsLayer = true
    addSubview(contentHost)
    addSubview(tabBar)
    addSubview(dropOverlay)
    dropOverlay.isHidden = true
    registerForDraggedTypes([
      NSPasteboard.PasteboardType(UTType.tabTransfer.identifier),
      .fileURL,
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(
    pane: PaneState,
    controller: BonsplitController,
    contentControllers: [(UUID, NSViewController)],
    selectedTabID: UUID?,
    emptyController: NSViewController?
  ) {
    self.pane = pane
    self.controller = controller
    layer?.backgroundColor =
      TabBarColors.nsColorPaneBackground(
        for: controller.configuration.appearance
      ).cgColor
    tabBar.configure(pane: pane, controller: controller)

    let liveViews = Set(contentControllers.map { ObjectIdentifier($0.1.view) })
      .union(emptyController.map { [ObjectIdentifier($0.view)] } ?? [])
    for stale in contentHost.subviews where !liveViews.contains(ObjectIdentifier(stale)) {
      stale.removeFromSuperview()
    }
    for (tabID, child) in contentControllers {
      let contentView = child.view
      if contentView.superview !== contentHost { contentHost.addSubview(contentView) }
      contentView.isHidden = tabID != selectedTabID
      contentView.frame = contentHost.bounds
    }
    if let emptyController {
      if emptyController.view.superview !== contentHost {
        contentHost.addSubview(emptyController.view)
      }
      emptyController.view.isHidden = false
      emptyController.view.frame = contentHost.bounds
    }
    contentController =
      selectedTabID.flatMap { id in
        contentControllers.first { $0.0 == id }?.1
      } ?? emptyController
    needsLayout = true
  }

  override func layout() {
    super.layout()
    guard let pane, let controller else { return }
    let showsBar = controller.configuration.tabBarVisibility.showsTabBar(tabCount: pane.tabs.count)
    let barHeight = showsBar ? controller.configuration.appearance.tabBarHeight : 0
    tabBar.isHidden = !showsBar
    tabBar.frame = NSRect(x: 0, y: 0, width: bounds.width, height: barHeight)
    contentHost.frame = NSRect(
      x: 0, y: barHeight, width: bounds.width, height: max(0, bounds.height - barHeight))
    for contentView in contentHost.subviews {
      contentView.frame = contentHost.bounds
    }
    dropOverlay.frame = contentHost.frame
  }

  override func mouseDown(with event: NSEvent) {
    if let pane { controller?.focusPane(pane.id) }
    super.mouseDown(with: event)
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    updateDropZone(sender)
  }

  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
    updateDropZone(sender)
  }

  override func draggingExited(_ sender: NSDraggingInfo?) {
    setDropZone(nil)
  }

  override func draggingEnded(_ sender: NSDraggingInfo) {
    setDropZone(nil)
  }

  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    updateDropZone(sender) != []
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let pane, let controller, let zone = activeDropZone else { return false }
    defer { setDropZone(nil) }
    let pasteboard = sender.draggingPasteboard
    let tabType = NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
    let hasTab = pasteboard.availableType(from: [tabType]) != nil
    let urls = Self.fileURLs(from: pasteboard)
    let hasFiles = !urls.isEmpty
    let permitsTab = permitsTabTransfer(hasTabTransfer: hasTab, zone: zone)

    if UnifiedPaneDropDelegate.shouldHandleFileDrop(
      hasTabTransfer: hasTab,
      hasFileURL: hasFiles,
      permitsTabTransfer: permitsTab
    ) {
      let destination = destination(for: zone, pane: pane.id)
      if let handler = controller.onExternalFileDrop {
        return handler(.init(urls: urls, destination: destination))
      }
      if zone == .center {
        return controller.onFileDrop?(urls, pane.id) ?? false
      }
      return false
    }

    guard permitsTab else { return false }

    if let transfer = Self.decodeTransfer(from: pasteboard), transfer.isFromCurrentProcess {
      let internalController = controller.internalController
      let localTab = internalController.activeDragTab ?? internalController.draggingTab
      let sourcePane =
        internalController.activeDragSourcePaneId ?? internalController.dragSourcePaneId
      if let localTab, let sourcePane {
        internalController.clearTabDragState()
        if zone == .center {
          if sourcePane != pane.id {
            return controller.moveTab(TabID(id: localTab.id), toPane: pane.id)
          }
          return true
        }
        guard controller.configuration.allowCrossPaneTabMove,
          let orientation = zone.orientation
        else { return false }
        return controller.splitPane(
          pane.id,
          orientation: orientation,
          movingTab: TabID(id: localTab.id),
          insertFirst: zone.insertsFirst
        ) != nil
      }
      let destination = destination(for: zone, pane: pane.id)
      return controller.onExternalTabDrop?(
        .init(
          tabId: TabID(id: transfer.tab.id),
          sourcePaneId: PaneID(id: transfer.sourcePaneId),
          destination: destination
        )) ?? false
    }
    return false
  }

  private func updateDropZone(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard pane != nil, let controller, controller.isInteractive else {
      setDropZone(nil)
      return []
    }
    let pasteboard = sender.draggingPasteboard
    let hasTab =
      pasteboard.availableType(from: [
        NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
      ]) != nil
    let hasFiles = !Self.fileURLs(from: pasteboard).isEmpty
    guard hasTab || hasFiles else {
      setDropZone(nil)
      return []
    }
    let point = convert(sender.draggingLocation, from: nil)
    let defaultZone = zone(at: point)
    let permitsDefaultTab = permitsTabTransfer(
      hasTabTransfer: hasTab,
      zone: defaultZone
    )
    let handlesFiles = UnifiedPaneDropDelegate.shouldHandleFileDrop(
      hasTabTransfer: hasTab,
      hasFileURL: hasFiles,
      permitsTabTransfer: permitsDefaultTab
    )
    let zone = handlesFiles ? defaultZone : effectiveTabDropZone(defaultZone)
    let permitsTab = permitsTabTransfer(hasTabTransfer: hasTab, zone: zone)
    if !handlesFiles, !permitsTab {
      setDropZone(nil)
      return []
    }
    guard
      UnifiedPaneDropDelegate.acceptedDropZone(
        zone,
        isFileDropOnly: handlesFiles,
        hasExternalFileDropHandler: controller.onExternalFileDrop != nil,
        hasLegacyFileDropHandler: controller.onFileDrop != nil
      ) != nil
    else {
      setDropZone(nil)
      return []
    }
    setDropZone(zone)
    return handlesFiles ? .copy : .move
  }

  private func permitsTabTransfer(hasTabTransfer: Bool, zone: DropZone) -> Bool {
    guard hasTabTransfer, let pane, let controller else { return false }
    let internalController = controller.internalController
    let source = internalController.activeDragSourcePaneId ?? internalController.dragSourcePaneId
    if zone == .center, source == pane.id { return true }
    return controller.configuration.allowCrossPaneTabMove
  }

  private func effectiveTabDropZone(_ defaultZone: DropZone) -> DropZone {
    guard let pane, let controller else { return defaultZone }
    let internalController = controller.internalController
    guard let tab = internalController.activeDragTab ?? internalController.draggingTab,
      let source = internalController.activeDragSourcePaneId
        ?? internalController.dragSourcePaneId,
      tab.kind == "terminal",
      source != pane.id
    else { return defaultZone }
    if defaultZone == .left,
      controller.adjacentPane(to: source, direction: .right) == pane.id
    {
      return .center
    }
    if defaultZone == .right,
      controller.adjacentPane(to: source, direction: .left) == pane.id
    {
      return .center
    }
    return defaultZone
  }

  #if DEBUG
    func effectiveTabDropZoneForTesting(_ defaultZone: DropZone) -> DropZone {
      effectiveTabDropZone(defaultZone)
    }
  #endif

  private func zone(at point: NSPoint) -> DropZone {
    let local = contentHost.convert(point, from: self)
    let size = contentHost.bounds.size
    let horizontalEdge = max(80, size.width * 0.25)
    let verticalEdge = max(80, size.height * 0.25)
    if local.x < horizontalEdge { return .left }
    if local.x > size.width - horizontalEdge { return .right }
    if local.y < verticalEdge { return .top }
    if local.y > size.height - verticalEdge { return .bottom }
    return .center
  }

  private func setDropZone(_ zone: DropZone?) {
    guard activeDropZone != zone else { return }
    activeDropZone = zone
    dropOverlay.zone = zone
    dropOverlay.isHidden = zone == nil
    (contentController as? BonsplitPaneDropZoneReceiving)?.bonsplitPaneDropZoneDidChange(zone)
  }

  private func destination(
    for zone: DropZone,
    pane: PaneID
  ) -> BonsplitController.ExternalTabDropRequest.Destination {
    if zone == .center { return .insert(targetPane: pane, targetIndex: nil) }
    return .split(
      targetPane: pane,
      orientation: zone.orientation ?? .horizontal,
      insertFirst: zone.insertsFirst
    )
  }

  private static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
    UnifiedPaneDropDelegate.fileURLs(from: pasteboard)
  }

  private static func decodeTransfer(from pasteboard: NSPasteboard) -> TabTransferData? {
    let type = NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
    if let data = pasteboard.data(forType: type),
      let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data)
    {
      return transfer
    }
    guard let raw = pasteboard.string(forType: type),
      let data = raw.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode(TabTransferData.self, from: data)
  }
}

@MainActor
private final class BonsplitFlippedView: NSView {
  override var isFlipped: Bool { true }
}

@MainActor
private final class BonsplitDropOverlayView: NSView {
  var zone: DropZone? { didSet { needsDisplay = true } }
  override var isFlipped: Bool { true }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let zone else { return }
    let padding: CGFloat = 4
    var rect = bounds.insetBy(dx: padding, dy: padding)
    switch zone {
    case .center: break
    case .left: rect.size.width *= 0.5
    case .right:
      rect.origin.x += rect.width * 0.5
      rect.size.width *= 0.5
    case .top: rect.size.height *= 0.5
    case .bottom:
      rect.origin.y += rect.height * 0.5
      rect.size.height *= 0.5
    }
    NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    NSColor.controlAccentColor.setStroke()
    let border = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
    border.lineWidth = 2
    border.stroke()
  }
}

@MainActor
final class BonsplitNativeTabBarView: NSView, BonsplitTabItemHitRegionProviding {
  private weak var pane: PaneState?
  private weak var controller: BonsplitController?
  private let scrollView = NSScrollView()
  private let documentView = BonsplitTabDocumentView()
  private let selectionChrome = TabBarSelectionChromeView.ChromeNSView()
  private let actionChrome = BonsplitActionLaneChromeView()
  private let actionLane = BonsplitActionButtonLaneView()
  private let geometryRegistry = TabBarItemGeometryRegistry()
  private let shortcutMonitor = TabControlShortcutKeyMonitor()
  private let contentMask = CAGradientLayer()
  private var tabViews: [UUID: BonsplitNativeTabView] = [:]
  private var actionButtons: [BonsplitActionButton] = []
  private var dropTargetIndex: Int?
  private var lastRevealedSelection: UUID?
  private var selectionNeedsReveal = false
  private var lastViewportWidth: CGFloat?
  private var trackingArea: NSTrackingArea?
  private var isHovering = false

  var scrollViewForTesting: NSScrollView { scrollView }
  var tabViewsForTesting: [UUID: BonsplitNativeTabView] { tabViews }
  var actionButtonsForTesting: [BonsplitActionButton] { actionButtons }
  var actionLaneVisibleForTesting: Bool { !actionLane.isHidden }

  override var isFlipped: Bool { true }
  override var mouseDownCanMoveWindow: Bool {
    UserDefaults.standard.string(forKey: "workspacePresentationMode") == "minimal"
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.documentView = documentView
    scrollView.wantsLayer = true
    contentMask.startPoint = CGPoint(x: 0, y: 0.5)
    contentMask.endPoint = CGPoint(x: 1, y: 0.5)
    scrollView.layer?.mask = contentMask
    selectionChrome.geometryRegistry = geometryRegistry
    geometryRegistry.registerObserver(selectionChrome)
    geometryRegistry.attachScrollView(scrollView)
    addSubview(scrollView)
    addSubview(actionChrome)
    addSubview(selectionChrome)
    addSubview(actionLane)
    shortcutMonitor.onChange = { [weak self] in
      self?.configureTabs()
      self?.needsLayout = true
    }
    registerForDraggedTypes([
      NSPasteboard.PasteboardType(UTType.tabTransfer.identifier),
      .fileURL,
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  isolated deinit {
    shortcutMonitor.stop()
    BonsplitTabBarHitRegionRegistry.unregister(self)
    BonsplitTabItemHitRegionRegistry.unregister(self)
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
    isHovering = true
    needsLayout = true
  }

  override func mouseExited(with event: NSEvent) {
    isHovering = false
    needsLayout = true
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    shortcutMonitor.setHostWindow(window)
    BonsplitTabBarHitRegionRegistry.unregister(self)
    BonsplitTabItemHitRegionRegistry.unregister(self)
    if window != nil {
      shortcutMonitor.start()
      BonsplitTabBarHitRegionRegistry.register(self)
      BonsplitTabItemHitRegionRegistry.register(self)
    } else {
      shortcutMonitor.stop()
    }
  }

  func containsBonsplitTabItemHit(localPoint: NSPoint) -> Bool {
    tabViews.values.contains { tabView in
      convert(tabView.bounds, from: tabView)
        .insetBy(dx: -10, dy: -6)
        .contains(localPoint)
    }
  }

  func configure(pane: PaneState, controller: BonsplitController) {
    self.pane = pane
    self.controller = controller
    layer?.backgroundColor =
      TabBarColors.nsColorBarBackground(
        for: controller.configuration.appearance
      ).cgColor
    configureTabs()
    configureActions()
    needsLayout = true
  }

  private func configureTabs() {
    guard let pane, let controller else { return }
    let isFocused =
      controller.internalController.focusedPaneId == pane.id
      || controller.internalController.dragSourcePaneId == pane.id
    let showsShortcutHints =
      isFocused
      && controller.internalController.tabShortcutHintsEnabled
      && shortcutMonitor.isShortcutHintVisible
    let shownTabs: [TabItem]
    if pane.isFullWidthTabMode, let selected = pane.selectedTab ?? pane.tabs.first {
      shownTabs = [selected]
    } else {
      shownTabs = pane.tabs
    }
    let live = Set(shownTabs.map(\.id))
    for (id, view) in tabViews where !live.contains(id) {
      geometryRegistry.unregister(view, for: id)
      view.removeFromSuperview()
      tabViews[id] = nil
    }
    for (index, tab) in shownTabs.enumerated() {
      let tabView = tabViews[tab.id] ?? BonsplitNativeTabView()
      tabViews[tab.id] = tabView
      if tabView.superview == nil { documentView.addSubview(tabView) }
      geometryRegistry.register(tabView, for: tab.id)
      let originalIndex = pane.tabs.firstIndex(where: { $0.id == tab.id }) ?? index
      tabView.configure(
        tab: tab,
        index: originalIndex,
        pane: pane,
        controller: controller,
        showsZoomIndicator: controller.internalController.zoomedPaneId == pane.id
          && pane.selectedTabId == tab.id,
        isFocused: isFocused,
        shortcutDigit: Self.shortcutDigit(
          for: originalIndex,
          tabCount: pane.tabs.count
        ),
        showsShortcutHint: showsShortcutHints,
        shortcutModifierSymbol: shortcutMonitor.shortcutModifierSymbol
      )
    }
    if lastRevealedSelection != pane.selectedTabId {
      lastRevealedSelection = pane.selectedTabId
      selectionNeedsReveal = true
    }
  }

  private func configureActions() {
    actionButtons.forEach { $0.removeFromSuperview() }
    actionButtons.removeAll()
    guard let controller,
      controller.configuration.allowSplits,
      controller.configuration.appearance.showSplitButtons
    else { return }
    for descriptor in controller.configuration.appearance.splitButtons {
      let button = BonsplitActionButton(
        title: "",
        target: self,
        action: #selector(performAction(_:))
      )
      button.identifier = NSUserInterfaceItemIdentifier(descriptor.id)
      button.bezelStyle = .inline
      button.isBordered = false
      button.imagePosition = .imageOnly
      button.image = image(for: descriptor.icon)
      button.activatesOnMouseDown = descriptor.activatesOnMouseDown
      button.contentTintColor = TabBarColors.nsColorInactiveText(
        for: controller.configuration.appearance)
      button.toolTip = tooltip(for: descriptor)
      button.tag = actionButtons.count
      button.setAccessibilityIdentifier(accessibilityIdentifier(for: descriptor.action))
      actionLane.addButton(button)
      actionButtons.append(button)
    }
  }

  override func layout() {
    super.layout()
    guard let pane, let controller else { return }
    let appearance = controller.configuration.appearance
    let ordered =
      pane.isFullWidthTabMode
      ? pane.tabs.filter { $0.id == (pane.selectedTab ?? pane.tabs.first)?.id }
      : pane.tabs
    let isMinimalMode =
      UserDefaults.standard.string(forKey: "workspacePresentationMode") == "minimal"
    let shouldShowActions =
      !actionButtons.isEmpty
      && (!isMinimalMode || isHovering)
      && (!appearance.splitButtonsOnHover || isHovering)
    let naturalWidths = ordered.map {
      tabViews[$0.id]?.preferredNaturalWidth
        ?? naturalWidth(for: $0, appearance: appearance)
    }
    let naturalContentWidth =
      naturalWidths.reduce(0, +)
      + CGFloat(max(0, ordered.count - 1)) * appearance.tabSpacing
    let availableWidth = max(0, bounds.width - appearance.tabBarLeadingInset)
    let barLayout = TabBarLayout(
      tabBarHeight: bounds.height,
      availableWidth: availableWidth,
      tabContentWidthExcludingSplitButtonLane: naturalContentWidth,
      splitButtonCount: actionButtons.count,
      splitButtonLaneVisible: shouldShowActions,
      reservesSplitButtonLane: !isMinimalMode,
      measuredSplitButtonLaneWidth: TabBarStyling.splitButtonsBackdropWidth(
        buttonCount: actionButtons.count
      )
    )
    let isFocused =
      controller.internalController.focusedPaneId == pane.id
      || controller.internalController.dragSourcePaneId == pane.id
    let snapshot = TabBarChromeSnapshot(
      appearance: appearance,
      layout: barLayout,
      isFocused: isFocused,
      shouldShowSplitButtons: shouldShowActions,
      fadeColorStyle: UserDefaults.standard.integer(forKey: "debugFadeColorStyle")
    )
    let laneWidth = snapshot.actionLaneWidth
    actionLane.isHidden = !shouldShowActions
    actionLane.frame = NSRect(
      x: max(0, bounds.width - laneWidth),
      y: 0,
      width: laneWidth,
      height: bounds.height
    )
    actionLane.layoutButtons(actionButtons, barHeight: bounds.height)
    actionChrome.frame = bounds
    actionChrome.snapshot = snapshot
    selectionChrome.frame = bounds
    selectionChrome.selectedTabId = pane.selectedTabId
    selectionChrome.indicatorColor = TabBarColors.nsColorActiveIndicator(
      saturation: isFocused ? 1 : 0
    )
    selectionChrome.separatorColor = TabBarColors.nsColorSeparator(for: appearance)
    scrollView.frame = NSRect(
      x: appearance.tabBarLeadingInset,
      y: 0,
      width: availableWidth,
      height: bounds.height
    )
    layer?.backgroundColor = snapshot.barColor.cgColor
    let scrollOffset = scrollView.contentView.bounds.origin.x
    let documentWidthBeforeLayout = max(documentView.frame.width, documentView.bounds.width)
    let canScrollLeft = scrollOffset > 1
    let canScrollRight =
      documentWidthBeforeLayout > availableWidth + 4
      && scrollOffset < documentWidthBeforeLayout - availableWidth - 1
    let fadeWidth: CGFloat = 24
    selectionChrome.mask = TabBarSelectionChromeMask(
      leftFadeWidth: canScrollLeft ? fadeWidth : 0,
      rightFadeWidth: snapshot.masksTabContentUnderActionLane
        ? snapshot.contentFadeWidth
        : (canScrollRight ? fadeWidth : 0),
      rightOcclusionWidth: snapshot.masksTabContentUnderActionLane
        ? snapshot.contentOcclusionWidth
        : 0,
      actionLaneSeparatorFadeWidth: snapshot.drawsActionLaneSeparator
        ? snapshot.actionLaneGeometry.separatorFadeWidth
        : 0,
      actionLaneSeparatorSolidWidth: snapshot.drawsActionLaneSeparator
        ? snapshot.actionLaneGeometry.backgroundSolidWidth
        : 0,
      actionLaneSeparatorFadeRampStartFraction: snapshot.backdropFadeRampStartFraction
    )
    let fill = appearance.tabWidthMode == .fill || pane.isFullWidthTabMode
    let available = availableWidth
    let fillWidth =
      fill && naturalWidths.reduce(0, +) <= available && !ordered.isEmpty
      ? available / CGFloat(ordered.count)
      : 0
    var x: CGFloat = 0
    for (index, tab) in ordered.enumerated() {
      guard let tabView = tabViews[tab.id] else { continue }
      let width = fillWidth > 0 ? fillWidth : naturalWidths[index]
      tabView.frame = NSRect(x: x, y: 0, width: width, height: bounds.height)
      x += width + appearance.tabSpacing
      geometryRegistry.geometryDidChange(for: tab.id)
    }
    let trailingInset = barLayout.trailingTabContentInset
    let documentSize = NSSize(
      width: max(available, max(0, x - appearance.tabSpacing) + trailingInset),
      height: bounds.height
    )
    if abs(documentView.frame.width - documentSize.width) > 0.5
      || abs(documentView.frame.height - documentSize.height) > 0.5
    {
      documentView.setFrameSize(documentSize)
    }
    geometryRegistry.setTrailingObscuredWidth(trailingInset)
    if lastViewportWidth == nil || abs((lastViewportWidth ?? 0) - available) > 0.5 {
      lastViewportWidth = available
      geometryRegistry.viewportLayoutDidChange()
    }
    if selectionNeedsReveal {
      selectionNeedsReveal = false
      geometryRegistry.revealSelection(pane.selectedTabId)
    }
    updateContentMask(snapshot: snapshot)
    selectionChrome.needsDisplay = true
    actionChrome.needsDisplay = true
  }

  private func updateContentMask(snapshot: TabBarChromeSnapshot) {
    let width = max(1, scrollView.bounds.width)
    let offset = scrollView.contentView.bounds.origin.x
    let documentWidth = max(documentView.frame.width, documentView.bounds.width)
    let leftFade = offset > 1 ? min(24, width) : 0
    let rightFade: CGFloat
    let rightOcclusion: CGFloat
    if snapshot.masksTabContentUnderActionLane {
      rightFade = min(snapshot.contentFadeWidth, width)
      rightOcclusion = min(snapshot.contentOcclusionWidth, max(0, width - rightFade))
    } else if documentWidth > width + 4, offset < documentWidth - width - 1 {
      rightFade = min(24, width)
      rightOcclusion = 0
    } else {
      rightFade = 0
      rightOcclusion = 0
    }
    contentMask.frame = scrollView.bounds
    let opaque = CGColor(gray: 1, alpha: 1)
    let clear = CGColor(gray: 1, alpha: 0)
    var colors: [CGColor] = []
    var locations: [NSNumber] = []
    if leftFade > 0 {
      colors.append(clear)
      locations.append(0)
      colors.append(opaque)
      locations.append(NSNumber(value: Double(leftFade / width)))
    } else {
      colors.append(opaque)
      locations.append(0)
    }
    let rightEnd = max(0, width - rightOcclusion)
    let rightStart = max(leftFade, rightEnd - rightFade)
    colors.append(opaque)
    locations.append(NSNumber(value: Double(rightStart / width)))
    if rightFade > 0 || rightOcclusion > 0 {
      colors.append(clear)
      locations.append(NSNumber(value: Double(rightEnd / width)))
      colors.append(clear)
      locations.append(1)
    } else {
      colors.append(opaque)
      locations.append(1)
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    contentMask.colors = colors
    contentMask.locations = locations
    CATransaction.commit()
  }

  override func mouseDown(with event: NSEvent) {
    guard let pane, let controller else { return }
    if event.clickCount == 2,
      controller.configuration.appearance.splitButtons.contains(where: { $0.action == .newTerminal }
      )
    {
      controller.requestNewTab(kind: "terminal", inPane: pane.id)
    } else {
      controller.focusPane(pane.id)
      super.mouseDown(with: event)
    }
  }

  override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
  override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
  override func draggingExited(_ sender: NSDraggingInfo?) { setDropTarget(nil) }
  override func draggingEnded(_ sender: NSDraggingInfo) { setDropTarget(nil) }
  override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    updateDrag(sender) != []
  }

  override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    guard let pane, let controller, let target = dropTargetIndex else { return false }
    defer { setDropTarget(nil) }
    let internalController = controller.internalController
    let pasteboard = sender.draggingPasteboard
    let tabType = NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
    let hasTab = pasteboard.availableType(from: [tabType]) != nil
    let urls = UnifiedPaneDropDelegate.fileURLs(from: pasteboard)
    let hasFiles = !urls.isEmpty
    let permitsTab = permitsTabTransfer(hasTabTransfer: hasTab, pasteboard: pasteboard)
    if UnifiedPaneDropDelegate.shouldHandleFileDrop(
      hasTabTransfer: hasTab,
      hasFileURL: hasFiles,
      permitsTabTransfer: permitsTab
    ) {
      let destination: BonsplitController.ExternalTabDropRequest.Destination = .insert(
        targetPane: pane.id,
        targetIndex: target
      )
      return controller.onExternalFileDrop?(.init(urls: urls, destination: destination))
        ?? controller.onFileDrop?(urls, pane.id)
        ?? false
    }
    guard permitsTab else { return false }
    if let dragged = internalController.activeDragTab ?? internalController.draggingTab,
      let source = internalController.activeDragSourcePaneId ?? internalController.dragSourcePaneId
    {
      internalController.clearTabDragState()
      if source == pane.id {
        guard controller.configuration.allowTabReordering,
          let sourceIndex = pane.tabs.firstIndex(where: { $0.id == dragged.id })
        else { return false }
        if target == sourceIndex || target == sourceIndex + 1 { return true }
        let before = pane.tabs.map(\.id)
        pane.moveTab(from: sourceIndex, to: target)
        if before != pane.tabs.map(\.id) {
          controller.delegate?.splitTabBar(
            controller,
            didReorderTabsInPane: pane.id,
            orderedTabIds: pane.tabs.map { TabID(id: $0.id) }
          )
        }
        return true
      }
      guard controller.configuration.allowCrossPaneTabMove else { return false }
      return controller.moveTab(TabID(id: dragged.id), toPane: pane.id, atIndex: target)
    }

    if let transfer = Self.decodeTransfer(from: pasteboard),
      transfer.isFromCurrentProcess,
      controller.configuration.allowCrossPaneTabMove
    {
      return controller.onExternalTabDrop?(
        .init(
          tabId: TabID(id: transfer.tab.id),
          sourcePaneId: PaneID(id: transfer.sourcePaneId),
          destination: .insert(targetPane: pane.id, targetIndex: target)
        )) ?? false
    }
    return false
  }

  private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
    guard let pane, let controller, controller.isInteractive else { return [] }
    let pasteboard = sender.draggingPasteboard
    let tabType = NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
    let hasTab = pasteboard.availableType(from: [tabType]) != nil
    let urls = UnifiedPaneDropDelegate.fileURLs(from: pasteboard)
    let hasFiles = !urls.isEmpty
    guard hasTab || hasFiles else {
      setDropTarget(nil)
      return []
    }
    let permitsTab = permitsTabTransfer(hasTabTransfer: hasTab, pasteboard: pasteboard)
    let handlesFiles = UnifiedPaneDropDelegate.shouldHandleFileDrop(
      hasTabTransfer: hasTab,
      hasFileURL: hasFiles,
      permitsTabTransfer: permitsTab
    )
    if handlesFiles,
      controller.onExternalFileDrop == nil,
      controller.onFileDrop == nil
    {
      setDropTarget(nil)
      return []
    }
    guard handlesFiles || permitsTab else {
      setDropTarget(nil)
      return []
    }
    let internalController = controller.internalController
    let point = documentView.convert(sender.draggingLocation, from: nil)
    let ordered = pane.tabs.compactMap { tabViews[$0.id] }
    let target = ordered.firstIndex { point.x < $0.frame.midX } ?? pane.tabs.count
    setDropTarget(target, suppressIndicator: !handlesFiles && isNoopSamePaneDrop(target: target))
    _ = internalController
    return handlesFiles ? .copy : .move
  }

  private func setDropTarget(_ target: Int?, suppressIndicator: Bool = false) {
    dropTargetIndex = target
    documentView.dropIndicatorX =
      suppressIndicator
      ? nil
      : target.flatMap { index in
        guard let pane else { return nil }
        if pane.tabs.indices.contains(index), let view = tabViews[pane.tabs[index].id] {
          return view.frame.minX
        }
        return pane.tabs.last.flatMap { tabViews[$0.id]?.frame.maxX }
      }
  }

  private func permitsTabTransfer(
    hasTabTransfer: Bool,
    pasteboard: NSPasteboard
  ) -> Bool {
    guard hasTabTransfer, let pane, let controller else { return false }
    let internalController = controller.internalController
    if let source = internalController.activeDragSourcePaneId
      ?? internalController.dragSourcePaneId
    {
      return source == pane.id
        ? controller.configuration.allowTabReordering
        : controller.configuration.allowCrossPaneTabMove
    }
    return controller.configuration.allowCrossPaneTabMove
      && Self.decodeTransfer(from: pasteboard)?.isFromCurrentProcess == true
  }

  private func isNoopSamePaneDrop(target: Int) -> Bool {
    guard let pane, let controller else { return false }
    let internalController = controller.internalController
    guard let dragged = internalController.activeDragTab ?? internalController.draggingTab,
      (internalController.activeDragSourcePaneId ?? internalController.dragSourcePaneId) == pane.id,
      let sourceIndex = pane.tabs.firstIndex(where: { $0.id == dragged.id })
    else {
      return false
    }
    return target == sourceIndex || target == sourceIndex + 1
  }

  private static func decodeTransfer(from pasteboard: NSPasteboard) -> TabTransferData? {
    let type = NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
    if let data = pasteboard.data(forType: type),
      let transfer = try? JSONDecoder().decode(TabTransferData.self, from: data)
    {
      return transfer
    }
    guard let raw = pasteboard.string(forType: type),
      let data = raw.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode(TabTransferData.self, from: data)
  }

  private func naturalWidth(for tab: TabItem, appearance: BonsplitConfiguration.Appearance)
    -> CGFloat
  {
    if TabItemStyling.isIconOnlyPinned(isPinned: tab.isPinned, kind: tab.kind) {
      return TabItemStyling.pinnedIconOnlyWidth(iconSlotSize: 14, horizontalPadding: 6)
    }
    let title = (tab.title as NSString).size(withAttributes: [
      .font: NSFont.systemFont(ofSize: appearance.tabTitleFontSize)
    ]).width
    let hasLeadingIcon =
      tab.isLoading
      || tab.icon != nil
      || tab.iconAsset != nil
      || tab.iconImageData != nil
    let chromeWidth: CGFloat = hasLeadingIcon ? 44 : 38
    return min(max(TabBarMetrics.tabMinWidth, title + chromeWidth), max(48, appearance.tabMaxWidth))
  }

  private func image(for icon: BonsplitConfiguration.SplitActionButton.Icon) -> NSImage? {
    switch icon {
    case .systemImage(let name):
      let resolved = TabBarStyling.splitActionSystemImage(for: name)
      guard
        let image = NSImage(
          systemSymbolName: resolved.name,
          accessibilityDescription: nil
        )?.withSymbolConfiguration(.init(pointSize: resolved.pointSize, weight: .regular))
      else {
        return nil
      }
      return Self.rotatedImage(image, degrees: resolved.rotationDegrees)
    case .emoji(let value, let scale):
      let image = NSImage(size: NSSize(width: 18, height: 18))
      image.lockFocus()
      let font = NSFont.systemFont(ofSize: 14 * CGFloat(scale))
      let attributes: [NSAttributedString.Key: Any] = [.font: font]
      let size = (value as NSString).size(withAttributes: attributes)
      (value as NSString).draw(
        at: NSPoint(x: (18 - size.width) * 0.5, y: (18 - size.height) * 0.5),
        withAttributes: attributes
      )
      image.unlockFocus()
      return image
    case .imageData(let data):
      guard let image = TabBarStyling.splitActionButtonImage(from: data) else { return nil }
      image.isTemplate = TabBarStyling.imageDataShouldRenderAsTemplate(data)
      return image
    }
  }

  private func tooltip(for descriptor: BonsplitConfiguration.SplitActionButton) -> String {
    if let value = descriptor.tooltip?.trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    {
      return value
    }
    guard let controller else { return descriptor.id }
    let tooltips = controller.configuration.appearance.splitButtonTooltips
    switch descriptor.action {
    case .newTerminal: return tooltips.newTerminal
    case .newBrowser: return tooltips.newBrowser
    case .splitRight: return tooltips.splitRight
    case .splitDown: return tooltips.splitDown
    case .custom(let value): return value
    }
  }

  @objc private func performAction(_ sender: NSButton) {
    guard let pane, let controller, controller.isInteractive,
      controller.configuration.appearance.splitButtons.indices.contains(sender.tag)
    else { return }
    let action = controller.configuration.appearance.splitButtons[sender.tag].action
    switch action {
    case .newTerminal: controller.requestNewTab(kind: "terminal", inPane: pane.id)
    case .newBrowser: controller.requestNewTab(kind: "browser", inPane: pane.id)
    case .splitRight: _ = controller.splitPane(pane.id, orientation: .horizontal)
    case .splitDown: _ = controller.splitPane(pane.id, orientation: .vertical)
    case .custom(let id): controller.requestCustomAction(id, inPane: pane.id)
    }
  }

  private func accessibilityIdentifier(
    for action: BonsplitConfiguration.SplitActionButton.Action
  ) -> String {
    switch action {
    case .newTerminal: "paneTabBarControl.newTerminal"
    case .newBrowser: "paneTabBarControl.newBrowser"
    case .splitRight: "paneTabBarControl.splitRight"
    case .splitDown: "paneTabBarControl.splitDown"
    case .custom(let id): "paneTabBarControl.custom.\(id)"
    }
  }

  private static func shortcutDigit(for index: Int, tabCount: Int) -> Int? {
    guard tabCount > 0 else { return nil }
    for digit in 1...9 where shortcutIndex(for: digit, tabCount: tabCount) == index {
      return digit
    }
    return nil
  }

  private static func shortcutIndex(for digit: Int, tabCount: Int) -> Int? {
    guard (1...9).contains(digit), tabCount > 0 else { return nil }
    if digit == 9 { return tabCount - 1 }
    let index = digit - 1
    return index < tabCount ? index : nil
  }

  private static func rotatedImage(_ image: NSImage, degrees: Double) -> NSImage {
    guard abs(degrees) > 0.001 else { return image }
    let size = image.size
    let rotated = NSImage(size: size)
    rotated.lockFocus()
    let transform = NSAffineTransform()
    transform.translateX(by: size.width * 0.5, yBy: size.height * 0.5)
    transform.rotate(byDegrees: degrees)
    transform.translateX(by: -size.width * 0.5, yBy: -size.height * 0.5)
    transform.concat()
    image.draw(in: NSRect(origin: .zero, size: size))
    rotated.unlockFocus()
    rotated.isTemplate = image.isTemplate
    return rotated
  }
}

@MainActor
private final class BonsplitActionLaneChromeView: NSView {
  var snapshot: TabBarChromeSnapshot? {
    didSet { needsDisplay = true }
  }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { false }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let snapshot, snapshot.paintsActionLaneSurface else { return }
    let geometry = snapshot.actionLaneGeometry
    let fadeFrame = geometry.backgroundFadeFrame(
      totalWidth: bounds.width,
      height: bounds.height
    )
    if fadeFrame.width > 0 {
      let rampStart = min(max(snapshot.backdropFadeRampStartFraction, 0), 0.95)
      let gradient = NSGradient(
        colorsAndLocations: (snapshot.backdropLeadingColor, 0),
        (snapshot.backdropLeadingColor, rampStart),
        (snapshot.backdropTrailingColor, 1)
      )
      gradient?.draw(in: fadeFrame, angle: 0)
    }
    let solidFrame = geometry.backgroundSolidFrame(
      totalWidth: bounds.width,
      height: bounds.height
    )
    if solidFrame.width > 0 {
      snapshot.backdropTrailingColor.setFill()
      solidFrame.fill()
    }
  }
}

@MainActor
final class BonsplitActionButton: NSButton {
  var activatesOnMouseDown = false

  override func mouseDown(with event: NSEvent) {
    guard activatesOnMouseDown else {
      super.mouseDown(with: event)
      return
    }
    guard isEnabled, action != nil else { return }
    highlight(true)
    defer { highlight(false) }
    sendAction(action, to: target)
  }
}

@MainActor
private final class BonsplitActionButtonLaneView: NSView {
  private let scrollView = NSScrollView()
  private let document = BonsplitFlippedView()

  override var isFlipped: Bool { true }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = true
    scrollView.drawsBackground = false
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = false
    scrollView.horizontalScrollElasticity = .none
    scrollView.verticalScrollElasticity = .none
    scrollView.documentView = document
    addSubview(scrollView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func addButton(_ button: NSButton) {
    document.addSubview(button)
  }

  func layoutButtons(_ buttons: [NSButton], barHeight: CGFloat) {
    scrollView.frame = bounds
    let width = TabBarStyling.splitButtonsBackdropWidth(buttonCount: buttons.count)
    document.setFrameSize(NSSize(width: max(bounds.width, width), height: barHeight))
    for (index, button) in buttons.enumerated() {
      button.frame = NSRect(
        x: TabBarStyling.splitButtonsLeadingPadding
          + CGFloat(index)
          * (TabBarStyling.splitActionButtonReservedWidth
            + TabBarStyling.splitButtonsSpacing),
        y: 4,
        width: TabBarStyling.splitActionButtonReservedWidth,
        height: max(18, barHeight - 8)
      )
    }
    let maximumOffset = max(0, document.frame.width - bounds.width)
    let currentOffset = min(max(scrollView.contentView.bounds.origin.x, 0), maximumOffset)
    if abs(currentOffset - scrollView.contentView.bounds.origin.x) > 0.5 {
      scrollView.contentView.scroll(to: NSPoint(x: currentOffset, y: 0))
      scrollView.reflectScrolledClipView(scrollView.contentView)
    }
  }
}

@MainActor
final class BonsplitTabDocumentView: NSView {
  var dropIndicatorX: CGFloat? { didSet { needsDisplay = true } }
  override var isFlipped: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let x = dropIndicatorX else { return }
    NSColor.controlAccentColor.setFill()
    NSRect(x: x - 1, y: 5, width: 2, height: max(0, bounds.height - 10)).fill()
  }
}
