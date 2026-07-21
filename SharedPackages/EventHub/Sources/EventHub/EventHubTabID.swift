import Foundation

/// Identifies a browser tab for EventHub's per-tab web-event dedup. `.empty` stands in for "no tab"
/// (used by native/aggregated events, which have no page/tab lifecycle to dedup against).
public struct EventHubTabID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public static func new() -> EventHubTabID { EventHubTabID() }

    public static let empty = EventHubTabID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
}
