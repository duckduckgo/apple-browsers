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

    private static func makeParameter() -> CounterParameter {
        CounterParameter(buckets: buckets)
    }

    @Test("counts every delivered event")
    func countsEveryDeliveredEvent() {
        // De-duplication happens at the hub, before fan-out, so everything reaching a parameter is a
        // genuine occurrence — the parameter itself never suppresses anything. See `DedupStore`.
        let parameter = Self.makeParameter()
        #expect(parameter.handle(data: nil))
        #expect(parameter.handle(data: nil))
        #expect(parameter.state.value == 2)
    }

    @Test("stops counting at the open-ended bucket and further events are no-ops")
    func stopsCountingAtOpenEndedBucket() {
        let parameter = Self.makeParameter()
        for _ in 0..<5 { parameter.handle(data: nil) }
        #expect(parameter.state.stopCounting)
        let valueAtStop = parameter.state.value
        #expect(!parameter.handle(data: nil))
        #expect(parameter.state.value == valueAtStop)
    }

    @Test("queryValue reflects the matching bucket")
    func queryValueReflectsMatchingBucket() {
        let parameter = Self.makeParameter()
        #expect(parameter.queryValue() == "0")
        parameter.handle(data: nil)
        #expect(parameter.queryValue() == "1")
    }

    @Test("restoreState round trips value and stopCounting")
    func restoreStateRoundTrips() {
        let parameter = Self.makeParameter()
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
        #expect(parameter.handle(data: ["loginState": "logged-in"]))
        #expect(parameter.queryValue() != nil)
    }

    @Test("an event without the key clears a previously captured value")
    func eventWithoutKeyClearsPreviousValue() {
        // Every delivered event of the parameter's source assigns, so the pixel reports what the
        // latest event carried rather than a stale reading from an earlier one.
        let parameter = DataParameter(dataKey: "loginState")
        parameter.handle(data: ["loginState": "logged-in"])
        #expect(parameter.handle(data: ["other": "x"]))
        #expect(parameter.queryValue() == nil)
    }

    @Test("an event without the key is no change when there is nothing to clear")
    func eventWithoutKeyIsNoChangeWhenEmpty() {
        let parameter = DataParameter(dataKey: "loginState")
        #expect(!parameter.handle(data: ["other": "x"]))
        #expect(parameter.queryValue() == nil)
    }

    @Test("re-reporting the same value is no change")
    func reReportingSameValueIsNoChange() {
        let parameter = DataParameter(dataKey: "loginState")
        #expect(parameter.handle(data: ["loginState": "a"]))
        #expect(!parameter.handle(data: ["loginState": "a"]))
    }

    @Test("keeps the last value across multiple matching events")
    func keepsLastValueAcrossMultipleEvents() {
        let parameter = DataParameter(dataKey: "loginState")
        parameter.handle(data: ["loginState": "a"])
        parameter.handle(data: ["loginState": "b"])
        #expect(parameter.queryValue()?.contains("b") == true)
    }

    @Test("restoreState round trips lastDataValue")
    func restoreStateRoundTrips() {
        let parameter = DataParameter(dataKey: "loginState")
        parameter.restoreState(ParamState(value: 0, lastDataValue: "%22a%22"))
        #expect(parameter.queryValue() == "%22a%22")
    }
}
