import AppKit
import Foundation
import SwiftUI

enum TabAppearanceColor {
    private static let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")

    static func nsColor(hex value: String) -> NSColor? {
        var hex = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6 || hex.count == 8 else { return nil }
        guard hex.unicodeScalars.allSatisfy({ hexDigits.contains($0) }) else { return nil }
        guard let rgba = UInt64(hex, radix: 16) else { return nil }

        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
        if hex.count == 8 {
            red = CGFloat((rgba & 0xFF000000) >> 24) / 255.0
            green = CGFloat((rgba & 0x00FF0000) >> 16) / 255.0
            blue = CGFloat((rgba & 0x0000FF00) >> 8) / 255.0
            alpha = CGFloat(rgba & 0x000000FF) / 255.0
        } else {
            red = CGFloat((rgba & 0xFF0000) >> 16) / 255.0
            green = CGFloat((rgba & 0x00FF00) >> 8) / 255.0
            blue = CGFloat(rgba & 0x0000FF) / 255.0
            alpha = 1.0
        }
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    static func color(hex value: String?) -> Color? {
        guard let value, let color = nsColor(hex: value) else { return nil }
        return Color(nsColor: color)
    }

    static func hex(from color: Color) -> String? {
        hex(from: NSColor(color))
    }

    static func hex(from color: NSColor) -> String? {
        guard let color = color.usingColorSpace(.sRGB) else { return nil }
        let red = byte(from: color.redComponent)
        let green = byte(from: color.greenComponent)
        let blue = byte(from: color.blueComponent)
        let alpha = byte(from: color.alphaComponent)

        if alpha == 255 {
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
        return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
    }

    private static func byte(from component: CGFloat) -> Int {
        Int((min(max(component, 0), 1) * 255).rounded())
    }
}
