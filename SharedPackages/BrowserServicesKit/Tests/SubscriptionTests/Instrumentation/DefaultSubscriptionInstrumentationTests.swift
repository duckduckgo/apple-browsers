//
//  DefaultSubscriptionInstrumentationTests.swift
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
import Common
import PixelKit
import PixelKitTestingUtilities
@testable import Subscription

final class DefaultSubscriptionInstrumentationTests: XCTestCase {

    var sut: DefaultSubscriptionInstrumentation!
    var mockWideEvent: WideEventMock!
    var mockInstrumentationPixelHandler: MockInstrumentationPixelHandler!

    override func setUp() {
        super.setUp()
        mockWideEvent = WideEventMock()
        mockInstrumentationPixelHandler = MockInstrumentationPixelHandler()
        sut = DefaultSubscriptionInstrumentation(wideEvent: mockWideEvent, pixelHandler: mockInstrumentationPixelHandler.eventMapping)
    }

    override func tearDown() {
        sut = nil
        mockWideEvent = nil
        mockInstrumentationPixelHandler = nil
        super.tearDown()
    }

    // MARK: - Purchase Flow Tests

    func testPurchaseAttempted_FiresPurchaseAttemptEvent() {
        // When
        sut.purchaseAttempted()

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 1)
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.first, .purchaseAttempt)
    }

    func testPurchaseFlowStarted_StartsWideEventWithCorrectData() {
        // Given
        let subscriptionId = "yearly-subscription"
        let origin = "funnel_settings"

        // When
        sut.purchaseFlowStarted(subscriptionId: subscriptionId,
                                freeTrialEligible: true,
                                origin: origin,
                                purchasePlatform: .appStore)

        // Then
        XCTAssertEqual(mockWideEvent.started.count, 1)
        let startedData = mockWideEvent.started.first as? SubscriptionPurchaseWideEventData
        XCTAssertNotNil(startedData)
        XCTAssertEqual(startedData?.purchasePlatform, .appStore)
        XCTAssertEqual(startedData?.subscriptionIdentifier, subscriptionId)
        XCTAssertEqual(startedData?.freeTrialEligible, true)
        XCTAssertEqual(startedData?.contextData.name, origin)
    }

    func testPurchaseFlowStarted_WithNilOrigin_StartsWideEventWithNilContextName() {
        // When
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: nil,
                                purchasePlatform: .appStore)

        // Then
        XCTAssertEqual(mockWideEvent.started.count, 1)
        let startedData = mockWideEvent.started.first as? SubscriptionPurchaseWideEventData
        XCTAssertNil(startedData?.contextData.name)
    }

    func testPurchaseFlowStarted_WithStripePlatform_SetsCorrectPlatform() {
        // When
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: true,
                                origin: nil,
                                purchasePlatform: .stripe)

        // Then
        let startedData = mockWideEvent.started.first as? SubscriptionPurchaseWideEventData
        XCTAssertEqual(startedData?.purchasePlatform, .stripe)
    }

    func testPurchaseSucceeded_FiresSuccessEventAndCompletesWideEvent() throws {
        // Given
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: "test_origin",
                                purchasePlatform: .appStore)
        sut.startPurchaseActivationTiming()

        // When
        sut.purchaseSucceeded(origin: "test_origin")

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 1)
        guard case .purchaseSuccess(let origin) = mockInstrumentationPixelHandler.firedEvents.first else {
            XCTFail("Expected purchaseSuccess event")
            return
        }
        XCTAssertEqual(origin, "test_origin")

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionPurchaseWideEventData)
        XCTAssertEqual(completion.1, .success(reason: nil))
    }

    func testPurchaseSucceeded_ClearsPurchaseWideEventData() {
        // Given
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: nil,
                                purchasePlatform: .appStore)

        // When
        sut.purchaseSucceeded(origin: nil)

        // Then - subsequent call should not complete anything since data was cleared
        sut.purchaseSucceeded(origin: nil)
        XCTAssertEqual(mockWideEvent.completions.count, 1)
    }

    func testPurchaseSucceededStripe_FiresStripeSuccessEventAndCompletesWideEvent() throws {
        // Given
        sut.purchaseFlowStarted(subscriptionId: nil,
                                freeTrialEligible: true,
                                origin: "stripe_origin",
                                purchasePlatform: .stripe)
        sut.startPurchaseActivationTiming()

        // When
        sut.purchaseSucceededStripe(origin: "stripe_origin")

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 1)
        guard case .purchaseSuccessStripe(let origin) = mockInstrumentationPixelHandler.firedEvents.first else {
            XCTFail("Expected purchaseSuccessStripe event")
            return
        }
        XCTAssertEqual(origin, "stripe_origin")

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionPurchaseWideEventData)
        XCTAssertEqual(completion.1, .success(reason: nil))
    }

    func testPurchaseFailed_FiresFailureEventAndCompletesWideEvent() throws {
        // Given
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: nil,
                                purchasePlatform: .appStore)
        let testError = NSError(domain: "test", code: 123)

        // When
        sut.purchaseFailed(error: testError, step: .accountCreate)

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 1)
        guard case .purchaseFailure(let step, _) = mockInstrumentationPixelHandler.firedEvents.first else {
            XCTFail("Expected purchaseFailure event")
            return
        }
        XCTAssertEqual(step, .accountCreate)

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionPurchaseWideEventData)
        XCTAssertEqual(completion.1, .failure)

        let completedData = completion.0 as? SubscriptionPurchaseWideEventData
        XCTAssertNotNil(completedData?.failingStep)
        XCTAssertEqual(completedData?.failingStep, .accountCreate)
    }

    func testPurchaseCancelled_CompletesWideEventWithCancelled() throws {
        // Given
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: nil,
                                purchasePlatform: .appStore)

        // When
        sut.purchaseCancelled()

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(completion.1, .cancelled)
    }

    func testPurchasePendingTransaction_FiresEventAndCompletesWideEventWithFailure() throws {
        // Given
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: nil,
                                purchasePlatform: .appStore)

        // When
        sut.purchasePendingTransaction()

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 1)
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.first, .purchasePendingTransaction)

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(completion.1, .failure)

        let completedData = completion.0 as? SubscriptionPurchaseWideEventData
        XCTAssertEqual(completedData?.failingStep, .accountPayment)
    }

    func testExistingSubscriptionFoundDuringPurchase_FiresEventAndDiscardsWideEvent() {
        // Given
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: nil,
                                purchasePlatform: .appStore)

        // When
        sut.existingSubscriptionFoundDuringPurchase()

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 1)
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.first, .existingSubscriptionFound)

        XCTAssertEqual(mockWideEvent.discarded.count, 1)
        XCTAssertTrue(mockWideEvent.discarded.first is SubscriptionPurchaseWideEventData)
        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    func testDiscardPurchaseFlow_DiscardsWideEvent() {
        // Given
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: nil,
                                purchasePlatform: .appStore)

        // When
        sut.discardPurchaseFlow()

        // Then
        XCTAssertEqual(mockWideEvent.discarded.count, 1)
        XCTAssertTrue(mockWideEvent.discarded.first is SubscriptionPurchaseWideEventData)
    }

    // MARK: - Purchase Duration Tests

    func testUpdatePurchaseAccountCreationDuration_UpdatesWideEventData() throws {
        // Given
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: nil,
                                purchasePlatform: .appStore)
        var duration = WideEvent.MeasuredInterval.startingNow()
        duration.complete()

        // When
        sut.updatePurchaseAccountCreationDuration(duration)

        // Then
        XCTAssertEqual(mockWideEvent.updates.count, 1)
        let updatedData = mockWideEvent.updates.first as? SubscriptionPurchaseWideEventData
        XCTAssertNotNil(updatedData?.createAccountDuration)
        XCTAssertNotNil(updatedData?.createAccountDuration?.end)
    }

    func testStartPurchaseActivationTiming_StartsActivationDuration() throws {
        // Given
        sut.purchaseFlowStarted(subscriptionId: "test",
                                freeTrialEligible: false,
                                origin: nil,
                                purchasePlatform: .appStore)

        // When
        sut.startPurchaseActivationTiming()

        // Then
        XCTAssertEqual(mockWideEvent.updates.count, 1)
        let updatedData = mockWideEvent.updates.first as? SubscriptionPurchaseWideEventData
        XCTAssertNotNil(updatedData?.activateAccountDuration?.start)
        XCTAssertNil(updatedData?.activateAccountDuration?.end)
    }

    // MARK: - Restore Store Flow Tests

    func testRestoreStoreStarted_FiresEventAndStartsWideEvent() throws {
        // Given
        let origin = "app_settings"

        // When
        sut.restoreStoreStarted(origin: origin)

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 1)
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.first, .restoreStoreStart)

        XCTAssertEqual(mockWideEvent.started.count, 1)
        let startedData = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionRestoreWideEventData)
        XCTAssertEqual(startedData.restorePlatform, .appleAccount)
        XCTAssertEqual(startedData.contextData.name, origin)
        XCTAssertNotNil(startedData.appleAccountRestoreDuration?.start)
    }

    func testRestoreStoreSucceeded_FiresEventAndCompletesWideEvent() throws {
        // Given
        sut.restoreStoreStarted(origin: "test")

        // When
        sut.restoreStoreSucceeded()

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 2) // start + success
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.last, .restoreStoreSuccess)

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionRestoreWideEventData)
        XCTAssertEqual(completion.1, .success)
    }

    func testRestoreStoreFailed_WithExpiredSubscription_FiresNotFoundEvent() throws {
        // Given
        sut.restoreStoreStarted(origin: "test")

        // When
        sut.restoreStoreFailed(error: .subscriptionExpired)

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.last, .restoreStoreFailureNotFound)

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(completion.1, .failure)

        let completedData = completion.0 as? SubscriptionRestoreWideEventData
        XCTAssertNotNil(completedData?.errorData)
    }

    func testRestoreStoreFailed_WithMissingAccount_FiresNotFoundEvent() throws {
        // Given
        sut.restoreStoreStarted(origin: "test")

        // When
        sut.restoreStoreFailed(error: .missingAccountOrTransactions)

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.last, .restoreStoreFailureNotFound)
    }

    func testRestoreStoreFailed_WithOtherError_FiresOtherEvent() throws {
        // Given
        sut.restoreStoreStarted(origin: "test")

        // When
        sut.restoreStoreFailed(error: .failedToObtainAccessToken)

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.last, .restoreStoreFailureOther)
    }

    func testRestoreStoreCancelled_DiscardsWideEvent() {
        // Given
        sut.restoreStoreStarted(origin: "test")

        // When
        sut.restoreStoreCancelled()

        // Then
        XCTAssertEqual(mockWideEvent.discarded.count, 1)
        XCTAssertTrue(mockWideEvent.discarded.first is SubscriptionRestoreWideEventData)
        XCTAssertEqual(mockWideEvent.completions.count, 0)
    }

    // MARK: - Restore Email Flow Tests

    func testBeginRestoreEmailAttempt_FiresEventAndStartsWideEvent() throws {
        // Given
        let origin = "purchase_offer"

        // When
        sut.beginRestoreEmailAttempt(origin: origin)

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 1)
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.first, .restoreEmailStart)

        XCTAssertEqual(mockWideEvent.started.count, 1)
        let startedData = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionRestoreWideEventData)
        XCTAssertEqual(startedData.restorePlatform, .emailAddress)
        XCTAssertEqual(startedData.contextData.name, origin)
        XCTAssertNotNil(startedData.emailAddressRestoreDuration?.start)
    }

    func testBeginRestoreEmailAttempt_WhenAlreadyActive_DoesNotStartNewFlow() {
        // Given
        sut.beginRestoreEmailAttempt(origin: "first")

        // When - try to start another one
        sut.beginRestoreEmailAttempt(origin: "second")

        // Then - only one flow should have started
        XCTAssertEqual(mockWideEvent.started.count, 1)
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.count, 1) // Only one event fired
        let startedData = mockWideEvent.started.first as? SubscriptionRestoreWideEventData
        XCTAssertEqual(startedData?.contextData.name, "first")
    }

    func testEndRestoreEmailAttempt_DiscardsWideEvent() {
        // Given
        sut.beginRestoreEmailAttempt(origin: "test")

        // When
        sut.endRestoreEmailAttempt()

        // Then
        XCTAssertEqual(mockWideEvent.discarded.count, 1)
        XCTAssertTrue(mockWideEvent.discarded.first is SubscriptionRestoreWideEventData)
    }

    func testEndRestoreEmailAttempt_AllowsNewAttemptToStart() {
        // Given
        sut.beginRestoreEmailAttempt(origin: "first")
        sut.endRestoreEmailAttempt()

        // When
        sut.beginRestoreEmailAttempt(origin: "second")

        // Then - new flow should be started
        XCTAssertEqual(mockWideEvent.started.count, 2)
        let secondStartedData = mockWideEvent.started.last as? SubscriptionRestoreWideEventData
        XCTAssertEqual(secondStartedData?.contextData.name, "second")
    }

    func testRestoreEmailSucceeded_FiresEventAndCompletesWideEvent() throws {
        // Given
        sut.beginRestoreEmailAttempt(origin: "test")

        // When
        sut.restoreEmailSucceeded()

        // Then
        XCTAssertEqual(mockInstrumentationPixelHandler.firedEvents.last, .restoreEmailSuccess)

        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionRestoreWideEventData)
        XCTAssertEqual(completion.1, .success)
    }

    func testRestoreEmailSucceeded_AllowsNewAttemptToStart() {
        // Given
        sut.beginRestoreEmailAttempt(origin: "first")
        sut.restoreEmailSucceeded()

        // When
        sut.beginRestoreEmailAttempt(origin: "second")

        // Then
        XCTAssertEqual(mockWideEvent.started.count, 2)
    }

    func testRestoreEmailFailed_CompletesWideEventWithFailure() throws {
        // Given
        sut.beginRestoreEmailAttempt(origin: "test")
        let testError = NSError(domain: "test", code: 456)

        // When
        sut.restoreEmailFailed(error: testError)

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(completion.1, .failure)

        let completedData = completion.0 as? SubscriptionRestoreWideEventData
        XCTAssertNotNil(completedData?.errorData)
    }

    func testRestoreEmailFailed_WithNilError_CompletesWithoutErrorData() throws {
        // Given
        sut.beginRestoreEmailAttempt(origin: "test")

        // When
        sut.restoreEmailFailed(error: nil)

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        let completedData = completion.0 as? SubscriptionRestoreWideEventData
        XCTAssertNil(completedData?.errorData)
    }

    func testUpdateEmailRestoreURL_UpdatesWideEventData() throws {
        // Given
        sut.beginRestoreEmailAttempt(origin: "test")

        // When
        sut.updateEmailRestoreURL(.activationFlowEmail)

        // Then
        XCTAssertEqual(mockWideEvent.updates.count, 1)
        let updatedData = try XCTUnwrap(mockWideEvent.updates.first as? SubscriptionRestoreWideEventData)
        XCTAssertEqual(updatedData.emailAddressRestoreLastURL, .activationFlowEmail)
    }

    // MARK: - Restore Background Check Tests

    func testRestoreBackgroundCheckStarted_StartsWideEvent() throws {
        // Given
        let origin = "pre_purchase_check"

        // When
        sut.restoreBackgroundCheckStarted(origin: origin)

        // Then
        XCTAssertEqual(mockWideEvent.started.count, 1)
        let startedData = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionRestoreWideEventData)
        XCTAssertEqual(startedData.restorePlatform, .purchaseBackgroundTask)
        XCTAssertEqual(startedData.contextData.name, origin)
        XCTAssertNotNil(startedData.appleAccountRestoreDuration?.start)
    }

    func testRestoreBackgroundCheckSucceeded_CompletesWideEventWithSuccess() throws {
        // Given
        sut.restoreBackgroundCheckStarted(origin: "test")

        // When
        sut.restoreBackgroundCheckSucceeded()

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionRestoreWideEventData)
        XCTAssertEqual(completion.1, .success(reason: nil))
    }

    func testRestoreBackgroundCheckFailed_CompletesWideEventWithFailure() throws {
        // Given
        sut.restoreBackgroundCheckStarted(origin: "test")
        let testError = NSError(domain: "test", code: 789)

        // When
        sut.restoreBackgroundCheckFailed(error: testError)

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(completion.1, .failure)

        let completedData = completion.0 as? SubscriptionRestoreWideEventData
        XCTAssertNotNil(completedData?.errorData)
    }

    // MARK: - Plan Change Flow Tests

    func testPlanChangeStarted_StartsWideEventWithCorrectData() throws {
        // Given
        let fromPlan = "monthly-plus"
        let toPlan = "yearly-pro"
        let origin = "settings"

        // When
        sut.planChangeStarted(from: fromPlan,
                              to: toPlan,
                              changeType: .upgrade,
                              origin: origin,
                              purchasePlatform: .appStore)

        // Then
        XCTAssertEqual(mockWideEvent.started.count, 1)
        let startedData = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionPlanChangeWideEventData)
        XCTAssertEqual(startedData.purchasePlatform, .appStore)
        XCTAssertEqual(startedData.fromPlan, fromPlan)
        XCTAssertEqual(startedData.toPlan, toPlan)
        XCTAssertEqual(startedData.changeType, .upgrade)
        XCTAssertEqual(startedData.contextData.name, origin)
        XCTAssertNotNil(startedData.paymentDuration?.start)
    }

    func testPlanChangeStarted_WithStripePlatform_SetsCorrectPlatform() throws {
        // When
        sut.planChangeStarted(from: "old",
                              to: "new",
                              changeType: .upgrade,
                              origin: nil,
                              purchasePlatform: .stripe)

        // Then
        let startedData = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionPlanChangeWideEventData)
        XCTAssertEqual(startedData.purchasePlatform, .stripe)
    }

    func testPlanChangeStarted_WithDowngrade_SetsCorrectChangeType() throws {
        // When
        sut.planChangeStarted(from: "yearly-pro",
                              to: "monthly-plus",
                              changeType: .downgrade,
                              origin: nil,
                              purchasePlatform: .appStore)

        // Then
        let startedData = try XCTUnwrap(mockWideEvent.started.first as? SubscriptionPlanChangeWideEventData)
        XCTAssertEqual(startedData.changeType, .downgrade)
    }

    func testPlanChangePaymentSucceeded_CompletesPaymentAndStartsConfirmation() throws {
        // Given
        sut.planChangeStarted(from: "old", to: "new", changeType: .upgrade, origin: nil, purchasePlatform: .appStore)

        // When
        sut.planChangePaymentSucceeded()

        // Then
        XCTAssertEqual(mockWideEvent.updates.count, 1)
        let updatedData = try XCTUnwrap(mockWideEvent.updates.first as? SubscriptionPlanChangeWideEventData)
        XCTAssertNotNil(updatedData.paymentDuration?.end) // Payment duration completed
        XCTAssertNotNil(updatedData.confirmationDuration?.start) // Confirmation started
        XCTAssertNil(updatedData.confirmationDuration?.end) // Confirmation not yet completed
    }

    func testPlanChangeSucceeded_CompletesWideEventWithSuccess() throws {
        // Given
        sut.planChangeStarted(from: "old", to: "new", changeType: .upgrade, origin: nil, purchasePlatform: .appStore)
        sut.planChangePaymentSucceeded()

        // When
        sut.planChangeSucceeded()

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertTrue(completion.0 is SubscriptionPlanChangeWideEventData)
        XCTAssertEqual(completion.1, .success)

        // Verify confirmation duration was completed
        XCTAssertEqual(mockWideEvent.updates.count, 2) // Payment + confirmation completion
    }

    func testPlanChangeFailed_CompletesWideEventWithFailure() throws {
        // Given
        sut.planChangeStarted(from: "old", to: "new", changeType: .upgrade, origin: nil, purchasePlatform: .appStore)
        let testError = NSError(domain: "test", code: 999)

        // When
        sut.planChangeFailed(error: testError, step: .payment)

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(completion.1, .failure)

        let completedData = completion.0 as? SubscriptionPlanChangeWideEventData
        XCTAssertEqual(completedData?.failingStep, .payment)
    }

    func testPlanChangeFailed_AtConfirmationStep_SetsCorrectFailingStep() throws {
        // Given
        sut.planChangeStarted(from: "old", to: "new", changeType: .upgrade, origin: nil, purchasePlatform: .appStore)
        sut.planChangePaymentSucceeded()
        let testError = NSError(domain: "test", code: 999)

        // When
        sut.planChangeFailed(error: testError, step: .confirmation)

        // Then
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        let completedData = completion.0 as? SubscriptionPlanChangeWideEventData
        XCTAssertEqual(completedData?.failingStep, .confirmation)
    }

    func testPlanChangeCancelled_CompletesWideEventWithCancelled() throws {
        // Given
        sut.planChangeStarted(from: "old", to: "new", changeType: .upgrade, origin: nil, purchasePlatform: .appStore)

        // When
        sut.planChangeCancelled()

        // Then
        XCTAssertEqual(mockWideEvent.completions.count, 1)
        let completion = try XCTUnwrap(mockWideEvent.completions.first)
        XCTAssertEqual(completion.1, .cancelled)
    }

    // MARK: - Edge Case Tests

    func testMethodsWithNoActiveFlow_DoNotCrash() {
        // These should all be no-ops when no flow is active
        sut.purchaseSucceeded(origin: nil)
        sut.purchaseSucceededStripe(origin: nil)
        sut.purchaseFailed(error: NSError(domain: "test", code: 0), step: .accountCreate)
        sut.purchaseCancelled()
        sut.purchasePendingTransaction()
        sut.existingSubscriptionFoundDuringPurchase()
        sut.discardPurchaseFlow()
        sut.updatePurchaseAccountCreationDuration(WideEvent.MeasuredInterval.startingNow())
        sut.startPurchaseActivationTiming()

        sut.restoreStoreSucceeded()
        sut.restoreStoreFailed(error: .missingAccountOrTransactions)
        sut.restoreStoreCancelled()
        sut.endRestoreEmailAttempt()
        sut.restoreEmailSucceeded()
        sut.restoreEmailFailed(error: nil)
        sut.restoreBackgroundCheckSucceeded()
        sut.restoreBackgroundCheckFailed(error: NSError(domain: "test", code: 0))
        sut.updateEmailRestoreURL(.activationFlowEmail)

        sut.planChangePaymentSucceeded()
        sut.planChangeSucceeded()
        sut.planChangeFailed(error: NSError(domain: "test", code: 0), step: .payment)
        sut.planChangeCancelled()

        // No assertions needed - just verify no crashes
        XCTAssertEqual(mockWideEvent.started.count, 0)
        XCTAssertEqual(mockWideEvent.completions.count, 0)
        XCTAssertEqual(mockWideEvent.discarded.count, 0)
    }

    func testRestoreFlows_CanRunSequentially() {
        // Given - run store restore
        sut.restoreStoreStarted(origin: "store")
        sut.restoreStoreSucceeded()

        // When - then run email restore
        sut.beginRestoreEmailAttempt(origin: "email")
        sut.restoreEmailSucceeded()

        // Then - both should have completed
        XCTAssertEqual(mockWideEvent.started.count, 2)
        XCTAssertEqual(mockWideEvent.completions.count, 2)
    }

    func testStripeAndAppStorePurchaseFlows_CanRunSequentially() throws {
        // Given - App Store purchase
        sut.purchaseFlowStarted(subscriptionId: "appstore-sub",
                                freeTrialEligible: true,
                                origin: "appstore",
                                purchasePlatform: .appStore)
        sut.purchaseSucceeded(origin: "appstore")

        // When - Stripe purchase
        sut.purchaseFlowStarted(subscriptionId: nil,
                                freeTrialEligible: true,
                                origin: "stripe",
                                purchasePlatform: .stripe)
        sut.purchaseSucceededStripe(origin: "stripe")

        // Then - both should have completed
        XCTAssertEqual(mockWideEvent.started.count, 2)
        XCTAssertEqual(mockWideEvent.completions.count, 2)

        let firstCompletion = mockWideEvent.completions[0].0 as? SubscriptionPurchaseWideEventData
        let secondCompletion = mockWideEvent.completions[1].0 as? SubscriptionPurchaseWideEventData
        XCTAssertEqual(firstCompletion?.purchasePlatform, .appStore)
        XCTAssertEqual(secondCompletion?.purchasePlatform, .stripe)
    }
}

