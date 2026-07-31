//
//  YouTubeAdBlockingTelemetryConsentRequirementTests.swift
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
import EventHub
import Persistence
import PersistenceTestingUtils
import XCTest

@testable import DuckDuckGo

/// Covers the notification bridge this requirement exists for: the store backing the opt-in has no
/// change publisher, so a revoked opt-in only reaches EventHub if a posted notification makes it re-read.
final class YouTubeAdBlockingTelemetryConsentRequirementTests: XCTestCase {

    private var store: MockKeyValueFileStore!
    private var notificationCenter: NotificationCenter!
    private var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        store = MockKeyValueFileStore()
        notificationCenter = NotificationCenter()
        cancellables = []
    }

    override func tearDown() {
        store = nil
        notificationCenter = nil
        cancellables = nil
        super.tearDown()
    }

    func testGatedConfigNamesDefaultToTheSharedSet() {
        XCTAssertEqual(makeSUT().configNames, EventHubGatedConfigNames.youTubeAdBlockingTelemetry)
    }

    func testIsGrantedIsFalseWhenTheOptInWasNeverSet() {
        XCTAssertEqual(record(from: makeSUT()).values, [false])
    }

    func testIsGrantedEmitsTheStoredValueOnSubscribe() throws {
        try setOptIn(true)

        XCTAssertEqual(record(from: makeSUT()).values, [true])
    }

    func testIsGrantedReEmitsWhenTheOptInIsRevoked() throws {
        try setOptIn(true)
        let recorder = record(from: makeSUT())

        try setOptIn(false)
        postChange()

        XCTAssertEqual(recorder.values, [true, false])
    }

    func testIsGrantedReEmitsWhenTheOptInIsGranted() throws {
        let recorder = record(from: makeSUT())

        try setOptIn(true)
        postChange()

        XCTAssertEqual(recorder.values, [false, true])
    }

    /// The ad-blocking toggle cascades into this setting whether or not the value changes, so a write
    /// landing on the stored value must not churn EventHub's config.
    func testWriteThatDoesNotChangeTheValueDoesNotReEmit() throws {
        try setOptIn(true)
        let recorder = record(from: makeSUT())

        try setOptIn(true)
        postChange()

        XCTAssertEqual(recorder.values, [true])
    }

    // MARK: - Helpers

    private func makeSUT() -> YouTubeAdBlockingTelemetryConsentRequirement {
        YouTubeAdBlockingTelemetryConsentRequirement(keyValueStore: store, notificationCenter: notificationCenter)
    }

    private final class Recorder {
        var values: [Bool] = []
    }

    private func record(from sut: YouTubeAdBlockingTelemetryConsentRequirement) -> Recorder {
        let recorder = Recorder()
        sut.isGrantedPublisher.sink { recorder.values.append($0) }.store(in: &cancellables)
        return recorder
    }

    private func setOptIn(_ enabled: Bool) throws {
        let storage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys> = store.throwingKeyedStoring()
        try storage.set(enabled, for: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)
    }

    private func postChange() {
        notificationCenter.post(name: YouTubeAdBlockingStorageKeys.youTubeAnalyticsEnabledDidChangeNotification, object: nil)
    }
}
