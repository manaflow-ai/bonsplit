import Foundation

/// A named color shown in the tab color context-menu palette.
public struct TabColorPaletteEntry: Identifiable, Hashable, Sendable {
    /// The user-facing color name.
    public let name: String

    /// The color encoded as `#RRGGBB` or `#RRGGBBAA`.
    public let hex: String

    /// A stable identifier derived from the color name.
    public var id: String { name }

    /// Creates a named tab color palette entry.
    ///
    /// - Parameters:
    ///   - name: The user-facing color name.
    ///   - hex: The color encoded as `#RRGGBB` or `#RRGGBBAA`.
    public init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }
}

extension TabColorPaletteEntry {
    static let defaultPalette: [Self] = [
        .init(name: "Red", hex: "#C0392B"),
        .init(name: "Crimson", hex: "#922B21"),
        .init(name: "Orange", hex: "#A04000"),
        .init(name: "Amber", hex: "#7D6608"),
        .init(name: "Olive", hex: "#4A5C18"),
        .init(name: "Green", hex: "#196F3D"),
        .init(name: "Teal", hex: "#006B6B"),
        .init(name: "Aqua", hex: "#0E6B8C"),
        .init(name: "Blue", hex: "#1565C0"),
        .init(name: "Navy", hex: "#1A5276"),
        .init(name: "Indigo", hex: "#283593"),
        .init(name: "Purple", hex: "#6A1B9A"),
        .init(name: "Magenta", hex: "#AD1457"),
        .init(name: "Rose", hex: "#880E4F"),
        .init(name: "Brown", hex: "#7B3F00"),
        .init(name: "Charcoal", hex: "#3E4B5E"),
    ]
}
