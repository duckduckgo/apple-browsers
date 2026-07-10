//
//  SubscriptionExpirationReminderSchedulerTests.swift
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
import UIKit
import UserNotifications
@testable import Core
@testable import DuckDuckGo
import Subscription
import SubscriptionTestingUtilities

final class SubscriptionExpirationReminderSchedulerTests: XCTestCase {

    private var subscriptionManager: SubscriptionManagerMock!
    private var notificationCenter: MockUNUserNotificationCenter!
    private var observerNotificationCenter: NotificationCenter!
    private var featureFlagEnabled: Bool = true
    private var sut: DefaultSubscriptionExpirationReminderScheduler!

    private let identifier = DefaultSubscriptionExpirationReminderScheduler.notificationIdentifier

    override func setUp() {
        super.setUp()
        subscriptionManager = SubscriptionManagerMock()
        notificationCenter = MockUNUserNotificationCenter()
        notificationCenter.authorizationStatus = .authorized
        observerNotificationCenter = NotificationCenter()
        featureFlagEnabled = true
        PixelFiringMock.tearDown()
        sut = DefaultSubscriptionExpirationReminderScheduler(
            subscriptionManager: subscriptionManager,
            isFeatureEnabled: { [weak self] in self?.featureFlagEnabled ?? false },
            notificationCenter: notificationCenter,
            notificationCenterObserver: observerNotificationCenter,
            pixelFiring: PixelFiringMock.self,
            dailyPixelFiring: PixelFiringMock.self
        )
    }

    override func tearDown() {
        sut = nil
        subscriptionManager = nil
        notificationCenter = nil
        observerNotificationCenter = nil
        PixelFiringMock.tearDown()
        super.tearDown()
    }

    // MARK: - Helpers

    // Default to trial: only trial subs are eligible for the expiration reminder
    private func setSubscription(status: DuckDuckGoSubscription.Status, withTrialOffer: Bool = true) {
        let offers: [DuckDuckGoSubscription.Offer] = withTrialOffer ? [Self.trialOffer] : []
        subscriptionManager.resultSubscription = .success(SubscriptionMockFactory.subscription(status: status, activeOffers: offers))
    }

