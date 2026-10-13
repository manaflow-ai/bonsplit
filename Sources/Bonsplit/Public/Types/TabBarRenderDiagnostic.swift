import Foundation

/// A sampled report that tab-bar rendering stayed active across many view updates.
public struct TabBarRenderDiagnostic: Sendable {
    /// Wall-clock duration covered by the sampled render window.
    public let elapsed: TimeInterval

    /// Number of tab-bar body evaluations in the sampled window.
    public let renderCount: Int

    /// Sum of tab counts observed across those evaluations.
    public let tabCount: Int

    /// Number of distinct panes observed across those evaluations.
    public let paneCount: Int

    /// Creates a diagnostic from one sustained tab-bar render window.
    public init(elapsed: TimeInterval, renderCount: Int, tabCount: Int, paneCount: Int) {
        self.elapsed = elapsed
        self.renderCount = renderCount
        self.tabCount = tabCount
        self.paneCount = paneCount
    }
}
