import AppKit
import Bonsplit

func exampleLocalized(
  _ key: StaticString,
  defaultValue: String.LocalizationValue
) -> String {
  String(localized: key, defaultValue: defaultValue)
}

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let debugState = DebugState()
  private var mainWindowController: NSWindowController?
  private var debugWindowController: DebugWindowController?

  private var contentViewController: ContentViewController? {
    mainWindowController?.contentViewController as? ContentViewController
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = makeMainMenu()

    let content = ContentViewController(debugState: debugState)
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
      styleMask: [.titled, .closable, .miniaturizable, .resizable, .unifiedTitleAndToolbar],
      backing: .buffered,
      defer: false
    )
    window.title = exampleLocalized(
      "example.window.title",
      defaultValue: "Bonsplit Example"
    )
    window.minSize = NSSize(width: 800, height: 600)
    window.center()
    window.contentViewController = content
    let windowController = NSWindowController(window: window)
    mainWindowController = windowController
    windowController.showWindow(nil)
    NSApp.activate()
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    true
  }

  @objc private func newTab(_ sender: Any?) {
    contentViewController?.appState.newTab()
  }

  @objc private func closeTab(_ sender: Any?) {
    contentViewController?.appState.closeCurrentTab()
  }

  @objc private func previousTab(_ sender: Any?) {
    contentViewController?.appState.controller.selectPreviousTab()
  }

  @objc private func nextTab(_ sender: Any?) {
    contentViewController?.appState.controller.selectNextTab()
  }

  @objc private func splitRight(_ sender: Any?) {
    contentViewController?.appState.splitHorizontal()
  }

  @objc private func splitDown(_ sender: Any?) {
    contentViewController?.appState.splitVertical()
  }

  @objc private func navigateLeft(_ sender: Any?) {
    contentViewController?.appState.controller.navigateFocus(direction: .left)
  }

  @objc private func navigateRight(_ sender: Any?) {
    contentViewController?.appState.controller.navigateFocus(direction: .right)
  }

  @objc private func navigateUp(_ sender: Any?) {
    contentViewController?.appState.controller.navigateFocus(direction: .up)
  }

  @objc private func navigateDown(_ sender: Any?) {
    contentViewController?.appState.controller.navigateFocus(direction: .down)
  }

  @objc private func showDebugWindow(_ sender: Any?) {
    if debugWindowController == nil {
      debugWindowController = DebugWindowController(debugState: debugState)
    }
    debugWindowController?.showWindow(nil)
  }

  private func makeMainMenu() -> NSMenu {
    let main = NSMenu()

    let applicationItem = NSMenuItem()
    main.addItem(applicationItem)
    let applicationMenu = NSMenu()
    applicationItem.submenu = applicationMenu
    let quit = NSMenuItem(
      title: exampleLocalized(
        "example.menu.quit",
        defaultValue: "Quit Bonsplit Example"
      ),
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quit.target = NSApp
    applicationMenu.addItem(quit)

    main.addItem(
      menuItem(
        title: exampleLocalized("example.menu.file", defaultValue: "File"),
        items: [
          command(
            exampleLocalized("example.menu.newTab", defaultValue: "New Tab"),
            action: #selector(newTab(_:)), key: "t"),
          command(
            exampleLocalized("example.menu.closeTab", defaultValue: "Close Tab"),
            action: #selector(closeTab(_:)), key: "w"),
          .separator(),
          command(
            exampleLocalized("example.menu.previousTab", defaultValue: "Show Previous Tab"),
            action: #selector(previousTab(_:)), key: "[", modifiers: [.command, .shift]),
          command(
            exampleLocalized("example.menu.nextTab", defaultValue: "Show Next Tab"),
            action: #selector(nextTab(_:)), key: "]", modifiers: [.command, .shift]),
        ]))
    main.addItem(
      menuItem(
        title: exampleLocalized("example.menu.split", defaultValue: "Split"),
        items: [
          command(
            exampleLocalized("example.menu.splitRight", defaultValue: "Split Right"),
            action: #selector(splitRight(_:)), key: "\\"),
          command(
            exampleLocalized("example.menu.splitDown", defaultValue: "Split Down"),
            action: #selector(splitDown(_:)), key: "\\", modifiers: [.command, .shift]),
          .separator(),
          command(
            exampleLocalized("example.menu.navigateLeft", defaultValue: "Navigate Left"),
            action: #selector(navigateLeft(_:)),
            key: String(UnicodeScalar(NSLeftArrowFunctionKey)!), modifiers: [.command, .option]),
          command(
            exampleLocalized("example.menu.navigateRight", defaultValue: "Navigate Right"),
            action: #selector(navigateRight(_:)),
            key: String(UnicodeScalar(NSRightArrowFunctionKey)!), modifiers: [.command, .option]),
          command(
            exampleLocalized("example.menu.navigateUp", defaultValue: "Navigate Up"),
            action: #selector(navigateUp(_:)), key: String(UnicodeScalar(NSUpArrowFunctionKey)!),
            modifiers: [.command, .option]),
          command(
            exampleLocalized("example.menu.navigateDown", defaultValue: "Navigate Down"),
            action: #selector(navigateDown(_:)),
            key: String(UnicodeScalar(NSDownArrowFunctionKey)!), modifiers: [.command, .option]),
        ]))
    main.addItem(
      menuItem(
        title: exampleLocalized("example.menu.debug", defaultValue: "Debug"),
        items: [
          command(
            exampleLocalized("example.menu.showGeometryDebug", defaultValue: "Show Geometry Debug"),
            action: #selector(showDebugWindow(_:)), key: "d", modifiers: [.command, .option])
        ]))
    return main
  }

  private func menuItem(title: String, items: [NSMenuItem]) -> NSMenuItem {
    let root = NSMenuItem()
    let submenu = NSMenu(title: title)
    items.forEach(submenu.addItem)
    root.submenu = submenu
    return root
  }

  private func command(
    _ title: String,
    action: Selector,
    key: String,
    modifiers: NSEvent.ModifierFlags = .command
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = self
    return item
  }
}
