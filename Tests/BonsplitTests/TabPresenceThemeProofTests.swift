import XCTest
@testable import Bonsplit
import AppKit
import SwiftUI

/// Renders the presence accessory on a tab, and a replica of the host's pane
/// chip / grid border, for several themes. Opt-in: set
/// `BONSPLIT_THEME_PROOF_DIR` to write one PNG per theme for visual review.
@MainActor
final class TabPresenceThemeProofTests: XCTestCase {
    private static let themes: [(name: String, background: String, foreground: String)] = [
        ("light", "#ffffff", "#1d1d1f"),
        ("dark", "#282c34", "#ffffff"),
        ("solarized-light", "#fdf6e3", "#657b83"),
        ("solarized-dark", "#002b36", "#839496"),
        ("dracula", "#282a36", "#f8f8f2"),
        ("low-contrast-dark", "#1e1e1e", "#3a3a3a"),
        ("mid-grey", "#808080", "#ffffff"),
    ]

    func testRenderThemeProofs() throws {
        guard let directory = ProcessInfo.processInfo.environment["BONSPLIT_THEME_PROOF_DIR"] else {
            throw XCTSkip("Set BONSPLIT_THEME_PROOF_DIR to render theme proofs.")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for theme in Self.themes {
            for systemAppearance in [NSAppearance.Name.aqua, .darkAqua] {
                let view = ThemeProofView(background: theme.background, foreground: theme.foreground)
                    .environment(\.colorScheme, systemAppearance == .aqua ? .light : .dark)
                let host = NSHostingView(rootView: view)
                host.appearance = NSAppearance(named: systemAppearance)
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                host.layoutSubtreeIfNeeded()
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                let suffix = systemAppearance == .aqua ? "system-light" : "system-dark"
                try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("mac-\(theme.name)-\(suffix).png"))
            }
        }
    }
}

private struct ThemeProofView: View {
    let background: String
    let foreground: String

    private var appearance: BonsplitConfiguration.Appearance {
        BonsplitConfiguration.Appearance(chromeColors: .init(backgroundHex: background))
    }

