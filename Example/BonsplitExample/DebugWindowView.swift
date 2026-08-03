import AppKit
import Bonsplit

@MainActor
final class DebugWindowController: NSWindowController {
  init(debugState: DebugState) {
    let content = DebugViewController(debugState: debugState)
    let window = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 400, height: 600),
      styleMask: [.titled, .closable, .resizable, .utilityWindow],
      backing: .buffered,
      defer: false
    )
    window.title = exampleLocalized(
      "example.debug.windowTitle",
      defaultValue: "Geometry Debug"
    )
    window.minSize = NSSize(width: 350, height: 400)
    window.contentViewController = content
    super.init(window: window)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@MainActor
private final class DebugViewController: NSViewController {
  private let debugState: DebugState
  private let geometryStack = NSStackView()
  private let logTextView = NSTextView()

  init(debugState: DebugState) {
    self.debugState = debugState
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  isolated deinit {
    debugState.onChange = nil
  }

  override func loadView() {
    let split = NSSplitView()
    split.isVertical = false
    split.dividerStyle = .thin

    geometryStack.orientation = .vertical
    geometryStack.alignment = .leading
    geometryStack.spacing = 8
    geometryStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
    let geometryScroll = NSScrollView()
    geometryScroll.hasVerticalScroller = true
    geometryScroll.documentView = geometryStack

    let logContainer = NSView()
    let header = NSTextField(
      labelWithString: exampleLocalized(
        "example.debug.eventLog",
        defaultValue: "Event Log"
      ))
    header.font = .preferredFont(forTextStyle: .subheadline)
    header.translatesAutoresizingMaskIntoConstraints = false
    let clearButton = NSButton(
      title: exampleLocalized("example.debug.clear", defaultValue: "Clear"),
      target: self,
      action: #selector(clearLogs(_:))
    )
    clearButton.bezelStyle = .inline
    clearButton.translatesAutoresizingMaskIntoConstraints = false
    let logScroll = NSScrollView()
    logScroll.hasVerticalScroller = true
    logScroll.translatesAutoresizingMaskIntoConstraints = false
    logTextView.isEditable = false
    logTextView.isSelectable = true
    logTextView.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    logScroll.documentView = logTextView
    logContainer.addSubview(header)
    logContainer.addSubview(clearButton)
    logContainer.addSubview(logScroll)
    NSLayoutConstraint.activate([
      header.leadingAnchor.constraint(equalTo: logContainer.leadingAnchor, constant: 8),
      header.topAnchor.constraint(equalTo: logContainer.topAnchor, constant: 8),
      clearButton.trailingAnchor.constraint(equalTo: logContainer.trailingAnchor, constant: -8),
      clearButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),
      logScroll.leadingAnchor.constraint(equalTo: logContainer.leadingAnchor),
      logScroll.trailingAnchor.constraint(equalTo: logContainer.trailingAnchor),
      logScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
      logScroll.bottomAnchor.constraint(equalTo: logContainer.bottomAnchor),
    ])

    split.addArrangedSubview(geometryScroll)
    split.addArrangedSubview(logContainer)
    view = split

    debugState.onChange = { [weak self] in
      self?.refresh()
    }
    refresh()
  }

  @objc private func clearLogs(_ sender: Any?) {
    debugState.logs.removeAll()
    refresh()
  }

  @objc private func dividerChanged(_ sender: NSSlider) {
    guard let identifier = sender.identifier?.rawValue,
      let splitID = UUID(uuidString: identifier)
    else { return }
    debugState.setDividerPosition(CGFloat(sender.doubleValue), splitId: splitID)
  }

  private func refresh() {
    geometryStack.arrangedSubviews.forEach {
      geometryStack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }

    guard let snapshot = debugState.currentSnapshot else {
      geometryStack.addArrangedSubview(
        label(
          exampleLocalized(
            "example.debug.noSnapshot",
            defaultValue: "No snapshot, waiting for layout"
          ),
          color: .secondaryLabelColor
        ))
      refreshLogs()
      return
    }

    geometryStack.addArrangedSubview(
      label(
        exampleLocalized("example.debug.layoutSnapshot", defaultValue: "Layout Snapshot"),
        font: .preferredFont(forTextStyle: .subheadline)
      ))
    geometryStack.addArrangedSubview(
      label(
        String(
          format: exampleLocalized(
            "example.debug.containerFormat",
            defaultValue: "Container: %d x %d at (%d, %d)"
          ),
          Int(snapshot.containerFrame.width),
          Int(snapshot.containerFrame.height),
          Int(snapshot.containerFrame.x),
          Int(snapshot.containerFrame.y)
        ),
        font: .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
      ))
    geometryStack.addArrangedSubview(
      label(
        String(
          format: exampleLocalized("example.debug.panesFormat", defaultValue: "Panes (%d)"),
          snapshot.panes.count
        )))
    for pane in snapshot.panes {
      let focused = pane.paneId == snapshot.focusedPaneId ? " ★" : ""
      geometryStack.addArrangedSubview(
        label(
          String(
            format: exampleLocalized(
              "example.debug.paneFormat",
              defaultValue: "%@…%@\n  pos: (%d, %d)\n  size: %d x %d\n  tabs: %d"
            ),
            String(pane.paneId.prefix(8)),
            focused,
            Int(pane.frame.x),
            Int(pane.frame.y),
            Int(pane.frame.width),
            Int(pane.frame.height),
            pane.tabIds.count
          ),
          font: .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        ))
    }
    if let tree = debugState.currentTree {
      geometryStack.addArrangedSubview(
        label(
          exampleLocalized("example.debug.splits", defaultValue: "Splits")
        ))
      appendSplitControls(for: tree)
    }
    refreshLogs()
  }

  private func appendSplitControls(for node: ExternalTreeNode) {
    guard case .split(let split) = node else { return }
    let row = NSStackView()
    row.orientation = .horizontal
    row.spacing = 6
    row.addArrangedSubview(
      label(
        String(
          format: exampleLocalized(
            "example.debug.splitFormat",
            defaultValue: "%@… (%@)"
          ),
          String(split.id.prefix(8)),
          split.orientation
        )))
    let slider = NSSlider(
      value: split.dividerPosition, minValue: 0.1, maxValue: 0.9, target: self,
      action: #selector(dividerChanged(_:)))
    slider.identifier = NSUserInterfaceItemIdentifier(split.id)
    row.addArrangedSubview(slider)
    row.addArrangedSubview(label(String(format: "%.2f", split.dividerPosition)))
    geometryStack.addArrangedSubview(row)
    appendSplitControls(for: split.first)
    appendSplitControls(for: split.second)
  }

  private func refreshLogs() {
    logTextView.string = debugState.logs.joined(separator: "\n")
    logTextView.scrollToEndOfDocument(nil)
  }

  private func label(
    _ value: String,
    font: NSFont = .systemFont(ofSize: NSFont.smallSystemFontSize),
    color: NSColor = .labelColor
  ) -> NSTextField {
    let field = NSTextField(wrappingLabelWithString: value)
    field.font = font
    field.textColor = color
    return field
  }
}
