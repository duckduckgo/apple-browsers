import Testing
@testable import EventHub

@Suite("EventHub immediate pixels")
struct EventHubImmediatePixelTests {
    static let immediateConfig = """
    { "telemetry": { "webEvent_impression": {
        "state": "enabled",
        "trigger": { "type": "immediate", "source": "impression" },
        "parameters": {}
    } } }
    """

    @Test("immediate trigger fires one pixel per event")
    func immediateTriggerFiresOnePixelPerEvent() {
        let f = EventHubManagerFixture.active(Self.immediateConfig)
        f.manager.handleWebEvent(EventHubManagerFixture.webEvent("impression"), tabID: .new())
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.name == "webEvent_impression_windows")
    }

    @Test("immediate pixels are not deduplicated")
    func immediatePixelsAreNotDeduplicated() {
        let f = EventHubManagerFixture.active(Self.immediateConfig)
        let tab = EventHubTabID.new()
        f.manager.handleWebEvent(EventHubManagerFixture.webEvent("impression"), tabID: tab)
        f.manager.handleWebEvent(EventHubManagerFixture.webEvent("impression"), tabID: tab)
        f.manager.handleWebEvent(EventHubManagerFixture.webEvent("impression"), tabID: tab)
        #expect(f.fired.count == 3)
    }

    @Test("immediate pixels fire without the app being foregrounded")
    func immediatePixelsFireWithoutForeground() {
        // No onAppForegrounded — immediate pixels are not foreground-gated.
        let f = EventHubManagerFixture.background(Self.immediateConfig)
        f.manager.onConfigChanged()
        f.manager.handleWebEvent(EventHubManagerFixture.webEvent("impression"), tabID: .new())
        #expect(f.fired.count == 1)
    }

    @Test("immediate pixels do not persist state")
    func immediatePixelsDoNotPersistState() {
        let f = EventHubManagerFixture.active(Self.immediateConfig)
        f.manager.handleWebEvent(EventHubManagerFixture.webEvent("impression"), tabID: .new())
        #expect(f.repository.allPixelStates().isEmpty)
    }

    @Test("immediate ignores an unknown event type")
    func immediateIgnoresUnknownEventType() {
        let f = EventHubManagerFixture.active(Self.immediateConfig)
        f.manager.handleWebEvent(EventHubManagerFixture.webEvent("something-else"), tabID: .new())
        #expect(f.fired.isEmpty)
    }

    @Test("immediate does not fire when the feature is disabled")
    func immediateDoesNotFireWhenDisabled() {
        let f = EventHubManagerFixture.active(Self.immediateConfig, enabled: false)
        f.manager.handleWebEvent(EventHubManagerFixture.webEvent("impression"), tabID: .new())
        #expect(f.fired.isEmpty)
    }
}
