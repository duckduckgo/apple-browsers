//
//  SubscriptionOnboardingActivationRecorderTests.swift
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

import XCTest
import Persistence
@testable import DuckDuckGo

final class SubscriptionOnboardingActivationRecorderTests: XCTestCase {

    private var keyValueStore: InMemoryThrowingStore!
    private var sut: SubscriptionOnboardingActivationRecorder!

    override func setUp() {
        super.setUp()
        keyValueStore = InMemoryThrowingStore()
        sut = SubscriptionOnboardingActivationRecorder(keyValueStore: keyValueStore)
    }

    override func tearDown() {
        keyValueStore = nil
        sut = nil
        super.tearDown()
    }

    private var completedItems: Set<SubscriptionOnboardingChecklistItem> {
        SubscriptionOnboardingProgressPersistor(keyValueStore: keyValueStore).completedItems
    }

    func testWhenRecordingDuckAIActivatedThenOnlyDuckAIIsMarkedComplete() {
        sut.recordDuckAIActivated()

        XCTAssertEqual(completedItems, [.duckAI])
    }

    func testWhenRecordingPIRActivatedThenOnlyPIRIsMarkedComplete() {
        sut.recordPIRActivated()

        XCTAssertEqual(completedItems, [.pir])
    }

    func testWhenRecordingVPNActivatedThenOnlyVPNIsMarkedComplete() {
        sut.recordVPNActivated()

        XCTAssertEqual(completedItems, [.vpn])
    }

    func testWhenRecordingMultipleActivationsThenEachIsAddedWithoutDisturbingTheOthers() {
        sut.recordDuckAIActivated()
        sut.recordPIRActivated()

        XCTAssertEqual(completedItems, [.duckAI, .pir])
    }

    func testWhenRecordingTheSameActivationTwiceThenTheSetIsUnchanged() {
        sut.recordVPNActivated()
        sut.recordVPNActivated()

        XCTAssertEqual(completedItems, [.vpn])
    }

    func testWhenRecordingDuckAIActivatedIfNeededTwiceThenTheRealIsActivatedReadReflectsIt() {
        XCTAssertFalse(sut.recordDuckAIActivatedIfNeeded())
        XCTAssertTrue(sut.recordDuckAIActivatedIfNeeded())
        XCTAssertEqual(completedItems, [.duckAI])
    }

    func testWhenRecordingPIRActivatedIfNeededTwiceThenTheRealIsActivatedReadReflectsIt() {
        XCTAssertFalse(sut.recordPIRActivatedIfNeeded())
        XCTAssertTrue(sut.recordPIRActivatedIfNeeded())
        XCTAssertEqual(completedItems, [.pir])
    }

    func testWhenRecordingVPNActivatedIfNeededTwiceThenTheRealIsActivatedReadReflectsIt() {
        XCTAssertFalse(sut.recordVPNActivatedIfNeeded())
        XCTAssertTrue(sut.recordVPNActivatedIfNeeded())
        XCTAssertEqual(completedItems, [.vpn])
    }

    func testWhenRecordingDuckAIActivatedIfNeededTwiceThenTheUnderlyingRecordIsCalledOnlyOnce() {
        let mock = MockSubscriptionOnboardingActivationRecorder()

        let wasAlreadyActivatedFirstCall = mock.recordDuckAIActivatedIfNeeded()
        mock.isDuckAIActivated = true
        let wasAlreadyActivatedSecondCall = mock.recordDuckAIActivatedIfNeeded()

        XCTAssertFalse(wasAlreadyActivatedFirstCall)
        XCTAssertTrue(wasAlreadyActivatedSecondCall)
        XCTAssertEqual(mock.recordDuckAIActivatedCallCount, 1)
    }

    func testWhenRecordingPIRActivatedIfNeededTwiceThenTheUnderlyingRecordIsCalledOnlyOnce() {
        let mock = MockSubscriptionOnboardingActivationRecorder()

        let wasAlreadyActivatedFirstCall = mock.recordPIRActivatedIfNeeded()
        mock.isPIRActivated = true
        let wasAlreadyActivatedSecondCall = mock.recordPIRActivatedIfNeeded()

        XCTAssertFalse(wasAlreadyActivatedFirstCall)
        XCTAssertTrue(wasAlreadyActivatedSecondCall)
        XCTAssertEqual(mock.recordPIRActivatedCallCount, 1)
    }

    func testWhenRecordingVPNActivatedIfNeededTwiceThenTheUnderlyingRecordIsCalledOnlyOnce() {
        let mock = MockSubscriptionOnboardingActivationRecorder()

        let wasAlreadyActivatedFirstCall = mock.recordVPNActivatedIfNeeded()
        mock.isVPNActivated = true
        let wasAlreadyActivatedSecondCall = mock.recordVPNActivatedIfNeeded()

        XCTAssertFalse(wasAlreadyActivatedFirstCall)
        XCTAssertTrue(wasAlreadyActivatedSecondCall)
        XCTAssertEqual(mock.recordVPNActivatedCallCount, 1)
    }
}

/// A local stub rather than `PersistenceTestingUtils`
private final class InMemoryThrowingStore: ThrowingKeyValueStoring {

    private var values: [String: Any] = [:]

    func object(forKey key: String) throws -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) throws { values[key] = value }
    func removeObject(forKey key: String) throws { values.removeValue(forKey: key) }
}
