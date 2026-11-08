import AppKit
import SwiftUI

/// Draws a ``TabStatusIndicator`` in a tab, pulsing unless Reduce Motion is on.
struct TabStatusIndicatorView: View {
    let indicator: TabStatusIndicator
    let fallbackColor: Color
    let fontSize: CGFloat
    @State private var dimmed = false

    private var shouldPulse: Bool {
        indicator.pulses && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        glyph
            .foregroundStyle(indicator.color ?? fallbackColor)
            .opacity(shouldPulse && dimmed ? 0.3 : 1)
            .animation(
                shouldPulse ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true) : nil,
                value: dimmed
            )
            .onAppear { dimmed = shouldPulse }
            .onChange(of: shouldPulse) { dimmed = $0 }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var glyph: some View {
        if let symbolName = indicator.symbolName {
            Image(systemName: symbolName)
                .font(.system(size: fontSize, weight: .semibold))
        } else {
            Circle().frame(width: TabBarMetrics.statusDotSize, height: TabBarMetrics.statusDotSize)
        }
    }
}
