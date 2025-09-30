//
//  SubscriptionWideEventTests.swift
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
@testable import PixelKit

final class SubscriptionWideEventTests: XCTestCase {

    private var wideEvent: WideEvent!
    private var firedPixels: [(name: String, parameters: [String: String])] = []
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        wideEvent = WideEvent(storage: WideEventUserDefaultsStorage(userDefaults: testDefaults), pixelKitProvider: { PixelKit.shared })
        firedPixels.removeAll()
        setupMockPixelKit()
    }

    override func tearDown() {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        PixelKit.tearDown()

        super.tearDown()
    }

    private func setupMockPixelKit() {
        let mockFireRequest: PixelKit.FireRequest = { pixelName, headers, parameters, allowedQueryReservedCharacters, callBackOnMainThread, onComplete in
            self.firedPixels.append((name: pixelName, parameters: parameters))
            DispatchQueue.main.async {
                onComplete(true, nil)
            }
        }

        PixelKit.setUp(
            dryRun: false, // We set a mock `fireRequest` value to ensure no network requests are actually sent
            appVersion: "1.0.0",
            source: "test",
            defaultHeaders: [:],
            dateGenerator: Date.init,
            defaults: testDefaults,
            fireRequest: mockFireRequest
        )
    }

    // MARK: - Test Utilities

    private func makeTestError(domain: String = "TestDomain", code: Int = 999) -> NSError {
        return NSError(domain: domain, code: code, userInfo: [
            NSLocalizedDescriptionKey: "Test error",
            NSUnderlyingErrorKey: NSError(domain: "UnderlyingDomain", code: 123)
        ])
    }

    private func waitForPixelFired(timeout: TimeInterval = 1.0) {
        let expectation = XCTestExpectation(description: "Pixel fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
    }

    // MARK: - Successful Subscription Flow Tests

    func testSuccessfulAppStoreSubscriptionFlow() throws {
        let context = WideEventContextData(name: "funnel_onboarding_ios")
        let subscriptionData = SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: "ddg.privacy.pro.monthly.renews.us",
            freeTrialEligible: true,
            contextData: context
        )

        wideEvent.startFlow(subscriptionData)

        subscriptionData.subscriptionIdentifier = "ddg.privacy.pro.monthly.renews.us"
        subscriptionData.freeTrialEligible = true
        wideEvent.updateFlow(subscriptionData)

        // User creates account (2.5s)
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 2.5)
        let flow0 = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        flow0.createAccountDuration = WideEvent.MeasuredInterval(start: t0, end: t1)
        wideEvent.updateFlow(flow0)

        // User completes purchase (1s)
        let t2 = Date(timeIntervalSince1970: 10)
        let t3 = Date(timeIntervalSince1970: 11)
        let flow1 = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        flow1.completePurchaseDuration = WideEvent.MeasuredInterval(start: t2, end: t3)
        wideEvent.updateFlow(flow1)

        // Account gets activated (7.5s)
        let t4 = Date(timeIntervalSince1970: 20)
        let t5 = Date(timeIntervalSince1970: 27.5)
        let flow2 = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        flow2.activateAccountDuration = WideEvent.MeasuredInterval(start: t4, end: t5)
        wideEvent.updateFlow(flow2)

        // Complete the flow successfully
        let expectation = XCTestExpectation(description: "Pixel fired")
        let finalData = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        wideEvent.completeFlow(finalData, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let firedPixel = firedPixels[0]
        XCTAssertTrue(firedPixel.name.contains("wide_subscription_purchase"))

        let params = firedPixel.parameters
        XCTAssertEqual(params["feature.status"], "SUCCESS")
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "app_store")
        XCTAssertEqual(params["feature.data.ext.subscription_identifier"], "ddg.privacy.pro.monthly.renews.us")
        XCTAssertEqual(params["feature.data.ext.free_trial_eligible"], "true")
        XCTAssertEqual(params["feature.data.ext.account_creation_latency_ms_bucketed"], "5000")
        XCTAssertEqual(params["feature.data.ext.account_payment_latency_ms_bucketed"], "5000")
        XCTAssertEqual(params["feature.data.ext.account_activation_latency_ms_bucketed"], "10000")
        XCTAssertEqual(params["context.name"], "funnel_onboarding_ios")

        XCTAssertNotNil(params["app.name"])
        XCTAssertNotNil(params["app.version"])
        XCTAssertNotNil(params["global.platform"])
        XCTAssertEqual(params["global.type"], "app")
        XCTAssertEqual(params["global.sample_rate"], "1.0")

        XCTAssertEqual(wideEvent.getAllFlowData(SubscriptionPurchaseWideEventData.self).count, 0)
    }

    func testSuccessfulStripeSubscriptionFlow() throws {
        let context = WideEventContextData(name: "funnel_onboarding_ios")
        let subscriptionData = SubscriptionPurchaseWideEventData(
            purchasePlatform: .stripe,
            subscriptionIdentifier: "ddg.privacy.pro.yearly.renews.us",
            freeTrialEligible: false,
            contextData: context
        )

        wideEvent.startFlow(subscriptionData)

        let updated = subscriptionData
        updated.subscriptionIdentifier = "ddg.privacy.pro.yearly.renews.us"
        updated.freeTrialEligible = false
        wideEvent.updateFlow(updated)

        let flow = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        flow.createAccountDuration = WideEvent.MeasuredInterval(start: Date(), end: Date())
        flow.completePurchaseDuration = WideEvent.MeasuredInterval(start: Date(), end: Date())
        flow.activateAccountDuration = WideEvent.MeasuredInterval(start: Date(), end: Date())
        wideEvent.updateFlow(flow)

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "stripe")
        XCTAssertEqual(params["feature.data.ext.free_trial_eligible"], "false")
        XCTAssertEqual(params["context.name"], "funnel_onboarding_ios")
    }

    // MARK: - Failed Subscription Flow Tests

    func testFailedSubscriptionFlowAccountCreation() throws {
        let subscriptionData = SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: "ddg.privacy.pro.monthly.renews.us",
            freeTrialEligible: true,
            contextData: WideEventContextData()
        )
        wideEvent.startFlow(subscriptionData)

        // Account creation fails
        let accountError = NSError(domain: "Error", code: 123, userInfo: [
            NSLocalizedDescriptionKey: "Failed to create account",
            NSUnderlyingErrorKey: NSError(domain: "UnderlyingError", code: 456, userInfo: nil)
        ])

        let failed = subscriptionData
        failed.markAsFailed(at: .accountCreate, error: accountError)
        wideEvent.updateFlow(failed)
        let f1 = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        f1.createAccountDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 8))
        wideEvent.updateFlow(f1) // 8s -> 10000 bucket

        // Complete the failed flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id, status: .failure) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters

        XCTAssertEqual(params["feature.status"], "FAILURE")
        XCTAssertEqual(params["feature.data.ext.failing_step"], "ACCOUNT_CREATE")
        XCTAssertEqual(params["feature.data.error.domain"], "Error")
        XCTAssertEqual(params["feature.data.error.code"], "123")
        XCTAssertEqual(params["feature.data.error.underlying_domain"], "UnderlyingError")
        XCTAssertEqual(params["feature.data.error.underlying_code"], "456")
        XCTAssertEqual(params["feature.data.ext.account_creation_latency_ms_bucketed"], "10000") // Bucketed from 8000
    }

    func testFailedSubscriptionFlowStoreKitPurchase() throws {
        let subscriptionData = SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: "ddg.privacy.pro.monthly.renews.us",
            freeTrialEligible: true,
            contextData: WideEventContextData()
        )
        wideEvent.startFlow(subscriptionData)

        let s1 = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        s1.createAccountDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1.5)) // 1.5s -> 5000
        wideEvent.updateFlow(s1)

        let storeKitError = NSError(domain: "SKErrorDomain", code: 2)

        let currentForFailure = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        currentForFailure.markAsFailed(at: .accountPayment, error: storeKitError)
        wideEvent.updateFlow(currentForFailure)
        let f2 = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        f2.completePurchaseDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 15))
        wideEvent.updateFlow(f2) // 15s -> 30000

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id, status: .failure) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters

        XCTAssertEqual(params["feature.status"], "FAILURE")
        XCTAssertEqual(params["feature.data.ext.failing_step"], "ACCOUNT_PAYMENT")
        XCTAssertEqual(params["feature.data.error.domain"], "SKErrorDomain")
        XCTAssertEqual(params["feature.data.error.code"], "2")
        XCTAssertEqual(params["feature.data.ext.account_creation_latency_ms_bucketed"], "5000")
        XCTAssertEqual(params["feature.data.ext.account_payment_latency_ms_bucketed"], "30000")
    }

    // MARK: - Cancelled/Timeout Flow Tests

    func testCancelledSubscriptionFlow() throws {
        let subscriptionData = SubscriptionPurchaseWideEventData(
            purchasePlatform: .appStore,
            subscriptionIdentifier: "ddg.privacy.pro.monthly.renews.us",
            freeTrialEligible: false,
            contextData: WideEventContextData()
        )
        wideEvent.startFlow(subscriptionData)

        let c1 = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        c1.createAccountDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2)) // 2s -> 5000
        wideEvent.updateFlow(c1)

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id, status: .cancelled) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "CANCELLED")
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "app_store")
        XCTAssertEqual(params["feature.data.ext.account_creation_latency_ms_bucketed"], "5000")
        XCTAssertNil(params["feature.data.ext.account_payment_latency_ms_bucketed"])
        XCTAssertNil(params["feature.data.ext.failing_step"])
    }

    func testTimeoutSubscriptionFlow() throws {
        let subscriptionData = SubscriptionPurchaseWideEventData(
            purchasePlatform: .stripe,
            subscriptionIdentifier: "ddg.privacy.pro.yearly.renews.us",
            freeTrialEligible: false,
            contextData: WideEventContextData()
        )
        wideEvent.startFlow(subscriptionData)

        var t = wideEvent.getFlowData(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id)!
        t.createAccountDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2)) // 2s -> 5000
        t.completePurchaseDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 12.5)) // 2.5s -> 5000
        t.activateAccountDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 20), end: Date(timeIntervalSince1970: 85)) // 65s -> 60000
        wideEvent.updateFlow(t)

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(SubscriptionPurchaseWideEventData.self, globalID: subscriptionData.globalData.id, status: .unknown(reason: "activation_timeout")) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "UNKNOWN")
        XCTAssertEqual(params["feature.status_reason"], "activation_timeout")
        XCTAssertEqual(params["feature.data.ext.account_activation_latency_ms_bucketed"], "300000") // Max bucket
    }

}
