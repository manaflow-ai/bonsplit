import Foundation

/// Represents a tab's metadata (read-only snapshot for library consumers)
public struct Tab: Identifiable, Hashable, Sendable {
    public let id: TabID
    public let title: String
    public let icon: String?
    /// Optional image data (PNG recommended) for the tab icon. When present, this takes precedence over `icon`.
    public let iconImageData: Data?
    public let isDirty: Bool
    /// Whether the tab should show an "unread/activity" badge (library consumer-defined meaning).
    public let showsNotificationBadge: Bool
    /// Whether the tab should show an activity/loading indicator (e.g. spinning icon).
    public let isLoading: Bool

    public init(
        id: TabID = TabID(),
        title: String,
        icon: String? = nil,
        iconImageData: Data? = nil,
        isDirty: Bool = false,
        showsNotificationBadge: Bool = false,
        isLoading: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.iconImageData = iconImageData
        self.isDirty = isDirty
        self.showsNotificationBadge = showsNotificationBadge
        self.isLoading = isLoading
    }

    internal init(from tabItem: TabItem) {
        self.id = TabID(id: tabItem.id)
        self.title = tabItem.title
        self.icon = tabItem.icon
        self.iconImageData = tabItem.iconImageData
        self.isDirty = tabItem.isDirty
        self.showsNotificationBadge = tabItem.showsNotificationBadge
        self.isLoading = tabItem.isLoading
    }
}
