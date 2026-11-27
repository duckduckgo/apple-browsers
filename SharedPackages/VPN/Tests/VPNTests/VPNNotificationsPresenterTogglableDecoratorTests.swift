//
//  VPNNotificationsPresenterTogglableDecoratorTests.swift
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
@testable import VPN

final class VPNNotificationsPresenterTogglableDecoratorTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var settings: VPNSettings!
    private var presenter: RecordingPresenter!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        settings = VPNSettings(defaults: defaults)
        presenter = RecordingPresenter()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        settings = nil
        presenter = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeDecorator() -> VPNNotificationsPresenterTogglableDecorator {
        VPNNotificationsPresenterTogglableDecorator(settings: settings, defaults: defaults, wrappee: presenter)
    }

    func testWhenTheTunnelStartsWithoutATokenTwiceThenTheSignedOutNotificationIsShownOnce() {
        let decorator = makeDecorator()

        decorator.showSignedOutNotification()
        decorator.showSignedOutNotification()

        XCTAssertEqual(presenter.signedOutNotificationsShown, 1)
    }

    func testWhenTheTunnelProcessRestartsThenTheSignedOutNotificationIsNotShownAgain() {
        makeDecorator().showSignedOutNotification()

        makeDecorator().showSignedOutNotification()

        XCTAssertEqual(presenter.signedOutNotificationsShown, 1)
    }

    func testWhenTheVPNConnectsBetweenTwoSignedOutStartsThenTheSignedOutNotificationIsShownAgain() {
        let decorator = makeDecorator()

        decorator.showSignedOutNotification()
        decorator.showConnectedNotification(serverLocation: nil, snoozeEnded: false)
        decorator.showSignedOutNotification()

        XCTAssertEqual(presenter.signedOutNotificationsShown, 2)
    }

    func testWhenStatusNotificationsAreOffAndTheVPNConnectsThenTheSignedOutNotificationIsShownAgain() {
        settings.notifyStatusChanges = false
        let decorator = makeDecorator()

        decorator.showSignedOutNotification()
        decorator.showConnectedNotification(serverLocation: nil, snoozeEnded: false)
        decorator.showSignedOutNotification()

        XCTAssertEqual(presenter.connectedNotificationsShown, 0)
        XCTAssertEqual(presenter.signedOutNotificationsShown, 2)
    }

    func testWhenTheSignedOutNotificationWasShownThenTheExpiredNotificationIsStillShownOnce() {
        let decorator = makeDecorator()
        decorator.showSignedOutNotification()

        defaults.enableEntitlementMessaging()
        decorator.showEntitlementNotification()
        decorator.showEntitlementNotification()

        XCTAssertEqual(presenter.entitlementNotificationsShown, 1)
        XCTAssertEqual(presenter.signedOutNotificationsShown, 1)
    }

    func testWhenTheExpiredNotificationWasShownThenTheSignedOutNotificationIsStillShown() {
        let decorator = makeDecorator()
        defaults.enableEntitlementMessaging()
        decorator.showEntitlementNotification()

        decorator.showSignedOutNotification()

        XCTAssertEqual(presenter.entitlementNotificationsShown, 1)
        XCTAssertEqual(presenter.signedOutNotificationsShown, 1)
    }
}

private final class RecordingPresenter: VPNNotificationsPresenting {
    private(set) var connectedNotificationsShown = 0
    private(set) var entitlementNotificationsShown = 0
    private(set) var signedOutNotificationsShown = 0

    func showConnectedNotification(serverLocation: String?, snoozeEnded: Bool) { connectedNotificationsShown += 1 }
    func showStrictRoutingReminderNotification() {}
    func showReconnectingNotification() {}
    func showConnectionFailureNotification() {}
    func showSnoozingNotification(duration: TimeInterval) {}
    func showSupersededNotification() {}
    func showTestNotification() {}
    func showEntitlementNotification() { entitlementNotificationsShown += 1 }
    func showDebugEventNotification(message: String) {}
    func showSignedOutNotification() { signedOutNotificationsShown += 1 }
}
