import SwiftUI

/// Bridges an immutable animation snapshot into Core Animation-owned playback.
@MainActor
struct AnimatedTabIconView: NSViewRepresentable {
    let animation: TabIconAnimation

    func makeNSView(context: Context) -> AnimatedTabIconNSView {
        let view = AnimatedTabIconNSView(frame: .zero)
        view.configure(animation)
        return view
    }

    func updateNSView(_ nsView: AnimatedTabIconNSView, context: Context) {
        nsView.configure(animation)
    }

    static func dismantleNSView(_ nsView: AnimatedTabIconNSView, coordinator: ()) {
        nsView.stopObserving()
    }
}
