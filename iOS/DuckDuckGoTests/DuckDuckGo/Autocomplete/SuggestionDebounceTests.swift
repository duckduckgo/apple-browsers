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

    func testDisabledFlagDebouncesAllSuggestionsBy100Milliseconds() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<String, Never>()
        var received = [SuggestionRequest]()
        let subscription = subject.debounceSuggestions(using: MockFeatureFlagger(enabledFeatureFlags: []), scheduler: scheduler)
            .sink { received.append($0) }
        defer { subscription.cancel() }

        subject.send("du")
        scheduler.advance(by: .milliseconds(99))
        XCTAssertTrue(received.isEmpty)
        subject.send("duck")
        scheduler.advance(by: .milliseconds(99))
        XCTAssertTrue(received.isEmpty)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(received, [SuggestionRequest(query: "duck", includeRemoteSuggestions: true)])
        subject.send("")
        scheduler.advance(by: .milliseconds(99))
        XCTAssertEqual(received.count, 1)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(received.last, SuggestionRequest(query: "", includeRemoteSuggestions: true))
    }

    func testEnabledFlagSeparatesLocalAndRemoteDebounces() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<String, Never>()
        var received = [SuggestionRequest]()
        let subscription = subject.debounceSuggestions(using: MockFeatureFlagger(enabledFeatureFlags: [.suggestionDebounce200ms]), scheduler: scheduler)
            .sink { received.append($0) }
        defer { subscription.cancel() }

        subject.send("du")
        XCTAssertEqual(received, [SuggestionRequest(query: "du", includeRemoteSuggestions: false)])
        scheduler.advance(by: .milliseconds(149))
        XCTAssertEqual(received.count, 1)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(received.last, SuggestionRequest(query: "du", includeRemoteSuggestions: true))

        subject.send("duck")
        scheduler.advance(by: .milliseconds(99))
        XCTAssertEqual(received.count, 2)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(received.last, SuggestionRequest(query: "duck", includeRemoteSuggestions: false))
        scheduler.advance(by: .milliseconds(49))
        XCTAssertEqual(received.count, 3)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(received.last, SuggestionRequest(query: "duck", includeRemoteSuggestions: true))
    }

    func testTypingCancelsPendingRemoteRequestWithoutCancellingPublishedLocalRequest() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<String, Never>()
        var received = [SuggestionRequest]()
        let subscription = subject.debounceSuggestions(using: MockFeatureFlagger(enabledFeatureFlags: [.suggestionDebounce200ms]), scheduler: scheduler)
            .sink { received.append($0) }
        defer { subscription.cancel() }

        subject.send("du")
        scheduler.advance(by: .milliseconds(100))
        subject.send("duck")
        scheduler.advance(by: .milliseconds(100))
        XCTAssertEqual(received, [SuggestionRequest(query: "du", includeRemoteSuggestions: false),
                                  SuggestionRequest(query: "duck", includeRemoteSuggestions: false)])
        scheduler.advance(by: .milliseconds(50))
        XCTAssertEqual(received.last, SuggestionRequest(query: "duck", includeRemoteSuggestions: true))
    }

    func testClearingEnabledQueryCancelsPendingRequestsAndRestartsLeadingQuery() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<String, Never>()
        var received = [SuggestionRequest]()
        let subscription = subject.debounceSuggestions(using: MockFeatureFlagger(enabledFeatureFlags: [.suggestionDebounce200ms]), scheduler: scheduler)
            .sink { received.append($0) }
        defer { subscription.cancel() }

        subject.send("du")
        subject.send("duck")
        subject.send("")
        subject.send("w")
        XCTAssertEqual(received, [SuggestionRequest(query: "du", includeRemoteSuggestions: false),
                                  SuggestionRequest(query: "", includeRemoteSuggestions: true),
                                  SuggestionRequest(query: "w", includeRemoteSuggestions: false)])
        subscription.cancel()
        scheduler.advance(by: .milliseconds(200))
        XCTAssertEqual(received.count, 3)
    }

    func testFlagChangesApplyWithoutResubscribing() {
        let scheduler = DispatchQueue.test
        let subject = PassthroughSubject<String, Never>()
        let featureFlagger = MockFeatureFlagger(enabledFeatureFlags: [])
        var received = [SuggestionRequest]()
        let subscription = subject.debounceSuggestions(using: featureFlagger, scheduler: scheduler)
            .sink { received.append($0) }
        defer { subscription.cancel() }

        subject.send("one")
        scheduler.advance(by: .milliseconds(100))
        XCTAssertEqual(received, [SuggestionRequest(query: "one", includeRemoteSuggestions: true)])
        featureFlagger.enabledFeatureFlags = [.suggestionDebounce200ms]
        subject.send("two")
        scheduler.advance(by: .milliseconds(100))
        XCTAssertEqual(received.last, SuggestionRequest(query: "two", includeRemoteSuggestions: false))
        scheduler.advance(by: .milliseconds(50))
        XCTAssertEqual(received.last, SuggestionRequest(query: "two", includeRemoteSuggestions: true))
        featureFlagger.enabledFeatureFlags = []
        subject.send("three")
        scheduler.advance(by: .milliseconds(99))
        XCTAssertEqual(received.count, 3)
        scheduler.advance(by: .milliseconds(1))
        XCTAssertEqual(received.last, SuggestionRequest(query: "three", includeRemoteSuggestions: true))
    }
}