// MARK: - Mock Instrumentation Pixel Handler

final class MockInstrumentationPixelHandler {
    var firedEvents: [SubscriptionInstrumentationEvent] = []

    lazy var eventMapping: EventMapping<SubscriptionInstrumentationEvent> = {
        EventMapping { [weak self] event, _, _, onComplete in
            self?.firedEvents.append(event)
            onComplete(nil)
        }
    }()
}

// MARK: - SubscriptionInstrumentationEvent Equatable

extension SubscriptionInstrumentationEvent: Equatable {
    public static func == (lhs: SubscriptionInstrumentationEvent, rhs: SubscriptionInstrumentationEvent) -> Bool {
        switch (lhs, rhs) {
        case (.purchaseAttempt, .purchaseAttempt),
             (.purchasePendingTransaction, .purchasePendingTransaction),
             (.existingSubscriptionFound, .existingSubscriptionFound),
             (.restoreStoreStart, .restoreStoreStart),
             (.restoreStoreSuccess, .restoreStoreSuccess),
             (.restoreStoreFailureNotFound, .restoreStoreFailureNotFound),
             (.restoreStoreFailureOther, .restoreStoreFailureOther),
             (.restoreEmailStart, .restoreEmailStart),
             (.restoreEmailSuccess, .restoreEmailSuccess):
            return true
        case (.purchaseSuccess(let lhsOrigin), .purchaseSuccess(let rhsOrigin)):
            return lhsOrigin == rhsOrigin
        case (.purchaseSuccessStripe(let lhsOrigin), .purchaseSuccessStripe(let rhsOrigin)):
            return lhsOrigin == rhsOrigin
        case (.purchaseFailure(let lhsStep, _), .purchaseFailure(let rhsStep, _)):
            return lhsStep == rhsStep
        default:
            return false
        }
    }
}
