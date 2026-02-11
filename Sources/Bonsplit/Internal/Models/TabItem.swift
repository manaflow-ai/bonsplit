import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Custom UTTypes for tab drag and drop
extension UTType {
    static var tabItem: UTType {
        UTType(exportedAs: "com.splittabbar.tabitem")
    }

    static var tabTransfer: UTType {
        UTType(exportedAs: "com.splittabbar.tabtransfer")
    }
}

/// Represents a single tab in a pane's tab bar (internal representation)
struct TabItem: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var icon: String?
    var iconImageData: Data?
    var isDirty: Bool
    var showsNotificationBadge: Bool
    var isLoading: Bool

    init(
        id: UUID = UUID(),
        title: String,
        icon: String? = "doc.text",
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

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: TabItem, rhs: TabItem) -> Bool {
        lhs.id == rhs.id
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case icon
        case iconImageData
        case isDirty
        case showsNotificationBadge
        case isLoading
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.icon = try c.decodeIfPresent(String.self, forKey: .icon)
        self.iconImageData = try c.decodeIfPresent(Data.self, forKey: .iconImageData)
        self.isDirty = try c.decodeIfPresent(Bool.self, forKey: .isDirty) ?? false
        self.showsNotificationBadge = try c.decodeIfPresent(Bool.self, forKey: .showsNotificationBadge) ?? false
        self.isLoading = try c.decodeIfPresent(Bool.self, forKey: .isLoading) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(iconImageData, forKey: .iconImageData)
        try c.encode(isDirty, forKey: .isDirty)
        try c.encode(showsNotificationBadge, forKey: .showsNotificationBadge)
        try c.encode(isLoading, forKey: .isLoading)
    }
}

// MARK: - Transferable for Drag & Drop

extension TabItem: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tabItem)
    }
}

/// Transfer data that includes source pane information for cross-pane moves
struct TabTransferData: Codable, Transferable {
    let tab: TabItem
    let sourcePaneId: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tabTransfer)
    }
}
