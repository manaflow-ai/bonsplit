import AppKit
import Bonsplit

/// Content associated with a tab
struct TabContent {
  var text: String
}

/// Application state managing tabs and their content
@MainActor
final class AppState {
  let controller: BonsplitController

  var tabContents: [TabID: TabContent] = [:]

  /// Reference to debug state for geometry notifications
  weak var debugState: DebugState?

  private var tabCounter = 0

  init() {
    let config = BonsplitConfiguration(
      allowSplits: true,
      allowCloseTabs: true,
      allowCloseLastPane: false,
      // Keep every native content controller alive to preserve scroll position and focus.
      contentViewLifecycle: .keepAllAlive
    )
    self.controller = BonsplitController(configuration: config)
    self.controller.delegate = self
  }

  // MARK: - Tab Operations

  func newTab() {
    tabCounter += 1
    let title = String(
      format: exampleLocalized("example.tab.untitledFormat", defaultValue: "Untitled %d"),
      tabCounter
    )

    if let tabId = controller.createTab(title: title, icon: "doc.text") {
      tabContents[tabId] = TabContent(text: sampleText(for: tabCounter))
      debugState?.refresh()
    }
  }

  func closeCurrentTab() {
    guard let paneId = controller.focusedPaneId,
      let tab = controller.selectedTab(inPane: paneId)
    else { return }
    _ = controller.closeTab(tab.id)
  }

  func splitHorizontal() {
    // Split creates empty pane - we create a tab via the delegate callback
    _ = controller.splitPane(orientation: .horizontal)
  }

  func splitVertical() {
    // Split creates empty pane - we create a tab via the delegate callback
    _ = controller.splitPane(orientation: .vertical)
  }

  /// Create a new tab in a specific pane (called from empty pane view or delegate)
  func newTab(inPane paneId: PaneID) {
    tabCounter += 1
    let title = String(
      format: exampleLocalized("example.tab.untitledFormat", defaultValue: "Untitled %d"),
      tabCounter
    )

    if let tabId = controller.createTab(title: title, icon: "doc.text", inPane: paneId) {
      tabContents[tabId] = TabContent(text: sampleText(for: tabCounter))
      debugState?.refresh()
    }
  }

  /// Close a specific pane
  func closePane(_ paneId: PaneID) {
    _ = controller.closePane(paneId)
  }

  // MARK: - Sample Content

  private func sampleText(for index: Int) -> String {
    let samples = [
      exampleLocalized(
        "example.sample.welcome",
        defaultValue:
          "// Welcome to Bonsplit Example!\n\n// Try these actions:\n// - ⌘T to create a new tab\n// - ⌘W to close the current tab\n// - ⌘⇧D to split right\n// - ⌘⌥D to split down\n// - Drag tabs to reorder or move between panes\n// - ⌘⌥←→↑↓ to navigate between panes\n\nlet greeting = \"Hello, World!\"\nprint(greeting)"
      ),
      String(
        format: exampleLocalized(
          "example.sample.appKit",
          defaultValue:
            "import AppKit\n\nfinal class MyViewController: NSViewController {\n    override func loadView() {\n        view = NSTextField(labelWithString: \"Hello from tab %d\")\n    }\n}"
        ),
        index
      ),
      exampleLocalized(
        "example.sample.notes",
        defaultValue:
          "# Notes\n\nThis is a sample document.\n\n## Features\n\n- Drag and drop tabs\n- Split panes\n- Keyboard navigation\n\n## Tips\n\nTry dragging a tab to the edge of a pane to create a split!"
      ),
      exampleLocalized(
        "example.sample.fibonacci",
        defaultValue:
          "func fibonacci(_ n: Int) -> Int {\n    guard n > 1 else { return n }\n    return fibonacci(n - 1) + fibonacci(n - 2)\n}\n\nlet result = fibonacci(10)\nprint(\"Fibonacci(10) = \\(result)\")"
      ),
      exampleLocalized(
        "example.sample.document",
        defaultValue:
          "struct Document: Identifiable {\n    let id = UUID()\n    var title: String\n    var content: String\n    var isDirty: Bool = false\n}\n\nclass DocumentManager {\n    var documents: [Document] = []\n\n    func save(_ document: Document) {\n        // Save implementation\n    }\n}"
      ),
    ]
    return samples[(index - 1) % samples.count]
  }
}

