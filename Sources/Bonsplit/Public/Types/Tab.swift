import Foundation

/// Represents a tab's metadata (read-only snapshot for library consumers)
public struct Tab: Identifiable, Hashable, Sendable {
    public let id: TabID
    public let title: String
    public let hasCustomTitle: Bool
    public let icon: String?
    /// Optional image data (PNG recommended) for the tab icon. When present, this takes precedence over `icon`.
    public let iconImageData: Data?
    /// Optional asset-catalog image name for the tab icon. Resolved in the host app bundle.
    public let iconAsset: String?
    /// Consumer-defined tab kind identifier (for example, "terminal" or "browser").
    public let kind: String?
    public let isDirty: Bool
    /// Whether the tab should show an "unread/activity" badge (library consumer-defined meaning).
    public let showsNotificationBadge: Bool
    /// Whether the tab should show an activity/loading indicator (e.g. spinning icon).
    public let isLoading: Bool
    /// Whether the tab should show browser audio as muted.
    public let isAudioMuted: Bool
    /// Whether the tab is actively producing audible audio (for example, a
    /// browser page playing sound). Drives a click-to-mute speaker affordance.
    public let isAudioPlaying: Bool
    /// Whether the tab is pinned in its pane.
    public let isPinned: Bool
    /// Optional `#RRGGBB` color rendered as a leading tab marker.
    public let customColor: String?
    /// Whether the tab should show a remote-connection indicator (library consumer-defined meaning, e.g. SSH).
    public let showsRemoteIndicator: Bool

    public init(
        id: TabID = TabID(),
        title: String,
        hasCustomTitle: Bool = false,
        icon: String? = nil,
        iconImageData: Data? = nil,
        iconAsset: String? = nil,
        kind: String? = nil,
        isDirty: Bool = false,
        showsNotificationBadge: Bool = false,
        isLoading: Bool = false,
        isAudioMuted: Bool = false,
        isAudioPlaying: Bool = false,
        isPinned: Bool = false,
        customColor: String? = nil,
        showsRemoteIndicator: Bool = false
    ) {
        self.id = id
        self.title = title
        self.hasCustomTitle = hasCustomTitle
        self.icon = icon
        self.iconImageData = iconImageData
        self.iconAsset = iconAsset
        self.kind = kind
        self.isDirty = isDirty
        self.showsNotificationBadge = showsNotificationBadge
        self.isLoading = isLoading
        self.isAudioMuted = isAudioMuted
        self.isAudioPlaying = isAudioPlaying
        self.isPinned = isPinned
        self.customColor = customColor
        self.showsRemoteIndicator = showsRemoteIndicator
    }

    internal init(from tabItem: TabItem) {
        self.id = TabID(id: tabItem.id)
        self.title = tabItem.title
        self.hasCustomTitle = tabItem.hasCustomTitle
        self.icon = tabItem.icon
        self.iconImageData = tabItem.iconImageData
        self.iconAsset = tabItem.iconAsset
        self.kind = tabItem.kind
        self.isDirty = tabItem.isDirty
        self.showsNotificationBadge = tabItem.showsNotificationBadge
        self.isLoading = tabItem.isLoading
        self.isAudioMuted = tabItem.isAudioMuted
        self.isAudioPlaying = tabItem.isAudioPlaying
        self.isPinned = tabItem.isPinned
        self.customColor = tabItem.customColor
        self.showsRemoteIndicator = tabItem.showsRemoteIndicator
    }
}
