import SwiftUI

/// A single native drop destination spanning one pane's horizontal tab strip.
@MainActor
struct TabBarDropDestinationView: NSViewRepresentable {
    let pane: PaneState
    let bonsplitController: BonsplitController
    let splitViewController: SplitViewController
    let geometryRegistry: TabBarItemGeometryRegistry
    let onIndicatorIndexChanged: (Int?) -> Void

    func makeNSView(context: Context) -> TabBarDropDestinationNSView {
        let view = TabBarDropDestinationNSView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: TabBarDropDestinationNSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: TabBarDropDestinationNSView) {
        view.pane = pane
        view.bonsplitController = bonsplitController
        view.splitViewController = splitViewController
        view.geometryRegistry = geometryRegistry
        view.onIndicatorIndexChanged = onIndicatorIndexChanged
    }
}
