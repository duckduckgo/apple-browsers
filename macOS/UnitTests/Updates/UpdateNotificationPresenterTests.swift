//
//  UpdateNotificationPresenterTests.swift
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

import AppUpdaterShared
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class UpdateNotificationPresenterTests: XCTestCase {

    // MARK: - Post-Update Notification (showUpdateNotification(for: AppUpdateStatus))

    func testShowUpdateNotification_updated_callsShowNotificationPopover() {
        let expectation = expectation(description: "showNotificationPopover called")
        let presenter = makePresenter(showNotificationPopover: { _ in
            expectation.fulfill()
            return true
        })

        presenter.showUpdateNotification(for: .updated)

        waitForExpectations(timeout: 2)
    }

    func testShowUpdateNotification_downgraded_callsShowNotificationPopover() {
        let expectation = expectation(description: "showNotificationPopover called")
        let presenter = makePresenter(showNotificationPopover: { _ in
            expectation.fulfill()
            return true
        })

        presenter.showUpdateNotification(for: .downgraded)

        waitForExpectations(timeout: 2)
    }

    func testShowUpdateNotification_noChange_doesNotCallShowNotificationPopover() {
        let presenter = makePresenter(showNotificationPopover: { _ in
            XCTFail("showNotificationPopover should not be called for .noChange")
            return false
        })

        presenter.showUpdateNotification(for: .noChange)

        let expectation = expectation(description: "wait for main queue")
        DispatchQueue.main.async { expectation.fulfill() }
        waitForExpectations(timeout: 2)
    }

    // MARK: - Suppression

    func testShowUpdateNotification_suppressed_doesNotCallShowNotificationPopover_forUpdated() {
        let presenter = makePresenter(
            shouldSuppress: { true },
            showNotificationPopover: { _ in
                XCTFail("showNotificationPopover should not be called when suppressed")
                return false
            }
        )

        presenter.showUpdateNotification(for: .updated)

        let expectation = expectation(description: "wait for main queue")
        DispatchQueue.main.async { expectation.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testShowUpdateNotification_suppressed_doesNotCallShowNotificationPopover_forDowngraded() {
        let presenter = makePresenter(
            shouldSuppress: { true },
            showNotificationPopover: { _ in
                XCTFail("showNotificationPopover should not be called when suppressed")
                return false
            }
        )

        presenter.showUpdateNotification(for: .downgraded)

        let expectation = expectation(description: "wait for main queue")
        DispatchQueue.main.async { expectation.fulfill() }
        waitForExpectations(timeout: 2)
    }

    func testShowUpdateNotification_notSuppressed_callsShowNotificationPopover() {
        let expectation = expectation(description: "showNotificationPopover called")
        let presenter = makePresenter(
            shouldSuppress: { false },
            showNotificationPopover: { _ in
                expectation.fulfill()
                return true
            }
        )

        presenter.showUpdateNotification(for: .updated)

        waitForExpectations(timeout: 2)
    }

    // MARK: - Update Available Notification (not affected by suppression)

    func testShowUpdateAvailableNotification_notAffectedBySuppression() {
        let expectation = expectation(description: "showNotificationPopover called")
        let presenter = makePresenter(
            shouldSuppress: { true },
            showNotificationPopover: { _ in
                expectation.fulfill()
                return true
            }
        )

        presenter.showUpdateNotification(for: .regular, areAutomaticUpdatesEnabled: true)

        waitForExpectations(timeout: 2)
    }

    // MARK: - Helpers

    private func makePresenter(
        shouldSuppress: @escaping () -> Bool = { false },
        showNotificationPopover: @escaping (PopoverMessageViewController) -> Bool = { _ in true }
    ) -> UpdateNotificationPresenter {
        UpdateNotificationPresenter(
            pixelFiring: nil,
            shouldSuppressPostUpdateNotification: shouldSuppress,
            showNotificationPopover: showNotificationPopover
        )
    }
}
