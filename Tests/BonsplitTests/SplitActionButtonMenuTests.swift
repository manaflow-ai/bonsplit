import AppKit
import Foundation
import Testing
@testable import Bonsplit

@Suite("Split action button menus and alternates")
@MainActor
struct SplitActionButtonMenuTests {
    private typealias ActionButton = BonsplitConfiguration.SplitActionButton

    @Test("Menu behavior and alternate action round-trip through Codable")
    func menuFieldsRoundTrip() throws {
        let button = ActionButton(
            id: "split",
            systemImage: "square.split.2x1",
            action: .splitRight,
            alternateAction: .splitDown,
            menuBehavior: .secondary
        )
        let data = try JSONEncoder().encode(button)
        let decoded = try JSONDecoder().decode(ActionButton.self, from: data)
        #expect(decoded == button)
        #expect(decoded.menuBehavior == .secondary)
        #expect(decoded.alternateAction == .splitDown)
    }

    @Test("offersNewTerminal round-trips and is omitted when false")
    func offersNewTerminalRoundTrips() throws {
        let add = ActionButton(
            id: "add",
            systemImage: "plus",
            action: .custom("add"),
            menuBehavior: .secondary,
            offersNewTerminal: true
        )
        let decoded = try JSONDecoder().decode(ActionButton.self, from: try JSONEncoder().encode(add))
        #expect(decoded.offersNewTerminal)

        let plainData = try JSONEncoder().encode(ActionButton.newTerminal)
        let plain = try #require(JSONSerialization.jsonObject(with: plainData) as? [String: Any])
        #expect(plain["offersNewTerminal"] == nil)
    }

