import Foundation
import Testing
@testable import EventHub

@Suite("EventHub native ingress")
struct EventHubNativeIngressTests {
    static let pixel1 = "webTelemetry_testPixel1"

    static let immediateConfig = """
    { "telemetry": { "webEvent_impression": {
        "state": "enabled",
        "trigger": { "type": "immediate", "source": "impression" },
        "parameters": {}
    } } }
    """

    static let immediateDataConfig = """
    { "telemetry": { "webEvent_login": {
        "state": "enabled",
        "trigger": { "type": "immediate", "source": "login" },
        "parameters": { "loginState": { "template": "data", "dataKey": "loginState" } }
    } } }
    """

    static let periodConfig = """
    { "telemetry": { "webTelemetry_testPixel1": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 86400 } },
        "parameters": { "count": { "template": "counter", "source": "test", "buckets": {
            "0":     {"gte": 0,  "lt": 1},
            "1-2":   {"gte": 1,  "lt": 3},
            "3-5":   {"gte": 3,  "lt": 6},
            "6-10":  {"gte": 6,  "lt": 11},
            "11-20": {"gte": 11, "lt": 21},
            "21-39": {"gte": 21, "lt": 40},
            "40+":   {"gte": 40}
        } } }
    } } }
    """

    // One immediate pixel and one period counter sharing the same source ("test"), so each native
    // method can be shown to drive only its own trigger type.
    static let bothConfig = """
    { "telemetry": {
        "imm": { "state": "enabled", "trigger": { "type": "immediate", "source": "test" }, "parameters": {} },
        "per": { "state": "enabled", "trigger": { "period": { "seconds": 86400 } },
            "parameters": { "count": { "template": "counter", "source": "test", "buckets": { "0": {"gte": 0, "lt": 1}, "1+": {"gte": 1} } } } }
    } }
    """

    static let periodDataConfig = """
    { "telemetry": { "yt": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 60 } },
        "parameters": {
            "count": { "template": "counter", "source": "yt", "buckets": {"0-9": {"gte": 0, "lt": 10}, "10+": {"gte": 10}} },
            "loginState": { "template": "data", "source": "yt", "dataKey": "loginState" }
        }
    } } }
    """

    /// A payload whose encoding throws, to exercise the serialisation fail-safe.
    private struct ThrowingData: Encodable {
        func encode(to encoder: Encoder) throws {
            throw NSError(domain: "EventHubNativeIngressTests", code: -1)
        }
    }

    // MARK: handleImmediateEvent

