//
//  SubscriptionWidePixelTests.swift
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

final class SubscriptionWidePixelTests: XCTestCase {

    private var widePixel: WidePixel!
    private var firedPixels: [(name: String, parameters: [String: String])] = []
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        widePixel = WidePixel(storage: WidePixelUserDefaultsStorage(userDefaults: testDefaults), pixelKitProvider: { PixelKit.shared })
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
            dryRun: false,
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
        let context = WidePixelContextData(name: "funnel_onboarding_ios")
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appStore, contextData: context)

        widePixel.startFlow(subscriptionData)

        var updatedData = subscriptionData
        updatedData.subscriptionIdentifier = "ddg.privacy.pro.monthly.renews.us"
        updatedData.freeTrialEligible = true
        widePixel.updateFlow(updatedData)

        // User creates account (2.5s)
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 2.5)
        var flow0 = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        flow0.createAccountDuration = WidePixel.MeasuredInterval(start: t0, end: t1)
        widePixel.updateFlow(flow0)

        // User completes purchase (1.2s)
        let t2 = Date(timeIntervalSince1970: 10)
        let t3 = Date(timeIntervalSince1970: 11.2)
        var flow1 = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        flow1.completePurchaseDuration = WidePixel.MeasuredInterval(start: t2, end: t3)
        widePixel.updateFlow(flow1)

        // Account gets activated (7.5s)
        let t4 = Date(timeIntervalSince1970: 20)
        let t5 = Date(timeIntervalSince1970: 27.5)
        var flow2 = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        flow2.activateAccountDuration = WidePixel.MeasuredInterval(start: t4, end: t5)
        widePixel.updateFlow(flow2)

        // Complete the flow successfully
        let expectation = XCTestExpectation(description: "Pixel fired")
        let finalData = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        widePixel.completeFlow(finalData, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(firedPixels.count, 1)
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

        XCTAssertEqual(widePixel.getAllFlowData(SubscriptionPurchaseWidePixelData.self).count, 0)
    }

    func testSuccessfulStripeSubscriptionFlow() throws {
        let context = WidePixelContextData(name: "funnel_onboarding_ios")
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .stripe, contextData: context)

        widePixel.startFlow(subscriptionData)

        var updated = subscriptionData
        updated.subscriptionIdentifier = "ddg.privacy.pro.yearly.renews.us"
        updated.freeTrialEligible = false
        widePixel.updateFlow(updated)

        // Complete flow with timing data (simulate measured steps)
        var f = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        f.createAccountDuration = WidePixel.MeasuredInterval(start: Date(), end: Date())
        f.completePurchaseDuration = WidePixel.MeasuredInterval(start: Date(), end: Date())
        f.activateAccountDuration = WidePixel.MeasuredInterval(start: Date(), end: Date())
        widePixel.updateFlow(f)

        // Complete the flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Verify Stripe-specific parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "stripe")
        XCTAssertEqual(params["feature.data.ext.free_trial_eligible"], "false")
        XCTAssertEqual(params["context.name"], "funnel_onboarding_ios")
    }

    // MARK: - Failed Subscription Flow Tests

    func testFailedSubscriptionFlowAccountCreation() throws {
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appStore)
        widePixel.startFlow(subscriptionData)

        // Account creation fails
        let accountError = NSError(domain: "AccountCreationError", code: 500, userInfo: [
            NSLocalizedDescriptionKey: "Failed to create account",
            NSUnderlyingErrorKey: NSError(domain: "NetworkError", code: -1009, userInfo: nil)
        ])

        var failed = subscriptionData
        failed.markAsFailed(at: .accountCreate, error: accountError)
        widePixel.updateFlow(failed)
        var f1 = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        f1.createAccountDuration = WidePixel.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 8))
        widePixel.updateFlow(f1) // 8s -> 10000 bucket

        // Complete the failed flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, status: .failure) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters

        XCTAssertEqual(params["feature.status"], "FAILURE")
        XCTAssertEqual(params["feature.data.ext.failing_step"], "ACCOUNT_CREATE")
        XCTAssertEqual(params["feature.data.error.domain"], "AccountCreationError")
        XCTAssertEqual(params["feature.data.error.code"], "500")
        XCTAssertEqual(params["feature.data.error.underlying_domain"], "NetworkError")
        XCTAssertEqual(params["feature.data.error.underlying_code"], "-1009")
        XCTAssertEqual(params["feature.data.ext.account_creation_latency_ms_bucketed"], "10000") // Bucketed from 8000
    }

    func testFailedSubscriptionFlowStoreKitPurchase() throws {
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appStore)
        widePixel.startFlow(subscriptionData)

        var s1 = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        s1.createAccountDuration = WidePixel.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1.5)) // 1.5s -> 5000
        widePixel.updateFlow(s1)

        let storeKitError = NSError(domain: "SKErrorDomain", code: 2)

        var currentForFailure = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        currentForFailure.markAsFailed(at: .accountPayment, error: storeKitError)
        widePixel.updateFlow(currentForFailure)
        var f2 = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        f2.completePurchaseDuration = WidePixel.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 15))
        widePixel.updateFlow(f2) // 15s -> 30000

        // Complete the failed flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, status: .failure) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Verify StoreKit failure parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters

        XCTAssertEqual(params["feature.status"], "FAILURE")
        XCTAssertEqual(params["feature.data.ext.failing_step"], "ACCOUNT_PAYMENT")
        XCTAssertEqual(params["feature.data.error.domain"], "SKErrorDomain")
        XCTAssertEqual(params["feature.data.error.code"], "2")
        XCTAssertEqual(params["feature.data.ext.account_creation_latency_ms_bucketed"], "5000") // Successful step
        XCTAssertEqual(params["feature.data.ext.account_payment_latency_ms_bucketed"], "30000") // Failed step, bucketed from 15000
    }

    // MARK: - Cancelled/Timeout Flow Tests

    func testCancelledSubscriptionFlow() throws {
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appStore)
        widePixel.startFlow(subscriptionData)

        var c1 = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        c1.createAccountDuration = WidePixel.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2)) // 2s -> 5000
        widePixel.updateFlow(c1)
        // No purchase completion timing since it was cancelled

        // Complete the cancelled flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, status: .cancelled) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Verify cancellation parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "CANCELLED")
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "app_store")
        XCTAssertEqual(params["feature.data.ext.account_creation_latency_ms_bucketed"], "5000")
        XCTAssertNil(params["feature.data.ext.account_payment_latency_ms_bucketed"])
        XCTAssertNil(params["feature.data.ext.failing_step"])
    }

    func testTimeoutSubscriptionFlow() throws {
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .stripe)
        widePixel.startFlow(subscriptionData)

        // Flow times out during account activation
        var t = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        t.createAccountDuration = WidePixel.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 2)) // 2s -> 5000
        t.completePurchaseDuration = WidePixel.MeasuredInterval(start: Date(timeIntervalSince1970: 10), end: Date(timeIntervalSince1970: 12.5)) // 2.5s -> 5000
        t.activateAccountDuration = WidePixel.MeasuredInterval(start: Date(timeIntervalSince1970: 20), end: Date(timeIntervalSince1970: 85)) // 65s -> 60000
        widePixel.updateFlow(t)

        // Complete the timeout flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, status: .unknown(reason: "activation_timeout")) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Verify timeout parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "UNKNOWN")
        XCTAssertEqual(params["feature.status_reason"], "activation_timeout")
        XCTAssertEqual(params["feature.data.ext.account_activation_latency_ms_bucketed"], "300000") // Max bucket
    }

    func testMultipleFlowCompletionsInSequence() throws {
        for i in 1...3 {
            let subscriptionData = SubscriptionPurchaseWidePixelData(
                purchasePlatform: .appStore,
                subscriptionIdentifier: "subscription-\(i)"
            )

            widePixel.startFlow(subscriptionData)

            let expectation = XCTestExpectation(description: "Pixel \(i) fired")
            widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, status: .success) { success, error in
                XCTAssertTrue(success)
                XCTAssertNil(error)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }

        // Should have fired 3 pixels
        XCTAssertEqual(firedPixels.count, 3)

        // Each should have different subscription identifiers
        for (index, pixel) in firedPixels.enumerated() {
            XCTAssertEqual(pixel.parameters["feature.data.ext.subscription_identifier"], "subscription-\(index + 1)")
        }
    }

}
