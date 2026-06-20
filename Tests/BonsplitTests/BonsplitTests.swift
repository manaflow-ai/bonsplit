import XCTest
@testable import Bonsplit
import AppKit
import QuartzCore
import SwiftUI

final class BonsplitTests: XCTestCase {
    @MainActor
    private final class FakeTabBarHitRegionView: NSView {
        deinit {
            BonsplitTabBarHitRegionRegistry.unregister(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            BonsplitTabBarHitRegionRegistry.unregister(self)
            if window != nil {
                BonsplitTabBarHitRegionRegistry.register(self)
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if superview == nil {
                BonsplitTabBarHitRegionRegistry.unregister(self)
            }
        }
    }

    @MainActor
    private final class FakeTabItemHitRegionView: NSView, BonsplitTabItemHitRegionProviding {
        nonisolated(unsafe) var tabFrames: [CGRect] = []

        deinit {
            BonsplitTabItemHitRegionRegistry.unregister(self)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            BonsplitTabItemHitRegionRegistry.unregister(self)
            if window != nil {
                BonsplitTabItemHitRegionRegistry.register(self)
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if superview == nil {
                BonsplitTabItemHitRegionRegistry.unregister(self)
            }
        }

        nonisolated func containsBonsplitTabItemHit(localPoint: NSPoint) -> Bool {
            tabFrames.contains { $0.contains(localPoint) }
        }
    }

    @MainActor
    private final class LayoutProbeView: NSView {
        private(set) var sizeChangeCount = 0
        private(set) var originChangeCount = 0

        override func setFrameSize(_ newSize: NSSize) {
            if frame.size != newSize {
                sizeChangeCount += 1
            }
            super.setFrameSize(newSize)
        }

        override func setFrameOrigin(_ newOrigin: NSPoint) {
            if frame.origin != newOrigin {
                originChangeCount += 1
            }
            super.setFrameOrigin(newOrigin)
        }
    }

    @MainActor
    private struct LayoutProbeRepresentable: NSViewRepresentable {
        let probeView: LayoutProbeView

        func makeNSView(context: Context) -> LayoutProbeView {
            probeView
        }

        func updateNSView(_ nsView: LayoutProbeView, context: Context) {}
    }

    @MainActor
    private final class DropZoneModel: ObservableObject {
        @Published var zone: DropZone?
    }

    @MainActor
    private struct PaneDropInteractionHarness: View {
        @ObservedObject var model: DropZoneModel
        let probeView: LayoutProbeView

        var body: some View {
            PaneDropInteractionContainer(activeDropZone: model.zone) {
                LayoutProbeRepresentable(probeView: probeView)
            } dropLayer: { _ in
                Color.clear
            }
        }
    }

    private final class TabContextActionDelegateSpy: BonsplitDelegate {
        var action: TabContextAction?
        var tabId: TabID?
        var paneId: PaneID?
        var moveDestinationId: String?

        func splitTabBar(_ controller: BonsplitController, didRequestTabContextAction action: TabContextAction, for tab: Bonsplit.Tab, inPane pane: PaneID) {
            self.action = action
            self.tabId = tab.id
            self.paneId = pane
        }

        func splitTabBar(_ controller: BonsplitController, didRequestTabMoveToDestination destinationId: String, for tab: Bonsplit.Tab, inPane pane: PaneID) {
            self.moveDestinationId = destinationId
            self.tabId = tab.id
            self.paneId = pane
        }
    }

    private final class NewTabRequestDelegateSpy: BonsplitDelegate {
        var requestedKind: String?
        var requestedPaneId: PaneID?

        func splitTabBar(_ controller: BonsplitController, didRequestNewTab kind: String, inPane pane: PaneID) {
            requestedKind = kind
            requestedPaneId = pane
        }
    }

    private final class CustomActionDelegateSpy: BonsplitDelegate {
        var requestedIdentifier: String?
        var requestedPaneId: PaneID?

        func splitTabBar(_ controller: BonsplitController, didRequestCustomAction identifier: String, inPane pane: PaneID) {
            requestedIdentifier = identifier
            requestedPaneId = pane
        }
    }

    @MainActor
    func testControllerCreation() {
        let controller = BonsplitController()
        XCTAssertNotNil(controller.focusedPaneId)
    }

    @MainActor
    func testTabCreation() {
        let controller = BonsplitController()
        let tabId = controller.createTab(title: "Test Tab", icon: "doc")
        XCTAssertNotNil(tabId)
    }

    @MainActor
    func testTabRetrieval() {
        let controller = BonsplitController()
        let tabId = controller.createTab(title: "Test Tab", icon: "doc")!
        let tab = controller.tab(tabId)
        XCTAssertEqual(tab?.title, "Test Tab")
        XCTAssertEqual(tab?.icon, "doc")
    }

    @MainActor
    func testTabUpdate() {
        let controller = BonsplitController()
        let tabId = controller.createTab(title: "Original", icon: "doc")!

        controller.updateTab(tabId, title: "Updated", isDirty: true)

        let tab = controller.tab(tabId)
        XCTAssertEqual(tab?.title, "Updated")
        XCTAssertEqual(tab?.isDirty, true)
    }

    @MainActor
    func testTabAudioPlayingRoundTrips() {
        let controller = BonsplitController()
        let tabId = controller.createTab(title: "Audio", icon: "globe", isAudioPlaying: true)!

        XCTAssertEqual(controller.tab(tabId)?.isAudioPlaying, true)

        // A nil update leaves the flag untouched; an explicit false clears it.
        controller.updateTab(tabId, title: "Audio 2")
        XCTAssertEqual(controller.tab(tabId)?.isAudioPlaying, true)

        controller.updateTab(tabId, isAudioPlaying: false)
        XCTAssertEqual(controller.tab(tabId)?.isAudioPlaying, false)

        controller.updateTab(tabId, isAudioPlaying: true)
        XCTAssertEqual(controller.tab(tabId)?.isAudioPlaying, true)
    }

    @MainActor
    func testSplitPaneWithTabPreservesAudioPlaying() {
        let controller = BonsplitController()
        _ = controller.createTab(title: "Base", icon: "doc")
        let playing = Bonsplit.Tab(title: "Playing", isAudioPlaying: true)

        let newPane = controller.splitPane(orientation: .horizontal, withTab: playing)

        XCTAssertNotNil(newPane)
        // The supplied tab's audio-playing state must survive the public
        // Tab -> internal TabItem conversion in the split path.
        XCTAssertEqual(controller.tab(playing.id)?.isAudioPlaying, true)
    }

    @MainActor
    func testTabClose() {
        let controller = BonsplitController()
        let tabId = controller.createTab(title: "Test Tab", icon: "doc")!

        let closed = controller.closeTab(tabId)

        XCTAssertTrue(closed)
        XCTAssertNil(controller.tab(tabId))
    }

    @MainActor
    func testCloseSelectedTabKeepsIndexStableWhenPossible() {
        do {
            let config = BonsplitConfiguration(newTabPosition: .end)
            let controller = BonsplitController(configuration: config)

            let tab0 = controller.createTab(title: "0")!
            let tab1 = controller.createTab(title: "1")!
            let tab2 = controller.createTab(title: "2")!

            let pane = controller.focusedPaneId!

            controller.selectTab(tab1)
            XCTAssertEqual(controller.selectedTab(inPane: pane)?.id, tab1)

            _ = controller.closeTab(tab1)

            // Order is [0,1,2] and 1 was selected; after close we should select 2 (same index).
            XCTAssertEqual(controller.selectedTab(inPane: pane)?.id, tab2)
            XCTAssertNotNil(controller.tab(tab0))
        }

        do {
            let config = BonsplitConfiguration(newTabPosition: .end)
            let controller = BonsplitController(configuration: config)

            let tab0 = controller.createTab(title: "0")!
            let tab1 = controller.createTab(title: "1")!
            let tab2 = controller.createTab(title: "2")!

            let pane = controller.focusedPaneId!

            controller.selectTab(tab2)
            XCTAssertEqual(controller.selectedTab(inPane: pane)?.id, tab2)

            _ = controller.closeTab(tab2)

            // Closing last should select previous.
            XCTAssertEqual(controller.selectedTab(inPane: pane)?.id, tab1)
            XCTAssertNotNil(controller.tab(tab0))
        }
    }

    @MainActor
    func testConfiguration() {
        let config = BonsplitConfiguration(
            allowSplits: false,
            allowCloseTabs: true
        )
        let controller = BonsplitController(configuration: config)

        XCTAssertFalse(controller.configuration.allowSplits)
        XCTAssertTrue(controller.configuration.allowCloseTabs)
    }

    func testDefaultSplitButtonTooltips() {
        let defaults = BonsplitConfiguration.SplitButtonTooltips.default
        XCTAssertEqual(defaults.newTerminal, "New Terminal")
        XCTAssertEqual(defaults.newBrowser, "New Browser")
        XCTAssertEqual(defaults.splitRight, "Split Right")
        XCTAssertEqual(defaults.splitDown, "Split Down")
    }

    func testDefaultSplitActionButtons() {
        XCTAssertEqual(
            BonsplitConfiguration.SplitActionButton.defaults,
            [.newTerminal, .newBrowser, .splitRight, .splitDown]
        )
    }

    func testCustomSplitActionButtonRoundTrips() throws {
        let button = BonsplitConfiguration.SplitActionButton(
            id: "run-tests",
            systemImage: "checkmark.circle",
            tooltip: "Run tests",
            action: .custom("run-tests")
        )

        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertEqual(decoded, button)
    }

    func testCustomSplitActionButtonCanActivateOnMouseDown() throws {
        let button = BonsplitConfiguration.SplitActionButton(
            id: "tools",
            systemImage: "ellipsis.vertical",
            tooltip: "Tools",
            action: .custom("tools"),
            activatesOnMouseDown: true
        )

        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertEqual(decoded, button)
        XCTAssertTrue(decoded.activatesOnMouseDown)
    }

    func testSplitActionButtonDecodesMissingMouseDownActivationAsFalse() throws {
        let data = #"""
        {
          "id": "terminal",
          "icon": { "type": "systemImage", "name": "terminal" },
          "action": "newTerminal"
        }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertFalse(decoded.activatesOnMouseDown)
    }

    func testCustomSplitActionButtonPreservesReservedActionName() throws {
        let button = BonsplitConfiguration.SplitActionButton(
            id: "custom-terminal",
            systemImage: "terminal",
            tooltip: "Custom terminal action",
            action: .custom("newTerminal")
        )

        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertEqual(decoded.action, .custom("newTerminal"))
        XCTAssertEqual(decoded, button)
    }

    func testSplitActionButtonDecodesLegacyBuiltInActionString() throws {
        let data = #"""
        {
          "id": "terminal",
          "icon": { "type": "systemImage", "name": "terminal" },
          "action": "newTerminal"
        }
        """#.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertEqual(decoded.action, .newTerminal)
    }

    func testCustomSplitActionButtonSupportsEmojiIcon() throws {
        let button = BonsplitConfiguration.SplitActionButton(
            id: "agent",
            icon: .emoji("🤖", scale: 0.85),
            tooltip: "Start agent",
            action: .custom("agent")
        )

        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: data)

        XCTAssertEqual(decoded, button)
    }

    func testCustomSplitActionButtonSupportsImageDataIcon() throws {
        let data = Data([0x89, 0x50, 0x4E, 0x47])
        let button = BonsplitConfiguration.SplitActionButton(
            id: "image-agent",
            icon: .imageData(data),
            tooltip: "Start image agent",
            action: .custom("image-agent")
        )

        let encoded = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(BonsplitConfiguration.SplitActionButton.self, from: encoded)

        XCTAssertEqual(decoded, button)
    }

    func testCurrentColorSVGImageDataRendersAsTemplate() throws {
        let templateSVG = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="currentColor" d="M4 4h16v16H4z"/>
            </svg>
            """.utf8
        )
        let colorSVG = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="#D97757" d="M4 4h16v16H4z"/>
            </svg>
            """.utf8
        )

        XCTAssertTrue(TabBarStyling.imageDataShouldRenderAsTemplate(templateSVG))
        XCTAssertFalse(TabBarStyling.imageDataShouldRenderAsTemplate(colorSVG))
    }

    func testCurrentColorSVGImageDataRendersAsTemplateWithInvalidUTF8Suffix() throws {
        var svg = Data(
            """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
              <path fill="currentColor" d="M4 4h16v16H4z"/>
            </svg>
            """.utf8
        )
        svg.append(0xE2)

        XCTAssertTrue(TabBarStyling.imageDataShouldRenderAsTemplate(svg))
    }

    @MainActor
    func testSplitActionButtonImageDataIsCached() throws {
        let png = try XCTUnwrap(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="))
        let first = try XCTUnwrap(TabBarStyling.splitActionButtonImage(from: png))
        let second = try XCTUnwrap(TabBarStyling.splitActionButtonImage(from: png))

        XCTAssertTrue(first === second)
    }

    func testSplitActionSystemImageKeepsSupportedSymbols() {
        let image = TabBarStyling.splitActionSystemImage(for: "terminal")

        XCTAssertEqual(image, TabBarStyling.SplitActionSystemImage(name: "terminal", rotationDegrees: 0, pointSize: 12))
    }

    func testSplitActionSystemImageRendersVerticalEllipsisFallback() {
        let image = TabBarStyling.splitActionSystemImage(for: "ellipsis.vertical")

        XCTAssertEqual(image, TabBarStyling.SplitActionSystemImage(name: "ellipsis", rotationDegrees: 90, pointSize: 10.5))
    }

    func testSplitActionSystemImageUsesFallbackForUnknownSymbols() {
        let image = TabBarStyling.splitActionSystemImage(for: "cmux.definitely.missing.symbol")

        XCTAssertEqual(image, TabBarStyling.SplitActionSystemImage(name: "questionmark.circle", rotationDegrees: 0, pointSize: 12))
    }

    func testMinimalModeDoesNotReserveHiddenSplitButtonStrip() {
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: true, isMinimalMode: true),
            0,
            "Minimal mode should let the tab strip fill the full width until the hover-only split buttons are actually shown"
        )
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: true, isMinimalMode: false),
            TabBarStyling.splitButtonsBackdropWidth(buttonCount: 4),
            "Standard mode should keep reserving space for the always-visible split buttons"
        )
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: true, isMinimalMode: false, buttonCount: 2),
            TabBarStyling.splitButtonsBackdropWidth(buttonCount: 2),
            "Standard mode should reserve space for the configured split buttons only"
        )
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: true, isMinimalMode: false, buttonCount: 0),
            0,
            "No strip should be reserved when the configured split button list is empty"
        )
        XCTAssertEqual(
            TabBarStyling.trailingTabContentInset(showSplitButtons: false, isMinimalMode: false),
            0,
            "No split-button strip should be reserved when split buttons are disabled"
        )
    }

    func testTabBarLayoutKeepsDefaultSplitButtonLaneWidthAsMinimum() {
        let compactMeasuredWidth =
            TabBarStyling.splitButtonsLeadingPadding
            + TabBarStyling.splitButtonsTrailingPadding
            + (4 * CGFloat(14))
            + (3 * TabBarStyling.splitButtonsSpacing)
        let layout = TabBarLayout(
            tabBarHeight: 28,
            splitButtonCount: 4,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: compactMeasuredWidth
        )

        XCTAssertEqual(
            layout.fullSplitButtonLaneWidth,
            TabBarStyling.splitButtonsBackdropWidth(buttonCount: 4)
        )
    }

    func testTabBarLayoutExpandsForMeasuredSplitButtonLaneWidth() {
        let layout = TabBarLayout(
            tabBarHeight: 28,
            availableWidth: 800,
            splitButtonCount: 4,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: 160
        )

        XCTAssertEqual(layout.fullSplitButtonLaneWidth, 160)
        XCTAssertEqual(layout.trailingTabContentInset, 160)
    }

    func testTabBarLayoutKeepsFiveActionButtonsVisibleBeforeClipping() {
        let layout = TabBarLayout(
            tabBarHeight: 28,
            availableWidth: 240,
            splitButtonCount: 12,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: 400
        )
        let minimumVisibleWidth = TabBarStyling.splitButtonsBackdropWidth(buttonCount: 5)

        XCTAssertEqual(layout.fullSplitButtonLaneWidth, 400)
        XCTAssertEqual(layout.maximumSplitButtonLaneWidth, minimumVisibleWidth)
        XCTAssertEqual(layout.visibleSplitButtonLaneWidth, minimumVisibleWidth)
        XCTAssertEqual(layout.trailingTabContentInset, minimumVisibleWidth)
        XCTAssertTrue(layout.splitButtonLaneOverflowsViewport)
    }

    func testTabBarLayoutDoesNotTreatZeroTabContentAsTrailingWhitespace() {
        let layout = TabBarLayout(
            tabBarHeight: 28,
            availableWidth: 240,
            tabContentWidthExcludingSplitButtonLane: 0,
            splitButtonCount: 12,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: 400
        )

        let minimumVisibleWidth = TabBarStyling.splitButtonsBackdropWidth(buttonCount: 5)
        XCTAssertEqual(layout.maximumSplitButtonLaneWidth, minimumVisibleWidth)
        XCTAssertEqual(layout.visibleSplitButtonLaneWidth, minimumVisibleWidth)
        XCTAssertEqual(layout.trailingTabContentInset, minimumVisibleWidth)
    }

    func testTabBarLayoutUsesTrailingWhitespaceBeforeClippingSplitButtons() {
        let measuredWidth = TabBarStyling.splitButtonsBackdropWidth(buttonCount: 10)
        let layout = TabBarLayout(
            tabBarHeight: 28,
            availableWidth: 930,
            tabContentWidthExcludingSplitButtonLane: 300,
            splitButtonCount: 10,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: measuredWidth
        )

        XCTAssertEqual(layout.maximumSplitButtonLaneWidth, 630)
        XCTAssertEqual(layout.visibleSplitButtonLaneWidth, measuredWidth)
        XCTAssertEqual(layout.trailingTabContentInset, measuredWidth)
        XCTAssertFalse(layout.splitButtonLaneOverflowsViewport)
    }

    func testTabBarLayoutKeepsMeasuredLaneWhenItFitsQuarterOfAvailableWidth() {
        let layout = TabBarLayout(
            tabBarHeight: 28,
            availableWidth: 800,
            splitButtonCount: 4,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: 160
        )

        XCTAssertEqual(layout.fullSplitButtonLaneWidth, 160)
        XCTAssertEqual(layout.maximumSplitButtonLaneWidth, 200)
        XCTAssertEqual(layout.visibleSplitButtonLaneWidth, 160)
        XCTAssertEqual(layout.trailingTabContentInset, 160)
        XCTAssertFalse(layout.splitButtonLaneOverflowsViewport)
    }

    func testActionLaneSolidSurfaceCoversVisibleViewportWhenButtonsOverflow() {
        let layout = TabBarLayout(
            tabBarHeight: 28,
            availableWidth: 240,
            splitButtonCount: 12,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: 400
        )
        let effect = BonsplitConfiguration.Appearance.SplitButtonBackdropEffect(
            solidWidth: 23.875,
            solidSurfaceWidthAdjustment: -53,
            contentOcclusionFraction: 0.6875
        )
        let geometry = TabBarActionLaneGeometry(
            layout: layout,
            effect: effect,
            masksTabContent: true
        )

        let minimumVisibleWidth = TabBarStyling.splitButtonsBackdropWidth(buttonCount: 5)
        XCTAssertEqual(layout.visibleSplitButtonLaneWidth, minimumVisibleWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.backgroundSolidWidth, minimumVisibleWidth, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentOcclusionWidth, minimumVisibleWidth, accuracy: 0.0001)
    }

    func testActionLaneSolidSurfaceAllowsTrimWhenButtonsDoNotOverflow() {
        let layout = TabBarLayout(
            tabBarHeight: 28,
            availableWidth: 800,
            splitButtonCount: 4,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: 160
        )
        let effect = BonsplitConfiguration.Appearance.SplitButtonBackdropEffect(
            solidWidth: 23.875,
            solidSurfaceWidthAdjustment: -53,
            contentOcclusionFraction: 0.6875
        )
        let geometry = TabBarActionLaneGeometry(
            layout: layout,
            effect: effect,
            masksTabContent: true
        )

        XCTAssertEqual(layout.visibleSplitButtonLaneWidth, 160, accuracy: 0.0001)
        XCTAssertEqual(geometry.backgroundSolidWidth, 107, accuracy: 0.0001)
        XCTAssertEqual(geometry.contentOcclusionWidth, 110, accuracy: 0.0001)
    }

    func testSplitButtonBackdropSolidSurfaceCoversVisibleActionLane() {
        XCTAssertEqual(
            TabBarStyling.splitButtonBackdropSolidSurfaceWidth(
                effectSolidWidth: 2,
                visibleLaneWidth: 90,
                solidSurfaceWidthAdjustment: 0
            ),
            90
        )
        XCTAssertEqual(
            TabBarStyling.splitButtonBackdropSolidSurfaceWidth(
                effectSolidWidth: 96,
                visibleLaneWidth: 72,
                solidSurfaceWidthAdjustment: 0
            ),
            96
        )
    }

    func testSplitButtonContentOcclusionFractionDoesNotChangeSolidSurface() {
        let occlusion = TabBarStyling.splitButtonContentOcclusionWidth(
            visibleLaneWidth: 200,
            contentOcclusionFraction: 0.25
        )

        XCTAssertEqual(occlusion, 50)
        XCTAssertEqual(
            TabBarStyling.splitButtonBackdropSolidSurfaceWidth(
                effectSolidWidth: 2,
                visibleLaneWidth: 200,
                solidSurfaceWidthAdjustment: 0
            ),
            200
        )
    }

    func testSplitButtonBackdropSolidSurfaceWidthCanBeAdjusted() {
        XCTAssertEqual(
            TabBarStyling.splitButtonBackdropSolidSurfaceWidth(
                effectSolidWidth: 2,
                visibleLaneWidth: 90,
                solidSurfaceWidthAdjustment: 12
            ),
            102
        )
        XCTAssertEqual(
            TabBarStyling.splitButtonBackdropSolidSurfaceWidth(
                effectSolidWidth: 2,
                visibleLaneWidth: 90,
                solidSurfaceWidthAdjustment: -12
            ),
            78
        )
    }

    func testSplitButtonScrollAffordancesTrackHiddenButtons() {
        var affordances = TabBarStyling.splitButtonScrollAffordances(
            scrollOffset: 0,
            contentWidth: 320,
            viewportWidth: 60
        )
        XCTAssertFalse(affordances.left)
        XCTAssertTrue(affordances.right)

        affordances = TabBarStyling.splitButtonScrollAffordances(
            scrollOffset: 120,
            contentWidth: 320,
            viewportWidth: 60
        )
        XCTAssertTrue(affordances.left)
        XCTAssertTrue(affordances.right)

        affordances = TabBarStyling.splitButtonScrollAffordances(
            scrollOffset: 260,
            contentWidth: 320,
            viewportWidth: 60
        )
        XCTAssertTrue(affordances.left)
        XCTAssertFalse(affordances.right)

        affordances = TabBarStyling.splitButtonScrollAffordances(
            scrollOffset: 0,
            contentWidth: 60,
            viewportWidth: 60
        )
        XCTAssertFalse(affordances.left)
        XCTAssertFalse(affordances.right)
    }

    func testTabBarLayoutDoesNotHardClipSelectedChromeAtSplitButtonLane() {
        let layout = TabBarLayout(
            tabBarHeight: 28,
            splitButtonCount: 4,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: 160
        )
        let indicatorFrame = layout.selectedIndicatorFrame(
            selectedTabFrame: CGRect(x: 0, y: 0, width: 240, height: 28),
            totalWidth: 240
        )
        XCTAssertNotNil(indicatorFrame)
        XCTAssertEqual(
            indicatorFrame?.maxX ?? 0,
            239,
            accuracy: 0.001
        )
    }

    func testTabBarSelectedChromeFrameFollowsCurrentSelection() {
        let firstTabId = UUID()
        let secondTabId = UUID()
        let layout = TabBarLayout(
            tabBarHeight: 28,
            splitButtonCount: 0,
            splitButtonLaneVisible: false,
            reservesSplitButtonLane: false
        )
        let frames = [
            firstTabId: CGRect(x: 12, y: 0, width: 120, height: 28),
            secondTabId: CGRect(x: 144, y: 0, width: 96, height: 28),
        ]
        let totalWidth: CGFloat = 300

        let firstSelectedFrame = TabBarStyling.selectedTabFrame(
            selectedTabId: firstTabId,
            tabFrames: frames
        )
        let secondSelectedFrame = TabBarStyling.selectedTabFrame(
            selectedTabId: secondTabId,
            tabFrames: frames
        )
        let firstIndicatorFrame = layout.selectedIndicatorFrame(
            selectedTabFrame: firstSelectedFrame,
            totalWidth: totalWidth
        )
        let secondIndicatorFrame = layout.selectedIndicatorFrame(
            selectedTabFrame: secondSelectedFrame,
            totalWidth: totalWidth
        )

        XCTAssertEqual(firstIndicatorFrame?.minX, frames[firstTabId]?.minX)
        XCTAssertEqual(
            secondIndicatorFrame?.minX,
            frames[secondTabId]?.minX,
            "Selected tab chrome must be derived from the current selected tab id, not a cached frame from a previous selection."
        )
        let nilSelectedFrame = TabBarStyling.selectedTabFrame(
            selectedTabId: nil,
            tabFrames: frames
        )
        XCTAssertNil(
            layout.selectedIndicatorFrame(
                selectedTabFrame: nilSelectedFrame,
                totalWidth: totalWidth
            )
        )
    }

    func testTabBarLayoutIgnoresMeasuredSplitButtonLaneWidthWithoutButtons() {
        let layout = TabBarLayout(
            tabBarHeight: 28,
            splitButtonCount: 0,
            splitButtonLaneVisible: false,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: 160
        )

        XCTAssertEqual(layout.fullSplitButtonLaneWidth, 0)
        XCTAssertEqual(layout.trailingTabContentInset, 0)
    }

    func testTabBarKeepsNonOverflowingTabsLeadingAligned() {
        let tabId = UUID()

        XCTAssertEqual(
            TabBarStyling.preferredScrollTarget(
                selectedTabId: tabId,
                contentWidth: 132,
                containerWidth: 349
            ),
            .leading,
            "When the tab strip fits in the pane, it should stay leading-aligned instead of creating a dead leading clip-view band"
        )

        XCTAssertEqual(
            TabBarStyling.preferredScrollTarget(
                selectedTabId: tabId,
                contentWidth: 420,
                containerWidth: 349
            ),
            .selectedTab(tabId),
            "Overflowing tab strips should still auto-scroll the selected tab into view"
        )
    }

    func testTabBarForcesLeadingResetWhenNonOverflowingStripStaysScrolled() {
        XCTAssertTrue(
            TabBarStyling.shouldForceResetToLeading(
                scrollOffset: 28,
                contentWidth: 180,
                containerWidth: 349
            ),
            "A non-overflowing tab strip with a stale horizontal offset should be snapped back to x=0"
        )

        XCTAssertTrue(
            TabBarStyling.shouldForceResetToLeading(
                scrollOffset: -30,
                contentWidth: 180,
                containerWidth: 349
            ),
            "The leading reset must correct both left and right stale offsets"
        )

        XCTAssertFalse(
            TabBarStyling.shouldForceResetToLeading(
                scrollOffset: 0.2,
                contentWidth: 180,
                containerWidth: 349
            ),
            "Tiny floating-point drift should not trigger redundant clip-view resets"
        )

        XCTAssertFalse(
            TabBarStyling.shouldForceResetToLeading(
                scrollOffset: 28,
                contentWidth: 420,
                containerWidth: 349
            ),
            "Overflowing tab strips are allowed to stay horizontally scrolled"
        )
    }

    @MainActor
    func testTabBarHitRegionRegistryTracksVisibleWindowPoint() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let tabBar = FakeTabBarHitRegionView(frame: NSRect(x: 20, y: 132, width: 180, height: 30))
        contentView.addSubview(tabBar)

        let hitPoint = tabBar.convert(NSPoint(x: 24, y: 12), to: nil)
        XCTAssertTrue(
            BonsplitTabBarHitRegionRegistry.containsWindowPoint(hitPoint, in: window),
            "The registry should expose visible tab-bar hit regions in window coordinates"
        )

        let missPoint = tabBar.convert(NSPoint(x: 24, y: -18), to: nil)
        XCTAssertFalse(
            BonsplitTabBarHitRegionRegistry.containsWindowPoint(missPoint, in: window),
            "The registry should ignore points outside the registered tab-bar region"
        )
    }

    @MainActor
    func testTabBarHitRegionRegistryIgnoresViewsHiddenByAncestors() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let container = NSView(frame: contentView.bounds)
        contentView.addSubview(container)

        let tabBar = FakeTabBarHitRegionView(frame: NSRect(x: 32, y: contentView.bounds.maxY + 6, width: 180, height: 30))
        container.addSubview(tabBar)

        let hitPoint = tabBar.convert(NSPoint(x: 20, y: 14), to: nil)
        XCTAssertTrue(
            BonsplitTabBarHitRegionRegistry.containsWindowPoint(hitPoint, in: window),
            "The registry should use the actual registered tab-bar frame even when it extends outside its immediate container bounds"
        )

        container.isHidden = true
        XCTAssertFalse(
            BonsplitTabBarHitRegionRegistry.containsWindowPoint(hitPoint, in: window),
            "Ancestor-hidden tab-bar regions must not keep stealing portal hit testing"
        )
    }

    @MainActor
    func testTabItemHitRegionRegistryTracksOnlyRealTabFrames() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let tabBar = FakeTabItemHitRegionView(frame: NSRect(x: 20, y: 132, width: 220, height: 30))
        tabBar.tabFrames = [
            CGRect(x: 8, y: 0, width: 96, height: 30),
            CGRect(x: 112, y: 0, width: 80, height: 30)
        ]
        contentView.addSubview(tabBar)

        let tabPoint = tabBar.convert(NSPoint(x: 32, y: 12), to: nil)
        XCTAssertTrue(
            BonsplitTabItemHitRegionRegistry.containsWindowPoint(tabPoint, in: window),
            "Points inside actual tab frames should suppress implicit AppKit window dragging"
        )

        let emptyChromePoint = tabBar.convert(NSPoint(x: 204, y: 12), to: nil)
        XCTAssertFalse(
            BonsplitTabItemHitRegionRegistry.containsWindowPoint(emptyChromePoint, in: window),
            "Empty tab-bar chrome should stay available for explicit app-window dragging"
        )
    }

    @MainActor
    func testTabItemHitRegionRegistryIgnoresHiddenProviders() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let tabBar = FakeTabItemHitRegionView(frame: NSRect(x: 20, y: 132, width: 220, height: 30))
        tabBar.tabFrames = [CGRect(x: 8, y: 0, width: 96, height: 30)]
        contentView.addSubview(tabBar)

        let tabPoint = tabBar.convert(NSPoint(x: 32, y: 12), to: nil)
        XCTAssertTrue(BonsplitTabItemHitRegionRegistry.containsWindowPoint(tabPoint, in: window))

        tabBar.isHidden = true
        XCTAssertFalse(
            BonsplitTabItemHitRegionRegistry.containsWindowPoint(tabPoint, in: window),
            "Hidden tab providers must not suppress app-window dragging"
        )
    }

    @MainActor
    func testConfigurationAcceptsCustomSplitButtonTooltips() {
        let customTooltips = BonsplitConfiguration.SplitButtonTooltips(
            newTerminal: "Terminal (⌘T)",
            newBrowser: "Browser (⌘⇧L)",
            splitRight: "Split Right (⌘D)",
            splitDown: "Split Down (⌘⇧D)"
        )
        let config = BonsplitConfiguration(
            appearance: .init(
                splitButtonTooltips: customTooltips
            )
        )
        let controller = BonsplitController(configuration: config)

        XCTAssertEqual(controller.configuration.appearance.splitButtonTooltips, customTooltips)
    }

    @MainActor
    func testConfigurationAcceptsCustomSplitActionButtons() {
        let buttons: [BonsplitConfiguration.SplitActionButton] = [
            .newTerminal,
            .init(
                id: "run-tests",
                systemImage: "checkmark.circle",
                tooltip: "Run tests",
                action: .custom("run-tests")
            ),
        ]
        let config = BonsplitConfiguration(
            appearance: .init(
                splitButtons: buttons
            )
        )
        let controller = BonsplitController(configuration: config)

        XCTAssertEqual(controller.configuration.appearance.splitButtons, buttons)
    }

    func testAppearanceKeepsFirstSplitActionButtonForDuplicateIds() {
        let firstRunTests = BonsplitConfiguration.SplitActionButton(
            id: "run-tests",
            systemImage: "checkmark.circle",
            tooltip: "Run tests",
            action: .custom("run-tests")
        )
        let duplicateRunTests = BonsplitConfiguration.SplitActionButton(
            id: "run-tests",
            systemImage: "xmark.circle",
            tooltip: "Duplicate",
            action: .custom("duplicate")
        )
        var appearance = BonsplitConfiguration.Appearance(
            splitButtons: [.newTerminal, .newTerminal, firstRunTests, duplicateRunTests]
        )

        XCTAssertEqual(appearance.splitButtons, [.newTerminal, firstRunTests])

        appearance.splitButtons = [duplicateRunTests, firstRunTests, .splitRight]

        XCTAssertEqual(appearance.splitButtons, [duplicateRunTests, .splitRight])
    }

    func testAppearanceDefaultsToHairlineDividerThickness() {
        XCTAssertEqual(BonsplitConfiguration.Appearance().dividerThickness, 1)
    }

    func testAppearanceCarriesConfiguredDividerThickness() {
        let appearance = BonsplitConfiguration.Appearance(dividerThickness: 3)
        XCTAssertEqual(appearance.dividerThickness, 3)
    }

    func testResolvedDividerThicknessClampsToRange() {
        XCTAssertEqual(TabBarMetrics.resolvedDividerThickness(2), 2)
        XCTAssertEqual(TabBarMetrics.resolvedDividerThickness(-5), TabBarMetrics.minimumDividerThickness)
        XCTAssertEqual(TabBarMetrics.resolvedDividerThickness(999), TabBarMetrics.maximumDividerThickness)
        XCTAssertEqual(TabBarMetrics.resolvedDividerThickness(.nan), TabBarMetrics.dividerThickness)
    }

    @MainActor
    func testControllerRequestsCustomAction() {
        let controller = BonsplitController()
        let delegate = CustomActionDelegateSpy()
        controller.delegate = delegate
        let paneId = controller.focusedPaneId!

        controller.requestCustomAction("run-tests", inPane: paneId)

        XCTAssertEqual(delegate.requestedIdentifier, "run-tests")
        XCTAssertEqual(delegate.requestedPaneId, paneId)
    }

    func testChromeBackgroundHexOverrideParsesForPaneBackground() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#FDF6E3")
        )
        let color = TabBarColors.nsColorPaneBackground(for: appearance).usingColorSpace(.sRGB)!

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(Int(round(red * 255)), 253)
        XCTAssertEqual(Int(round(green * 255)), 246)
        XCTAssertEqual(Int(round(blue * 255)), 227)
        XCTAssertEqual(Int(round(alpha * 255)), 255)
    }

    func testPaneBackgroundHexOverrideCanDifferFromChromeBackground() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(
                backgroundHex: "#FDF6E3",
                paneBackgroundHex: "#11223380"
            )
        )
        let paneColor = TabBarColors.nsColorPaneBackground(for: appearance).usingColorSpace(.sRGB)!
        let barColor = NSColor(TabBarColors.barBackground(for: appearance)).usingColorSpace(.sRGB)!

        var paneRed: CGFloat = 0
        var paneGreen: CGFloat = 0
        var paneBlue: CGFloat = 0
        var paneAlpha: CGFloat = 0
        paneColor.getRed(&paneRed, green: &paneGreen, blue: &paneBlue, alpha: &paneAlpha)

        var barRed: CGFloat = 0
        var barGreen: CGFloat = 0
        var barBlue: CGFloat = 0
        var barAlpha: CGFloat = 0
        barColor.getRed(&barRed, green: &barGreen, blue: &barBlue, alpha: &barAlpha)

        XCTAssertEqual(Int(round(paneRed * 255)), 17)
        XCTAssertEqual(Int(round(paneGreen * 255)), 34)
        XCTAssertEqual(Int(round(paneBlue * 255)), 51)
        XCTAssertEqual(Int(round(paneAlpha * 255)), 128)
        XCTAssertEqual(Int(round(barRed * 255)), 253)
        XCTAssertEqual(Int(round(barGreen * 255)), 246)
        XCTAssertEqual(Int(round(barBlue * 255)), 227)
        XCTAssertEqual(Int(round(barAlpha * 255)), 255)
    }

    func testTabBarAndSplitButtonBackdropSurfacesCanBeExplicit() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(
                backgroundHex: "#010203",
                tabBarBackgroundHex: "#11223380",
                splitButtonBackdropHex: "#44556699"
            )
        )
        let barColor = TabBarColors.nsColorBarBackground(for: appearance).usingColorSpace(.sRGB)!
        let backdropColor = TabBarColors.nsColorSplitButtonBackdropSurface(for: appearance).usingColorSpace(.sRGB)!

        var barRed: CGFloat = 0
        var barGreen: CGFloat = 0
        var barBlue: CGFloat = 0
        var barAlpha: CGFloat = 0
        barColor.getRed(&barRed, green: &barGreen, blue: &barBlue, alpha: &barAlpha)

        var backdropRed: CGFloat = 0
        var backdropGreen: CGFloat = 0
        var backdropBlue: CGFloat = 0
        var backdropAlpha: CGFloat = 0
        backdropColor.getRed(
            &backdropRed,
            green: &backdropGreen,
            blue: &backdropBlue,
            alpha: &backdropAlpha
        )

        XCTAssertEqual(Int(round(barRed * 255)), 17)
        XCTAssertEqual(Int(round(barGreen * 255)), 34)
        XCTAssertEqual(Int(round(barBlue * 255)), 51)
        XCTAssertEqual(Int(round(barAlpha * 255)), 128)
        XCTAssertEqual(Int(round(backdropRed * 255)), 68)
        XCTAssertEqual(Int(round(backdropGreen * 255)), 85)
        XCTAssertEqual(Int(round(backdropBlue * 255)), 102)
        XCTAssertEqual(Int(round(backdropAlpha * 255)), 153)
    }

    func testSplitButtonBackdropPrecomposesTranslucentPaneBackground() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(
                backgroundHex: "#11223380",
                paneBackgroundHex: "#00000000"
            )
        )
        let color = TabBarColors.nsColorSplitButtonBackdrop(for: appearance).usingColorSpace(.sRGB)!
        let expected = NSColor.windowBackgroundColor.usingColorSpace(.sRGB)!

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        var expectedRed: CGFloat = 0
        var expectedGreen: CGFloat = 0
        var expectedBlue: CGFloat = 0
        var expectedAlpha: CGFloat = 0
        expected.getRed(&expectedRed, green: &expectedGreen, blue: &expectedBlue, alpha: &expectedAlpha)

        XCTAssertEqual(Int(round(red * 255)), Int(round(expectedRed * 255)))
        XCTAssertEqual(Int(round(green * 255)), Int(round(expectedGreen * 255)))
        XCTAssertEqual(Int(round(blue * 255)), Int(round(expectedBlue * 255)))
        XCTAssertEqual(Int(round(alpha * 255)), 255)
        XCTAssertTrue(TabBarColors.shouldPaintSplitButtonBackdrop(for: appearance))
    }

    func testSplitButtonBackdropPaintsForOpaqueChromeBackground() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#112233")
        )

        XCTAssertTrue(TabBarColors.shouldPaintSplitButtonBackdrop(for: appearance))
    }

    func testSplitButtonBackdropEffectTracksSolidWidthSeparately() {
        let effect = BonsplitConfiguration.Appearance.SplitButtonBackdropEffect(
            fadeWidth: 80,
            contentFadeWidth: 42,
            solidWidth: 32,
            solidSurfaceWidthAdjustment: 7,
            fadeRampStartFraction: 0.58,
            contentOcclusionFraction: 0.25
        )

        XCTAssertEqual(effect.fadeWidth, 80)
        XCTAssertEqual(effect.contentFadeWidth, 42)
        XCTAssertEqual(effect.solidWidth, 32)
        XCTAssertEqual(effect.solidSurfaceWidthAdjustment, 7)
        XCTAssertNil(effect.separatorFadeWidth)
        XCTAssertEqual(effect.fadeRampStartFraction, 0.58)
        XCTAssertEqual(effect.contentOcclusionFraction, 0.25)

        let clamped = BonsplitConfiguration.Appearance.SplitButtonBackdropEffect(
            solidSurfaceWidthAdjustment: .infinity,
            separatorFadeWidth: -4,
            fadeRampStartFraction: 1.4,
            contentOcclusionFraction: 2.2
        )
        XCTAssertEqual(clamped.solidSurfaceWidthAdjustment, 0)
        XCTAssertEqual(clamped.separatorFadeWidth, 0)
        XCTAssertEqual(clamped.fadeRampStartFraction, 0.95)
        XCTAssertEqual(clamped.contentOcclusionFraction, 1.0)
    }

    func testChromeBorderHexOverrideParsesForSeparatorColor() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#272822", borderHex: "#112233")
        )
        let color = TabBarColors.nsColorSeparator(for: appearance).usingColorSpace(.sRGB)!

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertEqual(Int(round(red * 255)), 17)
        XCTAssertEqual(Int(round(green * 255)), 34)
        XCTAssertEqual(Int(round(blue * 255)), 51)
        XCTAssertEqual(Int(round(alpha * 255)), 255)
    }

    func testInvalidChromeBackgroundHexFallsBackToPaneDefaultColor() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#ZZZZZZ")
        )
        let resolved = TabBarColors.nsColorPaneBackground(for: appearance).usingColorSpace(.sRGB)!
        let fallback = NSColor.textBackgroundColor.usingColorSpace(.sRGB)!

        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        resolved.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)

        var fr: CGFloat = 0
        var fg: CGFloat = 0
        var fb: CGFloat = 0
        var fa: CGFloat = 0
        fallback.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)

        XCTAssertEqual(rr, fr, accuracy: 0.0001)
        XCTAssertEqual(rg, fg, accuracy: 0.0001)
        XCTAssertEqual(rb, fb, accuracy: 0.0001)
        XCTAssertEqual(ra, fa, accuracy: 0.0001)
    }

    func testPartiallyInvalidChromeBackgroundHexFallsBackToPaneDefaultColor() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#FF000G")
        )
        let resolved = TabBarColors.nsColorPaneBackground(for: appearance).usingColorSpace(.sRGB)!
        let fallback = NSColor.textBackgroundColor.usingColorSpace(.sRGB)!

        var rr: CGFloat = 0
        var rg: CGFloat = 0
        var rb: CGFloat = 0
        var ra: CGFloat = 0
        resolved.getRed(&rr, green: &rg, blue: &rb, alpha: &ra)

        var fr: CGFloat = 0
        var fg: CGFloat = 0
        var fb: CGFloat = 0
        var fa: CGFloat = 0
        fallback.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)

        XCTAssertEqual(rr, fr, accuracy: 0.0001)
        XCTAssertEqual(rg, fg, accuracy: 0.0001)
        XCTAssertEqual(rb, fb, accuracy: 0.0001)
        XCTAssertEqual(ra, fa, accuracy: 0.0001)
    }

    func testInactiveTextUsesLightForegroundOnDarkCustomChromeBackground() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#272822")
        )
        let color = TabBarColors.nsColorInactiveText(for: appearance).usingColorSpace(.sRGB)!

        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        XCTAssertGreaterThan(red, 0.5)
        XCTAssertGreaterThan(green, 0.5)
        XCTAssertGreaterThan(blue, 0.5)
        XCTAssertGreaterThan(alpha, 0.6)
    }

    func testSharedBackdropUsesSemanticBackgroundForTextAndHover() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(
                backgroundHex: "#272822",
                tabBarBackgroundHex: "#00000000",
                splitButtonBackdropHex: "#00000000",
                paneBackgroundHex: "#00000000"
            ),
            usesSharedBackdrop: true
        )
        let text = TabBarColors.nsColorInactiveText(for: appearance).usingColorSpace(.sRGB)!
        let hover = NSColor(TabBarColors.hoveredTabBackground(for: appearance)).usingColorSpace(.sRGB)!

        var textRed: CGFloat = 0
        var textGreen: CGFloat = 0
        var textBlue: CGFloat = 0
        var textAlpha: CGFloat = 0
        text.getRed(&textRed, green: &textGreen, blue: &textBlue, alpha: &textAlpha)

        var hoverRed: CGFloat = 0
        var hoverGreen: CGFloat = 0
        var hoverBlue: CGFloat = 0
        var hoverAlpha: CGFloat = 0
        hover.getRed(&hoverRed, green: &hoverGreen, blue: &hoverBlue, alpha: &hoverAlpha)

        XCTAssertGreaterThan(textRed, 0.5)
        XCTAssertGreaterThan(textGreen, 0.5)
        XCTAssertGreaterThan(textBlue, 0.5)
        XCTAssertGreaterThan(textAlpha, 0.6)
        XCTAssertGreaterThan(hoverRed, 0.9)
        XCTAssertGreaterThan(hoverGreen, 0.9)
        XCTAssertGreaterThan(hoverBlue, 0.9)
        XCTAssertGreaterThan(hoverAlpha, 0.04)
        XCTAssertLessThan(hoverAlpha, 0.12)
    }

    func testSharedBackdropActiveTabBackgroundIsClear() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(
                backgroundHex: "#272822",
                tabBarBackgroundHex: "#00000000",
                splitButtonBackdropHex: "#00000000",
                paneBackgroundHex: "#00000000"
            ),
            usesSharedBackdrop: true
        )
        let active = NSColor(TabBarColors.activeTabBackground(for: appearance)).usingColorSpace(.sRGB)!

        var alpha: CGFloat = 1
        active.getRed(nil, green: nil, blue: nil, alpha: &alpha)

        XCTAssertLessThan(
            alpha,
            0.01,
            "Shared-backdrop selected tabs should rely on the active indicator instead of a hover-like fill"
        )
    }

    func testSplitActionPressedStateUsesHigherContrast() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(backgroundHex: "#272822")
        )

        let idleIcon = TabBarColors.nsColorSplitActionIcon(for: appearance, isPressed: false).usingColorSpace(.sRGB)!
        let pressedIcon = TabBarColors.nsColorSplitActionIcon(for: appearance, isPressed: true).usingColorSpace(.sRGB)!

        var idleAlpha: CGFloat = 0
        idleIcon.getRed(nil, green: nil, blue: nil, alpha: &idleAlpha)
        var pressedAlpha: CGFloat = 0
        pressedIcon.getRed(nil, green: nil, blue: nil, alpha: &pressedAlpha)

        XCTAssertGreaterThan(pressedAlpha, idleAlpha)
    }

    @MainActor
    func testMoveTabNoopAfterItself() {
        let t0 = TabItem(title: "0")
        let t1 = TabItem(title: "1")
        let pane = PaneState(tabs: [t0, t1], selectedTabId: t1.id)

        // Dragging the last tab to the right corresponds to moving it to `tabs.count`,
        // which should be treated as a no-op.
        pane.moveTab(from: 1, to: 2)
        XCTAssertEqual(pane.tabs.map(\.id), [t0.id, t1.id])
        XCTAssertEqual(pane.selectedTabId, t1.id)

        // Still allow real moves.
        pane.moveTab(from: 0, to: 2)
        XCTAssertEqual(pane.tabs.map(\.id), [t1.id, t0.id])
        XCTAssertEqual(pane.selectedTabId, t1.id)
    }

    @MainActor
    func testPinnedTabInsertionsStayAheadOfUnpinnedTabs() {
        let unpinnedA = TabItem(title: "A", isPinned: false)
        let unpinnedB = TabItem(title: "B", isPinned: false)
        let pinned = TabItem(title: "Pinned", isPinned: true)
        let pane = PaneState(tabs: [unpinnedA, unpinnedB], selectedTabId: unpinnedA.id)

        pane.insertTab(pinned, at: 2)

        XCTAssertEqual(pane.tabs.map(\.isPinned), [true, false, false])
        XCTAssertEqual(pane.tabs.first?.id, pinned.id)
    }

    @MainActor
    func testMovingUnpinnedTabCannotCrossPinnedBoundary() {
        let pinnedA = TabItem(title: "Pinned A", isPinned: true)
        let pinnedB = TabItem(title: "Pinned B", isPinned: true)
        let unpinnedA = TabItem(title: "A", isPinned: false)
        let unpinnedB = TabItem(title: "B", isPinned: false)
        let pane = PaneState(
            tabs: [pinnedA, pinnedB, unpinnedA, unpinnedB],
            selectedTabId: unpinnedB.id
        )

        // Attempt to move an unpinned tab ahead of pinned tabs; move should clamp to
        // the first unpinned position.
        pane.moveTab(from: 3, to: 0)

        XCTAssertEqual(pane.tabs.map(\.id), [pinnedA.id, pinnedB.id, unpinnedB.id, unpinnedA.id])
        XCTAssertEqual(pane.tabs.prefix(2).allSatisfy(\.isPinned), true)
        XCTAssertEqual(pane.tabs.suffix(2).allSatisfy { !$0.isPinned }, true)
    }

    @MainActor
    func testCreateTabStoresKindAndPinnedState() {
        let controller = BonsplitController()
        let tabId = controller.createTab(
            title: "Browser",
            icon: "globe",
            kind: "browser",
            isPinned: true
        )!

        let tab = controller.tab(tabId)
        XCTAssertEqual(tab?.kind, "browser")
        XCTAssertEqual(tab?.isPinned, true)
    }

    @MainActor
    func testCreateAndUpdateTabCustomTitleFlag() {
        let controller = BonsplitController()
        let tabId = controller.createTab(
            title: "Infra",
            hasCustomTitle: true
        )!

        XCTAssertEqual(controller.tab(tabId)?.hasCustomTitle, true)

        controller.updateTab(tabId, hasCustomTitle: false)
        XCTAssertEqual(controller.tab(tabId)?.hasCustomTitle, false)
    }

    @MainActor
    func testSplitPaneWithOptionalTabPreservesCustomTitleFlag() {
        let controller = BonsplitController()
        _ = controller.createTab(title: "Base")
        let sourcePaneId = controller.focusedPaneId!
        let customTab = Bonsplit.Tab(title: "Custom", hasCustomTitle: true)

        guard let newPaneId = controller.splitPane(sourcePaneId, orientation: .horizontal, withTab: customTab) else {
            return XCTFail("Expected splitPane to return new pane")
        }
        let inserted = controller.tabs(inPane: newPaneId).first(where: { $0.id == customTab.id })
        XCTAssertEqual(inserted?.hasCustomTitle, true)
    }

    @MainActor
    func testSplitPaneWithInsertSidePreservesCustomTitleFlag() {
        let controller = BonsplitController()
        _ = controller.createTab(title: "Base")
        let sourcePaneId = controller.focusedPaneId!
        let customTab = Bonsplit.Tab(title: "Custom", hasCustomTitle: true)

        guard let newPaneId = controller.splitPane(
            sourcePaneId,
            orientation: .vertical,
            withTab: customTab,
            insertFirst: true
        ) else {
            return XCTFail("Expected splitPane(insertFirst:) to return new pane")
        }
        let inserted = controller.tabs(inPane: newPaneId).first(where: { $0.id == customTab.id })
        XCTAssertEqual(inserted?.hasCustomTitle, true)
    }

    @MainActor
    func testTogglePaneZoomTracksState() {
        let controller = BonsplitController()
        guard let originalPane = controller.focusedPaneId else {
            return XCTFail("Expected focused pane")
        }

        // Single-pane layouts cannot be zoomed.
        XCTAssertFalse(controller.togglePaneZoom(inPane: originalPane))
        XCTAssertNil(controller.zoomedPaneId)

        guard controller.splitPane(originalPane, orientation: .horizontal) != nil else {
            return XCTFail("Expected splitPane to create a new pane")
        }

        XCTAssertTrue(controller.togglePaneZoom(inPane: originalPane))
        XCTAssertEqual(controller.zoomedPaneId, originalPane)
        XCTAssertTrue(controller.isSplitZoomed)

        XCTAssertTrue(controller.togglePaneZoom(inPane: originalPane))
        XCTAssertNil(controller.zoomedPaneId)
        XCTAssertFalse(controller.isSplitZoomed)
    }

    @MainActor
    func testRequestTabZoomToggleUsesHostHandler() {
        let controller = BonsplitController()
        let pane = controller.focusedPaneId!
        let tabId = controller.createTab(title: "Zoom target")!
        var requestedTabId: TabID?
        var requestedPaneId: PaneID?
        controller.onTabZoomToggleRequest = { tabId, paneId in
            requestedTabId = tabId
            requestedPaneId = paneId
            return true
        }

        XCTAssertTrue(controller.requestTabZoomToggle(for: tabId, inPane: pane))

        XCTAssertEqual(requestedTabId, tabId)
        XCTAssertEqual(requestedPaneId, pane)
        XCTAssertNil(controller.zoomedPaneId)
    }

    @MainActor
    func testRequestTabZoomToggleFallsBackToInternalZoom() {
        let controller = BonsplitController()
        let pane = controller.focusedPaneId!
        let tabId = controller.createTab(title: "Zoom target")!
        guard controller.splitPane(pane, orientation: .horizontal) != nil else {
            return XCTFail("Expected splitPane to create a new pane")
        }

        XCTAssertTrue(controller.requestTabZoomToggle(for: tabId, inPane: pane))
        XCTAssertEqual(controller.zoomedPaneId, pane)

        XCTAssertTrue(controller.requestTabZoomToggle(for: tabId, inPane: pane))
        XCTAssertNil(controller.zoomedPaneId)
    }

    @MainActor
    func testSplitClearsExistingPaneZoom() {
        let controller = BonsplitController()
        guard let originalPane = controller.focusedPaneId else {
            return XCTFail("Expected focused pane")
        }

        guard let secondPane = controller.splitPane(originalPane, orientation: .horizontal) else {
            return XCTFail("Expected splitPane to create a new pane")
        }

        XCTAssertTrue(controller.togglePaneZoom(inPane: secondPane))
        XCTAssertEqual(controller.zoomedPaneId, secondPane)

        _ = controller.splitPane(secondPane, orientation: .vertical)
        XCTAssertNil(controller.zoomedPaneId, "Splitting should reset zoom state")
    }

    @MainActor
    func testRequestTabContextActionForwardsToDelegate() {
        let controller = BonsplitController()
        let pane = controller.focusedPaneId!
        let tabId = controller.createTab(title: "Test", kind: "browser")!
        let spy = TabContextActionDelegateSpy()
        controller.delegate = spy

        controller.requestTabContextAction(.reload, for: tabId, inPane: pane)

        XCTAssertEqual(spy.action, .reload)
        XCTAssertEqual(spy.tabId, tabId)
        XCTAssertEqual(spy.paneId, pane)
    }

    @MainActor
    func testRequestTabContextActionForwardsMarkAsReadToDelegate() {
        let controller = BonsplitController()
        let pane = controller.focusedPaneId!
        let tabId = controller.createTab(title: "Test", kind: "terminal")!
        let spy = TabContextActionDelegateSpy()
        controller.delegate = spy

        controller.requestTabContextAction(.markAsRead, for: tabId, inPane: pane)

        XCTAssertEqual(spy.action, .markAsRead)
        XCTAssertEqual(spy.tabId, tabId)
        XCTAssertEqual(spy.paneId, pane)
    }

    @MainActor
    func testRequestTabMoveDestinationForwardsToDelegate() {
        let controller = BonsplitController()
        let pane = controller.focusedPaneId!
        let tabId = controller.createTab(title: "Test", kind: "terminal")!
        let spy = TabContextActionDelegateSpy()
        controller.delegate = spy

        controller.requestTabMove(toDestination: "workspace:abc", for: tabId, inPane: pane)

        XCTAssertEqual(spy.moveDestinationId, "workspace:abc")
        XCTAssertEqual(spy.tabId, tabId)
        XCTAssertEqual(spy.paneId, pane)
    }

    @MainActor
    func testTabContextMenuBuilderCreatesAppKitMoveSubmenu() throws {
        let target = TabContextMenuActionTarget()
        var selectedAction: TabContextAction?
        var selectedDestinationId: String?
        target.onContextAction = { selectedAction = $0 }
        target.onMoveDestination = { selectedDestinationId = $0 }
        let state = TabContextMenuState(
            isPinned: false,
            isUnread: false,
            isBrowser: false,
            isAudioMuted: false,
            isTerminal: true,
            hasCustomTitle: false,
            canCloseToLeft: true,
            canCloseToRight: true,
            canCloseOthers: true,
            canMoveToNewWorkspace: true,
            canMoveToLeftPane: false,
            canMoveToRightPane: true,
            canForkConversation: false,
            forkConversationDefaultAction: .forkConversationRight,
            isZoomed: false,
            hasSplits: true,
            shortcuts: [:]
        )
        var moveDestinationRequestCount = 0
        let snapshot = TabContextMenuSnapshot(
            tabId: UUID(),
            state: state,
            moveDestinationsProvider: {
                moveDestinationRequestCount += 1
                return [
                    TabContextMoveDestination(id: "workspace:abc", title: "Workspace A", isEnabled: false)
                ]
            }
        )

        let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: target)
        let moveItem = menu.items.first { $0.title == "Move Tab" }

        XCTAssertEqual(moveDestinationRequestCount, 1)
        XCTAssertNotNil(moveItem)
        XCTAssertTrue(moveItem?.isEnabled ?? false)
        XCTAssertEqual(moveItem?.submenu?.items.map(\.title), ["Move Tab to New Workspace", "Workspace A"])
        XCTAssertEqual(moveItem?.submenu?.items.map(\.isEnabled), [true, false])

        let newWorkspaceItem = try XCTUnwrap(moveItem?.submenu?.items.first)
        target.performContextAction(newWorkspaceItem)
        XCTAssertEqual(selectedAction, .moveToNewWorkspace)

        let workspaceItem = try XCTUnwrap(moveItem?.submenu?.items.dropFirst().first)
        target.performMoveDestination(workspaceItem)
        XCTAssertEqual(selectedDestinationId, "workspace:abc")
    }

    @MainActor
    func testBrowserTabContextMenuCreatesAudioMuteToggle() throws {
        let target = TabContextMenuActionTarget()
        var selectedAction: TabContextAction?
        target.onContextAction = { selectedAction = $0 }
        let snapshot = TabContextMenuSnapshot(
            tabId: UUID(),
            state: TabContextMenuState(
                isPinned: false,
                isUnread: false,
                isBrowser: true,
                isAudioMuted: false,
                isTerminal: false,
                hasCustomTitle: false,
                canCloseToLeft: false,
                canCloseToRight: false,
                canCloseOthers: false,
                canMoveToNewWorkspace: false,
                canMoveToLeftPane: false,
                canMoveToRightPane: false,
                canForkConversation: false,
                forkConversationDefaultAction: .forkConversationRight,
                isZoomed: false,
                hasSplits: false,
                shortcuts: [:]
            ),
            moveDestinationsProvider: { [] }
        )

        let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: target)
        let muteItem = try XCTUnwrap(menu.items.first { $0.title == "Mute Tab" })
        target.performContextAction(muteItem)

        XCTAssertEqual(selectedAction, .toggleAudioMute)
    }

    @MainActor
    func testBrowserTabContextMenuUsesUnmuteTitleWhenAudioMuted() throws {
        let target = TabContextMenuActionTarget()
        let snapshot = TabContextMenuSnapshot(
            tabId: UUID(),
            state: TabContextMenuState(
                isPinned: false,
                isUnread: false,
                isBrowser: true,
                isAudioMuted: true,
                isTerminal: false,
                hasCustomTitle: false,
                canCloseToLeft: false,
                canCloseToRight: false,
                canCloseOthers: false,
                canMoveToNewWorkspace: false,
                canMoveToLeftPane: false,
                canMoveToRightPane: false,
                canForkConversation: false,
                forkConversationDefaultAction: .forkConversationRight,
                isZoomed: false,
                hasSplits: false,
                shortcuts: [:]
            ),
            moveDestinationsProvider: { [] }
        )

        let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: target)

        XCTAssertTrue(menu.items.contains { $0.title == "Unmute Tab" })
        XCTAssertFalse(menu.items.contains { $0.title == "Mute Tab" })
    }

    @MainActor
    func testTabContextMenuBuilderCreatesForkConversationSubmenu() throws {
        let target = TabContextMenuActionTarget()
        var selectedAction: TabContextAction?
        target.onContextAction = { selectedAction = $0 }
        let state = TabContextMenuState(
            isPinned: false,
            isUnread: false,
            isBrowser: false,
            isAudioMuted: false,
            isTerminal: true,
            hasCustomTitle: false,
            canCloseToLeft: true,
            canCloseToRight: true,
            canCloseOthers: true,
            canMoveToNewWorkspace: false,
            canMoveToLeftPane: false,
            canMoveToRightPane: false,
            canForkConversation: true,
            forkConversationDefaultAction: .forkConversationLeft,
            isZoomed: false,
            hasSplits: false,
            shortcuts: [:]
        )
        let snapshot = TabContextMenuSnapshot(
            tabId: UUID(),
            state: state,
            moveDestinationsProvider: { [] }
        )

        let menu = TabContextMenuBuilder.makeMenu(snapshot: snapshot, target: target)
        let forkItem = try XCTUnwrap(menu.items.first { $0.title == "Fork Conversation" })
        target.performContextAction(forkItem)
        XCTAssertEqual(selectedAction, .forkConversation)

        let forkSubmenuItem = try XCTUnwrap(menu.items.first { $0.title == "Fork Conversation To" })
        let destinationItems = try XCTUnwrap(forkSubmenuItem.submenu?.items.filter { !$0.isSeparatorItem })
        XCTAssertEqual(
            destinationItems.map(\.title),
            ["Right Split", "Left Split", "Top Split", "Bottom Split", "New Tab", "New Workspace"]
        )
        XCTAssertEqual(destinationItems.map(\.state), [.off, .on, .off, .off, .off, .off])

        let newTabItem = try XCTUnwrap(destinationItems.first { $0.title == "New Tab" })
        target.performContextAction(newTabItem)
        XCTAssertEqual(selectedAction, .forkConversationNewTab)
    }

    @MainActor
    func testDoubleClickingEmptyTrailingTabBarSpaceRequestsNewTerminalTab() {
        let appearance = BonsplitConfiguration.Appearance()
        let configuration = BonsplitConfiguration(appearance: appearance)
        let controller = BonsplitController(configuration: configuration)
        let pane = controller.internalController.rootNode.allPanes.first!
        let spy = NewTabRequestDelegateSpy()
        controller.delegate = spy

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: true)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 60),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        let clickPoint = NSPoint(x: hostingView.bounds.maxX - 12, y: hostingView.bounds.midY)
        let pointInWindow = hostingView.convert(clickPoint, to: nil)
        guard let hitView = waitForDescendant(
            ofType: TabBarDragZoneView.DragNSView.self,
            in: contentView,
            containingWindowPoint: pointInWindow,
            where: { $0.onDoubleClick != nil }
        ) else {
            XCTFail("Expected trailing tab bar drag zone")
            return
        }
        XCTAssertEqual(hitView.onDoubleClick?(), true)

        XCTAssertEqual(spy.requestedKind, "terminal")
        XCTAssertEqual(spy.requestedPaneId, pane.id)
    }

    @MainActor
    func testEmptyTrailingTabBarSpaceDoesNotRequestNewTerminalWhenButtonHidden() {
        let appearance = BonsplitConfiguration.Appearance(splitButtons: [])
        let configuration = BonsplitConfiguration(appearance: appearance)
        let controller = BonsplitController(configuration: configuration)
        let pane = controller.internalController.rootNode.allPanes.first!
        let spy = NewTabRequestDelegateSpy()
        controller.delegate = spy

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: true)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 60),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        let clickPoint = NSPoint(x: hostingView.bounds.maxX - 12, y: hostingView.bounds.midY)
        let pointInWindow = hostingView.convert(clickPoint, to: nil)
        guard let hitView = waitForDescendant(
            ofType: TabBarDragZoneView.DragNSView.self,
            in: contentView,
            containingWindowPoint: pointInWindow,
            where: { $0.onDoubleClick != nil }
        ) else {
            XCTFail("Expected trailing tab bar drag zone")
            return
        }
        XCTAssertEqual(hitView.onDoubleClick?(), false)

        XCTAssertNil(spy.requestedKind)
        XCTAssertNil(spy.requestedPaneId)
    }

    @MainActor
    func testShortConfiguredTabKeepsCompactChromeWithExpandedHitSlop() {
        let appearance = BonsplitConfiguration.Appearance(
            tabMinWidth: 140,
            tabMaxWidth: 220,
            splitButtons: []
        )
        let controller = BonsplitController(configuration: BonsplitConfiguration(appearance: appearance))
        let pane = controller.internalController.rootNode.allPanes.first!
        let tab = TabItem(title: "~", icon: "terminal.fill")
        pane.tabs = [tab]
        pane.selectedTabId = tab.id

        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: true, showSplitButtons: true)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        let verticalCenter = appearance.tabBarHeight / 2
        let compactTabHitEdge = TabBarMetrics.tabMinWidth + BonsplitTabItemHitTesting.horizontalSlop
        let expandedHitPoint = hostingView.convert(
            NSPoint(x: compactTabHitEdge - 2, y: verticalCenter),
            to: nil
        )
        XCTAssertTrue(
            BonsplitTabItemHitRegionRegistry.containsWindowPoint(expandedHitPoint, in: window),
            "A short-titled tab should keep compact visible chrome while owning a small expanded hit rect for minimal-mode drags"
        )

        let topEdgeTabPoint = hostingView.convert(
            NSPoint(x: compactTabHitEdge - 2, y: appearance.tabBarHeight + 3),
            to: nil
        )
        XCTAssertTrue(
            BonsplitTabItemHitRegionRegistry.containsWindowPoint(topEdgeTabPoint, in: window),
            "A tab's horizontal lane must own near-titlebar-edge drags so minimal-mode top-edge tab drags do not become window drags"
        )

        let emptyChromePoint = hostingView.convert(
            NSPoint(x: compactTabHitEdge + 24, y: verticalCenter),
            to: nil
        )
        XCTAssertFalse(
            BonsplitTabItemHitRegionRegistry.containsWindowPoint(emptyChromePoint, in: window),
            "Empty tab-strip chrome after the configured tab remains available for app-window dragging"
        )

        let topEdgeEmptyChromePoint = hostingView.convert(
            NSPoint(x: compactTabHitEdge + 24, y: appearance.tabBarHeight + 3),
            to: nil
        )
        XCTAssertFalse(
            BonsplitTabItemHitRegionRegistry.containsWindowPoint(topEdgeEmptyChromePoint, in: window),
            "Near-titlebar-edge empty chrome after the tab should remain available for app-window dragging"
        )
    }

    @MainActor
    func testTabBarVisibilityDefaultsToAlways() throws {
        XCTAssertEqual(BonsplitConfiguration().tabBarVisibility, .always)
        XCTAssertTrue(try XCTUnwrap(renderedPaneContainerHasTabBar(tabCount: 0, visibility: .always)))
        XCTAssertTrue(try XCTUnwrap(renderedPaneContainerHasTabBar(tabCount: 1, visibility: .always)))
        XCTAssertTrue(try XCTUnwrap(renderedPaneContainerHasTabBar(tabCount: 2, visibility: .always)))
    }

    @MainActor
    func testMultipleTabsVisibilityHidesPaneBarUntilThereAreMultipleTabs() throws {
        XCTAssertFalse(try XCTUnwrap(renderedPaneContainerHasTabBar(tabCount: 0, visibility: .multipleTabs)))
        XCTAssertFalse(try XCTUnwrap(renderedPaneContainerHasTabBar(tabCount: 1, visibility: .multipleTabs)))
        XCTAssertTrue(try XCTUnwrap(renderedPaneContainerHasTabBar(tabCount: 2, visibility: .multipleTabs)))
    }

    func testIconSaturationKeepsRasterFaviconInColorWhenInactive() {
        XCTAssertEqual(
            TabItemStyling.iconSaturation(hasRasterIcon: true, tabSaturation: 0.0),
            1.0
        )
    }

    func testIconSaturationStillDesaturatesSymbolIconsWhenInactive() {
        XCTAssertEqual(
            TabItemStyling.iconSaturation(hasRasterIcon: false, tabSaturation: 0.0),
            0.0
        )
    }

    func testResolvedFaviconImageUsesIncomingDataWhenDecodable() {
        let existing = NSImage(size: NSSize(width: 12, height: 12))
        let incoming = NSImage(size: NSSize(width: 16, height: 16))
        incoming.lockFocus()
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        incoming.unlockFocus()
        let data = incoming.tiffRepresentation

        let resolved = TabItemStyling.resolvedFaviconImage(existing: existing, incomingData: data)
        XCTAssertNotNil(resolved)
        XCTAssertFalse(resolved === existing)
    }

    func testResolvedFaviconImageKeepsExistingImageWhenIncomingDataIsInvalid() {
        let existing = NSImage(size: NSSize(width: 16, height: 16))
        let invalidData = Data([0x00, 0x11, 0x22, 0x33])

        let resolved = TabItemStyling.resolvedFaviconImage(existing: existing, incomingData: invalidData)
        XCTAssertTrue(resolved === existing)
    }

    func testResolvedFaviconImageClearsWhenIncomingDataIsNil() {
        let existing = NSImage(size: NSSize(width: 16, height: 16))
        let resolved = TabItemStyling.resolvedFaviconImage(existing: existing, incomingData: nil)
        XCTAssertNil(resolved)
    }

    @MainActor
    func testLoadingSpinnerUsesCoreAnimationRotationLayer() throws {
        let spinner = TabLoadingSpinnerLayerView(frame: NSRect(x: 4, y: 4, width: 12, height: 12))
        spinner.configure(size: 12, color: .labelColor)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        contentView.addSubview(spinner)
        contentView.layoutSubtreeIfNeeded()
        spinner.layoutSubtreeIfNeeded()

        try withExtendedLifetime(window) {
            let animation = try XCTUnwrap(
                spinner.activeRotationAnimationForTesting as? CABasicAnimation
            )
            XCTAssertEqual(animation.keyPath, "transform.rotation.z")
            XCTAssertEqual(animation.duration, TabLoadingSpinnerLayerView.rotationDuration, accuracy: 0.001)
            XCTAssertEqual(animation.repeatCount, .infinity)
            XCTAssertFalse(animation.isRemovedOnCompletion)
            XCTAssertEqual(spinner.arcStrokeEndForTesting, 0.28, accuracy: 0.001)
            XCTAssertEqual(spinner.ringWidthForTesting, max(1.6, 12 * 0.14), accuracy: 0.001)
        }
    }

    @MainActor
    func testLoadingSpinnerResolvesDynamicColorWithEffectiveAppearance() throws {
        let previousAppearance = NSApplication.shared.appearance
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
        defer { NSApplication.shared.appearance = previousAppearance }

        let spinner = TabLoadingSpinnerLayerView(frame: NSRect(x: 4, y: 4, width: 12, height: 12))
        spinner.configure(size: 12, color: .labelColor)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = contentView
        contentView.addSubview(spinner)
        contentView.layoutSubtreeIfNeeded()
        spinner.layoutSubtreeIfNeeded()

        try withExtendedLifetime(window) {
            let cgColor = try XCTUnwrap(spinner.arcStrokeColorForTesting)
            let color = try XCTUnwrap(NSColor(cgColor: cgColor)?.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(color.redComponent, 0.9)
            XCTAssertGreaterThan(color.greenComponent, 0.9)
            XCTAssertGreaterThan(color.blueComponent, 0.9)
        }
    }

    @MainActor
    func testLoadingSpinnerStopsCoreAnimationWhenRemovedFromWindow() throws {
        let spinner = TabLoadingSpinnerLayerView(frame: NSRect(x: 4, y: 4, width: 12, height: 12))
        spinner.configure(size: 12, color: .labelColor)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        let window = NSWindow(
            contentRect: contentView.bounds,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        contentView.addSubview(spinner)

        withExtendedLifetime(window) {
            XCTAssertNotNil(spinner.activeRotationAnimationForTesting)

            spinner.removeFromSuperview()
            XCTAssertNil(spinner.activeRotationAnimationForTesting)
        }
    }

    func testTabControlShortcutHintPolicyMatchesConfiguredModifiers() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults)?.symbol,
                "⌃"
            )
            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)?.symbol,
                "⌃"
            )
            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [], defaults: defaults))
            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.control, .shift], defaults: defaults))
            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.command, .option], defaults: defaults))

            defaults.set(
                shortcutData(
                    key: "1",
                    command: true,
                    shift: false,
                    option: true,
                    control: false
                ),
                forKey: "shortcut.selectSurfaceByNumber"
            )

            let custom = TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)
            XCTAssertEqual(custom?.symbol, "⌥⌘")
            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)?.symbol,
                "⌥⌘"
            )
            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults)?.symbol,
                "⌥⌘"
            )
        }
    }

    func testTabControlShortcutHintPolicyCanDisableCommandAndControlHoldHintsIndependently() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.set(false, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults))
            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults)?.symbol,
                "⌃"
            )

            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(false, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertEqual(
                TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)?.symbol,
                "⌃"
            )
            XCTAssertNil(TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults))
        }
    }

    func testTabControlShortcutHintPolicyDefaultsToShowingHoldHints() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.removeObject(forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.removeObject(forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertEqual(TabControlShortcutHintPolicy.hintModifier(for: [.control], defaults: defaults)?.symbol, "⌃")
            XCTAssertEqual(TabControlShortcutHintPolicy.hintModifier(for: [.command], defaults: defaults)?.symbol, "⌃")
        }
    }

    func testTabControlShortcutHintsAreScopedToCurrentKeyWindow() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertTrue(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: true,
                    eventWindowNumber: 42,
                    keyWindowNumber: 42,
                    defaults: defaults
                )
            )

            XCTAssertFalse(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: true,
                    eventWindowNumber: 7,
                    keyWindowNumber: 42,
                    defaults: defaults
                )
            )

            XCTAssertFalse(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: false,
                    eventWindowNumber: 42,
                    keyWindowNumber: 42,
                    defaults: defaults
                )
            )
        }
    }

    func testTabControlShortcutHintsFallbackToKeyWindowWhenEventWindowMissing() {
        withShortcutHintDefaultsSuite { defaults in
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnCommandHoldKey)
            defaults.set(true, forKey: TabControlShortcutHintPolicy.showHintsOnControlHoldKey)

            XCTAssertTrue(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: true,
                    eventWindowNumber: nil,
                    keyWindowNumber: 42,
                    defaults: defaults
                )
            )

            XCTAssertFalse(
                TabControlShortcutHintPolicy.shouldShowHints(
                    for: [.control],
                    hostWindowNumber: 42,
                    hostWindowIsKey: true,
                    eventWindowNumber: nil,
                    keyWindowNumber: 7,
                    defaults: defaults
                )
            )
        }
    }

    @MainActor
    func testControllerMirrorsTabShortcutHintEligibilityToInternalController() {
        let controller = BonsplitController()

        XCTAssertTrue(controller.tabShortcutHintsEnabled)
        XCTAssertTrue(controller.internalController.tabShortcutHintsEnabled)

        controller.tabShortcutHintsEnabled = false

        XCTAssertFalse(controller.tabShortcutHintsEnabled)
        XCTAssertFalse(controller.internalController.tabShortcutHintsEnabled)
    }

    func testLegacyFileDropsOnlyValidateCenterZone() {
        XCTAssertTrue(
            UnifiedPaneDropDelegate.acceptsFileDrop(
                zone: .center,
                hasExternalFileDropHandler: false,
                hasLegacyFileDropHandler: true
            )
        )
        XCTAssertFalse(
            UnifiedPaneDropDelegate.acceptsFileDrop(
                zone: .left,
                hasExternalFileDropHandler: false,
                hasLegacyFileDropHandler: true
            )
        )
        XCTAssertFalse(
            UnifiedPaneDropDelegate.acceptsFileDrop(
                zone: .center,
                hasExternalFileDropHandler: false,
                hasLegacyFileDropHandler: false
            )
        )
        XCTAssertTrue(
            UnifiedPaneDropDelegate.acceptsFileDrop(
                zone: .right,
                hasExternalFileDropHandler: true,
                hasLegacyFileDropHandler: false
            )
        )
    }

    func testLegacyFileDropUpdatedRejectsEdgeZones() {
        XCTAssertEqual(
            UnifiedPaneDropDelegate.acceptedDropZone(
                .center,
                isFileDropOnly: true,
                hasExternalFileDropHandler: false,
                hasLegacyFileDropHandler: true
            ),
            .center
        )
        XCTAssertNil(
            UnifiedPaneDropDelegate.acceptedDropZone(
                .left,
                isFileDropOnly: true,
                hasExternalFileDropHandler: false,
                hasLegacyFileDropHandler: true
            )
        )
        XCTAssertEqual(
            UnifiedPaneDropDelegate.acceptedDropZone(
                .left,
                isFileDropOnly: true,
                hasExternalFileDropHandler: true,
                hasLegacyFileDropHandler: false
            ),
            .left
        )
        XCTAssertEqual(
            UnifiedPaneDropDelegate.acceptedDropZone(
                .left,
                isFileDropOnly: false,
                hasExternalFileDropHandler: false,
                hasLegacyFileDropHandler: false
            ),
            .left
        )
    }

    func testFileURLPasteboardReaderReturnsFileURLs() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bonsplit-file-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("sample.txt")
        try "sample".write(to: fileURL, atomically: true, encoding: .utf8)

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("bonsplit.file-drop.\(UUID().uuidString)"))
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))

        XCTAssertEqual(UnifiedPaneDropDelegate.fileURLs(from: pasteboard), [fileURL])
    }

    func testFileDropValidationRequiresReadablePasteboardURLs() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("bonsplit.file-drop.empty.\(UUID().uuidString)"))
        pasteboard.clearContents()

        XCTAssertFalse(UnifiedPaneDropDelegate.hasReadableFileURLs(from: pasteboard))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bonsplit-file-drop-readable-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("sample.txt")
        try "sample".write(to: fileURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL]))
        XCTAssertTrue(UnifiedPaneDropDelegate.hasReadableFileURLs(from: pasteboard))
    }

    func testFileOnlyDropsDoNotUseStaleLocalTabDragState() {
        XCTAssertFalse(
            UnifiedPaneDropDelegate.shouldUseLocalTabDrag(
                hasTabTransfer: false,
                hasFileURL: true,
                hasLocalTabDrag: true
            )
        )
        XCTAssertTrue(
            UnifiedPaneDropDelegate.shouldUseLocalTabDrag(
                hasTabTransfer: true,
                hasFileURL: false,
                hasLocalTabDrag: true
            )
        )
        XCTAssertFalse(
            UnifiedPaneDropDelegate.shouldUseLocalTabDrag(
                hasTabTransfer: true,
                hasFileURL: false,
                hasLocalTabDrag: false
            )
        )
    }

    func testSelectedTabNeverShowsHoverBackground() {
        XCTAssertFalse(
            TabItemStyling.shouldShowHoverBackground(isHovered: true, isSelected: true)
        )
        XCTAssertTrue(
            TabItemStyling.shouldShowHoverBackground(isHovered: true, isSelected: false)
        )
        XCTAssertFalse(
            TabItemStyling.shouldShowHoverBackground(isHovered: false, isSelected: false)
        )
    }

    func testTabWidthRangeKeepsCompactVisualMinimum() {
        let range = TabItemStyling.tabWidthRange(
            for: BonsplitConfiguration.Appearance(tabMinWidth: 140, tabMaxWidth: 220)
        )

        XCTAssertEqual(range.lowerBound, TabBarMetrics.tabMinWidth)
        XCTAssertEqual(range.upperBound, 220)
    }

    func testActiveTabIndicatorHeightIsOneAndHalfPixels() {
        XCTAssertEqual(TabBarMetrics.activeIndicatorHeight, 1.5)
    }

    @MainActor
    func testActiveTabIndicatorLeavesTrailingPixelGap() {
        guard let width = renderedTabBarIndicatorWidth(isFocused: true) else {
            XCTFail("Expected rendered tab bar indicator width")
            return
        }

        XCTAssertEqual(
            width,
            TabBarMetrics.tabMinWidth - TabBarMetrics.activeIndicatorTrailingInset,
            accuracy: 0.5
        )
    }

    @MainActor
    func testSelectedTabLeftSeparatorDoesNotOverlapBottomSeparator() {
        guard let alphas = renderedSelectedTabLeftSeparatorAlphas() else {
            XCTFail("Expected rendered selected tab separator alphas")
            return
        }

        XCTAssertGreaterThan(alphas.top, 0.3)
        XCTAssertEqual(alphas.bottom, alphas.top, accuracy: 0.08)
    }

    @MainActor
    func testInactiveSelectedTabIndicatorUsesDesaturatedAccent() {
        guard let focusedSaturation = renderedTabBarIndicatorSaturation(isFocused: true),
              let unfocusedSaturation = renderedTabBarIndicatorSaturation(isFocused: false) else {
            XCTFail("Expected rendered tab bar colors")
            return
        }

        XCTAssertGreaterThan(focusedSaturation, 0.4)
        XCTAssertLessThan(unfocusedSaturation, 0.1)
    }

    @MainActor
    func testActiveTabIndicatorTracksSelectedTabAfterHorizontalScroll() {
        let size = NSSize(width: 160, height: TabBarMetrics.barHeight)
        let range = renderedSelectedIndicatorRangeAfterManualScroll(size: size)
        XCTAssertNil(
            range,
            "Selected indicator should scroll with its tab and leave the visible lane when the selected tab is manually scrolled out of view."
        )
    }

    @MainActor
    func testActiveTabIndicatorIgnoresAnimatedSelectionTransactions() {
        guard let range = renderedIndicatorRangeAfterAnimatedSelectionChange() else {
            XCTFail("Expected rendered selected indicator after selection change")
            return
        }

        XCTAssertGreaterThan(
            range.lowerBound,
            TabBarMetrics.tabMinWidth - 4,
            "Selected indicator should jump to the new selected tab instead of animating from the previous tab frame."
        )
    }

    @MainActor
    func testSplitButtonLaneDoesNotExposeSelectedTabIndicator() {
        guard let saturation = renderedSplitButtonLaneTopSaturation() else {
            XCTFail("Expected rendered split button lane colors")
            return
        }

        XCTAssertLessThan(saturation, 0.2)
    }

    @MainActor
    func testSplitButtonBackdropFadePaintsFullTabBarHeight() {
        guard let delta = renderedSplitButtonBackdropFadeVerticalColorDelta() else {
            XCTFail("Expected rendered split button backdrop fade colors")
            return
        }

        XCTAssertLessThan(delta, 0.08)
    }

    @MainActor
    func testSplitButtonBackdropSolidSurfaceCoversVisibleLane() {
        guard let brightness = renderedSplitButtonLaneSolidBackdropBrightness() else {
            XCTFail("Expected rendered split button lane backdrop color")
            return
        }

        XCTAssertGreaterThan(brightness, 0.5)
    }

    @MainActor
    func testSplitButtonBackdropDoesNotPaintSolidSurfaceAtTabContentFadeStart() {
        guard let brightness = renderedSplitButtonContentFadeStartBackdropBrightness() else {
            XCTFail("Expected rendered split button content fade backdrop color")
            return
        }

        XCTAssertLessThan(brightness, 0.1)
    }

    @MainActor
    func testSplitButtonBackdropOccludesTabChromeAtContentFadeStart() {
        guard let saturation = renderedSplitButtonContentFadeStartSaturation() else {
            XCTFail("Expected rendered split button content fade colors")
            return
        }

        XCTAssertLessThan(saturation, 0.2)
    }

    @MainActor
    func testSelectedTabIndicatorDoesNotBleedUnderSplitButtonBackdrop() {
        guard let brightnesses = renderedSelectedIndicatorBackdropBrightnesses() else {
            XCTFail("Expected rendered selected indicator backdrop colors")
            return
        }

        XCTAssertLessThan(brightnesses.leading, 0.08)
        XCTAssertLessThan(brightnesses.trailing, 0.08)
    }

    @MainActor
    func testSharedBackdropTransparentActionLaneDoesNotPaintSyntheticSurface() {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(
                backgroundHex: "#272822B8",
                tabBarBackgroundHex: "#00000000",
                splitButtonBackdropHex: "#00000000",
                paneBackgroundHex: "#00000000"
            ),
            usesSharedBackdrop: true
        )

        XCTAssertFalse(TabBarColors.shouldPaintSplitButtonBackdrop(for: appearance))
    }

    @MainActor
    func testSharedBackdropManySplitButtonsMaskTabContentWithoutSyntheticSurface() {
        guard let alpha = renderedSharedBackdropActionLaneSurfaceAlpha() else {
            XCTFail("Expected rendered shared backdrop action lane color")
            return
        }

        XCTAssertLessThan(alpha, 0.05)
    }

    @MainActor
    func testOverflowingSplitButtonsClipToActionLane() {
        guard let brightness = renderedEscapedSplitButtonBrightnessOutsideActionLane() else {
            XCTFail("Expected rendered split button overflow colors")
            return
        }

        XCTAssertLessThan(brightness, 0.30)
    }

    @MainActor
    func testSharedBackdropActionLaneBottomSeparatorCoversSolidAreaAndFadesOut() {
        guard let alphas = renderedSharedBackdropActionLaneBottomSeparatorAlphas() else {
            XCTFail("Expected rendered shared backdrop action lane separator colors")
            return
        }

        XCTAssertGreaterThan(alphas.solid, 0.25)
        XCTAssertLessThan(alphas.fadeStart, alphas.solid * 0.25)
        XCTAssertLessThan(alphas.beforeRamp, alphas.solid * 0.25)
        XCTAssertGreaterThan(alphas.afterRamp, alphas.solid * 0.25)
        XCTAssertGreaterThan(alphas.fadeEnd, alphas.solid * 0.55)
        XCTAssertEqual(alphas.fadeEnd, alphas.solidStart, accuracy: 0.15)
    }

    func testSharedBackdropActionLaneSeparatorMatchesBackdropGradientGeometry() {
        let buttonCount = 28
        let size = NSSize(width: 360, height: 28)
        let layout = TabBarLayout(
            tabBarHeight: size.height,
            availableWidth: size.width,
            splitButtonCount: buttonCount,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: TabBarStyling.splitButtonsBackdropWidth(buttonCount: buttonCount)
        )
        let snapshot = TabBarChromeSnapshot(
            appearance: sharedBackdropManyActionAppearance(
                tabBarHeight: size.height,
                buttonCount: buttonCount
            ),
            layout: layout,
            isFocused: true,
            shouldShowSplitButtons: true,
            fadeColorStyle: 0
        )

        XCTAssertEqual(snapshot.actionLaneSeparatorFadeWidth, snapshot.backdropFadeWidth, accuracy: 0.0001)
        XCTAssertEqual(snapshot.actionLaneSeparatorSolidWidth, snapshot.actionLaneWidth, accuracy: 0.0001)
        XCTAssertEqual(snapshot.backdropSolidWidth, snapshot.actionLaneWidth, accuracy: 0.0001)
        XCTAssertEqual(
            snapshot.actionLaneSeparatorFadeWidth + snapshot.actionLaneSeparatorSolidWidth,
            snapshot.backdropFadeWidth + snapshot.actionLaneWidth,
            accuracy: 0.0001
        )
    }

    func testSharedBackdropActionLaneSeparatorCanBeNarrowerThanContentFade() {
        let buttonCount = 28
        let size = NSSize(width: 360, height: 28)
        let layout = TabBarLayout(
            tabBarHeight: size.height,
            availableWidth: size.width,
            splitButtonCount: buttonCount,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: TabBarStyling.splitButtonsBackdropWidth(buttonCount: buttonCount)
        )
        let appearance = sharedBackdropManyActionAppearance(
            tabBarHeight: size.height,
            buttonCount: buttonCount,
            separatorFadeWidth: 12
        )
        let snapshot = TabBarChromeSnapshot(
            appearance: appearance,
            layout: layout,
            isFocused: true,
            shouldShowSplitButtons: true,
            fadeColorStyle: 0
        )

        XCTAssertEqual(snapshot.contentFadeWidth, 28.875, accuracy: 0.0001)
        XCTAssertEqual(snapshot.actionLaneSeparatorFadeWidth, 12, accuracy: 0.0001)
        XCTAssertLessThan(snapshot.actionLaneSeparatorFadeWidth, snapshot.contentFadeWidth)
    }

    func testActionLaneFallbackSeparatorClipsToSelectedSeparatorGap() {
        let buttonCount = 28
        let size = NSSize(width: 360, height: 28)
        let layout = TabBarLayout(
            tabBarHeight: size.height,
            availableWidth: size.width,
            splitButtonCount: buttonCount,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: TabBarStyling.splitButtonsBackdropWidth(buttonCount: buttonCount)
        )
        let snapshot = TabBarChromeSnapshot(
            appearance: sharedBackdropManyActionAppearance(
                tabBarHeight: size.height,
                buttonCount: buttonCount,
                separatorFadeWidth: 12
            ),
            layout: layout,
            isFocused: true,
            shouldShowSplitButtons: true,
            fadeColorStyle: 0
        )
        let geometry = snapshot.actionLaneGeometry
        let mask = geometry.fallbackSeparatorMaskFrame(
            totalWidth: size.width,
            height: size.height,
            selectedSeparatorGap: 300...340
        )

        XCTAssertEqual(mask?.minX ?? -1, 300, accuracy: 0.0001)
        XCTAssertEqual(mask?.maxX ?? -1, 340, accuracy: 0.0001)
        XCTAssertNil(geometry.fallbackSeparatorMaskFrame(
            totalWidth: size.width,
            height: size.height,
            selectedSeparatorGap: 0...40
        ))
    }

    func testTabBarSeparatorSegmentsClampGapIntoBounds() {
        var segments = TabBarStyling.separatorSegments(totalWidth: 100, gap: -20...40)
        XCTAssertEqual(segments.left, 0, accuracy: 0.0001)
        XCTAssertEqual(segments.right, 60, accuracy: 0.0001)

        segments = TabBarStyling.separatorSegments(totalWidth: 100, gap: 25...120)
        XCTAssertEqual(segments.left, 25, accuracy: 0.0001)
        XCTAssertEqual(segments.right, 0, accuracy: 0.0001)

        segments = TabBarStyling.separatorSegments(totalWidth: 100, gap: nil)
        XCTAssertEqual(segments.left, 100, accuracy: 0.0001)
        XCTAssertEqual(segments.right, 0, accuracy: 0.0001)
    }

    @MainActor
    func testPaneDropOverlayDoesNotResizeHostedContentDuringHover() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        let model = DropZoneModel()
        let probeView = LayoutProbeView(frame: .zero)
        let hostingView = NSHostingView(
            rootView: PaneDropInteractionHarness(
                model: model,
                probeView: probeView
            )
        )
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        let initialFrame = probeView.frame
        let initialSizeChanges = probeView.sizeChangeCount
        let initialOriginChanges = probeView.originChangeCount

        model.zone = .left
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        XCTAssertEqual(probeView.frame, initialFrame)
        XCTAssertEqual(
            probeView.sizeChangeCount,
            initialSizeChanges,
            "Drag-hover overlays must not resize the hosted pane content"
        )
        XCTAssertEqual(
            probeView.originChangeCount,
            initialOriginChanges,
            "Drag-hover overlays must not move the hosted pane content"
        )

        model.zone = .bottom
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        XCTAssertEqual(probeView.frame, initialFrame)
        XCTAssertEqual(
            probeView.sizeChangeCount,
            initialSizeChanges,
            "Switching hover targets should keep the hosted pane geometry stable"
        )
        XCTAssertEqual(
            probeView.originChangeCount,
            initialOriginChanges,
            "Switching hover targets should not reposition the hosted pane content"
        )
    }

    @MainActor
    func testTranslucentSplitWrappersStayClear() {
        let appearance = BonsplitConfiguration.Appearance(
            enableAnimations: false,
            chromeColors: .init(backgroundHex: "#11223380")
        )
        let configuration = BonsplitConfiguration(appearance: appearance)
        let controller = BonsplitController(configuration: configuration)
        _ = controller.createTab(title: "Base")
        guard let sourcePane = controller.focusedPaneId else {
            XCTFail("Expected focused pane")
            return
        }
        guard controller.splitPane(sourcePane, orientation: .horizontal) != nil else {
            XCTFail("Expected splitPane to create a new pane")
            return
        }

        let hostingView = NSHostingView(
            rootView: BonsplitView(controller: controller) { _, _ in
                Color.clear
            } emptyPane: { _ in
                Color.clear
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        guard let splitView = firstDescendant(ofType: NSSplitView.self, in: hostingView) else {
            XCTFail("Expected split view")
            return
        }
        XCTAssertEqual(splitView.arrangedSubviews.count, 2)

        let dividerBackground = splitView.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
        XCTAssertNotNil(dividerBackground, "Expected split view to be layer-backed")
        XCTAssertEqual(
            dividerBackground?.alphaComponent ?? 0,
            0,
            accuracy: 0.001,
            "Split root should stay clear so translucent pane chrome is painted only once"
        )

        for container in splitView.arrangedSubviews {
            let background = container.layer?.backgroundColor.flatMap(NSColor.init(cgColor:))
            XCTAssertNotNil(background, "Expected arranged subview to be layer-backed")
            XCTAssertEqual(
                background?.alphaComponent ?? -1,
                0,
                accuracy: 0.001,
                "Split-only wrapper containers should stay clear so translucent pane chrome is not composited twice"
            )
        }
    }

    @MainActor
    func testSplitContentAlphaMatchesSinglePane() {
        let appearance = BonsplitConfiguration.Appearance(
            enableAnimations: false,
            chromeColors: .init(backgroundHex: "#11223380")
        )
        let expectedAlpha = CGFloat(128.0 / 255.0)
        let samplePoint = NSPoint(x: 100, y: 100)

        let singlePaneController = BonsplitController(
            configuration: BonsplitConfiguration(appearance: appearance)
        )
        _ = singlePaneController.createTab(title: "Base")

        guard let singlePaneAlpha = renderedAlpha(
            for: singlePaneController,
            samplePoint: samplePoint
        ) else {
            XCTFail("Expected single-pane rendered alpha")
            return
        }
        XCTAssertEqual(
            singlePaneAlpha,
            expectedAlpha,
            accuracy: 0.03,
            "Single-pane content should preserve the configured translucent alpha"
        )

        let splitController = BonsplitController(
            configuration: BonsplitConfiguration(appearance: appearance)
        )
        _ = splitController.createTab(title: "Base")
        guard let sourcePane = splitController.focusedPaneId else {
            XCTFail("Expected focused pane")
            return
        }
        guard splitController.splitPane(sourcePane, orientation: .horizontal) != nil else {
            XCTFail("Expected splitPane to create a new pane")
            return
        }

        guard let splitAlpha = renderedAlpha(
            for: splitController,
            samplePoint: samplePoint
        ) else {
            XCTFail("Expected split rendered alpha")
            return
        }

        XCTAssertEqual(
            splitAlpha,
            singlePaneAlpha,
            accuracy: 0.03,
            "Split mode should render the same content alpha as single-pane mode"
        )
    }

    @MainActor
    func testTabBarDragZoneFocusesInactivePaneInMinimalMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = true
        view.isFocusedPane = false

        var focused = false
        var dragged = false
        view.onSingleClick = {
            focused = true
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let event = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        view.mouseDown(with: event)

        XCTAssertTrue(focused, "Inactive-pane drag zone should focus the pane before starting a window drag")
        XCTAssertFalse(dragged, "Inactive-pane focus click should not immediately begin a window drag")
        XCTAssertFalse(view.mouseDownCanMoveWindow, "Inactive-pane drag zone should not advertise window dragging to AppKit")
    }

    @MainActor
    func testTabBarDragZoneMinimalModeNeverRequestsNewTabAfterSingleThenDoubleClick() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = true
        view.isFocusedPane = true

        var requestedNewTab = false
        var dragged = false
        view.onDoubleClick = {
            requestedNewTab = true
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let firstDown = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        let firstUp = try makeMouseEvent(
            type: .leftMouseUp,
            in: view,
            at: NSPoint(x: 20, y: 15),
            clickCount: 1
        )
        let doubleClick = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 2)

        view.mouseDown(with: firstDown)
        view.mouseUp(with: firstUp)
        view.mouseDown(with: doubleClick)

        XCTAssertFalse(requestedNewTab, "Minimal-mode drag zone double-clicks must not request new tabs")
        XCTAssertFalse(dragged, "A plain click followed by a double-click should not start a window drag")
    }

    @MainActor
    func testTabBarDragZoneDoubleClickDoesNotRequestNewTabInMinimalMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = true
        view.isFocusedPane = true

        var requestedNewTab = false
        var dragged = false
        view.onDoubleClick = {
            requestedNewTab = true
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let event = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 2)
        view.mouseDown(with: event)

        XCTAssertFalse(requestedNewTab, "Minimal-mode drag zone double-click should behave like titlebar chrome, not new-tab chrome")
        XCTAssertFalse(dragged, "Minimal-mode double-click should not start a window drag")
    }

    @MainActor
    func testTabBarDragZoneSingleClickDoesNotRequestNewTabInStandardMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = false
        view.isFocusedPane = true

        var newTabCount = 0
        var dragged = false
        view.onDoubleClick = {
            newTabCount += 1
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let event = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        view.mouseDown(with: event)

        XCTAssertEqual(newTabCount, 0, "Standard-mode drag zone single click should wait for a double-click before creating a tab")
        XCTAssertFalse(dragged, "Standard-mode drag zone single click should not begin a window drag")
    }

    @MainActor
    func testTabBarDragZoneSingleClickFocusesInactivePaneInStandardMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = false
        view.isFocusedPane = false

        var focused = false
        var newTabCount = 0
        var dragged = false
        view.onSingleClick = {
            focused = true
            return true
        }
        view.onDoubleClick = {
            newTabCount += 1
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let event = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        view.mouseDown(with: event)

        XCTAssertTrue(focused, "Standard-mode inactive-pane single click should focus the pane")
        XCTAssertEqual(newTabCount, 0, "Standard-mode inactive-pane single click should not create a tab")
        XCTAssertFalse(dragged, "Standard-mode inactive-pane single click should not begin a window drag")
    }

    @MainActor
    func testTabBarDragZoneStandardModeDoubleClickCreatesOnlyOneTab() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = false
        view.isFocusedPane = true

        var newTabCount = 0
        view.onDoubleClick = {
            newTabCount += 1
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let firstDown = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        let firstUp = try makeMouseEvent(
            type: .leftMouseUp,
            in: view,
            at: NSPoint(x: 20, y: 15),
            clickCount: 1
        )
        let secondDown = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 2)

        view.mouseDown(with: firstDown)
        view.mouseUp(with: firstUp)
        view.mouseDown(with: secondDown)

        XCTAssertEqual(newTabCount, 1, "A standard-mode double-click should create exactly one tab")
    }

    @MainActor
    func testTabBarTrailingEmptyChromeCapturesOnlyEmptyArea() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 30))
        view.hitRegion = .trailingEmptyChrome(
            tabFrames: [CGRect(x: 10, y: 0, width: 90, height: 30)],
            reservedTrailingWidth: 48
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        view.hitTestEventTypeOverride = .leftMouseDown
        XCTAssertNil(view.hitTest(NSPoint(x: 40, y: 15)), "The empty chrome catcher must not cover tabs")
        XCTAssertNil(view.hitTest(NSPoint(x: 300, y: 15)), "The empty chrome catcher must not cover the action button lane")
        XCTAssertIdentical(view.hitTest(NSPoint(x: 140, y: 15)), view)
    }

    @MainActor
    func testTabBarTrailingEmptyChromeDefersToRegisteredTabItemWhenFrameCacheIsEmpty() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 30))
        view.hitRegion = .trailingEmptyChrome(tabFrames: [], reservedTrailingWidth: 48)
        view.hitTestEventTypeOverride = .leftMouseDown

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        let tabItem = FakeTabItemHitRegionView(frame: NSRect(x: 10, y: 0, width: 90, height: 30))
        tabItem.tabFrames = [tabItem.bounds]
        contentView.addSubview(tabItem)
        window.makeKeyAndOrderFront(nil)

        XCTAssertNil(
            view.hitTest(NSPoint(x: 40, y: 15)),
            "A registered pane tab owns its pixels even before the tab-frame preference cache is populated"
        )
        XCTAssertIdentical(
            view.hitTest(NSPoint(x: 140, y: 15)),
            view,
            "Empty chrome after the registered tab should still drag the app window"
        )
    }

    @MainActor
    func testTabBarDragZoneCursorMarksOnlyMinimalModeWindowDragArea() {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 320, height: 30))
        view.hitRegion = .trailingEmptyChrome(
            tabFrames: [CGRect(x: 10, y: 0, width: 90, height: 30)],
            reservedTrailingWidth: 48
        )

        XCTAssertEqual(
            view.windowDragCursorRectsForCurrentState(),
            [],
            "Standard mode should not advertise tab-bar window dragging with an open-hand cursor"
        )

        view.isMinimalMode = true

        XCTAssertEqual(
            view.windowDragCursorRectsForCurrentState(),
            [NSRect(x: 110, y: 0, width: 162, height: 30)],
            "Minimal mode should show the open-hand cursor only in empty chrome after the tab frames and before action buttons"
        )
    }

    @MainActor
    func testTabBarDragZoneCursorCoversEntireExplicitDragZoneInMinimalMode() {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = true

        XCTAssertEqual(
            view.windowDragCursorRectsForCurrentState(),
            [view.bounds],
            "Explicit leading and inline empty drag zones should be visibly marked as window-drag chrome in minimal mode"
        )
    }

    @MainActor
    func testTabBarDragZoneKeepsFocusedPaneWindowDragInMinimalMode() throws {
        let view = TabBarDragZoneView.DragNSView(frame: NSRect(x: 0, y: 0, width: 160, height: 30))
        view.isMinimalMode = true
        view.isFocusedPane = true

        var focused = false
        var dragged = false
        view.onSingleClick = {
            focused = true
            return true
        }
        view.performWindowDrag = { _ in
            dragged = true
            return true
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else {
            XCTFail("Expected content view")
            return
        }

        contentView.addSubview(view)
        window.makeKeyAndOrderFront(nil)
        let event = try makeLeftMouseDownEvent(in: view, at: NSPoint(x: 20, y: 15), clickCount: 1)
        let dragEvent = try makeMouseEvent(
            type: .leftMouseDragged,
            in: view,
            at: NSPoint(x: 30, y: 15),
            clickCount: 1
        )
        view.mouseDown(with: event)
        view.mouseDragged(with: dragEvent)

        XCTAssertFalse(focused, "Focused-pane drag zone should not bounce through first-click focus")
        XCTAssertTrue(dragged, "Focused-pane drag zone should continue to start window drags in minimal mode")
        XCTAssertFalse(view.mouseDownCanMoveWindow, "Focused-pane drag zone must not advertise window dragging to AppKit or AppKit steals mouseUp and breaks new-tab double-clicks")
    }

    private func withShortcutHintDefaultsSuite(_ body: (UserDefaults) -> Void) {
        let suiteName = "BonsplitShortcutHintPolicyTests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Failed to create defaults suite")
            return
        }

        defaults.removePersistentDomain(forName: suiteName)
        body(defaults)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func shortcutData(
        key: String,
        command: Bool,
        shift: Bool,
        option: Bool,
        control: Bool
    ) -> Data {
        let payload: [String: Any] = [
            "key": key,
            "command": command,
            "shift": shift,
            "option": option,
            "control": control
        ]
        return try! JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func firstDescendant<T: NSView>(ofType type: T.Type, in root: NSView) -> T? {
        if let match = root as? T {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(ofType: type, in: subview) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func waitForDescendant<T: NSView>(
        ofType type: T.Type,
        in root: NSView,
        timeout: TimeInterval = 1.0,
        where predicate: (T) -> Bool = { _ in true }
    ) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            root.layoutSubtreeIfNeeded()
            if let match = firstDescendant(
                ofType: type,
                in: root,
                where: predicate
            ) {
                return match
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline
        return firstDescendant(ofType: type, in: root, where: predicate)
    }

    private func firstDescendant<T: NSView>(
        ofType type: T.Type,
        in root: NSView,
        where predicate: (T) -> Bool
    ) -> T? {
        if let match = root as? T, predicate(match) {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(ofType: type, in: subview, where: predicate) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func waitForDescendant<T: NSView>(
        ofType type: T.Type,
        in root: NSView,
        containingWindowPoint point: NSPoint,
        timeout: TimeInterval = 1.0,
        where predicate: (T) -> Bool = { _ in true }
    ) -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            root.layoutSubtreeIfNeeded()
            if let match = firstDescendant(
                ofType: type,
                in: root,
                containingWindowPoint: point,
                where: predicate
            ) {
                return match
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline
        return firstDescendant(
            ofType: type,
            in: root,
            containingWindowPoint: point,
            where: predicate
        )
    }

    @MainActor
    private func firstDescendant<T: NSView>(
        ofType type: T.Type,
        in root: NSView,
        containingWindowPoint point: NSPoint,
        where predicate: (T) -> Bool = { _ in true }
    ) -> T? {
        if let match = root as? T {
            let frameInWindow = root.convert(root.bounds, to: nil)
            if frameInWindow.contains(point), predicate(match) {
                return match
            }
        }
        for subview in root.subviews {
            if let match = firstDescendant(
                ofType: type,
                in: subview,
                containingWindowPoint: point,
                where: predicate
            ) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func renderedAlpha(
        for controller: BonsplitController,
        samplePoint: NSPoint,
        size: NSSize = NSSize(width: 800, height: 600)
    ) -> CGFloat? {
        let hostingView = NSHostingView(
            rootView: BonsplitView(controller: controller) { _, _ in
                Color.clear
            } emptyPane: { _ in
                Color.clear
            }
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else { return nil }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        return renderedColor(in: hostingView, at: samplePoint)?.alphaComponent
    }

    @MainActor
    private func renderedTabBarIndicatorSaturation(isFocused: Bool) -> CGFloat? {
        renderedTabBarValue(isFocused: isFocused) { hostingView in
            let sampleRect = NSRect(x: 4, y: 0, width: 44, height: 4)
            return maximumSaturation(in: hostingView, sampleRect: sampleRect)
        }
    }

    @MainActor
    private func renderedTabBarIndicatorWidth(isFocused: Bool) -> CGFloat? {
        renderedTabBarValue(isFocused: isFocused) { hostingView in
            let sampleRect = NSRect(x: 0, y: 0, width: 80, height: 4)
            return highSaturationWidth(in: hostingView, sampleRect: sampleRect)
        }
    }

    @MainActor
    private func renderedSelectedIndicatorRangeAfterManualScroll(size: NSSize) -> ClosedRange<CGFloat>? {
        renderedTabBarValue(
            isFocused: true,
            size: size,
            configurePane: { pane in
                let tabs = (0..<8).map { index in
                    TabItem(title: "Tab \(index)", icon: nil)
                }
                pane.tabs = tabs
                pane.selectedTabId = tabs.first?.id
            }
        ) { hostingView in
            guard let scrollView = firstDescendant(ofType: NSScrollView.self, in: hostingView) else {
                XCTFail("Expected tab bar scroll view for manual scroll regression")
                return nil
            }
            scrollView.contentView.scroll(to: NSPoint(x: 96, y: 0))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            hostingView.layoutSubtreeIfNeeded()

            let sampleRect = NSRect(x: 0, y: 0, width: size.width, height: 4)
            return highSaturationRange(in: hostingView, sampleRect: sampleRect)
        }
    }

    @MainActor
    private func renderedIndicatorRangeAfterAnimatedSelectionChange() -> ClosedRange<CGFloat>? {
        let first = TabItem(title: "First", icon: nil)
        let second = TabItem(title: "Second", icon: nil)
        let size = NSSize(width: 160, height: TabBarMetrics.barHeight)
        var renderedPane: PaneState?

        return renderedTabBarValue(
            isFocused: true,
            size: size,
            configurePane: { pane in
                renderedPane = pane
                pane.tabs = [first, second]
                pane.selectedTabId = first.id
            }
        ) { hostingView in
            guard let renderedPane else { return nil }
            withAnimation(.linear(duration: 10)) {
                renderedPane.selectedTabId = second.id
            }
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            hostingView.layoutSubtreeIfNeeded()

            let sampleRect = NSRect(x: 0, y: 0, width: size.width, height: 4)
            return highSaturationRange(in: hostingView, sampleRect: sampleRect)
        }
    }

    @MainActor
    private func renderedSplitButtonLaneTopSaturation() -> CGFloat? {
        let buttonCount = BonsplitConfiguration.SplitActionButton.defaults.count
        let size = NSSize(width: 240, height: 28)
        let splitButtonLaneWidth = visibleSplitButtonLaneWidth(size: size, buttonCount: buttonCount)
        let appearance = BonsplitConfiguration.Appearance(
            tabBarHeight: size.height,
            splitButtonBackdropEffect: .default,
            chromeColors: .init(
                backgroundHex: "#111111",
                tabBarBackgroundHex: "#181818",
                splitButtonBackdropHex: "#242424",
                borderHex: "#666666"
            )
        )

        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            showSplitButtons: true,
            size: size,
            configurePane: { pane in
                let selected = TabItem(
                    title: "selected tab title that reaches under the controls",
                    icon: nil
                )
                pane.tabs = [selected]
                pane.selectedTabId = selected.id
            }
        ) { hostingView in
            let laneStartX = size.width - splitButtonLaneWidth
            let sampleRect = NSRect(x: laneStartX + 4, y: 0, width: 40, height: 4)
            return maximumSaturation(in: hostingView, sampleRect: sampleRect)
        }
    }

    @MainActor
    private func renderedSplitButtonBackdropFadeVerticalColorDelta() -> CGFloat? {
        let size = NSSize(width: 360, height: 28)
        let appearance = BonsplitConfiguration.Appearance(
            tabBarHeight: size.height,
            splitButtonBackdropEffect: .default,
            chromeColors: .init(
                backgroundHex: "#000000",
                tabBarBackgroundHex: "#000000",
                splitButtonBackdropHex: "#FFFFFF",
                borderHex: "#00000000"
            )
        )

        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            showSplitButtons: true,
            size: size,
            configurePane: { pane in
                let selected = TabItem(title: "", icon: nil)
                pane.tabs = [selected]
                pane.selectedTabId = selected.id
            }
        ) { hostingView in
            let sampleX = size.width - 124
            guard let top = renderedColorInViewCoordinates(
                in: hostingView,
                at: NSPoint(x: sampleX, y: 6)
            )?.usingColorSpace(.sRGB),
                  let bottom = renderedColorInViewCoordinates(
                    in: hostingView,
                    at: NSPoint(x: sampleX, y: size.height - 6)
                  )?.usingColorSpace(.sRGB) else {
                return nil
            }

            return abs(top.redComponent - bottom.redComponent)
                + abs(top.greenComponent - bottom.greenComponent)
                + abs(top.blueComponent - bottom.blueComponent)
                + abs(top.alphaComponent - bottom.alphaComponent)
        }
    }

    @MainActor
    private func renderedSplitButtonLaneSolidBackdropBrightness() -> CGFloat? {
        let buttonCount = BonsplitConfiguration.SplitActionButton.defaults.count
        let size = NSSize(width: 240, height: 28)
        let splitButtonLaneWidth = visibleSplitButtonLaneWidth(size: size, buttonCount: buttonCount)
        let appearance = BonsplitConfiguration.Appearance(
            tabBarHeight: size.height,
            splitButtonBackdropEffect: .default,
            chromeColors: .init(
                backgroundHex: "#000000",
                tabBarBackgroundHex: "#000000",
                splitButtonBackdropHex: "#FFFFFF",
                borderHex: "#00000000"
            )
        )

        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            showSplitButtons: true,
            size: size,
            configurePane: { pane in
                let selected = TabItem(title: "", icon: nil)
                pane.tabs = [selected]
                pane.selectedTabId = selected.id
            }
        ) { hostingView in
            let laneStartX = size.width - splitButtonLaneWidth
            guard let color = renderedColorInViewCoordinates(
                in: hostingView,
                at: NSPoint(x: laneStartX + 2, y: size.height / 2)
            )?.usingColorSpace(.sRGB) else {
                return nil
            }
            return brightness(of: color)
        }
    }

    @MainActor
    private func renderedSplitButtonContentFadeStartBackdropBrightness() -> CGFloat? {
        let buttonCount = BonsplitConfiguration.SplitActionButton.defaults.count
        let size = NSSize(width: 240, height: 28)
        let splitButtonLaneWidth = visibleSplitButtonLaneWidth(size: size, buttonCount: buttonCount)
        let contentFadeWidth = BonsplitConfiguration.Appearance.SplitButtonBackdropEffect.default.contentFadeWidth
        let appearance = BonsplitConfiguration.Appearance(
            tabBarHeight: size.height,
            splitButtonBackdropEffect: .default,
            chromeColors: .init(
                backgroundHex: "#000000",
                tabBarBackgroundHex: "#000000",
                splitButtonBackdropHex: "#FFFFFF",
                borderHex: "#00000000"
            )
        )

        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            showSplitButtons: true,
            size: size,
            configurePane: { pane in
                let selected = TabItem(
                    title: "selected tab title that reaches under the controls",
                    icon: nil
                )
                pane.tabs = [selected]
                pane.selectedTabId = selected.id
            }
        ) { hostingView in
            let laneStartX = size.width - splitButtonLaneWidth
            guard let color = renderedColorInViewCoordinates(
                in: hostingView,
                at: NSPoint(x: laneStartX - contentFadeWidth + 2, y: size.height / 2)
            )?.usingColorSpace(.sRGB) else {
                return nil
            }
            return brightness(of: color)
        }
    }

    @MainActor
    private func renderedSplitButtonContentFadeStartSaturation() -> CGFloat? {
        let buttonCount = BonsplitConfiguration.SplitActionButton.defaults.count
        let size = NSSize(width: 240, height: 28)
        let splitButtonLaneWidth = visibleSplitButtonLaneWidth(size: size, buttonCount: buttonCount)
        let contentFadeWidth = BonsplitConfiguration.Appearance.SplitButtonBackdropEffect.default.contentFadeWidth
        let appearance = BonsplitConfiguration.Appearance(
            tabBarHeight: size.height,
            splitButtonBackdropEffect: .default,
            chromeColors: .init(
                backgroundHex: "#000000",
                tabBarBackgroundHex: "#000000",
                splitButtonBackdropHex: "#000000",
                borderHex: "#00000000"
            )
        )

        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            showSplitButtons: true,
            size: size,
            configurePane: { pane in
                let selected = TabItem(
                    title: "selected tab title that reaches under the controls",
                    icon: nil
                )
                pane.tabs = [selected]
                pane.selectedTabId = selected.id
            }
        ) { hostingView in
            let laneStartX = size.width - splitButtonLaneWidth
            let sampleRect = NSRect(
                x: laneStartX - contentFadeWidth + 2,
                y: 0,
                width: 8,
                height: 4
            )
            return maximumSaturation(in: hostingView, sampleRect: sampleRect)
        }
    }

    @MainActor
    private func renderedSelectedIndicatorBackdropBrightnesses() -> (leading: CGFloat, trailing: CGFloat)? {
        let buttonCount = BonsplitConfiguration.SplitActionButton.defaults.count
        let size = NSSize(width: 240, height: 28)
        let splitButtonLaneWidth = visibleSplitButtonLaneWidth(size: size, buttonCount: buttonCount)
        let fadeWidth = BonsplitConfiguration.Appearance.SplitButtonBackdropEffect.default.contentFadeWidth
        let appearance = BonsplitConfiguration.Appearance(
            tabBarHeight: size.height,
            splitButtonBackdropEffect: .default,
            chromeColors: .init(
                backgroundHex: "#000000",
                tabBarBackgroundHex: "#000000",
                splitButtonBackdropHex: "#000000",
                borderHex: "#00000000"
            )
        )

        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            showSplitButtons: true,
            size: size,
            configurePane: { pane in
                let selected = TabItem(
                    title: "selected tab title that reaches under the controls",
                    icon: nil
                )
                pane.tabs = [selected]
                pane.selectedTabId = selected.id
            }
        ) { hostingView in
            let laneStartX = size.width - splitButtonLaneWidth
            guard let leading = renderedColorInViewCoordinates(
                in: hostingView,
                at: NSPoint(x: laneStartX - fadeWidth + 4, y: 0)
            )?.usingColorSpace(.sRGB),
                  let trailing = renderedColorInViewCoordinates(
                    in: hostingView,
                    at: NSPoint(x: laneStartX - 4, y: 0)
                  )?.usingColorSpace(.sRGB) else {
                return nil
            }

            return (
                leading: brightness(of: leading),
                trailing: brightness(of: trailing)
            )
        }
    }

    @MainActor
    private func renderedSharedBackdropActionLaneSurfaceAlpha() -> CGFloat? {
        let buttonCount = 28
        let size = NSSize(width: 360, height: 28)
        let splitButtonLaneWidth = visibleSplitButtonLaneWidth(size: size, buttonCount: buttonCount)
        let appearance = sharedBackdropManyActionAppearance(
            tabBarHeight: size.height,
            buttonCount: buttonCount
        )

        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            showSplitButtons: true,
            size: size,
            configurePane: { pane in
                let leading = TabItem(title: "", icon: nil)
                let selected = TabItem(
                    title: "selected tab title that reaches under the full action button lane",
                    icon: nil
                )
                pane.tabs = [leading, selected]
                pane.selectedTabId = selected.id
            }
        ) { hostingView in
            let laneStartX = size.width - splitButtonLaneWidth
            guard let color = renderedColorInViewCoordinates(
                in: hostingView,
                at: NSPoint(x: laneStartX + 2, y: 2)
            )?.usingColorSpace(.sRGB) else {
                return nil
            }
            return color.alphaComponent
        }
    }

    @MainActor
    private func renderedEscapedSplitButtonBrightnessOutsideActionLane() -> CGFloat? {
        let buttonCount = 28
        let size = NSSize(width: 360, height: 28)
        let splitButtonLaneWidth = visibleSplitButtonLaneWidth(size: size, buttonCount: buttonCount)
        let appearance = BonsplitConfiguration.Appearance(
            tabBarHeight: size.height,
            tabMaxWidth: 40,
            splitButtons: manySplitActionButtons(count: buttonCount),
            splitButtonBackdropEffect: .init(
                style: .translucentChrome,
                fadeWidth: 99.75,
                contentFadeWidth: 28.875,
                solidWidth: 23.875,
                fadeRampStartFraction: 0.60,
                leadingOpacity: 0,
                trailingOpacity: 0.8625,
                contentOcclusionFraction: 0.6875,
                masksTabContent: true
            ),
            chromeColors: .init(
                backgroundHex: "#000000",
                tabBarBackgroundHex: "#000000",
                splitButtonBackdropHex: "#000000",
                borderHex: "#00000000"
            )
        )

        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            showSplitButtons: true,
            size: size,
            configurePane: { pane in
                let tabs = (0..<16).map { _ in TabItem(title: "", icon: nil) }
                pane.tabs = tabs
                pane.selectedTabId = tabs.first?.id
            }
        ) { hostingView in
            maximumBrightness(
                in: hostingView,
                sampleRect: NSRect(
                    x: size.width - splitButtonLaneWidth - 16,
                    y: 5,
                    width: 8,
                    height: size.height - 10
                )
            )
        }
    }

    @MainActor
    private func renderedSharedBackdropActionLaneBottomSeparatorAlphas() -> (
        fadeStart: CGFloat,
        beforeRamp: CGFloat,
        afterRamp: CGFloat,
        fadeEnd: CGFloat,
        solidStart: CGFloat,
        solid: CGFloat
    )? {
        let buttonCount = 28
        let size = NSSize(width: 360, height: 28)
        let splitButtonLaneWidth = visibleSplitButtonLaneWidth(size: size, buttonCount: buttonCount)
        let separatorFadeWidth: CGFloat = 99.75
        let rampStartFraction: CGFloat = 0.60
        let contentOcclusionWidth = TabBarStyling.splitButtonContentOcclusionWidth(
            visibleLaneWidth: splitButtonLaneWidth,
            contentOcclusionFraction: 0.6875
        )
        let solidWidth = max(splitButtonLaneWidth, contentOcclusionWidth)
        let appearance = sharedBackdropManyActionAppearance(
            tabBarHeight: size.height,
            buttonCount: buttonCount,
            borderHex: "#FFFFFF80",
            tabMaxWidth: size.width
        )

        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            showSplitButtons: true,
            size: size,
            configurePane: { pane in
                let leading = TabItem(title: "", icon: nil)
                let selected = TabItem(
                    title: "selected tab title that reaches under the full action button lane",
                    icon: nil
                )
                pane.tabs = [leading, selected]
                pane.selectedTabId = selected.id
            }
        ) { hostingView in
            let separatorY = size.height - 0.5
            let fadeStartX = size.width - solidWidth - separatorFadeWidth
            let rampStartX = fadeStartX + separatorFadeWidth * rampStartFraction
            let solidStartX = size.width - solidWidth
            guard let fadeStart = renderedColorInViewCoordinates(
                in: hostingView,
                at: NSPoint(x: fadeStartX + 2, y: separatorY)
            )?.usingColorSpace(.sRGB)?.alphaComponent,
                  let beforeRamp = renderedColorInViewCoordinates(
                    in: hostingView,
                    at: NSPoint(x: rampStartX - 2, y: separatorY)
                  )?.usingColorSpace(.sRGB)?.alphaComponent,
                  let afterRamp = renderedColorInViewCoordinates(
                    in: hostingView,
                    at: NSPoint(x: rampStartX + 16, y: separatorY)
                  )?.usingColorSpace(.sRGB)?.alphaComponent,
                  let fadeEnd = renderedColorInViewCoordinates(
                    in: hostingView,
                    at: NSPoint(x: solidStartX - 2, y: separatorY)
                  )?.usingColorSpace(.sRGB)?.alphaComponent,
                  let solidStart = renderedColorInViewCoordinates(
                    in: hostingView,
                    at: NSPoint(x: solidStartX + 2, y: separatorY)
                  )?.usingColorSpace(.sRGB)?.alphaComponent,
                  let solid = renderedColorInViewCoordinates(
                    in: hostingView,
                    at: NSPoint(x: size.width - 6, y: separatorY)
                  )?.usingColorSpace(.sRGB)?.alphaComponent else {
                return nil
            }
            return (
                fadeStart: fadeStart,
                beforeRamp: beforeRamp,
                afterRamp: afterRamp,
                fadeEnd: fadeEnd,
                solidStart: solidStart,
                solid: solid
            )
        }
    }

    private func sharedBackdropManyActionAppearance(
        tabBarHeight: CGFloat,
        buttonCount: Int,
        borderHex: String = "#66666680",
        tabMaxWidth: CGFloat = 220,
        separatorFadeWidth: CGFloat? = nil
    ) -> BonsplitConfiguration.Appearance {
        BonsplitConfiguration.Appearance(
            tabBarHeight: tabBarHeight,
            tabMaxWidth: tabMaxWidth,
            splitButtons: manySplitActionButtons(count: buttonCount),
            splitButtonBackdropEffect: .init(
                style: .translucentChrome,
                fadeWidth: 99.75,
                contentFadeWidth: 28.875,
                solidWidth: 23.875,
                separatorFadeWidth: separatorFadeWidth,
                fadeRampStartFraction: 0.60,
                leadingOpacity: 0,
                trailingOpacity: 0.8625,
                contentOcclusionFraction: 0.6875,
                masksTabContent: true
            ),
            chromeColors: .init(
                backgroundHex: "#242424B8",
                tabBarBackgroundHex: "#00000000",
                splitButtonBackdropHex: "#00000000",
                paneBackgroundHex: "#00000000",
                borderHex: borderHex
            ),
            usesSharedBackdrop: true
        )
    }

    private func manySplitActionButtons(count: Int) -> [BonsplitConfiguration.SplitActionButton] {
        (0..<count).map { index in
            BonsplitConfiguration.SplitActionButton(
                id: "many-action-\(index)",
                icon: .systemImage("terminal"),
                tooltip: "Action \(index)",
                action: .custom("many-action-\(index)")
            )
        }
    }

    private func visibleSplitButtonLaneWidth(size: NSSize, buttonCount: Int) -> CGFloat {
        TabBarLayout(
            tabBarHeight: size.height,
            availableWidth: size.width,
            splitButtonCount: buttonCount,
            splitButtonLaneVisible: true,
            reservesSplitButtonLane: true,
            measuredSplitButtonLaneWidth: TabBarStyling.splitButtonsBackdropWidth(buttonCount: buttonCount)
        ).visibleSplitButtonLaneWidth
    }

    @MainActor
    private func renderedSelectedTabLeftSeparatorAlphas() -> (top: CGFloat, bottom: CGFloat)? {
        let appearance = BonsplitConfiguration.Appearance(
            chromeColors: .init(
                backgroundHex: "#00000000",
                tabBarBackgroundHex: "#00000000",
                borderHex: "#FFFFFF80"
            )
        )
        return renderedTabBarValue(
            isFocused: true,
            appearance: appearance,
            size: NSSize(width: 320, height: TabBarMetrics.barHeight),
            configurePane: { pane in
                let leading = TabItem(title: "", icon: nil)
                let selected = TabItem(title: "", icon: nil)
                pane.tabs = [leading, selected]
                pane.selectedTabId = selected.id
            }
        ) { hostingView in
            let separatorX = TabBarMetrics.tabMinWidth - 0.5
            guard let top = renderedColorInViewCoordinates(in: hostingView, at: NSPoint(x: separatorX, y: 4))?
                .usingColorSpace(.sRGB)?
                .alphaComponent,
                  let bottom = renderedColorInViewCoordinates(
                    in: hostingView,
                    at: NSPoint(x: separatorX, y: TabBarMetrics.barHeight - 0.5)
                  )?
                .usingColorSpace(.sRGB)?
                .alphaComponent else {
                return nil
            }
            return (top: top, bottom: bottom)
        }
    }

    @MainActor
    private func renderedColorInViewCoordinates(in view: NSView, at point: NSPoint) -> NSColor? {
        let integralBounds = view.bounds.integral
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: integralBounds) else { return nil }
        bitmap.size = integralBounds.size
        view.cacheDisplay(in: integralBounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, integralBounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, integralBounds.height)
        let x = Int((point.x * scaleX).rounded(.down))
        let y = Int((point.y * scaleY).rounded(.down))
        guard x >= 0,
              y >= 0,
              x < bitmap.pixelsWide,
              y < bitmap.pixelsHigh else { return nil }
        return bitmap.colorAt(x: x, y: y)
    }
    @MainActor
    private func renderedTabBarValue<T>(
        isFocused: Bool,
        appearance: BonsplitConfiguration.Appearance = .default,
        showSplitButtons: Bool = false,
        size: NSSize? = nil,
        configurePane: ((PaneState) -> Void)? = nil,
        extract: (NSView) -> T?
    ) -> T? {
        let controller = BonsplitController(configuration: BonsplitConfiguration(appearance: appearance))
        guard let pane = controller.internalController.rootNode.allPanes.first else { return nil }
        if let configurePane {
            configurePane(pane)
        } else {
            let tab = TabItem(title: "", icon: nil)
            pane.tabs = [tab]
            pane.selectedTabId = tab.id
        }

        let size = size ?? NSSize(width: 160, height: TabBarMetrics.barHeight)
        let hostingView = NSHostingView(
            rootView: TabBarView(pane: pane, isFocused: isFocused, showSplitButtons: showSplitButtons)
                .environment(controller)
                .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else { return nil }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        return extract(hostingView)
    }

    @MainActor
    private func renderedPaneContainerHasTabBar(
        tabCount: Int,
        visibility: TabBarVisibility
    ) -> Bool? {
        let controller = BonsplitController(
            configuration: BonsplitConfiguration(tabBarVisibility: visibility)
        )
        guard let pane = controller.internalController.rootNode.allPanes.first else { return nil }

        let tabs = (0..<tabCount).map { index in
            TabItem(title: "Tab \(index + 1)", icon: nil)
        }
        pane.tabs = tabs
        pane.selectedTabId = tabs.first?.id

        let size = NSSize(width: 320, height: 180)
        let hostingView = NSHostingView(
            rootView: PaneContainerView(
                pane: pane,
                controller: controller.internalController,
                contentBuilder: { _, _ in Color.clear },
                emptyPaneBuilder: { _ in Color.clear },
                showSplitButtons: false,
                tabBarVisibility: visibility
            )
            .environment(controller)
            .environment(controller.internalController)
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        defer { window.orderOut(nil) }
        guard let contentView = window.contentView else { return nil }

        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)

        window.makeKeyAndOrderFront(nil)
        contentView.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        contentView.layoutSubtreeIfNeeded()

        return waitForDescendant(
            ofType: TabBarDragZoneView.DragNSView.self,
            in: hostingView,
            timeout: 0.1
        ) != nil
    }

    @MainActor
    private func maximumSaturation(in view: NSView, sampleRect: NSRect? = nil) -> CGFloat? {
        let integralBounds = view.bounds.integral
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: integralBounds) else { return nil }
        bitmap.size = integralBounds.size
        view.cacheDisplay(in: integralBounds, to: bitmap)

        let rect = sampleRect ?? integralBounds
        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, integralBounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, integralBounds.height)
        let minX = max(0, Int(floor(rect.minX * scaleX)))
        let maxX = min(bitmap.pixelsWide, Int(ceil(rect.maxX * scaleX)))
        let minY = max(0, Int(floor(rect.minY * scaleY)))
        let maxY = min(bitmap.pixelsHigh, Int(ceil(rect.maxY * scaleY)))

        var maximum: CGFloat = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let color = bitmap.colorAt(x: x, y: y),
                      let rgb = color.usingColorSpace(.sRGB),
                      rgb.alphaComponent > 0.05 else { continue }
                let alpha = min(max(rgb.alphaComponent, 0), 1)
                let red = rgb.redComponent * alpha
                let green = rgb.greenComponent * alpha
                let blue = rgb.blueComponent * alpha
                let high = max(red, green, blue)
                guard high > 0.01 else { continue }
                let low = min(red, green, blue)
                let saturation = (high - low) / high
                maximum = max(maximum, saturation)
            }
        }
        return maximum
    }

    @MainActor
    private func maximumBrightness(in view: NSView, sampleRect: NSRect) -> CGFloat? {
        let integralBounds = view.bounds.integral
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: integralBounds) else { return nil }
        bitmap.size = integralBounds.size
        view.cacheDisplay(in: integralBounds, to: bitmap)

        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, integralBounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, integralBounds.height)
        let minX = max(0, Int(floor(sampleRect.minX * scaleX)))
        let maxX = min(bitmap.pixelsWide, Int(ceil(sampleRect.maxX * scaleX)))
        let minY = max(0, Int(floor(sampleRect.minY * scaleY)))
        let maxY = min(bitmap.pixelsHigh, Int(ceil(sampleRect.maxY * scaleY)))

        var maximum: CGFloat = 0
        for y in minY..<maxY {
            for x in minX..<maxX {
                guard let color = bitmap.colorAt(x: x, y: y),
                      let rgb = color.usingColorSpace(.sRGB),
                      rgb.alphaComponent > 0.05 else { continue }
                let alpha = min(max(rgb.alphaComponent, 0), 1)
                maximum = max(
                    maximum,
                    max(
                        rgb.redComponent * alpha,
                        rgb.greenComponent * alpha,
                        rgb.blueComponent * alpha
                    )
                )
            }
        }
        return maximum
    }

    private func brightness(of color: NSColor) -> CGFloat {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0 }
        let alpha = min(max(rgb.alphaComponent, 0), 1)
        guard alpha > 0.01 else { return 0 }
        return max(
            rgb.redComponent * alpha,
            rgb.greenComponent * alpha,
            rgb.blueComponent * alpha
        )
    }

    @MainActor
    private func highSaturationWidth(in view: NSView, sampleRect: NSRect) -> CGFloat? {
        let integralBounds = view.bounds.integral
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: integralBounds) else { return nil }
        bitmap.size = integralBounds.size
        view.cacheDisplay(in: integralBounds, to: bitmap)

        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, integralBounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, integralBounds.height)
        let minX = max(0, Int(floor(sampleRect.minX * scaleX)))
        let maxX = min(bitmap.pixelsWide, Int(ceil(sampleRect.maxX * scaleX)))
        let minY = max(0, Int(floor(sampleRect.minY * scaleY)))
        let maxY = min(bitmap.pixelsHigh, Int(ceil(sampleRect.maxY * scaleY)))

        var activeColumnCount = 0
        for x in minX..<maxX {
            var hasIndicatorPixel = false
            for y in minY..<maxY {
                guard let color = bitmap.colorAt(x: x, y: y),
                      let rgb = color.usingColorSpace(.sRGB),
                      rgb.alphaComponent > 0.05 else { continue }
                let alpha = min(max(rgb.alphaComponent, 0), 1)
                let red = rgb.redComponent * alpha
                let green = rgb.greenComponent * alpha
                let blue = rgb.blueComponent * alpha
                let high = max(red, green, blue)
                guard high > 0.01 else { continue }
                let low = min(red, green, blue)
                if (high - low) / high > 0.4 {
                    hasIndicatorPixel = true
                    break
                }
            }
            if hasIndicatorPixel {
                activeColumnCount += 1
            }
        }
        return CGFloat(activeColumnCount) / scaleX
    }

    @MainActor
    private func highSaturationRange(in view: NSView, sampleRect: NSRect) -> ClosedRange<CGFloat>? {
        let integralBounds = view.bounds.integral
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: integralBounds) else { return nil }
        bitmap.size = integralBounds.size
        view.cacheDisplay(in: integralBounds, to: bitmap)

        let scaleX = CGFloat(bitmap.pixelsWide) / max(1, integralBounds.width)
        let scaleY = CGFloat(bitmap.pixelsHigh) / max(1, integralBounds.height)
        let minX = max(0, Int(floor(sampleRect.minX * scaleX)))
        let maxX = min(bitmap.pixelsWide, Int(ceil(sampleRect.maxX * scaleX)))
        let minY = max(0, Int(floor(sampleRect.minY * scaleY)))
        let maxY = min(bitmap.pixelsHigh, Int(ceil(sampleRect.maxY * scaleY)))
        var firstActiveX: Int?
        var lastActiveX: Int?

        for x in minX..<maxX {
            var hasIndicatorPixel = false
            for y in minY..<maxY {
                guard let color = bitmap.colorAt(x: x, y: y),
                      let rgb = color.usingColorSpace(.sRGB),
                      rgb.alphaComponent > 0.05 else { continue }
                let alpha = min(max(rgb.alphaComponent, 0), 1)
                let red = rgb.redComponent * alpha
                let green = rgb.greenComponent * alpha
                let blue = rgb.blueComponent * alpha
                let high = max(red, green, blue)
                guard high > 0.01 else { continue }
                let low = min(red, green, blue)
                if (high - low) / high > 0.4 {
                    hasIndicatorPixel = true
                    break
                }
            }
            guard hasIndicatorPixel else { continue }
            if firstActiveX == nil {
                firstActiveX = x
            }
            lastActiveX = x
        }

        guard let firstActiveX, let lastActiveX else { return nil }
        return (CGFloat(firstActiveX) / scaleX)...(CGFloat(lastActiveX + 1) / scaleX)
    }

    @MainActor
    private func renderedColor(in view: NSView, at point: NSPoint) -> NSColor? {
        let integralBounds = view.bounds.integral
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: integralBounds) else { return nil }
        bitmap.size = integralBounds.size
        view.cacheDisplay(in: integralBounds, to: bitmap)

        let x = Int(point.x.rounded())
        let y = Int(point.y.rounded())
        guard x >= 0,
              y >= 0,
              x < bitmap.pixelsWide,
              y < bitmap.pixelsHigh else { return nil }
        return bitmap.colorAt(x: x, y: y)
    }

    @MainActor
    private func makeLeftMouseDownEvent(
        in view: NSView,
        at point: NSPoint,
        clickCount: Int
    ) throws -> NSEvent {
        try makeMouseEvent(type: .leftMouseDown, in: view, at: point, clickCount: clickCount)
    }

    @MainActor
    private func makeMouseEvent(
        type: NSEvent.EventType,
        in view: NSView,
        at point: NSPoint,
        clickCount: Int
    ) throws -> NSEvent {
        guard let window = view.window else {
            throw NSError(domain: "BonsplitTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing window"])
        }
        let pointInWindow = view.convert(point, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: pointInWindow,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1
        ) else {
            throw NSError(domain: "BonsplitTests", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create mouse event"])
        }
        return event
    }

    // MARK: - Tab Width Mode

    /// The tab strip must default to fixed-width sizing so existing layouts are
    /// unchanged; fill is strictly opt-in.
    func testTabWidthModeDefaultsToFixed() {
        XCTAssertEqual(BonsplitConfiguration.Appearance().tabWidthMode, .fixed)
        XCTAssertEqual(BonsplitConfiguration.Appearance.default.tabWidthMode, .fixed)
        XCTAssertEqual(BonsplitConfiguration.Appearance.compact.tabWidthMode, .fixed)
        XCTAssertEqual(BonsplitConfiguration.Appearance.spacious.tabWidthMode, .fixed)
        XCTAssertEqual(BonsplitConfiguration.default.appearance.tabWidthMode, .fixed)
    }

    /// Opting into fill is preserved on the configuration and is distinct from fixed.
    func testTabWidthModeFillIsSettableAndDistinct() {
        var appearance = BonsplitConfiguration.Appearance()
        appearance.tabWidthMode = .fill
        XCTAssertEqual(appearance.tabWidthMode, .fill)
        XCTAssertNotEqual(BonsplitConfiguration.Appearance.TabWidthMode.fill, .fixed)

        let configured = BonsplitConfiguration.Appearance(tabWidthMode: .fill)
        XCTAssertEqual(configured.tabWidthMode, .fill)
    }
}
