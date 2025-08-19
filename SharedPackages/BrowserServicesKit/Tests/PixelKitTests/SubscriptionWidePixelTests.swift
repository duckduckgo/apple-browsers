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
    
    // MARK: - Test Infrastructure
    
    private var widePixel: WidePixel!
    private var firedPixels: [(name: String, parameters: [String: String])] = []
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!
    
    override func setUp() {
        super.setUp()
        setupTestInfrastructure()
    }
    
    override func tearDown() {
        cleanupTestInfrastructure()
        super.tearDown()
    }
    
    private func setupTestInfrastructure() {
        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        widePixel = WidePixel(userDefaults: testDefaults, pixelKitProvider: { PixelKit.shared })
        widePixel.clearAllFlows()
        firedPixels.removeAll()
        setupMockPixelKit()
    }
    
    private func cleanupTestInfrastructure() {
        widePixel?.clearAllFlows()
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        PixelKit.tearDown()
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
        var subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        subscriptionData.setContext(name: "funnel_onboarding_ios")
        widePixel.startFlow(subscriptionData)
        
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
        
        // Verify pixel was fired with correct parameters
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
        var subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .stripe)
        subscriptionData.setContext(name: "direct_purchase")
        widePixel.startFlow(subscriptionData)
        
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
        
        // Verify Stripe-specific parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "stripe")
        XCTAssertEqual(params["feature.data.ext.free_trial_eligible"], "false")
        XCTAssertEqual(params["context.name"], "direct_purchase")
    }
    
    // MARK: - Failed Subscription Flow Tests
    
    func testFailedSubscriptionFlowAccountCreation() throws {
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        widePixel.startFlow(subscriptionData)
        
        // Account creation fails
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
        
        // Verify failure parameters
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
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        widePixel.startFlow(subscriptionData)

        widePixel.startMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 0))
        widePixel.stopMeasuring(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, keyPath: \.createAccountDuration, at: Date(timeIntervalSince1970: 1.5)) // 1.5s -> 5000
        
        // StoreKit purchase fails
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
        
        // Verify StoreKit failure parameters
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
        
        // Verify cancellation parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "CANCELLED")
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "appstore")
        XCTAssertEqual(params["feature.data.ext.create_account_latency_ms_bucketed"], "5000")
        XCTAssertNil(params["feature.data.ext.complete_purchase_latency_ms_bucketed"])
        XCTAssertNil(params["feature.data.ext.failing_step"])
    }
    
    func testTimeoutSubscriptionFlow() throws {
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .stripe)
        widePixel.startFlow(subscriptionData)
        
        // Flow times out during account activation
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
        
        // Verify timeout parameters
        XCTAssertEqual(firedPixels.count, 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "UNKNOWN")
        XCTAssertEqual(params["feature.status.unknown-status-reason"], "activation_timeout")
        XCTAssertEqual(params["feature.data.ext.activate_account_latency_ms_bucketed"], "60000") // Max bucket
    }
    
    // MARK: - Subscription Data Model Tests
    
    func testSubscriptionDataConvenienceMethods() throws {
        var subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        
        // Test markAsFailed
        let testError = NSError(domain: "TestDomain", code: 456, userInfo: nil)
        subscriptionData.markAsFailed(at: .storekitPurchase, error: testError)
        
        XCTAssertEqual(subscriptionData.failingStep, .storekitPurchase)
        XCTAssertEqual(subscriptionData.errorData?.domain, "TestDomain")
        XCTAssertEqual(subscriptionData.errorData?.code, 456)
        
        // Test setContext
        let uuid = UUID()
        subscriptionData.setContext(id: uuid, name: "onboarding")
        XCTAssertEqual(subscriptionData.contextData.id, uuid)
        XCTAssertEqual(subscriptionData.contextData.name, "onboarding")
        
        // Test setContext with only name
        let preservedUUID = subscriptionData.contextData.id
        subscriptionData.setContext(name: "updated_context")
        XCTAssertEqual(subscriptionData.contextData.id, preservedUUID)
        XCTAssertEqual(subscriptionData.contextData.name, "updated_context")
    }
    
    func testSubscriptionPlatformAndFailingStepEnums() {
        // Test PurchasePlatform enum
        let appstorePlatform = SubscriptionPurchaseWidePixelData.PurchasePlatform.appstore
        let stripePlatform = SubscriptionPurchaseWidePixelData.PurchasePlatform.stripe
        
        XCTAssertEqual(appstorePlatform.rawValue, "appstore")
        XCTAssertEqual(stripePlatform.rawValue, "stripe")
        
        // Test FailingStep enum
        let flowStart = SubscriptionPurchaseWidePixelData.FailingStep.flowStart
        let accountCreate = SubscriptionPurchaseWidePixelData.FailingStep.accountCreate
        let storekitPurchase = SubscriptionPurchaseWidePixelData.FailingStep.storekitPurchase
        let accountActivation = SubscriptionPurchaseWidePixelData.FailingStep.accountActivation
        
        XCTAssertEqual(flowStart.rawValue, "FLOW_START")
        XCTAssertEqual(accountCreate.rawValue, "ACCOUNT_CREATE")
        XCTAssertEqual(storekitPurchase.rawValue, "STOREKIT_PURCHASE")
        XCTAssertEqual(accountActivation.rawValue, "ACCOUNT_ACTIVATION")
        
        // Test CaseIterable
        XCTAssertEqual(SubscriptionPurchaseWidePixelData.PurchasePlatform.allCases.count, 2)
        XCTAssertEqual(SubscriptionPurchaseWidePixelData.FailingStep.allCases.count, 4)
    }
    
    // MARK: - Edge Case Tests
    
    func testCompleteFlowWithoutPixelKitInitialized() throws {
        PixelKit.tearDown()
        
        let subscriptionData = SubscriptionPurchaseWidePixelData(purchasePlatform: .appstore)
        widePixel.startFlow(subscriptionData)
        
        let expectation = XCTestExpectation(description: "Completion called")
        widePixel.completeFlow(SubscriptionPurchaseWidePixelData.self, contextID: subscriptionData.contextData.id, finalStatus: .success) { success, error in
            XCTAssertFalse(success)
            XCTAssertNotNil(error)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
        
        XCTAssertEqual(firedPixels.count, 0)
    }
    
    func testMultipleFlowCompletionsInSequence() throws {
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
