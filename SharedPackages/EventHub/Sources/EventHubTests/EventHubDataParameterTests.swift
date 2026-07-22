import Testing
@testable import EventHub

@Suite("EventHub data parameters")
struct EventHubDataParameterTests {
    static let immediateDataConfig = """
    { "telemetry": { "webEvent_login": {
        "state": "enabled",
        "trigger": { "type": "immediate", "source": "login" },
        "parameters": { "loginState": { "template": "data", "dataKey": "loginState" } }
    } } }
    """

    @Test("immediate data param encodes a string value")
    func immediateDataParamEncodesStringValue() {
        let f = EventHubFixture.active(Self.immediateDataConfig)
        f.manager.handleWebEvent(EventHubFixture.eventWithData("login", dataJSON: #"{ "loginState": "logged-in" }"#), tabID: .new())
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["loginState"] == "%22logged-in%22")
    }

    @Test("immediate data param encodes an object value")
    func immediateDataParamEncodesObjectValue() {
        let config = """
        { "telemetry": { "webEvent_login": {
            "state": "enabled",
            "trigger": { "type": "immediate", "source": "login" },
            "parameters": { "payload": { "template": "data", "dataKey": "payload" } }
        } } }
        """
        let f = EventHubFixture.active(config)
        f.manager.handleWebEvent(EventHubFixture.eventWithData("login", dataJSON: #"{ "payload": { "a": true } }"#), tabID: .new())
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["payload"] == "%7B%22a%22%3Atrue%7D")
    }

    @Test("immediate data param encodes a null value")
    func immediateDataParamEncodesNullValue() {
        let f = EventHubFixture.active(Self.immediateDataConfig)
        f.manager.handleWebEvent(EventHubFixture.eventWithData("login", dataJSON: #"{ "loginState": null }"#), tabID: .new())
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["loginState"] == "null")
    }

    @Test("immediate data param is omitted when the key is absent")
    func immediateDataParamOmittedWhenKeyAbsent() {
        let f = EventHubFixture.active(Self.immediateDataConfig)
        f.manager.handleWebEvent(EventHubFixture.eventWithData("login", dataJSON: #"{ "other": "x" }"#), tabID: .new())
        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["loginState"] == nil)
    }

    @Test("aggregate data param uses the last value from a matching source")
    func aggregateDataParamUsesLastValueFromMatchingSource() {
        let config = """
        { "telemetry": { "yt": {
            "state": "enabled",
            "trigger": { "period": { "seconds": 60 } },
            "parameters": {
                "count": { "template": "counter", "source": "yt", "buckets": {"0-9": {"gte": 0, "lt": 10}, "10+": {"gte": 10}} },
                "loginState": { "template": "data", "source": "yt", "dataKey": "loginState" }
            }
        } } }
        """
        let f = EventHubFixture.active(config)
        f.manager.handleWebEvent(EventHubFixture.eventWithData("yt", dataJSON: #"{ "loginState": "a" }"#), tabID: .new())
        f.manager.handleWebEvent(EventHubFixture.eventWithData("yt", dataJSON: #"{ "loginState": "b" }"#), tabID: .new())
        f.advance(by: 60)

        #expect(f.fired.count == 1)
        #expect(f.fired.first?.parameters["loginState"] == "%22b%22")
    }
}
