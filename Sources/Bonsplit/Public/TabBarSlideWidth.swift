import AppKit
import Observation
import SwiftUI

/// Lets a host animate a pane's width without laying the whole pane out
/// each frame: while `slideTabBarWidth` is set, the pane's tabs lay
/// themselves out at that width (leading aligned, with real truncation and
/// fades) and the action lane is hidden, so the host can draw it at the
/// pane's moving trailing edge itself. The bar's surface keeps the pane's
/// full width. The host finds one of these views in each pane's tab bar
/// and clears it when done.
@MainActor
public protocol BonsplitTabBarSlideWidthControlling: AnyObject {
    var slideTabBarWidth: CGFloat? { get set }
    /// The width the action lane takes at the bar's trailing edge, 0 when
    /// it is not shown.
    var slideActionLaneWidth: CGFloat { get }
}

@MainActor
@Observable
final class TabBarSlideWidthModel {
    var width: CGFloat?
    @ObservationIgnored var laneWidth: CGFloat = 0
}

private struct TabBarSlideWidthModelKey: EnvironmentKey {
    static let defaultValue: TabBarSlideWidthModel? = nil
}

extension EnvironmentValues {
    var tabBarSlideWidthModel: TabBarSlideWidthModel? {
        get { self[TabBarSlideWidthModelKey.self] }
        set { self[TabBarSlideWidthModelKey.self] = newValue }
    }
}

struct TabBarSlideLaneWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Gives its tab bar the model; only the two small modifiers below observe
/// the width. The tab row still measures its new width, so changing the
/// width every frame costs a tab bar body pass per frame; hold it steady.
struct TabBarSlideWidthContainer<Content: View>: View {
    @State private var model = TabBarSlideWidthModel()
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .environment(\.tabBarSlideWidthModel, model)
            .background(TabBarSlideWidthAnchor(model: model))
            .onPreferenceChange(TabBarSlideLaneWidthKey.self) { [model] width in
                model.laneWidth = width
            }
    }
}

/// The tabs' row at the slide's width, leading aligned.
struct TabBarSlideWidthFrame: ViewModifier {
    let model: TabBarSlideWidthModel?

    func body(content: Content) -> some View {
        content.frame(width: model?.width, alignment: .leading)
    }
}

/// The action lane, hidden while a slide width is set.
struct TabBarSlideLaneHidden: ViewModifier {
    let model: TabBarSlideWidthModel?

    func body(content: Content) -> some View {
        content.opacity(model?.width == nil ? 1 : 0)
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

        var slideActionLaneWidth: CGFloat { model.laneWidth }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