    private static let trialOffer: DuckDuckGoSubscription.Offer = {
        let data = Data(#"{"type":"Trial"}"#.utf8)
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(DuckDuckGoSubscription.Offer.self, from: data)
    }()

    private func days(_ count: Int) -> TimeInterval {
        TimeInterval(count) * 24 * 60 * 60
    }

    // MARK: - scheduleReminder skip paths

    func test_scheduleReminder_whenFeatureFlagOff_doesNotAddRequest() async {
        featureFlagEnabled = false
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func test_scheduleReminder_whenTimeBeforeCancelIsZero_doesNotAddRequest() async {
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: 0)

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func test_scheduleReminder_whenTimeBeforeCancelIsNegative_doesNotAddRequest() async {
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: -days(3))

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func test_scheduleReminder_whenAuthorizationStatusIsDenied_doesNotAddRequest() async {
        notificationCenter.authorizationStatus = .denied
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func test_scheduleReminder_whenAuthorizationStatusIsProvisional_doesNotAddRequest() async {
        notificationCenter.authorizationStatus = .provisional
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty,
                      "Provisional notifications deliver silently — the user would not see the reminder")
    }

    func test_scheduleReminder_whenAuthorizationStatusIsNotDetermined_doesNotAddRequest() async {
        notificationCenter.authorizationStatus = .notDetermined
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func test_scheduleReminder_whenNoSubscription_doesNotAddRequest() async {
        subscriptionManager.resultSubscription = nil

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func test_scheduleReminder_whenSubscriptionStatusIsExpired_doesNotAddRequest() async {
        setSubscription(status: .expired)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func test_scheduleReminder_whenSubscriptionIsNotOnFreeTrial_doesNotAddRequest() async {
        setSubscription(status: .autoRenewable, withTrialOffer: false)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    func test_scheduleReminder_whenFireDateInThePast_doesNotAddRequest() async {
        // Depends on SubscriptionMockFactory.subscription(status:) hardcoding a +30-day expiry.
        // 365 days puts the computed fire date ~335 days in the past.
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(365))

        XCTAssertTrue(notificationCenter.addedRequests.isEmpty)
    }

    // MARK: - scheduleReminder success path

    func test_scheduleReminder_withValidInputs_addsRequestWithCorrectIdentifierAndTrigger() async throws {
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertEqual(notificationCenter.addedRequests.count, 1)
        let request = try XCTUnwrap(notificationCenter.addedRequests.first)
        XCTAssertEqual(request.identifier, identifier)
        XCTAssertEqual(request.content.title, UserText.subscriptionExpirationReminderNotificationTitle(daysUntilTrialEnds: 7))
        XCTAssertEqual(request.content.categoryIdentifier, identifier)
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, days(23), accuracy: 5)
        XCTAssertFalse(trigger.repeats)
    }

    func test_scheduleReminder_withDaysBeforeCancel_usesThatDayCountInTitle() async throws {
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(daysBeforeCancel: 5)

        let request = try XCTUnwrap(notificationCenter.addedRequests.first)
        XCTAssertEqual(request.content.title, UserText.subscriptionExpirationReminderNotificationTitle(daysUntilTrialEnds: 5))
    }

    func test_notificationTitle_pluralisesByDayCount() {
        XCTAssertEqual(UserText.subscriptionExpirationReminderNotificationTitle(daysUntilTrialEnds: 1),
                       "Your trial ends in 1 day")
        XCTAssertEqual(UserText.subscriptionExpirationReminderNotificationTitle(daysUntilTrialEnds: 7),
                       "Your trial ends in 7 days")
    }

    func test_scheduleReminder_removesPreviouslyScheduledReminderBeforeAdding() async {
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertEqual(notificationCenter.removedIdentifiers.count, 1)
        XCTAssertEqual(notificationCenter.removedIdentifiers.first, [identifier])
    }

    // MARK: - Observer: .subscriptionDidChange

    func test_subscriptionDidChange_whenStatusBecomesExpired_cancelsPendingReminder() async {
        setSubscription(status: .autoRenewable)
        await sut.scheduleReminder(timeBeforeCancel: days(7))
        let priorRemovalCount = notificationCenter.removedIdentifiers.count

        setSubscription(status: .expired)
        observerNotificationCenter.post(name: .subscriptionDidChange, object: nil)

        await waitUntil("reminder cancelled after subscriptionDidChange") {
            self.notificationCenter.removedIdentifiers.count > priorRemovalCount
        }
        XCTAssertEqual(notificationCenter.removedIdentifiers.last, [identifier])
    }

    func test_subscriptionDidChange_whenStatusStillActive_doesNotCancel() async {
        setSubscription(status: .autoRenewable)
        await sut.scheduleReminder(timeBeforeCancel: days(7))
        let priorRemovalCount = notificationCenter.removedIdentifiers.count

        observerNotificationCenter.post(name: .subscriptionDidChange, object: nil)

        await assertNoActionWithinShortDelay()
        XCTAssertEqual(notificationCenter.removedIdentifiers.count, priorRemovalCount)
    }

    func test_subscriptionDidChange_whenTrialOfferEndsButStatusStaysActive_cancelsPendingReminder() async {
        // Reminder is scheduled while user is on a trial.
        setSubscription(status: .autoRenewable, withTrialOffer: true)
        await sut.scheduleReminder(timeBeforeCancel: days(7))
        let priorRemovalCount = notificationCenter.removedIdentifiers.count

        // Trial offer ends but status stays .autoRenewable (e.g. trial converted to a paid subscription).
        // The pending reminder is no longer applicable and should be cancelled.
        setSubscription(status: .autoRenewable, withTrialOffer: false)
        observerNotificationCenter.post(name: .subscriptionDidChange, object: nil)

        await waitUntil("reminder cancelled after trial offer ends") {
            self.notificationCenter.removedIdentifiers.count > priorRemovalCount
        }
        XCTAssertEqual(notificationCenter.removedIdentifiers.last, [identifier])
    }

    // MARK: - Observer: UIApplication.didBecomeActiveNotification

    func test_didBecomeActive_whenNoPendingReminder_doesNotCancel() async {
        // No call to scheduleReminder, so no pending notification queued.
        // Subscription is inactive — if the foreground observer didn't early-exit on the pending check,
        // it would proceed to the cancel branch. Verify the absence of cancellation.
        setSubscription(status: .inactive)
        observerNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        await assertNoActionWithinShortDelay()
        XCTAssertTrue(notificationCenter.removedIdentifiers.isEmpty,
                      "Foreground observer should early-exit when no reminder is queued, without reaching the cancel branch")
    }

    func test_didBecomeActive_whenPendingAndStatusInactive_cancelsPendingReminder() async {
        setSubscription(status: .autoRenewable)
        await sut.scheduleReminder(timeBeforeCancel: days(7))
        let priorRemovalCount = notificationCenter.removedIdentifiers.count

        setSubscription(status: .inactive)
        observerNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        await waitUntil("reminder cancelled after didBecomeActive") {
            self.notificationCenter.removedIdentifiers.count > priorRemovalCount
        }
        XCTAssertEqual(notificationCenter.removedIdentifiers.last, [identifier])
    }

    func test_didBecomeActive_whenPendingAndStatusActive_doesNotCancel() async {
        setSubscription(status: .autoRenewable)
        await sut.scheduleReminder(timeBeforeCancel: days(7))
        let priorRemovalCount = notificationCenter.removedIdentifiers.count

        observerNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        await assertNoActionWithinShortDelay()
        XCTAssertEqual(notificationCenter.removedIdentifiers.count, priorRemovalCount)
    }

    // MARK: - Feature-flag kill switch

    func test_cancelReminderIfInactive_whenFeatureFlagOff_cancelsRegardlessOfSubscriptionState() async {
        // Schedule with the flag on so the reminder makes it to the queue.
        setSubscription(status: .autoRenewable)
        await sut.scheduleReminder(timeBeforeCancel: days(7))
        let priorRemovalCount = notificationCenter.removedIdentifiers.count

        // Flag flips off remotely while subscription is still active — the kill switch should
        // still cancel without consulting the backend.
        featureFlagEnabled = false
        observerNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        await waitUntil("reminder cancelled by feature-flag kill switch") {
            self.notificationCenter.removedIdentifiers.count > priorRemovalCount
        }
        XCTAssertEqual(notificationCenter.removedIdentifiers.last, [identifier])
    }

    // MARK: - Category registration contract

    func test_notificationServiceManager_registersExpirationReminderCategoryWithCustomDismissAction() throws {
        let center = MockUNUserNotificationCenter()

        NotificationServiceManager.registerNotificationCategories(on: center)

        let category = try XCTUnwrap(center.registeredCategories.first {
            $0.identifier == DefaultSubscriptionExpirationReminderScheduler.notificationIdentifier
        })
        XCTAssertTrue(category.options.contains(.customDismissAction),
                      "The reminder category must register .customDismissAction, otherwise the dismiss callback is never delivered")
    }

    func test_scheduledReminder_categoryIdentifierIsRegisteredByNotificationServiceManager() async throws {
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        let request = try XCTUnwrap(notificationCenter.addedRequests.first)
        let registeredIdentifiers = Set(NotificationServiceManager.notificationCategories.map { $0.identifier })
        XCTAssertTrue(registeredIdentifiers.contains(request.content.categoryIdentifier),
                      "The scheduled reminder's categoryIdentifier must match a category registered by NotificationServiceManager, otherwise the dismiss action would not be delivered")
    }

    // MARK: - Pixels: scheduling

    func test_scheduleReminder_whenAddThrows_firesSchedulingErrorPixel() async {
        notificationCenter.addRequestError = .addRequestError
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.subscriptionExpirationReminderSchedulingError.name)
        XCTAssertNotNil(PixelFiringMock.lastPixelInfo?.error)
    }

    func test_scheduleReminder_whenSucceeds_firesScheduledPixel() async {
        setSubscription(status: .autoRenewable)

        await sut.scheduleReminder(timeBeforeCancel: days(7))

        XCTAssertEqual(PixelFiringMock.lastPixelName, Pixel.Event.subscriptionExpirationReminderScheduled.name)
    }

    // MARK: - Pixels: cancellation

    func test_cancelReminderIfInactive_whenSubscriptionInactive_firesCancelledDailyPixel() async {
        setSubscription(status: .autoRenewable)
        await sut.scheduleReminder(timeBeforeCancel: days(7))

        setSubscription(status: .inactive)
        observerNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        await waitUntil("cancelled pixel fired after subscription became inactive") {
            PixelFiringMock.lastDailyPixelInfo?.pixelName == Pixel.Event.subscriptionExpirationReminderCancelled.name
        }
    }

    func test_cancelReminderIfInactive_whenTrialOfferEndsButStatusStaysActive_firesCancelledDailyPixel() async {
        setSubscription(status: .autoRenewable, withTrialOffer: true)
        await sut.scheduleReminder(timeBeforeCancel: days(7))

        setSubscription(status: .autoRenewable, withTrialOffer: false)
        observerNotificationCenter.post(name: .subscriptionDidChange, object: nil)

        await waitUntil("cancelled pixel fired after trial offer ended") {
            PixelFiringMock.lastDailyPixelInfo?.pixelName == Pixel.Event.subscriptionExpirationReminderCancelled.name
        }
    }

    func test_cancelReminderIfInactive_whenFeatureFlagOff_doesNotFireCancelledPixel() async {
        setSubscription(status: .autoRenewable)
        await sut.scheduleReminder(timeBeforeCancel: days(7))
        let priorRemovalCount = notificationCenter.removedIdentifiers.count

        featureFlagEnabled = false
        observerNotificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        await waitUntil("reminder cancelled by feature-flag kill switch") {
            self.notificationCenter.removedIdentifiers.count > priorRemovalCount
        }
        XCTAssertNil(PixelFiringMock.lastDailyPixelInfo,
                     "Kill-switch cancellation should not fire the subscription-state cancelled pixel")
    }

    // MARK: - Async test helpers

    private func waitUntil(_ description: String,
                           timeout: TimeInterval = 1.0,
                           predicate: @escaping () -> Bool,
                           file: StaticString = #file,
                           line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting: \(description)", file: file, line: line)
    }

    private func assertNoActionWithinShortDelay() async {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
}
