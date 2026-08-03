import AppKit

/// An AppKit-native keyboard shortcut displayed by Bonsplit menus.
public struct BonsplitKeyboardShortcut: Hashable, Sendable {
    public var keyEquivalent: String
    public var modifierFlagsRawValue: UInt

    public init(keyEquivalent: String, modifierFlags: NSEvent.ModifierFlags = []) {
        self.keyEquivalent = keyEquivalent.lowercased()
        self.modifierFlagsRawValue = modifierFlags.rawValue
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue)
    }
}
