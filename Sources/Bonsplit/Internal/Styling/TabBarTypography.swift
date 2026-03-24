import SwiftUI
import AppKit

enum TabBarTypography {
    static func titleFont(for appearance: BonsplitConfiguration.Appearance) -> Font {
        Font(resolvedTitleNSFont(for: appearance))
    }

    static func resolvedTitleNSFont(for appearance: BonsplitConfiguration.Appearance) -> NSFont {
        let scaledSize = max(0.5, appearance.tabTitleFontScale) * TabBarMetrics.titleFontSize
        return resolvedFont(
            family: appearance.tabTitleFontFamily,
            size: scaledSize,
            weight: .regular
        ) ?? NSFont.systemFont(ofSize: scaledSize)
    }

    private static func resolvedFont(
        family rawValue: String?,
        size: CGFloat,
        weight: NSFont.Weight
    ) -> NSFont? {
        guard let fontName = resolvedPostScriptFontName(family: rawValue, size: size, weight: weight) else {
            return nil
        }
        return NSFont(name: fontName, size: size)
    }

    private static func resolvedPostScriptFontName(
        family rawValue: String?,
        size: CGFloat,
        weight: NSFont.Weight
    ) -> String? {
        guard let family = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !family.isEmpty else {
            return nil
        }

        if let font = NSFontManager.shared.font(
            withFamily: family,
            traits: [],
            weight: fontManagerWeight(for: weight),
            size: size
        ), fontMatchesRequestedFamily(font, family: family) {
            return font.fontName
        }

        let systemDescriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor
        let familyDescriptor = systemDescriptor.withFamily(family)
        if let font = NSFont(descriptor: familyDescriptor, size: size),
           fontMatchesRequestedFamily(font, family: family) {
            return font.fontName
        }
        if let font = NSFont(name: family, size: size),
           fontMatchesRequestedFamily(font, family: family) || font.fontName.caseInsensitiveCompare(family) == .orderedSame {
            return font.fontName
        }
        return nil
    }

    private static func fontMatchesRequestedFamily(_ font: NSFont, family: String) -> Bool {
        let requestedFamily = family.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !requestedFamily.isEmpty else { return false }
        guard let actualFamily = font.familyName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !actualFamily.isEmpty else {
            return false
        }
        return actualFamily.caseInsensitiveCompare(requestedFamily) == .orderedSame
    }

    private static func fontManagerWeight(for weight: NSFont.Weight) -> Int {
        switch weight {
        case .ultraLight:
            return 2
        case .thin:
            return 3
        case .light:
            return 4
        case .regular:
            return 5
        case .medium:
            return 6
        case .semibold:
            return 8
        case .bold:
            return 9
        case .heavy:
            return 11
        case .black:
            return 13
        default:
            return 5
        }
    }
}
