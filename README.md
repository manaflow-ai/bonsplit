# Bonsplit

Bonsplit is a native AppKit tab bar and split-pane library for macOS.

## Features

- Native `NSViewController`, `NSSplitView`, scrolling, menus, drag and drop, and accessibility
- Tab reordering within and between panes
- Horizontal and vertical panes
- Configurable appearance and behavior
- Delegate callbacks for tab, pane, focus, and geometry events
- Directional keyboard navigation
- Selectable content-controller lifecycle for state preservation or lower memory use

## Requirements

- macOS 14.0+
- Swift 6.3+
- Xcode 26.3+

## Installation

Add Bonsplit with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/manaflow-ai/bonsplit.git", branch: "main")
]
```

## Quick start

Create one `BonsplitController` for the model and one `BonsplitViewController` for its native view hierarchy:

```swift
import AppKit
import Bonsplit

@MainActor
final class WorkspaceViewController: NSViewController {
    private let splitModel = BonsplitController()
    private lazy var splitViewController = BonsplitViewController(
        controller: splitModel,
        content: { tab, pane in
            DocumentViewController(tab: tab, pane: pane)
        },
        emptyPane: { pane in
            EmptyPaneViewController(pane: pane)
        }
    )

    override func loadView() {
        let root = NSView()
        addChild(splitViewController)
        splitViewController.view.frame = root.bounds
        splitViewController.view.autoresizingMask = [.width, .height]
        root.addSubview(splitViewController.view)
        view = root

        _ = splitModel.createTab(title: "Untitled", icon: "doc.text")
    }
}
```

Splits create empty panes by default. Implement `didSplitPane` on `BonsplitDelegate` to create a tab automatically.

## Native content lifecycle

The content provider returns an `NSViewController`. Use `BonsplitContentUpdating` when a cached controller needs current tab metadata or its current pane:

```swift
@MainActor
final class DocumentViewController: NSViewController, BonsplitContentUpdating {
    private var tab: Tab
    private var pane: PaneID

    init(tab: Tab, pane: PaneID) {
        self.tab = tab
        self.pane = pane
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateBonsplitContent(tab: Tab, pane: PaneID) {
        self.tab = tab
        self.pane = pane
        updateLabels()
    }
}
```

Choose the lifetime in `BonsplitConfiguration`:

```swift
let configuration = BonsplitConfiguration(
    contentViewLifecycle: .keepAllAlive
)
```

| Mode | Behavior |
| --- | --- |
| `.recreateOnSwitch` | Keeps only selected content alive. Returning to a tab asks the provider for a new controller. |
| `.keepAllAlive` | Keeps every tab controller attached and hides unselected views. Scroll, selection, and responder state remain intact. |

Call `reloadContent()` to discard every cached tab and empty-pane controller. Call `updateProviders(content:emptyPane:)` to replace providers and rebuild their cached controllers.

## Controller API

### Tabs

```swift
let tabID = controller.createTab(
    title: "Document.swift",
    icon: "swift",
    isDirty: false,
    inPane: paneID
)

controller.updateTab(tabID, title: "NewName.swift")
controller.updateTab(tabID, isDirty: true)
controller.selectTab(tabID)
controller.selectPreviousTab()
controller.selectNextTab()
controller.closeTab(tabID)
```

### Splits

```swift
let rightPane = controller.splitPane(orientation: .horizontal)
let lowerPane = controller.splitPane(orientation: .vertical)
controller.splitPane(paneID, orientation: .horizontal)
controller.splitPane(
    orientation: .horizontal,
    withTab: Tab(title: "New", icon: "doc.text")
)
controller.closePane(paneID)
```

### Focus

```swift
let focusedPane = controller.focusedPaneId
controller.focusPane(paneID)
controller.navigateFocus(direction: .left)
controller.navigateFocus(direction: .right)
controller.navigateFocus(direction: .up)
controller.navigateFocus(direction: .down)
```

### Queries

```swift
let allTabs = controller.allTabIds
let allPanes = controller.allPaneIds
let tab = controller.tab(tabID)
let paneTabs = controller.tabs(inPane: paneID)
let selected = controller.selectedTab(inPane: paneID)
```

### Geometry and synchronization

```swift
let snapshot = controller.layoutSnapshot()
let tree = controller.treeSnapshot()

controller.setDividerPosition(0.3, forSplit: splitID, fromExternal: true)
controller.setImposedFirstExtent(420, forSplit: splitID, fromExternal: true)
controller.setContainerFrame(newFrame)
```

Pass `fromExternal: true` when restoring host-owned geometry. Bonsplit applies the model change without echoing it through the delegate. A normal call publishes one geometry snapshot synchronously.

## Delegate

All `BonsplitDelegate` methods have default implementations.

```swift
@MainActor
final class WorkspaceDelegate: BonsplitDelegate {
    func splitTabBar(
        _ controller: BonsplitController,
        shouldCloseTab tab: Tab,
        inPane pane: PaneID
    ) -> Bool {
        !tab.isDirty || confirmDiscard(tab)
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didSplitPane originalPane: PaneID,
        newPane: PaneID,
        orientation: SplitOrientation
    ) {
        controller.createTab(title: "Untitled", icon: "doc.text", inPane: newPane)
    }

    func splitTabBar(
        _ controller: BonsplitController,
        didChangeGeometry snapshot: LayoutSnapshot
    ) {
        save(snapshot)
    }

    func splitTabBar(
        _ controller: BonsplitController,
        shouldNotifyDuringDrag: Bool
    ) -> Bool {
        true
    }
}
```

Delegate hooks cover creation, close vetoes, selection, moves, splits, pane closure, focus, and geometry.

## Configuration

```swift
let appearance = BonsplitConfiguration.Appearance(
    tabBarHeight: 33,
    tabMinWidth: 140,
    tabMaxWidth: 220,
    tabSpacing: 0,
    minimumPaneWidth: 100,
    minimumPaneHeight: 100,
    showSplitButtons: true,
    animationDuration: 0.15,
    enableAnimations: true
)

let configuration = BonsplitConfiguration(
    allowSplits: true,
    allowCloseTabs: true,
    allowCloseLastPane: false,
    allowTabReordering: true,
    allowCrossPaneTabMove: true,
    autoCloseEmptyPanes: true,
    contentViewLifecycle: .recreateOnSwitch,
    newTabPosition: .current,
    appearance: appearance
)
```

Presets are available as `.default`, `.singlePane`, and `.readOnly`.

## AppKit menu commands

Bonsplit does not install application-global menu items. Route `NSMenuItem` actions to the same controller methods used by buttons and other entry points:

```swift
let nextTab = NSMenuItem(
    title: "Show Next Tab",
    action: #selector(showNextTab(_:)),
    keyEquivalent: "]"
)
nextTab.keyEquivalentModifierMask = [.command, .shift]

@objc func showNextTab(_ sender: Any?) {
    controller.selectNextTab()
}
```

See `Example/BonsplitExample` for a complete native application, including editable tab content, empty panes, keyboard commands, and a geometry inspector.

## License

MIT License
