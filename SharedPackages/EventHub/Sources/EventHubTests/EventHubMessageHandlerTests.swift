import Testing
import Foundation
import WebKit
import Combine
@testable import EventHub

@Suite("WebEventsHandler")
struct WebEventsHandlerTests {
    private final class SpyManager: EventHubManaging {
        var handledWebEvents: [(data: [String: Any], tabID: EventHubTabID)] = []
        var firedPixelsPublisher: AnyPublisher<FiredPixel, Never> { Empty().eraseToAnyPublisher() }
        func handleWebEvent(_ webEventData: [String: Any], tabID: EventHubTabID) {
            handledWebEvents.append((webEventData, tabID))
        }
        func handleImmediateEvent(_ type: String, data: Encodable?) {}
        func handleAggregatedEvent(_ type: String, data: Encodable?) {}
        func onNavigationStarted(tabID: EventHubTabID, url: String) {}
        func onTabClosed(tabID: EventHubTabID) {}
        func onConfigChanged() {}
        func isEnabled() -> Bool { true }
        func onAppForegrounded() {}
        func onAppBackgrounded() {}
    }

    @Test("featureName targets webEvents")
    func featureNameTargetsWebEvents() {
        let handler = WebEventsHandler(manager: SpyManager(), tabIDProvider: { _ in .new() })
        #expect(handler.featureName == "webEvents")
    }

    @Test("handler forwards an event with a type to the manager")
    func handlerForwardsEventWithTypeToManager() async throws {
        let manager = SpyManager()
        let tab = EventHubTabID.new()
        let handler = WebEventsHandler(manager: manager, tabIDProvider: { _ in tab })

        let notify = try #require(handler.handler(forMethodNamed: "webEvent"))
        _ = try await notify(["type": "click", "data": [String: Any]()], WKScriptMessage())

        #expect(manager.handledWebEvents.count == 1)
        #expect(manager.handledWebEvents.first?.data["type"] as? String == "click")
        #expect(manager.handledWebEvents.first?.tabID == tab)
    }

    @Test("handler does not forward when type is missing or empty", arguments: [
        ["data": [String: Any]()],
        ["type": "", "data": [String: Any]()],
    ] as [[String: Any]])
    func handlerDoesNotForwardWhenTypeMissingOrEmpty(params: [String: Any]) async throws {
        let manager = SpyManager()
        let handler = WebEventsHandler(manager: manager, tabIDProvider: { _ in .new() })

        let notify = try #require(handler.handler(forMethodNamed: "webEvent"))
        _ = try await notify(params, WKScriptMessage())

        #expect(manager.handledWebEvents.isEmpty)
    }
}