    private var presence: TabPresence {
        TabPresence(
            participants: [
                .init(id: "user:u_maya", initials: "MO", isOwner: true, accessibilityName: "Maya"),
                .init(id: "device:iphone", initials: "", symbolName: "iphone", isOwner: false, accessibilityName: "iPhone"),
                .init(id: "user:u_li", initials: "LC", isOwner: false, accessibilityName: "Li"),
                .init(id: "user:u_a", initials: "A", isOwner: false, accessibilityName: "A"),
            ],
            sizeMode: .smallest,
            canDisconnectOthers: false,
            accessibilityLabel: "Size"
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tab(title: "Claude Code", selected: true)
                tab(title: "zsh", selected: false)
                Spacer(minLength: 0)
            }
            .frame(height: 30)
            .background(TabBarColors.barBackground(for: appearance))
            pane
        }
        .frame(width: 420)
    }

    private func tab(title: String, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(selected
                    ? TabBarColors.activeText(for: appearance)
                    : TabBarColors.inactiveText(for: appearance))
            TabPresenceAccessoryView(
                presence: presence,
                colors: TabBarColors.presenceColors(for: appearance, isSelected: selected),
                isHovered: false,
                hoverBackground: .clear
            )
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background(selected ? TabBarColors.activeTabBackground(for: appearance) : .clear)
    }

    /// The host's default chrome border for this background, as cmux's
    /// `WindowChromeColorResolver.separatorColor(forChromeBackground:)`
    /// resolves it; the split divider falls back to it.
    private var hostBorderHex: String {
        let rgb = BonsplitContrastPalette.RGB(hex: background)!
        let isLight = 0.299 * rgb.red + 0.587 * rgb.green + 0.114 * rgb.blue > 0.5
        let amount = isLight ? -0.30 : 0.16
        let alpha = isLight ? 0.26 : 0.36
        func byte(_ value: Double) -> String { String(format: "%02x", Int((min(1, max(0, value)) * 255).rounded())) }
        return "#" + byte(rgb.red + amount) + byte(rgb.green + amount) + byte(rgb.blue + amount) + byte(alpha)
    }

    /// Mirrors the host's `TerminalSizeBoundsOverlayView` next to a split
    /// divider: border on the open sides and the chip outline in the
    /// divider's color, a fainter hatch with no fill, chip text 4.5:1.
    private var pane: some View {
        var dividerAppearance = appearance
        dividerAppearance.chromeColors.borderHex = hostBorderHex
        let divider: NSColor = dividerAppearance.splitDividerColor
        let background = BonsplitContrastPalette.RGB(hex: self.background)!
        let terminalBackground = NSColor(srgbRed: background.red, green: background.green, blue: background.blue, alpha: 1)
        let palette = BonsplitSizingChromePalette(
            background: background,
            foreground: BonsplitContrastPalette.RGB(hex: foreground)!,
            line: BonsplitContrastPalette.rgb(divider, over: terminalBackground)
        )
        return Canvas { context, size in
            Self.drawPane(in: &context, size: size, palette: palette, foreground: foreground, divider: divider)
        }
        .frame(height: 130)
    }

    private static func color(_ rgb: BonsplitContrastPalette.RGB) -> Color {
        Color(nsColor: NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1))
    }

    private static func drawPane(
        in context: inout GraphicsContext,
        size: CGSize,
        palette: BonsplitSizingChromePalette,
        foreground: String,
        divider: NSColor
    ) {
        let text: Color = color(BonsplitContrastPalette.RGB(hex: foreground)!)
        let neighborWidth: CGFloat = 100
        let grid = CGRect(x: neighborWidth + 1, y: 0, width: 220, height: 90)
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(color(palette.background)))
        // The neighbouring split pane and the divider between them.
        let prompt = Text("$ ls").font(.system(size: 11, design: .monospaced)).foregroundColor(text)
        context.draw(prompt, at: CGPoint(x: 8, y: 12), anchor: .leading)
        let dividerRect = CGRect(x: neighborWidth, y: 0, width: 1, height: size.height)
        context.fill(Path(dividerRect), with: .color(Color(nsColor: divider)))
        let paneRect = CGRect(x: neighborWidth + 1, y: 0, width: size.width - neighborWidth - 1, height: size.height)
        var hatch = Path()
        var x = -size.height
        while x < size.width {
            hatch.move(to: CGPoint(x: x, y: size.height))
            hatch.addLine(to: CGPoint(x: x + size.height, y: 0))
            x += 8
        }
        var outside = Path(paneRect)
        outside.addRect(grid)
        let hatchColor: Color = color(palette.hatch)
        context.drawLayer { layer in
            layer.clip(to: outside, style: FillStyle(eoFill: true))
            layer.stroke(hatch, with: .color(hatchColor), lineWidth: 0.5)
        }
        let lines = ["$ claude", "> Refactor the sizing palette", "  Reading 4 files…"]
        for (index, line) in lines.enumerated() {
            let row = Text(line).font(.system(size: 11, design: .monospaced)).foregroundColor(text)
            context.draw(row, at: CGPoint(x: grid.minX + 8, y: 12 + CGFloat(index) * 16), anchor: .leading)
        }
        var border = Path()
        border.move(to: CGPoint(x: grid.maxX - 0.5, y: 0))
        border.addLine(to: CGPoint(x: grid.maxX - 0.5, y: grid.maxY - 0.5))
        border.addLine(to: CGPoint(x: grid.minX, y: grid.maxY - 0.5))
        let lineColor: Color = color(palette.line)
        context.stroke(border, with: .color(lineColor), lineWidth: 1)
        let label = Text("118×38 · Maya's Mac").font(.system(size: 11).monospacedDigit()).foregroundColor(color(palette.text))
        let chipText = context.resolve(label)
        let textSize = chipText.measure(in: size)
        let chip = CGRect(x: grid.maxX - textSize.width - 12, y: grid.maxY + 4, width: textSize.width + 12, height: textSize.height + 6)
        let chipPath = Path(roundedRect: chip.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4)
        context.fill(chipPath, with: .color(color(palette.chipFill)))
        context.stroke(chipPath, with: .color(lineColor), lineWidth: 1)
        context.draw(chipText, at: CGPoint(x: chip.midX, y: chip.midY))
    }
}
