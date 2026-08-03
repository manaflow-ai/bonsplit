import Bonsplit
import Foundation

/// State for the geometry debug panel.
@MainActor
final class DebugState {
  var logs: [String] = []
  var currentSnapshot: LayoutSnapshot?
  var currentTree: ExternalTreeNode?

  weak var controller: BonsplitController?
  var onChange: (() -> Void)?

  func log(_ message: String) {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    let timestamp = formatter.string(from: Date())
    logs.append("[\(timestamp)] \(message)")
    // Keep last 100 logs
    if logs.count > 100 {
      logs.removeFirst(logs.count - 100)
    }
    onChange?()
  }

  func refresh() {
    guard let controller else { return }
    currentSnapshot = controller.layoutSnapshot()
    currentTree = controller.treeSnapshot()
    log(
      String(
        format: exampleLocalized(
          "example.debug.refreshedFormat",
          defaultValue: "Refreshed: %d panes"
        ),
        currentSnapshot?.panes.count ?? 0
      ))
  }

  func setDividerPosition(_ position: CGFloat, splitId: UUID) {
    guard let controller else { return }
    controller.setDividerPosition(position, forSplit: splitId, fromExternal: true)
    refresh()
  }
}
