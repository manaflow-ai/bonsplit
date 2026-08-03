import AppKit
import Observation
import UniformTypeIdentifiers
import XCTest
import os

@testable import Bonsplit

@MainActor
final class NativeRendererRegressionTests: XCTestCase {
  private final class NewTabRequestSpy: BonsplitDelegate {
    var requestedKind: String?
    var requestedPane: PaneID?

    func splitTabBar(
      _ controller: BonsplitController,
      didRequestNewTab kind: String,
      inPane pane: PaneID
    ) {
      requestedKind = kind
      requestedPane = pane
    }
  }

  private final class CustomActionSpy: BonsplitDelegate {
    var identifier: String?
    var pane: PaneID?

    func splitTabBar(
      _ controller: BonsplitController,
      didRequestCustomAction identifier: String,
      inPane pane: PaneID
    ) {
      self.identifier = identifier
      self.pane = pane
    }
  }

  private final class InvalidationFlag: Sendable {
    private let storage = OSAllocatedUnfairLock(initialState: false)

    var value: Bool {
      get { storage.withLock { $0 } }
      set { storage.withLock { $0 = newValue } }
    }
  }

  private final class LayoutProbeView: NSView {
    private(set) var sizeChangeCount = 0
    private(set) var originChangeCount = 0

    override func setFrameSize(_ newSize: NSSize) {
      if frame.size != newSize { sizeChangeCount += 1 }
      super.setFrameSize(newSize)
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
      if frame.origin != newOrigin { originChangeCount += 1 }
      super.setFrameOrigin(newOrigin)
    }
  }

  func testNoopTabUpdateDoesNotInvalidateObservedTabMetadata() {
    let controller = BonsplitController()
    let tabID = controller.createTab(
      title: "Original",
      hasCustomTitle: true,
      icon: "doc",
      iconAsset: "AgentIcons/Claude",
      kind: "terminal",
      isDirty: true,
      showsNotificationBadge: true,
      isLoading: true,
      isAudioMuted: true,
      isAudioPlaying: true,
      isPinned: true
    )!
    let invalidated = InvalidationFlag()
    withObservationTracking {
      _ = controller.tab(tabID)
    } onChange: {
      invalidated.value = true
    }

    controller.updateTab(
      tabID,
      title: "Original",
      icon: .some("doc"),
      iconAsset: .some("AgentIcons/Claude"),
      kind: .some("terminal"),
      hasCustomTitle: true,
      isDirty: true,
      showsNotificationBadge: true,
      isLoading: true,
      isAudioMuted: true,
      isAudioPlaying: true,
      isPinned: true
    )

    XCTAssertFalse(invalidated.value)
  }

  func testDoubleClickingEmptyTrailingTabBarSpaceRequestsNewTerminalTab() throws {
    let controller = BonsplitController()
    let spy = NewTabRequestSpy()
    controller.delegate = spy
    let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)

