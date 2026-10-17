import Foundation

/// A named accent color offered in the tab context menu's color submenu.
///
/// The host owns the palette: bonsplit renders whatever options the
/// `tabContextColorOptionsProvider` returns and reports the chosen hex back
/// through ``BonsplitDelegate/splitTabBar(_:didRequestTabColor:for:inPane:)``.
/// What a color *means* (priority, category, environment) is the host's
/// concern, not bonsplit's.
public struct TabColorOption: Identifiable, Equatable, Sendable {
    /// Palette entry name shown as the menu item title.
    public let name: String
    /// `#RRGGBB` or `#RRGGBBAA` hex applied to the tab when this entry is chosen.
    public let hex: String

    public var id: String { name }

    public init(name: String, hex: String) {
        self.name = name
        self.hex = hex
    }
}
