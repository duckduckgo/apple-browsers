//
//  SubscriptionWidePixelIntegrationTests.swift
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

final class SubscriptionWidePixelIntegrationTests: XCTestCase {
    
    private var mockPixelKit: PixelKit!
    private var firedPixels: [(name: String, parameters: [String: String])] = []
    private var widePixel: WidePixel!
    
    override func setUp() {
        super.setUp()
        widePixel = WidePixel(userDefaults: UserDefaults(suiteName: "SubscriptionWidePixelIntegrationTests") ?? .standard,
                              pixelKitProvider: { PixelKit.shared })
        widePixel.clearAllFlows()
        firedPixels.removeAll()
        setupMockPixelKit()
    }
    
    override func tearDown() {
        widePixel.clearAllFlows()
        PixelKit.tearDown()
        super.tearDown()
    }
    
    private func setupMockPixelKit() {
        // Create a mock fire request that captures pixels instead of sending them
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
            defaults: UserDefaults(suiteName: "SubscriptionWidePixelIntegrationTests") ?? UserDefaults.standard,
            fireRequest: mockFireRequest
        )
    }
    
    // MARK: - Successful Subscription Flow Tests
    
    func testSuccessfulAppStoreSubscriptionFlow() throws {
        // Given - Start subscription flow
        var subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        subscriptionData.setContext(name: "funnel_onboarding_ios")
        widePixel.startFlow(subscriptionData)
        
        // When - User selects App Store purchase
        var updatedData = subscriptionData
        updatedData.subscriptionIdentifier = "ddg.privacy.pro.monthly.renews.us"
        updatedData.freeTrialEligible = true
        widePixel.updateFlow(updatedData)
        
        // User creates account (2.5s)
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 2.5)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: t0)
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: t1)
        
        // User completes purchase (1.2s)
        let t2 = Date(timeIntervalSince1970: 10)
        let t3 = Date(timeIntervalSince1970: 11.2)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.completePurchaseDuration, at: t2)
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.completePurchaseDuration, at: t3)
        
        // Account gets activated (0.8s)
        let t4 = Date(timeIntervalSince1970: 20)
        let t5 = Date(timeIntervalSince1970: 20.8)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.activateAccountDuration, at: t4)
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.activateAccountDuration, at: t5)
        
        // Complete the flow successfully
        let expectation = XCTestExpectation(description: "Pixel fired")
        let finalData = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        widePixel.completeFlow(finalData, finalStatus: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then - Verify pixel was fired with correct parameters
        XCTAssertEqual(firedPixels.count, 1)
        
        let firedPixel = firedPixels[0]
        XCTAssertTrue(firedPixel.name.contains("wide_subscription_purchase"))
        
        let params = firedPixel.parameters
        XCTAssertEqual(params["feature.status"], "SUCCESS")
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "appstore")
        XCTAssertEqual(params["feature.data.ext.subscription_identifier"], "ddg.privacy.pro.monthly.renews.us")
        XCTAssertEqual(params["feature.data.ext.free_trial_eligible"], "true")
        XCTAssertEqual(params["feature.data.ext.create_account_latency_ms_bucketed"], "5000") // Bucketed from 2500
        XCTAssertEqual(params["feature.data.ext.complete_purchase_latency_ms_bucketed"], "5000") // Bucketed from 1200
        XCTAssertEqual(params["feature.data.ext.activate_account_latency_ms_bucketed"], "1000") // Bucketed from 800
        XCTAssertEqual(params["context.name"], "funnel_onboarding_ios")
        
        // Global and app parameters should be present
        XCTAssertNotNil(params["global.platform"])
        XCTAssertEqual(params["global.type"], "app")
        XCTAssertEqual(params["global.sample_rate"], "1.0")
        XCTAssertNotNil(params["app.name"])
        XCTAssertNotNil(params["app.version"])
        
        // Flow should be cleared after completion
        XCTAssertEqual(widePixel.getAllFlowData(SubscriptionPurchaseWidePixelData.self).count, 0)
    }
    
    func testSuccessfulStripeSubscriptionFlow() throws {
        // Given - Start subscription flow for Stripe
        var subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .stripe)
        subscriptionData.setContext(name: "direct_purchase")
        widePixel.startFlow(subscriptionData)
        
        // When - User selects Stripe purchase
        var updated = subscriptionData
        updated.subscriptionIdentifier = "ddg.privacy.pro.yearly.renews.us"
        updated.freeTrialEligible = false
        widePixel.updateFlow(updated)
        
        // Complete flow with timing data (simulate measured steps)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration)
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.completePurchaseDuration)
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.completePurchaseDuration)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.activateAccountDuration)
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.activateAccountDuration)
        
        // Complete the flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, finalStatus: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then - Verify Stripe-specific parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "stripe")
        XCTAssertEqual(params["feature.data.ext.free_trial_eligible"], "false")
        XCTAssertEqual(params["context.name"], "direct_purchase")
    }
    
    // MARK: - Failed Subscription Flow Tests
    
    func testFailedSubscriptionFlowAccountCreation() throws {
        // Given - Start subscription flow
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        widePixel.startFlow(subscriptionData)
        
        // When - Account creation fails
        let accountError = NSError(domain: "AccountCreationError", code: 500, userInfo: [
            NSLocalizedDescriptionKey: "Failed to create account",
            NSUnderlyingErrorKey: NSError(domain: "NetworkError", code: -1009, userInfo: nil)
        ])
        
        var failed = subscriptionData
        failed.markAsFailed(at: .accountCreate, error: accountError)
        widePixel.updateFlow(failed)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 0))
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 8)) // 8s -> 10000 bucket
        
        // Complete the failed flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, finalStatus: .failure) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then - Verify failure parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "FAILURE")
        XCTAssertEqual(params["feature.data.ext.failing_step"], "ACCOUNT_CREATE")
        XCTAssertEqual(params["feature.data.error.domain"], "AccountCreationError")
        XCTAssertEqual(params["feature.data.error.code"], "500")
        XCTAssertEqual(params["feature.data.error.underlying_domain"], "NetworkError")
        XCTAssertEqual(params["feature.data.error.underlying_code"], "-1009")
        XCTAssertEqual(params["feature.data.ext.create_account_latency_ms_bucketed"], "10000") // Bucketed from 8000
    }
    
    func testFailedSubscriptionFlowStoreKitPurchase() throws {
        // Given - Start subscription flow and get through account creation
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        widePixel.startFlow(subscriptionData)

        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 0))
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 1.5)) // 1.5s -> 5000
        
        // When - StoreKit purchase fails
        let storeKitError = NSError(domain: "SKErrorDomain", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Cannot connect to iTunes Store"
        ])
        
        var currentForFailure = widePixel.getFlowData(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id)!
        currentForFailure.markAsFailed(at: .storekitPurchase, error: storeKitError)
        widePixel.updateFlow(currentForFailure)
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.completePurchaseDuration, at: Date(timeIntervalSince1970: 0))
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.completePurchaseDuration, at: Date(timeIntervalSince1970: 15)) // 15s -> 30000
        
        // Complete the failed flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, finalStatus: .failure) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then - Verify StoreKit failure parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "FAILURE")
        XCTAssertEqual(params["feature.data.ext.failing_step"], "STOREKIT_PURCHASE")
        XCTAssertEqual(params["feature.data.error.domain"], "SKErrorDomain")
        XCTAssertEqual(params["feature.data.error.code"], "2")
        XCTAssertEqual(params["feature.data.ext.create_account_latency_ms_bucketed"], "5000") // Successful step
        XCTAssertEqual(params["feature.data.ext.complete_purchase_latency_ms_bucketed"], "30000") // Failed step, bucketed from 15000
    }
    
    // MARK: - Cancelled/Timeout Flow Tests
    
    func testCancelledSubscriptionFlow() throws {
        // Given - Start subscription flow
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        widePixel.startFlow(subscriptionData)

        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 0))
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 2)) // 2s -> 5000
        // No purchase completion timing since it was cancelled
        
        // Complete the cancelled flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, finalStatus: .cancelled) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then - Verify cancellation parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "CANCELLED")
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "appstore")
        XCTAssertEqual(params["feature.data.ext.create_account_latency_ms_bucketed"], "5000")
        XCTAssertNil(params["feature.data.ext.complete_purchase_latency_ms_bucketed"])
        XCTAssertNil(params["feature.data.ext.failing_step"])
    }
    
    func testTimeoutSubscriptionFlow() throws {
        // Given - Start subscription flow
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .stripe)
        widePixel.startFlow(subscriptionData)
        
        // When - Flow times out during account activation
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 0))
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 2)) // 2s -> 5000
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.completePurchaseDuration, at: Date(timeIntervalSince1970: 10))
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.completePurchaseDuration, at: Date(timeIntervalSince1970: 12.5)) // 2.5s -> 5000
        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.activateAccountDuration, at: Date(timeIntervalSince1970: 20))
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.activateAccountDuration, at: Date(timeIntervalSince1970: 85)) // 65s -> 60000
        
        // Complete the timeout flow
        let expectation = XCTestExpectation(description: "Pixel fired")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, finalStatus: .unknown(reason: "activation_timeout")) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // Then - Verify timeout parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "UNKNOWN")
        XCTAssertEqual(params["feature.status.unknown-status-reason"], "activation_timeout")
        XCTAssertEqual(params["feature.data.ext.activate_account_latency_ms_bucketed"], "60000") // Max bucket
    }
    
    // MARK: - Edge Case Tests
    
    func testCompleteFlowWithoutPixelKitInitialized() throws {
        // Given - Clear PixelKit
        PixelKit.tearDown()
        
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        widePixel.startFlow(subscriptionData)
        
        // When - Try to complete flow without PixelKit
        let expectation = XCTestExpectation(description: "Completion called")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, finalStatus: .success) { success, error in
            // Then - Should fail gracefully
            XCTAssertFalse(success)
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        // No pixels should have been fired
        XCTAssertEqual(firedPixels.count, 0)
    }
    
    func testMultipleFlowCompletionsInSequence() throws {
        // Test completing multiple subscription flows in sequence
        for i in 1...3 {
            let subscriptionData = SubscriptionPurchaseWidePixelData(
                purchasePlatform: .appstore,
                subscriptionIdentifier: "subscription-\(i)"
            )
            
            widePixel.startFlow(subscriptionData)
            
            let expectation = XCTestExpectation(description: "Pixel \(i) fired")
            widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, finalStatus: .success) { success, error in
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
