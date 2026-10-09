import AppKit
import Observation
import SwiftUI

/// Lets a host animate a pane's width without laying the whole pane out
/// each frame: while `slideTabBarWidth` is set, the pane's tab bar lays
/// itself out at that width (leading-aligned), with real tab truncation and
/// the action lane at that width's trailing edge. The host finds one of
/// these views in each pane's tab bar and clears it when done.
@MainActor
public protocol BonsplitTabBarSlideWidthControlling: AnyObject {
    var slideTabBarWidth: CGFloat? { get set }
}

@MainActor
@Observable
final class TabBarSlideWidthModel {
    var width: CGFloat?
}

/// Lays its tab bar out at the model's width while one is set, leading
/// aligned; only this wrapper observes the width.
struct TabBarSlideWidthContainer<Content: View>: View {
    @State private var model = TabBarSlideWidthModel()
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: model.width, alignment: .leading)
            .background(TabBarSlideWidthAnchor(model: model))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A zero-size view in the tab bar that carries the width to its model.
struct TabBarSlideWidthAnchor: NSViewRepresentable {
    let model: TabBarSlideWidthModel

    func makeNSView(context: Context) -> AnchorView {
        AnchorView(model: model)
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.model = model
    }

    final class AnchorView: NSView, BonsplitTabBarSlideWidthControlling {
        fileprivate(set) var model: TabBarSlideWidthModel

        init(model: TabBarSlideWidthModel) {
            self.model = model
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        var slideTabBarWidth: CGFloat? {
            get { model.width }
            set {
                guard model.width != newValue else { return }
                model.width = newValue
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
