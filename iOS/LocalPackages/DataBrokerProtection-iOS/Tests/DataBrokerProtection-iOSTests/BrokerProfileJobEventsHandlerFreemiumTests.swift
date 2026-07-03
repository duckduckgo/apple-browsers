//
//  BrokerProfileJobEventsHandlerFreemiumTests.swift
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
import DataBrokerProtectionCore
@testable import DataBrokerProtection_iOS

final class BrokerProfileJobEventsHandlerFreemiumTests: XCTestCase {

    private var userDefaults: UserDefaults!
    private var suiteName: String!
    private var isAuthenticated = false
    private var stateManager: DefaultFreemiumDBPUserStateManager!
    private var notificationService: MockDataBrokerProtectionUserNotificationService!
    private var sut: BrokerProfileJobEventsHandler!

    override func setUp() {
        super.setUp()
        suiteName = "BrokerProfileJobEventsHandlerFreemiumTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)!
        isAuthenticated = false
        stateManager = DefaultFreemiumDBPUserStateManager(
            userDefaults: userDefaults,
            isUserAuthenticated: { [self] in isAuthenticated },
            isFreemiumEnabled: { true }
        )
        notificationService = MockDataBrokerProtectionUserNotificationService()
        sut = BrokerProfileJobEventsHandler(
            userNotificationService: notificationService,
            freemiumUserStateManager: stateManager
        )
    }

    override func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        sut = nil
        notificationService = nil
        stateManager = nil
        userDefaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func fireAndAwait(_ event: JobEvent) async {
        await withCheckedContinuation { cont in
            sut.fire(event, onComplete: { _ in cont.resume() })
        }
    }

    // MARK: - .profileSaved

    func test_profileSaved_unauthenticated_writesFreemiumState() async {
        isAuthenticated = false

        await fireAndAwait(.profileSaved)

        XCTAssertTrue(stateManager.didActivate)
        XCTAssertNotNil(stateManager.firstProfileSavedTimestamp)
    }

    func test_profileSaved_authenticated_writesNothing() async {
        isAuthenticated = true

        await fireAndAwait(.profileSaved)

        XCTAssertFalse(stateManager.didActivate)
        XCTAssertNil(stateManager.firstProfileSavedTimestamp)
    }

    func test_profileSaved_firedTwice_timestampDoesNotChange() async {
        isAuthenticated = false

        await fireAndAwait(.profileSaved)
        let firstTimestamp = stateManager.firstProfileSavedTimestamp

        await fireAndAwait(.profileSaved)

        XCTAssertEqual(stateManager.firstProfileSavedTimestamp, firstTimestamp)
    }

    // MARK: - other events produce no freemium writes from this handler

    func test_firstScanCompleted_unauthenticated_noFreemiumWrites() async {
        isAuthenticated = false

        await fireAndAwait(.firstScanCompleted)

        XCTAssertFalse(stateManager.didActivate)
        XCTAssertNil(stateManager.firstScanResult)
    }

    func test_firstScanCompletedAndMatchesFound_unauthenticated_noFreemiumWrites() async {
        isAuthenticated = false

        await fireAndAwait(.firstScanCompletedAndMatchesFound)

        XCTAssertFalse(stateManager.didActivate)
        XCTAssertNil(stateManager.firstScanResult)
    }
}
