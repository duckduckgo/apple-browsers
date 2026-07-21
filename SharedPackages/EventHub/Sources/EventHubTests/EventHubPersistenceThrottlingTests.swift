import Testing
@testable import EventHub

@Suite("EventHub persistence throttling")
struct EventHubPersistenceThrottlingTests {
    static let burstSize = 5000

    // High buckets so the burst never hits the open-ended bucket / stop-counting (we want an exact count).
    static let burstConfig = """
    { "telemetry": { "burst": {
        "state": "enabled",
        "trigger": { "period": { "seconds": 3600 } },
        "parameters": { "count": { "template": "counter", "source": "e", "buckets": {
            "0-19999": {"gte": 0, "lt": 20000}, "20000+": {"gte": 20000}
        } } }
    } } }
    """

    @Test("burst counts every event without loss")
    func burstCountsEveryEventWithoutLoss() {
        let f = EventHubManagerFixture.active(Self.burstConfig)
        for _ in 0..<Self.burstSize {
            f.manager.handleWebEvent(EventHubManagerFixture.webEvent("e"), tabID: .new())
        }
        #expect(f.count(of: "burst") == Self.burstSize)
    }

    @Test("burst coalesces persistence writes")
    func burstCoalescesPersistenceWrites() {
        let f = EventHubManagerFixture.active(Self.burstConfig)
        let baseline = f.store.setCallCount

        for _ in 0..<Self.burstSize {
            f.manager.handleWebEvent(EventHubManagerFixture.webEvent("e"), tabID: .new())
        }

        // Counting is synchronous but persistence is deferred, so advance time to actually run the
        // write-behind flush — otherwise this would assert against zero writes trivially.
        f.advance(by: EventHubManagerFixture.writeBehindFlush)

        // Writes must be coalesced — far fewer than one per event (a per-event write would be ~burstSize).
        #expect(f.store.setCallCount - baseline < 50)
    }

    @Test("burst count survives a restart")
    func burstCountSurvivesRestart() {
        let f = EventHubManagerFixture.active(Self.burstConfig)
        for _ in 0..<Self.burstSize {
            f.manager.handleWebEvent(EventHubManagerFixture.webEvent("e"), tabID: .new())
        }

        let restarted = f.restart()

        #expect(restarted.count(of: "burst") == Self.burstSize)
    }
}
