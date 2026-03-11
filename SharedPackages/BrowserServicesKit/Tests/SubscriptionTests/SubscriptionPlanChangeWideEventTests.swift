//
//  SubscriptionPlanChangeWideEventTests.swift
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
import PixelKit
@testable import Subscription

final class SubscriptionPlanChangeWideEventTests: XCTestCase {

    private var wideEvent: WideEvent!
    private var firedPixels: [(name: String, parameters: [String: String])] = []
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        setupMockPixelKit()
        wideEvent = WideEvent(storage: WideEventUserDefaultsStorage(userDefaults: testDefaults),
                              featureFlagProvider: MockWideEventFeatureFlagProvider(isPostEndpointEnabled: true))
        firedPixels.removeAll()
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

    // MARK: - Successful Plan Change Flow Tests

    func testSuccessfulAppStorePlanChangeFlow() throws {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            funnelName: "funnel_appsettings_ios"
        )

        wideEvent.startFlow(planChangeData)

        // Payment completes (1.5s -> 5000 bucket)
        let t0 = Date(timeIntervalSince1970: 0)
        let t1 = Date(timeIntervalSince1970: 1.5)
        let flow0 = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        flow0.paymentDuration = WideEvent.MeasuredInterval(start: t0, end: t1)
        wideEvent.updateFlow(flow0)

        // Confirmation completes (2.5s -> 5000 bucket)
        let t2 = Date(timeIntervalSince1970: 10)
        let t3 = Date(timeIntervalSince1970: 12.5)
        let flow1 = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        flow1.confirmationDuration = WideEvent.MeasuredInterval(start: t2, end: t3)
        wideEvent.updateFlow(flow1)

        // Complete the flow successfully
        let expectation = XCTestExpectation(description: "Pixel fired")
        let finalData = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        wideEvent.completeFlow(finalData, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let firedPixel = firedPixels[0]
        XCTAssertTrue(firedPixel.name.contains("wide_subscription_plan_change"))

        let params = firedPixel.parameters
        #if os(iOS)
        XCTAssertEqual(params["meta.type"], "ios-subscription-plan-change")
        #elseif os(macOS)
        XCTAssertEqual(params["meta.type"], "macos-subscription-plan-change")
        #endif
        XCTAssertEqual(params["feature.status"], "SUCCESS")
        XCTAssertEqual(params["feature.name"], "subscription-plan-change")
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "app_store")
        XCTAssertEqual(params["feature.data.ext.change_type"], "UPGRADE")
        XCTAssertEqual(params["feature.data.ext.from_plan"], "ddg.privacy.plus.monthly.renews.us")
        XCTAssertEqual(params["feature.data.ext.to_plan"], "ddg.privacy.pro.monthly.renews.us")
        XCTAssertEqual(params["feature.data.ext.subscription_identifier"], "ddg.privacy.pro.monthly.renews.us")
        XCTAssertEqual(params["feature.data.ext.payment_latency_ms_bucketed"], "5000")
        XCTAssertEqual(params["feature.data.ext.confirmation_latency_ms_bucketed"], "5000")
        XCTAssertEqual(params["feature.data.ext.funnel_name"], "funnel_appsettings_ios")
        XCTAssertNil(params["context.name"])

        XCTAssertNotNil(params["app.name"])
        XCTAssertNotNil(params["app.version"])
        XCTAssertNotNil(params["global.platform"])
        XCTAssertEqual(params["global.type"], "app")
        XCTAssertEqual(params["global.sample_rate"], "1.0")

