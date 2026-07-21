import Foundation
import WebKit
import UserScript

/// Routes inbound content-scope-scripts `webEvent` messages to `EventHubPixelManaging`: extracts the
/// event payload (`{ type, data }`) and forwards only events whose `type` is present and non-empty.
/// The originating tab is supplied by the caller (the wiring layer, out of scope here) rather than
/// read from the message itself.
public final class EventHubMessageHandler: Subfeature {
    public let featureName = "webEvents"
    public let messageOriginPolicy: MessageOriginPolicy = .all
    public var broker: UserScriptMessageBroker?

    private let manager: EventHubPixelManaging
    private let tabIDProvider: (WKScriptMessage) -> EventHubTabID

    public init(manager: EventHubPixelManaging, tabIDProvider: @escaping (WKScriptMessage) -> EventHubTabID) {
        self.manager = manager
        self.tabIDProvider = tabIDProvider
    }

    /// Stub: always returns `nil` (no method is handled). `EventHubMessageHandlerTests` is expected to
    /// fail until a follow-up implementation task fills this in.
    public func handler(forMethodNamed methodName: String) -> Handler? {
        nil
    }
}
