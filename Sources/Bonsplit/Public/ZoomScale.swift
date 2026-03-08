import SwiftUI

private struct BonsplitZoomScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    public var bonsplitZoomScale: CGFloat {
        get { self[BonsplitZoomScaleKey.self] }
        set { self[BonsplitZoomScaleKey.self] = newValue }
    }
}
