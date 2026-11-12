import SwiftUI

/// The shared-terminal presence accessory drawn after a tab title: up to
/// three avatars side by side (initials for other people, a device glyph for
/// the viewer's own other devices), a thin ring on the owner, and `+N` for the
/// rest. Neutral colors derived from the tab surface and the tab bar's text
/// color (``TabBarColors/presenceColors(for:isSelected:)``), with 4.5:1
/// glyphs and 3:1 rings on any theme. No per-participant colors.
struct TabPresenceAccessoryView: View {
    let presence: TabPresence
    let colors: TabBarColors.PresenceColors
    let isHovered: Bool
    let hoverBackground: Color

    static let maxAvatars = 3
    static let avatarSize: CGFloat = 14
    static let horizontalPadding: CGFloat = 3
    /// Gap between avatars. Two 7 pt initials are about 10.5 pt wide in a
    /// 14 pt circle, so any overlap clips the next avatar's first letter.
    private static let avatarSpacing: CGFloat = 2
    private static let ringWidth: CGFloat = 1

    var body: some View {
        let shown = Array(presence.participants.prefix(Self.maxAvatars))
        let extra = presence.participants.count - shown.count
        HStack(spacing: Self.avatarSpacing) {
            ForEach(shown) { participant in
                avatar(participant)
            }
            if extra > 0 {
                Text(verbatim: "+\(extra)")
                    .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(nsColor: colors.text))
                    .padding(.leading, 1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, 1)
        .background(
            Capsule(style: .continuous)
                .fill(isHovered ? hoverBackground : .clear)
        )
        .contentShape(Capsule(style: .continuous))
    }

    private func avatar(_ participant: TabPresence.Participant) -> some View {
        ZStack {
            Circle().fill(Color(nsColor: colors.fill))
            if let symbolName = participant.symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(Color(nsColor: colors.glyph))
            } else {
                Text(verbatim: participant.initials)
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(Color(nsColor: colors.glyph))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .overlay(Circle().stroke(Color(nsColor: colors.surface), lineWidth: 1))
        .overlay {
            if participant.isOwner {
                Circle()
                    .inset(by: -(Self.ringWidth + 0.5))
                    .stroke(Color(nsColor: colors.line), lineWidth: Self.ringWidth)
            }
        }
        .padding(participant.isOwner ? Self.ringWidth + 0.5 : 0)
    }
}

/// Where the title row reserved space for the presence accessory.
struct TabPresenceAccessoryBoundsKey: PreferenceKey {
    static let defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}
