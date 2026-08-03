import AppKit
@testable import Bonsplit
import XCTest

@MainActor
final class BonsplitViewControllerLifecycleTests: XCTestCase {
    private final class UpdatingController: NSViewController, BonsplitContentUpdating {
        private(set) var updates: [(tab: Tab, pane: PaneID)] = []

        override func loadView() {
            view = NSView()
        }

        func updateBonsplitContent(tab: Tab, pane: PaneID) {
            updates.append((tab, pane))
        }
    }

    func testKeepAllAliveCreatesEveryTabOnceAndPreservesControllersAcrossSelection() throws {
        let controller = BonsplitController(configuration: .init(contentViewLifecycle: .keepAllAlive))
        let first = try XCTUnwrap(controller.createTab(title: "First"))
        let second = try XCTUnwrap(controller.createTab(title: "Second"))
        var created: [TabID: [UpdatingController]] = [:]

        try withRenderer(controller: controller) { tab, _ in
            let child = UpdatingController()
            created[tab.id, default: []].append(child)
            return child
        } body: { renderer, window in
            XCTAssertEqual(created[first]?.count, 1)
            XCTAssertEqual(created[second]?.count, 1)
            let firstController = try XCTUnwrap(created[first]?.first)
            let secondController = try XCTUnwrap(created[second]?.first)

            controller.selectTab(first)
            settle(renderer: renderer, window: window)
            controller.selectTab(second)
            settle(renderer: renderer, window: window)

            XCTAssertTrue(created[first]?.first === firstController)
            XCTAssertTrue(created[second]?.first === secondController)
            XCTAssertEqual(created[first]?.count, 1)
            XCTAssertEqual(created[second]?.count, 1)
            XCTAssertFalse(firstController.updates.isEmpty)
            XCTAssertFalse(secondController.updates.isEmpty)
        }
    }

    func testRecreateOnSwitchOnlyCreatesSelectedContentAndRecreatesItOnReturn() throws {
        let controller = BonsplitController(configuration: .init(contentViewLifecycle: .recreateOnSwitch))
        let first = try XCTUnwrap(controller.createTab(title: "First"))
        let second = try XCTUnwrap(controller.createTab(title: "Second"))
        var created: [TabID: [NSViewController]] = [:]

        try withRenderer(controller: controller) { tab, _ in
            let child = NSViewController()
            child.view = NSView()
            created[tab.id, default: []].append(child)
            return child
        } body: { renderer, window in
            XCTAssertNil(created[first])
            XCTAssertEqual(created[second]?.count, 1)
            let originalSecond = try XCTUnwrap(created[second]?.first)

            controller.selectTab(first)
            settle(renderer: renderer, window: window)
            XCTAssertEqual(created[first]?.count, 1)

            controller.selectTab(second)
            settle(renderer: renderer, window: window)
            XCTAssertEqual(created[second]?.count, 2)
            XCTAssertFalse(created[second]?.last === originalSecond)
        }
    }

    func testCachedControllerReceivesMetadataAndPaneUpdates() throws {
        let controller = BonsplitController(configuration: .init(contentViewLifecycle: .keepAllAlive))
        let tabID = try XCTUnwrap(controller.createTab(title: "Original"))
        var created: [TabID: [UpdatingController]] = [:]

        try withRenderer(controller: controller) { tab, _ in
            let child = UpdatingController()
            created[tab.id, default: []].append(child)
            return child
        } body: { renderer, window in
            let child = try XCTUnwrap(created[tabID]?.first)
            let initialUpdateCount = child.updates.count
            controller.updateTab(tabID, title: "Updated")
            settle(renderer: renderer, window: window)

            XCTAssertEqual(created[tabID]?.count, 1)
            XCTAssertGreaterThan(child.updates.count, initialUpdateCount)
            XCTAssertEqual(child.updates.last?.tab.title, "Updated")
            XCTAssertEqual(child.updates.last?.pane, controller.focusedPaneId)
        }
    }

    func testReloadAndProviderReplacementInvalidateContentAndEmptyControllerCaches() throws {
        let controller = BonsplitController()
        let welcome = try XCTUnwrap(controller.allTabIds.first)
        XCTAssertTrue(controller.closeTab(welcome))
        var firstEmptyControllers: [NSViewController] = []
        var replacementEmptyControllers: [NSViewController] = []
        var replacementContentControllers: [NSViewController] = []
        let renderer = BonsplitViewController(
            controller: controller,
            content: { _, _ in
                XCTFail("An empty controller must not request tab content")
                return NSViewController()
            },
            emptyPane: { _ in
                let child = NSViewController()
                child.view = NSView()
                firstEmptyControllers.append(child)
                return child
            }
        )

        try withMountedRenderer(renderer) { window in
            XCTAssertEqual(firstEmptyControllers.count, 1)
            let firstEmpty = try XCTUnwrap(firstEmptyControllers.first)
            renderer.reloadContent()
            settle(renderer: renderer, window: window)
            XCTAssertEqual(firstEmptyControllers.count, 2)
            XCTAssertNil(firstEmpty.parent)

            renderer.updateProviders(
                content: { _, _ in
                    let child = NSViewController()
                    child.view = NSView()
                    replacementContentControllers.append(child)
                    return child
                },
                emptyPane: { _ in
                    let child = NSViewController()
                    child.view = NSView()
                    replacementEmptyControllers.append(child)
                    return child
                }
            )
            settle(renderer: renderer, window: window)
            XCTAssertEqual(replacementEmptyControllers.count, 1)

            _ = try XCTUnwrap(controller.createTab(title: "Content"))
            settle(renderer: renderer, window: window)
            XCTAssertEqual(replacementContentControllers.count, 1)
            XCTAssertNil(replacementEmptyControllers[0].view.superview)
        }
    }

    private func withRenderer(
        controller: BonsplitController,
        content: @escaping BonsplitViewController.ContentProvider,
        body: (BonsplitViewController, NSWindow) throws -> Void
    ) throws {
        let renderer = BonsplitViewController(controller: controller, content: content)
        try withMountedRenderer(renderer) { window in
            try body(renderer, window)
        }
    }

    private func withMountedRenderer(
        _ renderer: BonsplitViewController,
        body: (NSWindow) throws -> Void
    ) throws {
        let size = NSSize(width: 640, height: 480)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        window.contentViewController = renderer
        window.setContentSize(size)
        window.makeKeyAndOrderFront(nil)
        settle(renderer: renderer, window: window)
        try body(window)
    }

    private func settle(renderer: BonsplitViewController, window: NSWindow, passes: Int = 8) {
        for _ in 0..<passes {
            window.contentView?.layoutSubtreeIfNeeded()
            renderer.view.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date.now.addingTimeInterval(0.005))
        }
    }
}
