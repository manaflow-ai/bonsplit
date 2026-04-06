import SwiftUI

/// Environment key for UI scale factor. Host apps inject a value; Bonsplit views
/// multiply font sizes by this factor so the tab bar respects the app-wide scale.
private struct BonsplitUIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

public extension EnvironmentValues {
    /// UI scale factor applied to Bonsplit font sizes. Defaults to 1.0.
    var bonsplitUIScale: CGFloat {
        get { self[BonsplitUIScaleKey.self] }
        set { self[BonsplitUIScaleKey.self] = newValue }
    }
}
