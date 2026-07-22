import Testing
import Foundation
@testable import EventHub

@Suite("CounterParameter")
struct CounterParameterTests {
    static let buckets: BucketList = [
        OrderedBucket(name: "0", config: BucketConfig(gte: 0, lt: 1)),
        OrderedBucket(name: "1", config: BucketConfig(gte: 1, lt: 2)),
        OrderedBucket(name: "2+", config: BucketConfig(gte: 2)),
    ]

    @Test("increments on each distinct-tab event")
    func incrementsOnEachDistinctTabEvent() {
        let parameter = CounterParameter(buckets: Self.buckets)
        #expect(parameter.handle(data: nil, tabID: .new()))
        #expect(parameter.handle(data: nil, tabID: .new()))
        #expect(parameter.state.value == 2)
    }

    @Test("dedups repeated events on the same tab")
    func dedupsRepeatedEventsOnSameTab() {
        let parameter = CounterParameter(buckets: Self.buckets)
        let tab = EventHubTabID.new()
        #expect(parameter.handle(data: nil, tabID: tab))
        #expect(!parameter.handle(data: nil, tabID: tab))
        #expect(parameter.state.value == 1)
    }

    @Test("native events (.empty tab) are never deduped")
    func nativeEventsAreNeverDeduped() {
        let parameter = CounterParameter(buckets: Self.buckets)
        #expect(parameter.handle(data: nil, tabID: .empty))
        #expect(parameter.handle(data: nil, tabID: .empty))
        #expect(parameter.state.value == 2)
    }

    @Test("onNavigationStarted clears dedup for that tab")
    func navigationClearsDedupForTab() {
        let parameter = CounterParameter(buckets: Self.buckets)
        let tab = EventHubTabID.new()
        #expect(parameter.handle(data: nil, tabID: tab))
        parameter.onNavigationStarted(tabID: tab)
        #expect(parameter.handle(data: nil, tabID: tab))
        #expect(parameter.state.value == 2)
    }

    @Test("onTabClosed clears dedup for that tab")
    func tabClosedClearsDedupForTab() {
        let parameter = CounterParameter(buckets: Self.buckets)
        let tab = EventHubTabID.new()
        #expect(parameter.handle(data: nil, tabID: tab))
        parameter.onTabClosed(tabID: tab)
        #expect(parameter.handle(data: nil, tabID: tab))
        #expect(parameter.state.value == 2)
    }

    @Test("stops counting at the open-ended bucket and further events are no-ops")
    func stopsCountingAtOpenEndedBucket() {
        let parameter = CounterParameter(buckets: Self.buckets)
        for _ in 0..<5 { parameter.handle(data: nil, tabID: .new()) }
        #expect(parameter.state.stopCounting)
        let valueAtStop = parameter.state.value
        #expect(!parameter.handle(data: nil, tabID: .new()))
        #expect(parameter.state.value == valueAtStop)
    }

    @Test("queryValue reflects the matching bucket")
    func queryValueReflectsMatchingBucket() {
        let parameter = CounterParameter(buckets: Self.buckets)
        #expect(parameter.queryValue() == "0")
        parameter.handle(data: nil, tabID: .new())
        #expect(parameter.queryValue() == "1")
    }

    @Test("restoreState round trips value and stopCounting")
    func restoreStateRoundTrips() {
        let parameter = CounterParameter(buckets: Self.buckets)
        parameter.restoreState(ParamState(value: 3, stopCounting: true))
        #expect(parameter.state.value == 3)
        #expect(parameter.state.stopCounting)
    }
}

@Suite("DataParameter")
struct DataParameterTests {
    @Test("captures and percent-encodes a matching data key")
    func capturesAndEncodesMatchingKey() {
        let parameter = DataParameter(dataKey: "loginState")
        #expect(parameter.handle(data: ["loginState": "logged-in"], tabID: .new()))
        #expect(parameter.queryValue() != nil)
    }

    @Test("ignores events with no matching data key")
    func ignoresEventsWithNoMatchingKey() {
        let parameter = DataParameter(dataKey: "loginState")
        #expect(!parameter.handle(data: ["other": "x"], tabID: .new()))
        #expect(parameter.queryValue() == nil)
    }

    @Test("keeps the last value across multiple matching events")
    func keepsLastValueAcrossMultipleEvents() {
        let parameter = DataParameter(dataKey: "loginState")
        parameter.handle(data: ["loginState": "a"], tabID: .new())
        parameter.handle(data: ["loginState": "b"], tabID: .new())
        #expect(parameter.queryValue()?.contains("b") == true)
    }

    @Test("restoreState round trips lastDataValue")
    func restoreStateRoundTrips() {
        let parameter = DataParameter(dataKey: "loginState")
        parameter.restoreState(ParamState(value: 0, lastDataValue: "%22a%22"))
        #expect(parameter.queryValue() == "%22a%22")
    }
}
