import Foundation

/// Who is viewing a shared terminal tab and what size its grid has.
///
/// The host app fills this from its terminal sizing state. Bonsplit renders the
/// participants as an avatar accessory after the tab title and adds the
/// terminal-size section to the tab context menu. A `nil` presence hides both.
public struct TabPresence: Hashable, Sendable, Codable {
    /// One other person, or one of the viewer's own other devices, shown in
    /// the tab's avatar stack. Avatars are neutral grey; the owner gets a ring.
    public struct Participant: Hashable, Sendable, Codable, Identifiable {
        /// Host-scoped id of the person or device group.
        public var id: String
        /// One or two letters drawn inside the avatar when `symbolName` is nil.
        public var initials: String
        /// SF Symbol drawn instead of initials, e.g. `iphone` for the viewer's own phone.
        public var symbolName: String?
        /// Whether this participant sets the terminal size (drawn with a ring).
        public var isOwner: Bool
        /// Name read by VoiceOver and shown in help text.
        public var accessibilityName: String

        /// Creates a participant row.
        ///
        /// - Parameters:
        ///   - id: Host-scoped id.
        ///   - initials: Letters drawn inside the avatar.
        ///   - symbolName: SF Symbol drawn instead of the initials, if any.
        ///   - isOwner: Whether this participant sets the terminal size.
        ///   - accessibilityName: Spoken name.
        public init(id: String, initials: String, symbolName: String? = nil, isOwner: Bool, accessibilityName: String) {
            self.id = id
            self.initials = initials
            self.symbolName = symbolName
            self.isOwner = isOwner
            self.accessibilityName = accessibilityName
        }
    }

    /// How the host picks the terminal grid. Mirrors the host's sizing modes.
    public enum SizeMode: String, Hashable, Sendable, Codable, CaseIterable {
        /// The participant with the newest input sets the size.
        case latest
        /// Component-wise minimum over counting participants.
        case smallest
        /// Component-wise maximum over counting participants.
        case largest
        /// The first attached participant in a priority list sets the size.
        case priority
        /// One fixed grid regardless of who is attached.
        case fixed
    }

    /// Other attached people and devices (never the viewer), owner first. Empty hides the tab accessory
    /// while keeping the terminal-size context menu section.
    public var participants: [Participant]
    /// The current sizing mode, checked in the context menu.
    public var sizeMode: SizeMode
    /// Whether "Disconnect Others…" appears in the context menu.
    public var canDisconnectOthers: Bool
    /// Label and tooltip for the accessory, e.g. `Size set by Maya's Mac · 118×38`.
    public var accessibilityLabel: String

    /// Whether the tab draws the avatar accessory.
    public var showsAccessory: Bool { !participants.isEmpty }

    /// Creates a presence snapshot.
    ///
    /// - Parameters:
    ///   - participants: Other people and devices, owner first; empty hides the accessory.
    ///   - sizeMode: Current sizing mode.
    ///   - canDisconnectOthers: Whether other clients can be disconnected.
    ///   - accessibilityLabel: Accessory label and tooltip.
    public init(
        participants: [Participant],
        sizeMode: SizeMode,
        canDisconnectOthers: Bool,
        accessibilityLabel: String
    ) {
        self.participants = participants
        self.sizeMode = sizeMode
        self.canDisconnectOthers = canDisconnectOthers
        self.accessibilityLabel = accessibilityLabel
    }
}
