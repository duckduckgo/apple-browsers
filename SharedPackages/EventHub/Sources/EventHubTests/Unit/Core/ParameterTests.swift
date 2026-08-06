//
//  ParameterTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

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

    /// Builds a parameter alongside the store it dedups against, so a test can clear dedup the way
    /// `EventHub` does (the parameter consults the store; it no longer owns the state itself).
    private static func makeParameter() -> (parameter: CounterParameter, dedupStore: DedupStore) {
        let dedupStore = DedupStore()
        let parameter = CounterParameter(buckets: buckets, dedupKey: "pixel:count:test", dedupStore: dedupStore)
        return (parameter, dedupStore)
    }

    @Test("increments on each distinct-tab event")
    func incrementsOnEachDistinctTabEvent() {
        let (parameter, _) = Self.makeParameter()
        #expect(parameter.handle(data: nil, tabID: .new()))
        #expect(parameter.handle(data: nil, tabID: .new()))
        #expect(parameter.state.value == 2)
    }

    @Test("dedups repeated events on the same tab")
    func dedupsRepeatedEventsOnSameTab() {
        let (parameter, _) = Self.makeParameter()
        let tab = EventHubTabID.new()
        #expect(parameter.handle(data: nil, tabID: tab))
        #expect(!parameter.handle(data: nil, tabID: tab))
        #expect(parameter.state.value == 1)
    }

    @Test("native events (.empty tab) are never deduped")
    func nativeEventsAreNeverDeduped() {
        let (parameter, _) = Self.makeParameter()
        #expect(parameter.handle(data: nil, tabID: .empty))
        #expect(parameter.handle(data: nil, tabID: .empty))
        #expect(parameter.state.value == 2)
    }

    @Test("clearing the tab's dedup entry lets it count again")
    func clearingTabDedupLetsItCountAgain() {
        // `EventHub` clears the store on navigation to a different URL and on tab close; from the
        // parameter's side both look the same, so one test covers each caller.
        let (parameter, dedupStore) = Self.makeParameter()
        let tab = EventHubTabID.new()
        #expect(parameter.handle(data: nil, tabID: tab))
        dedupStore.clear(tabID: tab)
        #expect(parameter.handle(data: nil, tabID: tab))
        #expect(parameter.state.value == 2)
    }

    @Test("two parameters sharing a store dedup independently")
    func parametersSharingStoreDedupIndependently() {
        // The store is hub-wide, so the dedup key must keep pixels/params from shadowing each other.
        let dedupStore = DedupStore()
        let first = CounterParameter(buckets: Self.buckets, dedupKey: "pixelA:count:test", dedupStore: dedupStore)
        let second = CounterParameter(buckets: Self.buckets, dedupKey: "pixelB:count:test", dedupStore: dedupStore)
        let tab = EventHubTabID.new()

        #expect(first.handle(data: nil, tabID: tab))
        #expect(second.handle(data: nil, tabID: tab))

        #expect(first.state.value == 1)
        #expect(second.state.value == 1)
    }

    @Test("stops counting at the open-ended bucket and further events are no-ops")
    func stopsCountingAtOpenEndedBucket() {
        let (parameter, _) = Self.makeParameter()
        for _ in 0..<5 { parameter.handle(data: nil, tabID: .new()) }
        #expect(parameter.state.stopCounting)
        let valueAtStop = parameter.state.value
        #expect(!parameter.handle(data: nil, tabID: .new()))
        #expect(parameter.state.value == valueAtStop)
    }

    @Test("queryValue reflects the matching bucket")
    func queryValueReflectsMatchingBucket() {
        let (parameter, _) = Self.makeParameter()
        #expect(parameter.queryValue() == "0")
        parameter.handle(data: nil, tabID: .new())
        #expect(parameter.queryValue() == "1")
    }

    @Test("restoreState round trips value and stopCounting")
    func restoreStateRoundTrips() {
        let (parameter, _) = Self.makeParameter()
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
