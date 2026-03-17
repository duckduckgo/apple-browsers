//
//  SyncAutoRestoreDecisionManagerTests.swift
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
import Core
@testable import DuckDuckGo

final class SyncAutoRestoreDecisionManagerTests: XCTestCase {

    private var mockDecisionStore: MockSyncAutoRestoreDecisionStore!
    private var mockFeatureFlagger: MockFeatureFlagger!
    private var sut: SyncAutoRestoreDecisionManager!

    override func setUp() {
        super.setUp()
        mockDecisionStore = MockSyncAutoRestoreDecisionStore()
        mockFeatureFlagger = MockFeatureFlagger(enabledFeatureFlags: [.syncAutoRestore])
        sut = SyncAutoRestoreDecisionManager(
            decisionStore: mockDecisionStore,
            featureFlagger: mockFeatureFlagger
        )
    }

    override func tearDown() {
        sut = nil
        mockFeatureFlagger = nil
        mockDecisionStore = nil
        super.tearDown()
    }

    func testIsAutoRestoreFeatureEnabledWhenFlagIsEnabledReturnsTrue() {
        XCTAssertTrue(sut.isAutoRestoreFeatureEnabled)
    }

    func testIsAutoRestoreFeatureEnabledWhenFlagIsDisabledReturnsFalse() {
        mockFeatureFlagger.enabledFeatureFlags = []

        XCTAssertFalse(sut.isAutoRestoreFeatureEnabled)
    }

    func testExistingDecisionWhenStoreReturnsDecisionReturnsDecision() {
        mockDecisionStore.decisionToReturn = true

        XCTAssertEqual(sut.existingDecision(), true)
    }

    func testExistingDecisionWhenStoreThrowsReturnsNil() {
        mockDecisionStore.getDecisionError = DecisionManagerTestError.expected

        XCTAssertNil(sut.existingDecision())
    }

    func testPersistDecisionWhenStoreWritesThenDecisionIsPersisted() throws {
        try sut.persistDecision(true)
        XCTAssertEqual(mockDecisionStore.persistedDecisions, [true])
    }

    func testPersistDecisionWhenStoreThrowsThenErrorIsRethrown() {
        mockDecisionStore.setDecisionError = DecisionManagerTestError.expected

        XCTAssertThrowsError(try sut.persistDecision(true))

        XCTAssertEqual(mockDecisionStore.persistedDecisions, [])
    }

    func testClearDecisionWhenStoreThrowsDoesNotCrash() {
        mockDecisionStore.clearDecisionError = DecisionManagerTestError.expected

        sut.clearDecision()
    }

    func testShouldPreserveAccountWhenDecisionIsTrueReturnsTrue() {
        mockDecisionStore.decisionToReturn = true

        XCTAssertTrue(sut.shouldPreserveAccountWhenSyncDisabled())
    }

    func testShouldPreserveAccountWhenDecisionIsFalseReturnsFalse() {
        mockDecisionStore.decisionToReturn = false

        XCTAssertFalse(sut.shouldPreserveAccountWhenSyncDisabled())
    }

    func testShouldPreserveAccountWhenDecisionMissingReturnsFalse() {
        mockDecisionStore.decisionToReturn = nil

        XCTAssertFalse(sut.shouldPreserveAccountWhenSyncDisabled())
    }
}

private enum DecisionManagerTestError: Error {
    case expected
}

private final class MockSyncAutoRestoreDecisionStore: SyncAutoRestoreDecisionStoring {

    var decisionToReturn: Bool?
    var getDecisionError: Error?
    var setDecisionError: Error?
    var clearDecisionError: Error?

    private(set) var persistedDecisions: [Bool] = []
    private(set) var clearDecisionCallCount = 0

    func getDecision() throws -> Bool? {
        if let getDecisionError {
            throw getDecisionError
        }

        return decisionToReturn
    }

    func setDecision(_ decision: Bool) throws {
        if let setDecisionError {
            throw setDecisionError
        }

        persistedDecisions.append(decision)
        decisionToReturn = decision
    }

    func clearDecision() throws {
        if let clearDecisionError {
            throw clearDecisionError
        }

        clearDecisionCallCount += 1
        decisionToReturn = nil
    }
}
