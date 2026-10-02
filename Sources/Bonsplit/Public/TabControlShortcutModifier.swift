import AppKit

/// The resolved modifier shown for Bonsplit's numbered surface tab hints.
public struct TabControlShortcutModifier: Equatable {
    /// The modifier flags used by the resolved surface-number shortcut.
    public let modifierFlags: NSEvent.ModifierFlags
    /// The display prefix before each tab digit, including any chord prefix.
    public let symbol: String

    /// Creates a tab hint modifier from the resolved shortcut's flags and display glyphs.
    ///
    /// - Parameters:
    ///   - modifierFlags: The modifier flags for the resolved surface-number shortcut.
    ///   - symbol: The prefix displayed before the digit, such as `⌃` or `⌘K ⌃`.
    public init(modifierFlags: NSEvent.ModifierFlags, symbol: String) {
        self.modifierFlags = modifierFlags
        self.symbol = symbol
    }

    /// The built-in Control modifier used when a host has not supplied a resolved shortcut.
    public static let control = Self(modifierFlags: [.control], symbol: "⌃")
}