    @Test("Buttons without menu fields keep their previous encoding")
    func plainButtonEncodingOmitsNewKeys() throws {
        let data = try JSONEncoder().encode(ActionButton.splitRight)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["menuBehavior"] == nil)
        #expect(object["alternateAction"] == nil)
        let decoded = try JSONDecoder().decode(ActionButton.self, from: data)
        #expect(decoded.menuBehavior == .none)
        #expect(decoded.alternateAction == nil)
        #expect(!decoded.usesMenuInteraction)
    }

    @Test("Option-click resolves to the alternate action only when one is set")
    func resolvedActionHonorsOption() {
        let split = ActionButton(id: "split", systemImage: "square.split.2x1", action: .splitRight, alternateAction: .splitDown)
        #expect(split.resolvedAction(optionKeyHeld: false) == .splitRight)
        #expect(split.resolvedAction(optionKeyHeld: true) == .splitDown)
        #expect(ActionButton.splitRight.resolvedAction(optionKeyHeld: true) == .splitRight)
        #expect(split.usesMenuInteraction)
    }

    @Test("Per-pane buttons override the configured defaults and can be cleared")
    func perPaneOverride() throws {
        let controller = BonsplitController()
        let pane = try #require(controller.focusedPaneId)
        #expect(controller.splitButtons(forPane: pane) == ActionButton.defaults)

        let more = ActionButton(id: "more", systemImage: "ellipsis", action: .custom("more"), menuBehavior: .primary)
        controller.setSplitButtons([more, more], forPane: pane)
        #expect(controller.splitButtons(forPane: pane) == [more])

        controller.setSplitButtons(nil, forPane: pane)
        #expect(controller.splitButtons(forPane: pane) == ActionButton.defaults)
    }

    @Test("Menu requests reach the delegate with the button and pane")
    func menuRequestReachesDelegate() throws {
        let controller = BonsplitController()
        let delegate = MenuDelegate()
        controller.delegate = delegate
        let pane = try #require(controller.focusedPaneId)

        let menu = controller.splitActionMenu(forButton: "more", inPane: pane)

        #expect(menu?.title == "more")
        #expect(delegate.requests.count == 1)
        #expect(delegate.requests.first?.0 == "more")
        #expect(delegate.requests.first?.1 == pane)
    }

    @Test("A quick click on a secondary-menu button clicks and reports Option")
    func quickClickPerformsAction() throws {
        let (window, view) = makeHostedView(menuBehavior: .secondary)
        defer { window.close() }
        var clicks: [Bool] = []
        var menuRequests = 0
        view.onClick = { clicks.append($0) }
        view.menuProvider = {
            menuRequests += 1
            return nil
        }

        view.mouseDown(with: try mouseEvent(.leftMouseDown, in: view, modifiers: []))
        #expect(view.isTrackingPress)
        view.mouseUp(with: try mouseEvent(.leftMouseUp, in: view, modifiers: []))
        view.mouseDown(with: try mouseEvent(.leftMouseDown, in: view, modifiers: [.option]))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, in: view, modifiers: [.option]))

        #expect(clicks == [false, true])
        #expect(menuRequests == 0)
        #expect(!view.isTrackingPress)
    }

    @Test("Right-click asks for the menu and does not click")
    func rightClickRequestsMenu() throws {
        let (window, view) = makeHostedView(menuBehavior: .secondary)
        defer { window.close() }
        var clicks = 0
        var menuRequests = 0
        view.onClick = { _ in clicks += 1 }
        view.menuProvider = {
            menuRequests += 1
            return nil
        }

        view.rightMouseDown(with: try mouseEvent(.rightMouseDown, in: view, modifiers: []))

        #expect(menuRequests == 1)
        #expect(clicks == 0)
    }

    @Test("A primary-menu button asks for the menu on mouse down")
    func primaryMenuOpensOnMouseDown() throws {
        let (window, view) = makeHostedView(menuBehavior: .primary)
        defer { window.close() }
        var clicks = 0
        var menuRequests = 0
        view.onClick = { _ in clicks += 1 }
        view.menuProvider = {
            menuRequests += 1
            return nil
        }

        view.mouseDown(with: try mouseEvent(.leftMouseDown, in: view, modifiers: []))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, in: view, modifiers: []))

        #expect(menuRequests == 1)
        #expect(clicks == 0)
    }

    @Test("Releasing outside the button does not click")
    func releaseOutsideDoesNotClick() throws {
        let (window, view) = makeHostedView(menuBehavior: .secondary)
        defer { window.close() }
        var clicks = 0
        view.onClick = { _ in clicks += 1 }

        view.mouseDown(with: try mouseEvent(.leftMouseDown, in: view, modifiers: []))
        view.mouseUp(with: try mouseEvent(.leftMouseUp, in: view, modifiers: [], at: NSPoint(x: 60, y: 11)))

        #expect(clicks == 0)
        #expect(!view.isTrackingPress)
    }

    @Test("Holding opens the menu only while the pointer stays on the button")
    func holdOpensMenuOnlyInside() throws {
        let (window, view) = makeHostedView(menuBehavior: .secondary)
        defer { window.close() }
        var clicks = 0
        var menuRequests = 0
        var inside = false
        view.onClick = { _ in clicks += 1 }
        view.menuProvider = {
            menuRequests += 1
            return nil
        }
        view.isPointerInside = { inside }

        view.mouseDown(with: try mouseEvent(.leftMouseDown, in: view, modifiers: []))
        view.holdToOpenMenuDelayElapsed()
        #expect(menuRequests == 0)
        #expect(view.isTrackingPress)
        view.mouseUp(with: try mouseEvent(.leftMouseUp, in: view, modifiers: [], at: NSPoint(x: 60, y: 11)))

        inside = true
        view.mouseDown(with: try mouseEvent(.leftMouseDown, in: view, modifiers: []))
        view.holdToOpenMenuDelayElapsed()
        #expect(menuRequests == 1)
        #expect(!view.isTrackingPress)
        view.mouseUp(with: try mouseEvent(.leftMouseUp, in: view, modifiers: []))

        #expect(clicks == 0)
    }

    @Test("Hover reports every enter, exits only once, and rechecks the pointer off the update")
    func hoverReportsEnterAndExit() async throws {
        let (window, view) = makeHostedView(menuBehavior: .secondary)
        defer { window.close() }
        var reports: [Bool] = []
        var inside = false
        view.onHoverChanged = { _, hovering in reports.append(hovering) }
        view.isPointerOverVisibleButton = { inside }
        await drainMainQueue()
        reports.removeAll()
        let event = try mouseEvent(.mouseMoved, in: view, modifiers: [])

        // The host may have dropped its copy (bar hover reset) while the view
        // still thought it was inside, so a repeated enter must reach it.
        view.mouseEntered(with: event)
        view.mouseEntered(with: event)
        view.mouseExited(with: event)
        view.mouseExited(with: event)
        #expect(reports == [true, true, false])

        // The view moved under a still pointer: no enter arrives, the recheck
        // after the tracking area is rebuilt publishes it on the next turn.
        inside = true
        view.updateTrackingAreas()
        #expect(reports == [true, true, false])
        await drainMainQueue()
        #expect(reports == [true, true, false, true])

        // A pane torn down under a still pointer never sees its exit.
        view.removeFromSuperview()
        await drainMainQueue()
        #expect(reports == [true, true, false, true, false])
        #expect(!view.isHovered)
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @Test("Menu anchors hold their views weakly")
    func menuAnchorsAreWeak() {
        let anchors = SplitActionMenuAnchors()
        autoreleasepool {
            let view = NSView()
            anchors.set(view, for: "split")
            #expect(anchors.view(for: "split") === view)
        }
        #expect(anchors.view(for: "split") == nil)
    }

    private func makeHostedView(
        menuBehavior: ActionButton.MenuBehavior
    ) -> (NSWindow, SplitActionMenuInteractionNSView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        let view = SplitActionMenuInteractionNSView(frame: NSRect(x: 10, y: 10, width: 22, height: 22))
        view.menuBehavior = menuBehavior
        window.contentView?.addSubview(view)
        return (window, view)
    }

    private func mouseEvent(
        _ type: NSEvent.EventType,
        in view: NSView,
        modifiers: NSEvent.ModifierFlags,
        at point: NSPoint = NSPoint(x: 11, y: 11)
    ) throws -> NSEvent {
        let window = try #require(view.window)
        return try #require(NSEvent.mouseEvent(
            with: type,
            location: view.convert(point, to: nil),
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}

@MainActor
private final class MenuDelegate: BonsplitDelegate {
    var requests: [(String, PaneID)] = []

    func splitTabBar(_ controller: BonsplitController, menuForSplitActionButton buttonId: String, inPane pane: PaneID) -> NSMenu? {
        requests.append((buttonId, pane))
        return NSMenu(title: buttonId)
    }
}