    try withRenderer(controller: controller, size: NSSize(width: 480, height: 180)) { root, _, _ in
      let tabBar = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeTabBarView.self, in: root))
      let event = try makeMouseEvent(
        type: .leftMouseDown,
        in: tabBar,
        at: NSPoint(x: 280, y: tabBar.bounds.midY),
        clickCount: 2
      )
      tabBar.mouseDown(with: event)
    }

    XCTAssertEqual(spy.requestedKind, "terminal")
    XCTAssertEqual(spy.requestedPane, pane.id)
  }

  func testEmptyTrailingTabBarSpaceDoesNotRequestNewTerminalWhenButtonHidden() throws {
    let controller = BonsplitController(
      configuration: .init(
        appearance: .init(splitButtons: [])
      ))
    let spy = NewTabRequestSpy()
    controller.delegate = spy

    try withRenderer(controller: controller, size: NSSize(width: 480, height: 180)) { root, _, _ in
      let tabBar = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeTabBarView.self, in: root))
      let event = try makeMouseEvent(
        type: .leftMouseDown,
        in: tabBar,
        at: NSPoint(x: 280, y: tabBar.bounds.midY),
        clickCount: 2
      )
      tabBar.mouseDown(with: event)
    }

    XCTAssertNil(spy.requestedKind)
    XCTAssertNil(spy.requestedPane)
  }

  func testTrailingTabBarChromeRoutesTabDropsAcrossFullWidth() throws {
    let controller = BonsplitController(
      configuration: .init(
        appearance: .init(splitButtons: [])
      ))

    try withRenderer(controller: controller, size: NSSize(width: 480, height: 180)) { root, _, _ in
      let tabBar = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeTabBarView.self, in: root))
      let transferType = NSPasteboard.PasteboardType(UTType.tabTransfer.identifier)
      XCTAssertTrue(tabBar.registeredDraggedTypes.contains(transferType))
      XCTAssertEqual(tabBar.bounds.width, 480, accuracy: 0.5)
      for point in [
        NSPoint(x: 90, y: 15),
        NSPoint(x: 240, y: 15),
        NSPoint(x: 460, y: 15),
      ] {
        let hit = try XCTUnwrap(tabBar.hitTest(point))
        let routesThroughTabBar = sequence(first: Optional(hit), next: { $0?.superview })
          .contains { $0 === tabBar }
        XCTAssertTrue(routesThroughTabBar, "Expected native drop routing at x=\(point.x)")
      }
    }
  }

  func testShortConfiguredTabKeepsCompactChromeWithExpandedHitSlop() throws {
    let appearance = BonsplitConfiguration.Appearance(
      tabMinWidth: 140,
      tabMaxWidth: 220,
      splitButtons: []
    )
    let controller = BonsplitController(configuration: .init(appearance: appearance))
    controller.tabShortcutHintsEnabled = false
    let pane = try XCTUnwrap(controller.internalController.rootNode.allPanes.first)
    let tab = TabItem(title: "~", icon: "terminal.fill")
    pane.tabs = [tab]
    pane.selectedTabId = tab.id

    try withRenderer(controller: controller, size: NSSize(width: 360, height: 180)) {
      root, window, _ in
      let tabBar = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeTabBarView.self, in: root))
      let tabView = try XCTUnwrap(tabBar.tabViewsForTesting[tab.id])
      XCTAssertLessThan(tabView.frame.width, appearance.tabMinWidth)
      let frameInWindow = tabView.convert(tabView.bounds, to: nil)
      let expandedPoint = NSPoint(
        x: frameInWindow.maxX + BonsplitTabItemHitTesting.horizontalSlop - 2,
        y: frameInWindow.midY
      )
      XCTAssertTrue(BonsplitTabItemHitRegionRegistry.containsWindowPoint(expandedPoint, in: window))
    }
  }

  func testPaneDropOverlayDoesNotResizeHostedContentDuringHover() throws {
    let controller = BonsplitController()
    let probe = LayoutProbeView()
    let child = NSViewController()
    child.view = probe

    try withRenderer(
      controller: controller,
      size: NSSize(width: 320, height: 240),
      content: { _, _ in child }
    ) { root, window, _ in
      let paneView = try XCTUnwrap(firstDescendant(ofType: BonsplitPaneView.self, in: root))
      let initialFrame = probe.frame
      let initialSizeChanges = probe.sizeChangeCount
      let initialOriginChanges = probe.originChangeCount

      paneView.setDropZoneForTesting(.left)
      settle(window: window, root: root)
      XCTAssertEqual(probe.frame, initialFrame)
      XCTAssertEqual(probe.sizeChangeCount, initialSizeChanges)
      XCTAssertEqual(probe.originChangeCount, initialOriginChanges)

      paneView.setDropZoneForTesting(.bottom)
      settle(window: window, root: root)
      XCTAssertEqual(probe.frame, initialFrame)
      XCTAssertEqual(probe.sizeChangeCount, initialSizeChanges)
      XCTAssertEqual(probe.originChangeCount, initialOriginChanges)
    }
  }

  func testSyncRestoresDividerThatDriftedOutsideConfiguredRange() throws {
    let controller = BonsplitController(
      configuration: .init(
        dividerPositionRange: 0.4...0.6,
        appearance: .init(enableAnimations: false)
      ))
    _ = controller.createTab(title: "Base")
    let sourcePane = try XCTUnwrap(controller.focusedPaneId)
    XCTAssertNotNil(
      controller.splitPane(
        sourcePane,
        orientation: .horizontal,
        initialDividerPosition: 0.4
      ))

    try withRenderer(controller: controller, size: NSSize(width: 800, height: 600)) {
      root, window, _ in
      let splitView = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeSplitView.self, in: root))
      let available = max(splitView.bounds.width - splitView.dividerThickness, 1)
      splitView.setPosition(available * 0.2, ofDividerAt: 0)
      settle(window: window, root: root)
      XCTAssertEqual(
        splitView.arrangedSubviews[0].frame.width / available,
        0.4,
        accuracy: 0.02
      )
      guard case .split(let state) = controller.treeSnapshot() else {
        return XCTFail("Expected split root")
      }
      XCTAssertEqual(state.dividerPosition, 0.4, accuracy: 0.0001)
    }
  }

  func testReimposingSameExtentAfterContainerResizeRetargetsExactly() throws {
    let (controller, splitID) = try makeImposedSplitController()
    try withRenderer(controller: controller, size: NSSize(width: 400, height: 300)) {
      root, window, _ in
      let splitView = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeSplitView.self, in: root))
      @MainActor func settleImposed(_ extent: CGFloat) -> CGFloat {
        _ = controller.setImposedFirstExtent(extent, forSplit: splitID, fromExternal: true)
        settle(window: window, root: root, passes: 12)
        return splitView.arrangedSubviews[0].frame.width
      }

      let imposed: CGFloat = 120
      XCTAssertEqual(settleImposed(imposed), imposed, accuracy: 1.5)
      window.setContentSize(NSSize(width: 300, height: 300))
      window.contentView?.layoutSubtreeIfNeeded()
      splitView.layoutSubtreeIfNeeded()
      XCTAssertLessThan(splitView.arrangedSubviews[0].frame.width, imposed - 4)
      settle(window: window, root: root, passes: 12)
      XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, imposed, accuracy: 1.5)

      let perturbed: CGFloat = 200
      splitView.setPosition(perturbed, ofDividerAt: 0)
      splitView.layoutSubtreeIfNeeded()
      XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, perturbed, accuracy: 1.5)
      settle(window: window, root: root, passes: 6)
      XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, perturbed, accuracy: 1.5)
      XCTAssertEqual(settleImposed(imposed), imposed, accuracy: 1.5)
    }
  }

  func testImposeDuringDragSessionDefersUntilSessionEnds() throws {
    let (controller, splitID) = try makeImposedSplitController()
    try withRenderer(controller: controller, size: NSSize(width: 400, height: 300)) {
      root, window, _ in
      let splitView = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeSplitView.self, in: root))
      let widthBefore = splitView.arrangedSubviews[0].frame.width
      let imposed: CGFloat = 120
      XCTAssertGreaterThan(abs(widthBefore - imposed), 20)

      controller.noteDividerDragSession(true)
      XCTAssertTrue(controller.setImposedFirstExtent(imposed, forSplit: splitID))
      settle(window: window, root: root, passes: 6)
      XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, widthBefore, accuracy: 1.5)

      controller.noteDividerDragSession(false)
      settle(window: window, root: root, passes: 12)
      XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, imposed, accuracy: 1.5)
    }
  }

  func testImposedExtentReappliesAfterContainerResizeWithoutFreshImposition() throws {
    let (controller, splitID) = try makeImposedSplitController()
    try withRenderer(controller: controller, size: NSSize(width: 400, height: 300)) {
      root, window, _ in
      let splitView = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeSplitView.self, in: root))
      let imposed: CGFloat = 120
      XCTAssertTrue(controller.setImposedFirstExtent(imposed, forSplit: splitID))
      settle(window: window, root: root, passes: 12)
      XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, imposed, accuracy: 1.5)

      window.setContentSize(NSSize(width: 640, height: 300))
      window.contentView?.layoutSubtreeIfNeeded()
      splitView.layoutSubtreeIfNeeded()
      XCTAssertGreaterThan(splitView.bounds.width, 500)
      XCTAssertGreaterThan(splitView.arrangedSubviews[0].frame.width, imposed + 20)
      settle(window: window, root: root, passes: 12)
      XCTAssertEqual(splitView.arrangedSubviews[0].frame.width, imposed, accuracy: 1.5)
    }
  }

  func testTranslucentSplitWrappersStayClear() throws {
    let controller = BonsplitController(
      configuration: .init(
        appearance: .init(
          enableAnimations: false,
          chromeColors: .init(backgroundHex: "#11223380")
        )
      ))
    _ = controller.createTab(title: "Base")
    let sourcePane = try XCTUnwrap(controller.focusedPaneId)
    XCTAssertNotNil(controller.splitPane(sourcePane, orientation: .horizontal))

    try withRenderer(controller: controller, size: NSSize(width: 800, height: 600)) { root, _, _ in
      let splitView = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeSplitView.self, in: root))
      let splitBackground = splitView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
      XCTAssertEqual(splitBackground?.alphaComponent ?? -1, 0, accuracy: 0.001)
      XCTAssertEqual(splitView.arrangedSubviews.count, 2)
      for container in splitView.arrangedSubviews {
        let background = container.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
        XCTAssertEqual(background?.alphaComponent ?? -1, 0, accuracy: 0.001)
      }
    }
  }

  func testNativeTabChromePreservesStatusControlsAndLocalizedAccessibility() throws {
    let controller = BonsplitController(
      configuration: .init(
        appearance: .init(splitButtons: [])
      ))
    let firstID = try XCTUnwrap(controller.allTabIds.first)
    controller.updateTab(
      firstID,
      title: "Remote audio",
      isDirty: true,
      showsNotificationBadge: true,
      isAudioPlaying: true,
      showsRemoteIndicator: true
    )

    try withRenderer(controller: controller, size: NSSize(width: 520, height: 200)) {
      root, window, _ in
      let tabBar = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeTabBarView.self, in: root))
      var first = try XCTUnwrap(tabBar.tabViewsForTesting[firstID.id])
      XCTAssertTrue(first.closeVisibleForTesting)
      XCTAssertTrue(first.audioVisibleForTesting)
      XCTAssertTrue(first.remoteVisibleForTesting)
      XCTAssertFalse(first.statusVisibleForTesting)
      let accessibility = first.accessibilityValue() as? String ?? ""
      XCTAssertTrue(accessibility.contains("Unread"))
      XCTAssertTrue(accessibility.contains("Modified"))
      XCTAssertTrue(accessibility.contains("Connected over SSH"))

      _ = controller.createTab(title: "Selected")
      settle(window: window, root: root)
      first = try XCTUnwrap(tabBar.tabViewsForTesting[firstID.id])
      XCTAssertFalse(first.closeVisibleForTesting)
      XCTAssertTrue(first.statusVisibleForTesting)

      controller.updateTab(firstID, isPinned: true)
      controller.selectTab(firstID)
      settle(window: window, root: root)
      first = try XCTUnwrap(tabBar.tabViewsForTesting[firstID.id])
      XCTAssertTrue(first.pinVisibleForTesting)
      XCTAssertFalse(first.closeVisibleForTesting)
    }
  }

  func testNativeShortcutHintUsesConfiguredModifierWithoutChangingTabWidth() throws {
    let defaults = UserDefaults.standard
    let key = TabControlShortcutHintDebugSettings.alwaysShowKey
    let oldValue = defaults.object(forKey: key)
    defaults.set(true, forKey: key)
    defer {
      if let oldValue {
        defaults.set(oldValue, forKey: key)
      } else {
        defaults.removeObject(forKey: key)
      }
    }
    let controller = BonsplitController(
      configuration: .init(
        appearance: .init(splitButtons: [])
      ))
    let tabID = try XCTUnwrap(controller.allTabIds.first)

    try withRenderer(controller: controller, size: NSSize(width: 420, height: 180)) {
      root, _, _ in
      let tabBar = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeTabBarView.self, in: root))
      let tabView = try XCTUnwrap(tabBar.tabViewsForTesting[tabID.id])
      let width = tabView.frame.width
      XCTAssertTrue(tabView.shortcutHintVisibleForTesting)
      XCTAssertTrue(tabView.shortcutHintTextForTesting.hasSuffix("1"))
      XCTAssertEqual(tabView.frame.width, width, accuracy: 0.001)
    }
  }

  func testSplitButtonsHonorHoverPolicyAndMouseDownActivation() throws {
    let action = BonsplitConfiguration.SplitActionButton(
      id: "instant",
      systemImage: "bolt.fill",
      action: .custom("instant"),
      activatesOnMouseDown: true
    )
    let controller = BonsplitController(
      configuration: .init(
        appearance: .init(
          splitButtons: [action],
          splitButtonsOnHover: true
        )
      ))
    let spy = CustomActionSpy()
    controller.delegate = spy

    try withRenderer(controller: controller, size: NSSize(width: 420, height: 180)) {
      root, window, _ in
      let tabBar = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeTabBarView.self, in: root))
      XCTAssertFalse(tabBar.actionLaneVisibleForTesting)
      tabBar.mouseEntered(
        with: try makeMouseEvent(
          type: .mouseMoved,
          in: tabBar,
          at: NSPoint(x: tabBar.bounds.midX, y: tabBar.bounds.midY),
          clickCount: 0
        ))
      settle(window: window, root: root)
      XCTAssertTrue(tabBar.actionLaneVisibleForTesting)

      let button = try XCTUnwrap(tabBar.actionButtonsForTesting.first)
      XCTAssertTrue(button.activatesOnMouseDown)
      button.mouseDown(
        with: try makeMouseEvent(
          type: .leftMouseDown,
          in: button,
          at: NSPoint(x: button.bounds.midX, y: button.bounds.midY),
          clickCount: 1
        ))
      XCTAssertEqual(spy.identifier, "instant")
      XCTAssertEqual(spy.pane, controller.focusedPaneId)
      XCTAssertEqual(button.accessibilityIdentifier(), "paneTabBarControl.custom.instant")
    }
  }

  func testAdjacentTerminalDropTreatsSharedEdgeAsMoveAndOuterEdgeAsSplit() throws {
    let controller = BonsplitController()
    let sourcePane = try XCTUnwrap(controller.focusedPaneId)
    let tabID = try XCTUnwrap(controller.allTabIds.first)
    controller.updateTab(tabID, kind: .some("terminal"))
    let targetPane = try XCTUnwrap(
      controller.splitPane(
        sourcePane,
        orientation: .horizontal,
        initialDividerPosition: 0.5
      ))
    let sourceState = try XCTUnwrap(controller.internalController.paneState(for: sourcePane))
    let tab = try XCTUnwrap(sourceState.tabs.first(where: { $0.id == tabID.id }))
    _ = controller.internalController.beginTabDrag(tab, from: sourcePane)
    defer { controller.internalController.clearTabDragState() }

    try withRenderer(controller: controller, size: NSSize(width: 640, height: 240)) {
      root, _, _ in
      let panes = descendants(ofType: BonsplitPaneView.self, in: root)
      let target = try XCTUnwrap(panes.first { $0.paneIDForTesting == targetPane })
      XCTAssertEqual(target.effectiveTabDropZoneForTesting(.left), .center)
      XCTAssertEqual(target.effectiveTabDropZoneForTesting(.right), .right)
    }
  }

  func testNativeSplitConsumesEntryAnimationAndSettlesAtConfiguredRatio() throws {
    var configuration = BonsplitConfiguration()
    configuration.appearance.minimumPaneWidth = 1
    configuration.appearance.animationDuration = 0.02
    configuration.appearance.enableAnimations = true
    configuration.dividerPositionRange = 0...1
    let controller = BonsplitController(configuration: configuration)
    let source = try XCTUnwrap(controller.focusedPaneId)
    XCTAssertNotNil(
      controller.splitPane(
        source,
        orientation: .horizontal,
        initialDividerPosition: 0.35
      ))

    try withRenderer(controller: controller, size: NSSize(width: 600, height: 240)) {
      root, window, _ in
      settle(window: window, root: root, passes: 12)
      let split = try XCTUnwrap(firstDescendant(ofType: BonsplitNativeSplitView.self, in: root))
      let available = split.bounds.width - split.dividerThickness
      XCTAssertFalse(split.isAnimatingEntryForTesting)
      XCTAssertEqual(split.arrangedSubviews[0].frame.width / available, 0.35, accuracy: 0.02)
      guard case .split(let state) = controller.internalController.rootNode else {
        return XCTFail("Expected split root")
      }
      XCTAssertNil(state.animationOrigin)
    }
  }

  private func makeImposedSplitController() throws -> (BonsplitController, UUID) {
    var configuration = BonsplitConfiguration()
    configuration.appearance.minimumPaneWidth = 1
    configuration.appearance.minimumPaneHeight = 1
    configuration.appearance.enableAnimations = false
    configuration.dividerPositionRange = 0...1
    let controller = BonsplitController(configuration: configuration)
    _ = controller.createTab(title: "Left")
    let sourcePane = try XCTUnwrap(controller.focusedPaneId)
    XCTAssertNotNil(
      controller.splitPane(
        sourcePane,
        orientation: .horizontal,
        initialDividerPosition: 0.5
      ))
    guard case .split(let split) = controller.treeSnapshot(),
      let splitID = UUID(uuidString: split.id)
    else {
      throw NSError(domain: "NativeRendererRegressionTests", code: 1)
    }
    return (controller, splitID)
  }

  private func withRenderer<T>(
    controller: BonsplitController,
    size: NSSize,
    content: @escaping BonsplitViewController.ContentProvider = { _, _ in
      let child = NSViewController()
      child.view = NSView()
      return child
    },
    body: (NSView, NSWindow, BonsplitViewController) throws -> T
  ) throws -> T {
    let renderer = BonsplitViewController(controller: controller, content: content)
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: size),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    defer { window.orderOut(nil) }
    let host = try XCTUnwrap(window.contentView)
    renderer.view.frame = host.bounds
    renderer.view.autoresizingMask = [.width, .height]
    host.addSubview(renderer.view)
    window.makeKeyAndOrderFront(nil)
    settle(window: window, root: renderer.view)
    return try body(renderer.view, window, renderer)
  }

  private func settle(window: NSWindow, root: NSView, passes: Int = 6) {
    for _ in 0..<passes {
      window.contentView?.layoutSubtreeIfNeeded()
      root.layoutSubtreeIfNeeded()
      RunLoop.current.run(mode: .default, before: Date.now.addingTimeInterval(0.01))
    }
  }

  private func firstDescendant<T: NSView>(ofType type: T.Type, in root: NSView) -> T? {
    if let match = root as? T { return match }
    for child in root.subviews {
      if let match = firstDescendant(ofType: type, in: child) { return match }
    }
    return nil
  }

  private func descendants<T: NSView>(ofType type: T.Type, in root: NSView) -> [T] {
    var matches: [T] = []
    if let match = root as? T { matches.append(match) }
    for child in root.subviews {
      matches.append(contentsOf: descendants(ofType: type, in: child))
    }
    return matches
  }

  private func makeMouseEvent(
    type: NSEvent.EventType,
    in view: NSView,
    at point: NSPoint,
    clickCount: Int
  ) throws -> NSEvent {
    let window = try XCTUnwrap(view.window)
    let location = view.convert(point, to: nil)
    return try XCTUnwrap(
      NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: clickCount,
        pressure: 1
      ))
  }
}
