import SwiftUI

/// A small status glyph drawn just before a tab's title.
///
/// Bonsplit does not know what the status means; the host app decides the
/// symbol, color and whether it pulses (for example an agent that is running,
/// waiting for input or waiting on background work).
public struct TabStatusIndicator: Hashable, Sendable {
    /// SF Symbol name. `nil` draws a filled dot.
    public var symbolName: String?
    /// Glyph color. `nil` uses the tab's secondary text color.
    public var color: Color?
    /// Whether the glyph fades in and out. Skipped when Reduce Motion is on.
    public var pulses: Bool
    /// Spoken by VoiceOver as part of the tab's value.
    public var accessibilityLabel: String

    public init(
        symbolName: String? = nil,
        color: Color? = nil,
        pulses: Bool = false,
        accessibilityLabel: String = ""
    ) {
        self.symbolName = symbolName
        self.color = color
        self.pulses = pulses
        self.accessibilityLabel = accessibilityLabel
    }
}