// MARK: - BonsplitDelegate

@MainActor
extension AppState: BonsplitDelegate {
  func splitTabBar(
    _ controller: BonsplitController,
    shouldCloseTab tab: Bonsplit.Tab,
    inPane pane: PaneID
  ) -> Bool {
    debugState?.log(
      String(
        format: exampleLocalized(
          "example.log.shouldCloseFormat",
          defaultValue: "🔔 shouldCloseTab: \"%@\" in pane %d"
        ),
        tab.title,
        pane.hashValue
      ))

    // If tab is dirty, show confirmation
    if tab.isDirty {
      let alert = NSAlert()
      alert.messageText = String(
        format: exampleLocalized(
          "example.alert.saveQuestionFormat",
          defaultValue: "Do you want to save changes to \"%@\"?"
        ),
        tab.title
      )
      alert.informativeText = exampleLocalized(
        "example.alert.unsavedWarning",
        defaultValue: "Your changes will be lost if you don't save them."
      )
      alert.addButton(withTitle: exampleLocalized("example.alert.save", defaultValue: "Save"))
      alert.addButton(
        withTitle: exampleLocalized(
          "example.alert.dontSave",
          defaultValue: "Don't Save"
        ))
      alert.addButton(withTitle: exampleLocalized("example.alert.cancel", defaultValue: "Cancel"))
      alert.alertStyle = .warning

      switch alert.runModal() {
      case .alertFirstButtonReturn:
        // Save - in a real app, save the file here
        print("Saving \(tab.title)...")
        debugState?.log(
          exampleLocalized(
            "example.log.allowedSaved",
            defaultValue: "   → allowed (saved)"
          ))
        return true
      case .alertSecondButtonReturn:
        // Don't save - just close
        debugState?.log(
          exampleLocalized(
            "example.log.allowedDiscarded",
            defaultValue: "   → allowed (discarded)"
          ))
        return true
      default:
        // Cancel
        debugState?.log(
          exampleLocalized(
            "example.log.deniedCancelled",
            defaultValue: "   → denied (cancelled)"
          ))
        return false
      }
    }
    debugState?.log(exampleLocalized("example.log.allowed", defaultValue: "   → allowed"))
    return true
  }

  func splitTabBar(
    _ controller: BonsplitController,
    didCloseTab tabId: TabID,
    fromPane pane: PaneID
  ) {
    debugState?.log(
      String(
        format: exampleLocalized(
          "example.log.didCloseFormat",
          defaultValue: "✅ didCloseTab: tab %d from pane %d"
        ),
        tabId.hashValue,
        pane.hashValue
      ))

    // Clean up content when tab is closed
    tabContents.removeValue(forKey: tabId)
    debugState?.refresh()
  }

  func splitTabBar(
    _ controller: BonsplitController,
    didSelectTab tab: Bonsplit.Tab,
    inPane pane: PaneID
  ) {
    // Update window title
    if let window = NSApp.keyWindow {
      window.title = tab.title
    }
  }

  func splitTabBar(
    _ controller: BonsplitController,
    didSplitPane originalPane: PaneID,
    newPane: PaneID,
    orientation: SplitOrientation
  ) {
    // Option 1: Auto-create a tab in the new pane
    newTab(inPane: newPane)

    // Option 2: Leave the pane empty and let user create content
    // The empty-pane controller is shown until the host creates content.
  }

  func splitTabBar(
    _ controller: BonsplitController,
    didChangeGeometry snapshot: LayoutSnapshot
  ) {
    debugState?.log(
      String(
        format: exampleLocalized(
          "example.log.geometryChangedFormat",
          defaultValue: "Geometry changed: %d panes"
        ),
        snapshot.panes.count
      ))
    debugState?.currentSnapshot = snapshot
    debugState?.currentTree = controller.treeSnapshot()
  }

  func splitTabBar(
    _ controller: BonsplitController,
    shouldNotifyDuringDrag: Bool
  ) -> Bool {
    // Enable real-time notifications during drag
    return true
  }
}
