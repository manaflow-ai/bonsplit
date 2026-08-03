import AppKit
import Bonsplit

@MainActor
final class ContentViewController: NSViewController {
  let appState = AppState()
  private let debugState: DebugState
  private lazy var splitController = BonsplitViewController(
    controller: appState.controller,
    content: { [weak appState] tab, pane in
      TabContentViewController(tab: tab, pane: pane, appState: appState)
    },
    emptyPane: { [weak appState] pane in
      EmptyPaneViewController(pane: pane, appState: appState)
    }
  )

  init(debugState: DebugState) {
    self.debugState = debugState
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
    view = root

    addChild(splitController)
    splitController.view.frame = root.bounds
    splitController.view.autoresizingMask = [.width, .height]
    root.addSubview(splitController.view)

    if appState.controller.allTabIds.isEmpty {
      appState.newTab()
    }
    appState.debugState = debugState
    debugState.controller = appState.controller
    debugState.refresh()
  }
}

@MainActor
private final class TabContentViewController: NSViewController, BonsplitContentUpdating,
  NSTextViewDelegate
{
  private var tab: Bonsplit.Tab
  private var pane: PaneID
  private weak var appState: AppState?
  private let textView = NSTextView()
  private let placeholder = NSStackView()

  init(tab: Bonsplit.Tab, pane: PaneID, appState: AppState?) {
    self.tab = tab
    self.pane = pane
    self.appState = appState
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

    let scrollView = NSScrollView(frame: root.bounds)
    scrollView.autoresizingMask = [.width, .height]
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.drawsBackground = false
    textView.isRichText = false
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    textView.textContainerInset = NSSize(width: 8, height: 8)
    textView.delegate = self
    scrollView.documentView = textView
    root.addSubview(scrollView)

    placeholder.orientation = .vertical
    placeholder.alignment = .centerX
    placeholder.spacing = 16
    placeholder.translatesAutoresizingMaskIntoConstraints = false
    let image = NSImageView(
      image: NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil) ?? NSImage())
    image.symbolConfiguration = .init(pointSize: 48, weight: .regular)
    image.contentTintColor = .tertiaryLabelColor
    placeholder.addArrangedSubview(image)
    let label = NSTextField(
      labelWithString: exampleLocalized(
        "example.content.noContent",
        defaultValue: "No content"
      ))
    label.textColor = .secondaryLabelColor
    placeholder.addArrangedSubview(label)
    root.addSubview(placeholder)
    NSLayoutConstraint.activate([
      placeholder.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      placeholder.centerYAnchor.constraint(equalTo: root.centerYAnchor),
    ])
    view = root
    updateEditor()
  }

  func updateBonsplitContent(tab: Bonsplit.Tab, pane: PaneID) {
    self.tab = tab
    self.pane = pane
    if isViewLoaded { updateEditor() }
  }

  func textDidBeginEditing(_ notification: Notification) {
    appState?.controller.focusPane(pane)
  }

  func textDidChange(_ notification: Notification) {
    appState?.tabContents[tab.id]?.text = textView.string
    appState?.controller.updateTab(tab.id, isDirty: true)
  }

  private func updateEditor() {
    guard let content = appState?.tabContents[tab.id] else {
      textView.enclosingScrollView?.isHidden = true
      placeholder.isHidden = false
      return
    }
    placeholder.isHidden = true
    textView.enclosingScrollView?.isHidden = false
    if textView.string != content.text {
      textView.string = content.text
    }
  }
}

@MainActor
private final class EmptyPaneViewController: NSViewController {
  private let pane: PaneID
  private weak var appState: AppState?

  init(pane: PaneID, appState: AppState?) {
    self.pane = pane
    self.appState = appState
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func loadView() {
    let root = NSView()
    root.wantsLayer = true
    root.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 20
    stack.translatesAutoresizingMaskIntoConstraints = false

    let image = NSImageView(
      image: NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil) ?? NSImage()
    )
    image.symbolConfiguration = .init(pointSize: 56, weight: .regular)
    image.contentTintColor = .tertiaryLabelColor
    stack.addArrangedSubview(image)

    let title = NSTextField(
      labelWithString: exampleLocalized(
        "example.empty.title",
        defaultValue: "No Open Files"
      ))
    title.font = .preferredFont(forTextStyle: .title2)
    title.textColor = .secondaryLabelColor
    stack.addArrangedSubview(title)

    let buttons = NSStackView()
    buttons.orientation = .horizontal
    buttons.spacing = 16
    let newButton = NSButton(
      title: exampleLocalized("example.empty.newFile", defaultValue: "New File"),
      target: self,
      action: #selector(newFile(_:))
    )
    newButton.bezelStyle = .rounded
    newButton.keyEquivalent = "\r"
    buttons.addArrangedSubview(newButton)
    if (appState?.controller.allPaneIds.count ?? 0) > 1 {
      buttons.addArrangedSubview(
        NSButton(
          title: exampleLocalized("example.empty.closePane", defaultValue: "Close Pane"),
          target: self,
          action: #selector(closePane(_:))
        ))
    }
    stack.addArrangedSubview(buttons)
    root.addSubview(stack)
    NSLayoutConstraint.activate([
      stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
    ])
    view = root
  }

  @objc private func newFile(_ sender: Any?) {
    appState?.newTab(inPane: pane)
  }

  @objc private func closePane(_ sender: Any?) {
    appState?.closePane(pane)
  }
}
