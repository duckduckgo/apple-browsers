//
//  SuggestionDebounceTests.swift
//  DuckDuckGo
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

import Combine
import CombineSchedulers
import XCTest
@testable import DuckDuckGo

final class SuggestionDebounceTests: XCTestCase {

    func testDisabledFlagSendsAfter100Milliseconds() {
        assertDebounceBoundary(enabled: false, milliseconds: 100)
    }

    func testEnabledFlagSendsAfter200Milliseconds() {
        assertDebounceBoundary(enabled: true, milliseconds: 200)
    }

    private func assertDebounceBoundary(enabled: Bool, milliseconds: Int, file: StaticString = #filePath, line: UInt = #line) {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<String, Never>()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: enabled ? [.suggestionDebounce200ms] : [])
        var received = [String]()
        let subscription = subject.debounceSuggestions(using: featureFlagger, scheduler: scheduler)
            .sink { received.append($0) }
        defer { subscription.cancel() }

        subject.send("duck")
        scheduler.advance(by: .milliseconds(milliseconds - 1))
        XCTAssertTrue(received.isEmpty, file: file, line: line)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(received, ["duck"], file: file, line: line)
    }

    func testContinuedTypingCancelsPendingSuggestionInBothFlagStates() {
        for enabled in [false, true] {
            let scheduler = DispatchQueue.test
            let subject = PassthroughSubject<String, Never>()
            let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: enabled ? [.suggestionDebounce200ms] : [])
            let delay = enabled ? 200 : 100
            var received = [String]()
            let subscription = subject.debounceSuggestions(using: featureFlagger, scheduler: scheduler)
                .sink { received.append($0) }
            defer { subscription.cancel() }

            subject.send("du")
            scheduler.advance(by: .milliseconds(delay - 1))
            subject.send("duck")
            scheduler.advance(by: .milliseconds(delay - 1))
            XCTAssertTrue(received.isEmpty)
            scheduler.advance(by: .milliseconds(1))
            XCTAssertEqual(received, ["duck"])
        }
    }

    func testCancellingSubscriptionDiscardsPendingQuery() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<String, Never>()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.suggestionDebounce200ms])
        var received = [String]()
        let subscription = subject.debounceSuggestions(using: featureFlagger, scheduler: scheduler)
            .sink { received.append($0) }

        subject.send("duck")
        scheduler.advance(by: .milliseconds(100))
        subscription.cancel()
        scheduler.advance(by: .milliseconds(200))
        XCTAssertTrue(received.isEmpty)
    }

    func testFlagChangesApplyToNextQueryWithoutResubscribing() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<String, Never>()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        var received = [String]()
        let subscription = subject.debounceSuggestions(using: featureFlagger, scheduler: scheduler)
            .sink { received.append($0) }
        defer { subscription.cancel() }

        subject.send("one")
        scheduler.advance(by: .milliseconds(100))
        XCTAssertEqual(received, ["one"])

        featureFlagger.enabledFeatureFlags = [.suggestionDebounce200ms]
        subject.send("two")
        scheduler.advance(by: .milliseconds(199))
        XCTAssertEqual(received, ["one"])
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(received, ["one", "two"])

        featureFlagger.enabledFeatureFlags = []
        subject.send("three")
        scheduler.advance(by: .milliseconds(99))
        XCTAssertEqual(received, ["one", "two"])
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(received, ["one", "two", "three"])
    }
}