        XCTAssertEqual(wideEvent.getAllFlowData(SubscriptionPlanChangeWideEventData.self).count, 0)
    }

    func testSuccessfulStripePlanChangeFlow() throws {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .stripe,
            changeType: .downgrade,
            fromPlan: "ddg.privacy.pro.yearly.renews.us",
            toPlan: "ddg.privacy.plus.yearly.renews.us",
            funnelName: "funnel_appsettings_macos"
        )

        wideEvent.startFlow(planChangeData)

        let flow = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        flow.paymentDuration = WideEvent.MeasuredInterval(start: Date(), end: Date())
        flow.confirmationDuration = WideEvent.MeasuredInterval(start: Date(), end: Date())
        wideEvent.updateFlow(flow)

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "stripe")
        XCTAssertEqual(params["feature.data.ext.change_type"], "DOWNGRADE")
        XCTAssertEqual(params["feature.data.ext.funnel_name"], "funnel_appsettings_macos")
        XCTAssertNil(params["context.name"])
    }

    func testCrossgradePlanChangeFlow() throws {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .crossgrade,
            fromPlan: "ddg.privacy.pro.monthly.renews.us",
            toPlan: "ddg.privacy.pro.yearly.renews.us",
            funnelName: "funnel_appsettings_ios"
        )

        wideEvent.startFlow(planChangeData)

        let flow = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        flow.paymentDuration = WideEvent.MeasuredInterval(start: Date(), end: Date())
        flow.confirmationDuration = WideEvent.MeasuredInterval(start: Date(), end: Date())
        wideEvent.updateFlow(flow)

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(flow, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.data.ext.change_type"], "CROSSGRADE")
    }

    // MARK: - Failed Plan Change Flow Tests

    func testFailedPlanChangeFlowPaymentStep() throws {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            contextData: WideEventContextData()
        )
        wideEvent.startFlow(planChangeData)

        let storeKitError = NSError(domain: "SKErrorDomain", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Payment failed",
            NSUnderlyingErrorKey: NSError(domain: "UnderlyingError", code: 456, userInfo: nil)
        ])

        let failed = planChangeData
        failed.markAsFailed(at: .payment, error: storeKitError)
        wideEvent.updateFlow(failed)

        let f1 = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        f1.paymentDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 8))
        wideEvent.updateFlow(f1)

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id, status: .failure) { success, error in
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
        XCTAssertEqual(params["feature.data.error.underlying_domain"], "UnderlyingError")
        XCTAssertEqual(params["feature.data.error.underlying_code"], "456")
        XCTAssertEqual(params["feature.data.ext.payment_latency_ms_bucketed"], "10000")
    }

    func testFailedPlanChangeFlowConfirmationStep() throws {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            contextData: WideEventContextData()
        )
        wideEvent.startFlow(planChangeData)

        let s1 = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        s1.paymentDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 1.5))
        wideEvent.updateFlow(s1)

        let confirmationError = NSError(domain: "SubscriptionError", code: 100)

        let currentForFailure = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        currentForFailure.markAsFailed(at: .confirmation, error: confirmationError)
        wideEvent.updateFlow(currentForFailure)

        let f2 = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        f2.confirmationDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 15))
        wideEvent.updateFlow(f2)

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id, status: .failure) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters

        XCTAssertEqual(params["feature.status"], "FAILURE")
        XCTAssertEqual(params["feature.data.ext.failing_step"], "ACCOUNT_ACTIVATION")
        XCTAssertEqual(params["feature.data.error.domain"], "SubscriptionError")
        XCTAssertEqual(params["feature.data.error.code"], "100")
        XCTAssertEqual(params["feature.data.ext.payment_latency_ms_bucketed"], "5000")
        XCTAssertEqual(params["feature.data.ext.confirmation_latency_ms_bucketed"], "30000")
    }

    // MARK: - Cancelled Flow Tests

    func testCancelledPlanChangeFlow() throws {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            contextData: WideEventContextData()
        )
        wideEvent.startFlow(planChangeData)

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id, status: .cancelled) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "CANCELLED")
        XCTAssertEqual(params["feature.data.ext.purchase_platform"], "app_store")
        XCTAssertNil(params["feature.data.ext.payment_latency_ms_bucketed"])
        XCTAssertNil(params["feature.data.ext.failing_step"])
    }

    // MARK: - Nil ChangeType Tests

    func testPlanChangeFlowWithNilChangeType() throws {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: nil,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            funnelName: "funnel_appsettings_ios"
        )

        wideEvent.startFlow(planChangeData)

        let flow = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        flow.paymentDuration = WideEvent.MeasuredInterval(start: Date(), end: Date())
        flow.confirmationDuration = WideEvent.MeasuredInterval(start: Date(), end: Date())
        wideEvent.updateFlow(flow)

        let expectation = XCTestExpectation(description: "Pixel fired")
        wideEvent.completeFlow(flow, status: .success) { success, error in
            XCTAssertTrue(success)
            XCTAssertNil(error)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1 && firedPixels.count <= 2)
        let params = firedPixels[0].parameters
        XCTAssertNil(params["feature.data.ext.change_type"])
        XCTAssertEqual(params["feature.data.ext.from_plan"], "ddg.privacy.plus.monthly.renews.us")
        XCTAssertEqual(params["feature.data.ext.to_plan"], "ddg.privacy.pro.monthly.renews.us")
    }

    // MARK: - Completion Decision Tests

    func testCompletionDecision_noConfirmationIntervalStart_returnsPartialData() async {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            contextData: WideEventContextData()
        )

        let decision = await planChangeData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: SubscriptionPlanChangeWideEventData.StatusReason.partialData.rawValue))
        case .keepPending:
            XCTFail("Expected completion with partial data")
        }
    }

    func testCompletionDecision_intervalAlreadyCompleted_returnsPartialData() async {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            contextData: WideEventContextData()
        )

        let start = Date()
        planChangeData.confirmationDuration = WideEvent.MeasuredInterval(start: start, end: start.addingTimeInterval(10))

        let decision = await planChangeData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: SubscriptionPlanChangeWideEventData.StatusReason.partialData.rawValue))
        case .keepPending:
            XCTFail("Expected completion with partial data")
        }
    }

    func testCompletionDecision_confirmationTimeoutExceeded_returnsTimeout() async {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .stripe,
            changeType: .downgrade,
            fromPlan: "ddg.privacy.pro.yearly.renews.us",
            toPlan: "ddg.privacy.plus.yearly.renews.us",
            contextData: WideEventContextData()
        )
        let start = Date().addingTimeInterval(-SubscriptionPlanChangeWideEventData.confirmationTimeout - 10)
        planChangeData.confirmationDuration = WideEvent.MeasuredInterval(start: start, end: nil)

        let decision = await planChangeData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: SubscriptionPlanChangeWideEventData.StatusReason.missingEntitlements.rawValue))
        case .keepPending:
            XCTFail("Expected completion with timeout")
        }
    }

    func testCompletionDecision_withinTimeout_returnsKeepPending() async {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .stripe,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.yearly.renews.us",
            toPlan: "ddg.privacy.pro.yearly.renews.us",
            contextData: WideEventContextData()
        )

        let start = Date().addingTimeInterval(-SubscriptionPlanChangeWideEventData.confirmationTimeout + 10)
        planChangeData.confirmationDuration = WideEvent.MeasuredInterval(start: start, end: nil)

        let decision = await planChangeData.completionDecision(for: .appLaunch)

        switch decision {
        case .keepPending:
            break
        case .complete:
            XCTFail("Expected keep pending")
        }
    }

    func testCompletionDecision_entitlementsCheckerReturnsTrue_completesWithSuccess() async {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            contextData: WideEventContextData()
        )

        let start = Date()
        planChangeData.confirmationDuration = WideEvent.MeasuredInterval(start: start, end: nil)
        planChangeData.entitlementsChecker = { true }

        let decision = await planChangeData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .success(reason: SubscriptionPlanChangeWideEventData.StatusReason.missingEntitlementsDelayedActivation.rawValue))
        case .keepPending:
            XCTFail("Expected completion with success")
        }
    }

    func testCompletionDecision_noEntitlementsChecker_neverCompletesWithSuccess() async {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            contextData: WideEventContextData()
        )

        let start = Date().addingTimeInterval(-SubscriptionPlanChangeWideEventData.confirmationTimeout + 10)
        planChangeData.confirmationDuration = WideEvent.MeasuredInterval(start: start, end: nil)

        let decision = await planChangeData.completionDecision(for: .appLaunch)

        switch decision {
        case .keepPending:
            break
        case .complete:
            XCTFail("Expected keep pending without entitlements checker")
        }
    }

    // MARK: - Latency Bucketing Tests

    func testLatencyBucketing() throws {
        let planChangeData = SubscriptionPlanChangeWideEventData(
            purchasePlatform: .appStore,
            changeType: .upgrade,
            fromPlan: "ddg.privacy.plus.monthly.renews.us",
            toPlan: "ddg.privacy.pro.monthly.renews.us",
            funnelName: "funnel_appsettings_ios"
        )

        wideEvent.startFlow(planChangeData)

        // Payment: 500ms -> 1000 bucket
        let flow0 = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        flow0.paymentDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 0.5))
        wideEvent.updateFlow(flow0)

        // Confirmation: 45s -> 60000 bucket
        let flow1 = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        flow1.confirmationDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 45))
        wideEvent.updateFlow(flow1)

        let expectation = XCTestExpectation(description: "Pixel fired")
        let finalData = wideEvent.getFlowData(SubscriptionPlanChangeWideEventData.self, globalID: planChangeData.globalData.id)!
        wideEvent.completeFlow(finalData, status: .success) { success, error in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        XCTAssert(firedPixels.count >= 1)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.data.ext.payment_latency_ms_bucketed"], "1000")
        XCTAssertEqual(params["feature.data.ext.confirmation_latency_ms_bucketed"], "60000")
    }

}
