import Foundation
import SwiftUI

/// A host-chosen color that marks a tab, for example the account or
/// environment a terminal belongs to.
///
/// Bonsplit tints the tab's background with it and draws it as a strip along
/// the tab's top edge. A `nil` color leaves the tab unmarked.
public struct TabColor: Hashable, Sendable, Codable {
    /// Red component, 0...1.
    public let red: Double
    /// Green component, 0...1.
    public let green: Double
    /// Blue component, 0...1.
    public let blue: Double

    /// Creates a color from sRGB components, each clamped to 0...1.
    ///
    /// - Parameters:
    ///   - red: Red component.
    ///   - green: Green component.
    ///   - blue: Blue component.
    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Creates a color from `#RRGGBB` (the `#` is optional).
    ///
    /// - Parameter hex: Six hexadecimal digits, optionally prefixed with `#`.
    /// - Returns: `nil` unless `hex` is exactly six hex digits after the `#`.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// The color as `#RRGGBB`, upper-case.
    public var hexString: String {
        let components = [red, green, blue].map { Int(($0 * 255).rounded()) }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue)
    }
}
