import Foundation
import WebKit
import UserScript

/// Routes inbound content-scope-scripts `webEvent` messages to `EventHubManaging`: extracts the
/// event payload (`{ type, data }`) and forwards only events whose `type` is present and non-empty.
/// The originating tab is supplied by the caller (the wiring layer, out of scope here) rather than
/// read from the message itself.
public final class WebEventsHandler: Subfeature {
    public let featureName = "webEvents"
    public let messageOriginPolicy: MessageOriginPolicy = .all
    public var broker: UserScriptMessageBroker?

    private let manager: EventHubManaging
    private let tabIDProvider: (WKScriptMessage) -> EventHubTabID

    public init(manager: EventHubManaging, tabIDProvider: @escaping (WKScriptMessage) -> EventHubTabID) {
        self.manager = manager
        self.tabIDProvider = tabIDProvider
    }

    public func handler(forMethodNamed methodName: String) -> Handler? {
        guard methodName == "webEvent" else { return nil }
        return { [weak self] params, original in
            guard let self,
                  let dict = params as? [String: Any],
                  let type = dict["type"] as? String, !type.isEmpty else {
                return nil
            }
            self.manager.handleWebEvent(dict, tabID: self.tabIDProvider(original))
            return nil
        }
    }
}
