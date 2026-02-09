import Foundation

/// Represents a tab's metadata (read-only snapshot for library consumers)
public struct Tab: Identifiable, Hashable, Sendable {
    public let id: TabID
    public let title: String
    public let icon: String?
    public let isDirty: Bool
    /// Whether the tab should show an "unread/activity" badge (library consumer-defined meaning).
    public let showsNotificationBadge: Bool

    public init(
        id: TabID = TabID(),
        title: String,
        icon: String? = nil,
        isDirty: Bool = false,
        showsNotificationBadge: Bool = false
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.isDirty = isDirty
        self.showsNotificationBadge = showsNotificationBadge
    }

    internal init(from tabItem: TabItem) {
        self.id = TabID(id: tabItem.id)
        self.title = tabItem.title
        self.icon = tabItem.icon
        self.isDirty = tabItem.isDirty
        self.showsNotificationBadge = tabItem.showsNotificationBadge
    }
}
