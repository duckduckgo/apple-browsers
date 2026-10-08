//
//  InactivityNotificationSchedulerServiceIntegrationTests.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import UserNotifications
import FoundationExtensions
@testable import DuckDuckGo

/// Verifies the `UNUserNotificationCenter` behaviour that `InactivityNotificationSchedulerService` relies on, and
/// that `FakeUNUserNotificationCenter` models in the unit tests. The scheduler's own behaviour is covered by
/// `InactivityNotificationSchedulerServiceTests` in the unit test bundle, so it does not depend on simulator state.
@MainActor
final class InactivityNotificationSchedulerServiceIntegrationTests: XCTestCase {

    private typealias Settings = InactivityNotificationSchedulerService.Settings

    // The host app may schedule the real inactivity notification while these tests run, so use a separate identifier.
    private let identifier = "com.duckduckgo.tests.inactivity-notification-contract.\(UUID().uuidString)"

    private var userNotificationCenter: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    func test_requestAuthorization_provisional_grantsWithoutPrompt() async throws {
        try await requireNotificationAuthorization()

        let status = await userNotificationCenter.authorizationStatus()
        XCTAssertTrue(status == .provisional || status == .authorized, "Unexpected authorization status \(status.stringValue).")
    }

    func test_add_requestWithSameIdentifier_replacesPendingRequest() async throws {
        try await requireNotificationAuthorization()
        expectFailureIfSimulatorRejectsNotificationRequests()

        try await userNotificationCenter.add(makeRequest(daysInactive: 7))
        try await userNotificationCenter.add(makeRequest(daysInactive: 3))

        let pending = await pendingRequests()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.content.userInfo[Settings.daysInactive.rawValue] as? Int, 3)
    }

    func test_removePendingNotificationRequests_removesRequestWithIdentifier() async throws {
        try await requireNotificationAuthorization()
        expectFailureIfSimulatorRejectsNotificationRequests()

        try await userNotificationCenter.add(makeRequest(daysInactive: 7))
        let pendingBeforeRemoval = await pendingRequests()
        XCTAssertEqual(pendingBeforeRemoval.count, 1)

        userNotificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])

        let pendingAfterRemoval = await pendingRequests()
        XCTAssertTrue(pendingAfterRemoval.isEmpty)
    }

    // MARK: - Helpers

    /// Requests provisional authorization the same way the scheduler does. A device where the user has already denied
    /// notifications cannot exercise these semantics, so those runs are skipped rather than failed.
    private func requireNotificationAuthorization() async throws {
        if await userNotificationCenter.authorizationStatus() == .notDetermined {
            _ = try await userNotificationCenter.requestAuthorization(options: [.provisional])
        }

        let status = await userNotificationCenter.authorizationStatus()
        try XCTSkipIf(status == .denied, "Notifications are denied on this device. Reset its privacy settings to run this test.")

        let identifier = identifier
        addTeardownBlock {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        }
    }

    /// The iOS 27.0 simulator reports provisional authorization but rejects every request with an undocumented
    /// `UNErrorDomain` 2003 error ("Repository could not save notification. Source is not authorized.").
    /// Only that error is expected, so any other failure still fails the test. Not strict, because it has only been
    /// confirmed on CI runners. Once it is confirmed on every iOS 27 simulator, make it strict so the test flags the fix.
    private func expectFailureIfSimulatorRejectsNotificationRequests() {
        #if targetEnvironment(simulator)
        let options = XCTExpectedFailure.Options()
        options.isStrict = false
        options.issueMatcher = { issue in
            guard let error = issue.associatedError as NSError? else { return false }
            return error.domain == UNErrorDomain && error.code == 2003
        }
        XCTExpectFailure("The iOS simulator notification repository rejected the request despite provisional authorization.", options: options)
        #endif
    }

    private func makeRequest(daysInactive: Int) -> UNNotificationRequest {
        UNNotificationRequest(
            identifier: identifier,
            content: InactivityNotificationSchedulerService.makeUNNotificationContent(with: daysInactive),
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: .days(daysInactive), repeats: false)
        )
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await userNotificationCenter.pendingNotificationRequests().filter { $0.identifier == identifier }
    }
}
