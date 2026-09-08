import AppKit
import SwiftUI
import Testing

@testable import Bonsplit

/// Mirrors cmux's file-preview panel body: an editable `NSTextView` inside an
/// `NSScrollView`, hosted through `NSViewRepresentable` as pane content.
private struct EditableTextEditorHost: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.string = "key: value\nother: thing\n"
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

/// Drives the real tab strip the way cmux opens a file from the file explorer
/// (`Workspace.newFilePreviewSurface`): create the tab, focus the pane, select
/// the tab, push its metadata, then hand first responder to the editor.
@MainActor
@Suite(.serialized) struct TabBarFilePreviewTabDragArmingTests {
    @Test func tabCreatedLikeAFilePreviewArmsOnTheFirstPressAfterItIsLaidOut() throws {
        var appearance = BonsplitConfiguration.Appearance()
        appearance.tabWidthMode = .fixed
        let controller = BonsplitController(configuration: BonsplitConfiguration(
            contentViewLifecycle: .keepAllAlive,
            newTabPosition: .current,
            appearance: appearance
        ))
        controller.tabShortcutHintsEnabled = false
        let paneId = try #require(controller.allPaneIds.first)
        _ = try #require(controller.createTab(title: "zsh", icon: "terminal", kind: "terminal", inPane: paneId))
        _ = try #require(controller.createTab(title: "vim", icon: "terminal", kind: "terminal", inPane: paneId))

        let hostingView = NSHostingView(
            rootView: BonsplitView(controller: controller) { tab, _ in
                if tab.kind == "filePreview" {
                    EditableTextEditorHost()
                } else {
                    Color.clear
                }
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        defer { window.orderOut(nil) }
        let contentView = try #require(window.contentView)
        hostingView.frame = contentView.bounds
        hostingView.autoresizingMask = [.width, .height]
        contentView.addSubview(hostingView)
        window.makeKeyAndOrderFront(nil)
        settle(window, hostingView)

        let background = try #require(
            descendants(ofType: TabBarDragAndHoverView.TabBarBackgroundNSView.self, in: hostingView).first
        )

        let newTab = try #require(controller.createTab(
            title: "docker-compose.yml",
            icon: "doc.text",
            kind: "filePreview",
            isDirty: false,
            isLoading: false,
            isPinned: false,
            inPane: paneId
        ))
        controller.focusPane(paneId)
        controller.selectTab(newTab)
        controller.updateTab(newTab, title: "docker-compose.yml", icon: .some("doc.text"), isDirty: false)
        settle(window, hostingView)

        let textView = try #require(descendants(ofType: NSTextView.self, in: hostingView).first)
        #expect(window.makeFirstResponder(textView))
        settle(window, hostingView, passes: 2)

        let frame = try #require(background.geometryRegistry?.frame(for: newTab.id, in: background))
        let pressPoint = NSPoint(x: frame.midX, y: frame.midY)
        #expect(background.containsBonsplitTabItemHit(localPoint: pressPoint))

        var beganTabId: UUID?
        background.onBeginTabDrag = { tabId, _, _, _, _ in
            beganTabId = tabId
            return true
        }
        let windowPoint = background.convert(pressPoint, to: nil)
        let mouseDown = try mouseEvent(type: .leftMouseDown, window: window, windowPoint: windowPoint)
        let mouseDragged = try mouseEvent(
            type: .leftMouseDragged,
            window: window,
            windowPoint: NSPoint(x: windowPoint.x + 12, y: windowPoint.y)
        )
        _ = background.handleTabDragEvent(mouseDown)
        _ = background.handleTabDragEvent(mouseDragged)

        #expect(beganTabId == newTab.id)
    }

    private func settle(_ window: NSWindow, _ hostingView: NSView, passes: Int = 8) {
        for _ in 0..<passes {
            window.contentView?.layoutSubtreeIfNeeded()
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.current.run(mode: .default, before: Date.now.addingTimeInterval(0.02))
        }
    }

    private func descendants<T: NSView>(ofType type: T.Type, in root: NSView) -> [T] {
        var matches: [T] = []
        if let match = root as? T {
            matches.append(match)
        }
        for subview in root.subviews {
            matches.append(contentsOf: descendants(ofType: type, in: subview))
        }
        return matches
    }

    private func mouseEvent(
        type: NSEvent.EventType,
        window: NSWindow,
        windowPoint: NSPoint
    ) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
    }
}