    @Test("handleImmediateEvent fires the matching immediate pixel")
    func handleImmediateEventFiresMatchingImmediatePixel() {
        let f = EventHubManagerFixture.active(Self.immediateConfig)
        f.manager.handleImmediateEvent("impression")
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.name == "webEvent_impression_windows")
    }

    @Test("handleImmediateEvent forwards the data object to data-template params")
    func handleImmediateEventForwardsDataObject() {
        struct LoginPayload: Encodable { let loginState: String }
        let f = EventHubManagerFixture.active(Self.immediateDataConfig)
        f.manager.handleImmediateEvent("login", data: LoginPayload(loginState: "logged-in"))
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["loginState"] == "%22logged-in%22")
    }

    @Test("handleImmediateEvent does not count toward a period counter of the same source")
    func handleImmediateEventDoesNotCountPeriodCounter() {
        let f = EventHubManagerFixture.active(Self.bothConfig)
        f.manager.handleImmediateEvent("test")
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.name == "imm_windows")
        #expect(f.count(of: "per") == 0)
    }

    @Test("handleImmediateEvent fires nothing when the feature is disabled")
    func handleImmediateEventFiresNothingWhenDisabled() {
        let f = EventHubManagerFixture.active(Self.immediateConfig, enabled: false)
        f.manager.handleImmediateEvent("impression")
        #expect(f.fired.isEmpty)
    }

    @Test("handleImmediateEvent fires nothing for an unknown or empty type", arguments: ["unknown", ""])
    func handleImmediateEventFiresNothingForUnknownOrEmptyType(type: String) {
        let f = EventHubManagerFixture.active(Self.immediateConfig)
        f.manager.handleImmediateEvent(type)
        #expect(f.fired.isEmpty)
    }

    @Test("handleImmediateEvent ignores unserialisable data and still fires")
    func handleImmediateEventIgnoresUnserialisableDataAndStillFires() {
        let f = EventHubManagerFixture.active(Self.immediateConfig)
        // The payload's encode(to:) throws; the fail-safe path drops the data and a parameter-less
        // immediate pixel still fires rather than the whole call aborting.
        f.manager.handleImmediateEvent("impression", data: ThrowingData())
        #expect(f.fired.count == 1)
    }

    // MARK: handleAggregatedEvent

    @Test("handleAggregatedEvent increments the matching counter")
    func handleAggregatedEventIncrementsMatchingCounter() {
        let f = EventHubManagerFixture.active(Self.periodConfig)
        f.manager.handleAggregatedEvent("test")
        #expect(f.count(of: Self.pixel1) == 1)
    }

    @Test("handleAggregatedEvent counts every call with no per-tab dedup")
    func handleAggregatedEventCountsEveryCallNoDedup() {
        let f = EventHubManagerFixture.active(Self.periodConfig)
        // The differentiator from the web path: three identical native events (no tab) count three
        // times, whereas three same-tab web events on one page would dedup to one.
        f.manager.handleAggregatedEvent("test")
        f.manager.handleAggregatedEvent("test")
        f.manager.handleAggregatedEvent("test")
        #expect(f.count(of: Self.pixel1) == 3)
    }

    @Test("handleAggregatedEvent stops at the open-ended bucket")
    func handleAggregatedEventStopsAtOpenEndedBucket() throws {
        let f = EventHubManagerFixture.active(Self.periodConfig)
        for _ in 0..<41 {
            f.manager.handleAggregatedEvent("test")
        }
        let state = try #require(f.state(of: Self.pixel1))
        #expect(state.params["count"]?.stopCounting == true)
        #expect(state.params["count"]?.value == 40)
    }

    @Test("handleAggregatedEvent records the last data value from a matching source")
    func handleAggregatedEventRecordsLastDataValue() {
        struct LoginPayload: Encodable { let loginState: String }
        let f = EventHubManagerFixture.active(Self.periodDataConfig)
        f.manager.handleAggregatedEvent("yt", data: LoginPayload(loginState: "a"))
        f.manager.handleAggregatedEvent("yt", data: LoginPayload(loginState: "b"))
        f.advance(by: 60)
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["loginState"] == "%22b%22")
    }

    @Test("handleAggregatedEvent does not fire an immediate pixel of the same source")
    func handleAggregatedEventDoesNotFireImmediatePixel() {
        let f = EventHubManagerFixture.active(Self.bothConfig)
        f.manager.handleAggregatedEvent("test")
        #expect(f.fired.isEmpty)
        #expect(f.count(of: "per") == 1)
    }

    @Test("handleAggregatedEvent counts nothing when the feature is disabled")
    func handleAggregatedEventCountsNothingWhenDisabled() {
        let f = EventHubManagerFixture.active(Self.periodConfig, enabled: false)
        f.manager.handleAggregatedEvent("test")
        #expect(f.state(of: Self.pixel1) == nil)
    }

    @Test("handleAggregatedEvent counts nothing for an unknown or empty type", arguments: ["unknown", ""])
    func handleAggregatedEventCountsNothingForUnknownOrEmptyType(type: String) {
        let f = EventHubManagerFixture.active(Self.periodConfig)
        f.manager.handleAggregatedEvent(type)
        #expect(f.count(of: Self.pixel1) == 0)
    }
}
