//
//  SubscriptionRestoreWideEventTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import Subscription

final class SubscriptionRestoreWideEventTests: XCTestCase {

    private var wideEvent: WideEvent!
    private var firedPixels: [(name: String, parameters: [String: String])] = []
    private var testDefaults: UserDefaults!
    private var testSuiteName: String!

    override func setUp() {
        super.setUp()

        testSuiteName = "\(type(of: self))-\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: testSuiteName) ?? .standard
        wideEvent = WideEvent(storage: WideEventUserDefaultsStorage(userDefaults: testDefaults),
                              pixelKitProvider: { PixelKit.shared })
        firedPixels.removeAll()
        setUpMockPixelKit()
    }

    override func tearDown() {
        testDefaults?.removePersistentDomain(forName: testSuiteName)
        PixelKit.tearDown()
        super.tearDown()
    }

    private func setUpMockPixelKit() {
        let mockFireRequest: PixelKit.FireRequest = { pixelName, _, parameters, _, _, onComplete in
            self.firedPixels.append((name: pixelName, parameters: parameters))
            DispatchQueue.main.async { onComplete(true, nil) }
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

    // MARK: - Utilities

    private func waitForPixelFired(timeout: TimeInterval = 1.0) {
        let exp = expectation(description: "Pixel fired")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: timeout)
    }

    private func unwrapFlow<T: WideEventData>(_ type: T.Type, id: String) throws -> T {
        guard let data = wideEvent.getFlowData(type, globalID: id) else {
            XCTFail("Flow not found for \(id)")
            throw NSError(domain: "FlowNotFound", code: -1)
        }
        return data
    }

    private func makeAppleRestore(contextName: String? = nil) -> SubscriptionRestoreWideEventData {
        SubscriptionRestoreWideEventData(
            restorePlatform: .appleAccount,
            contextData: WideEventContextData(name: contextName)
        )
    }

    private func makeEmailRestore(contextName: String? = nil,
                                  lastURL: SubscriptionRestoreWideEventData.EmailAddressRestoreURL? = nil) -> SubscriptionRestoreWideEventData {
        SubscriptionRestoreWideEventData(
            restorePlatform: .emailAddress,
            emailAddressRestoreLastURL: lastURL,
            contextData: WideEventContextData(name: contextName)
        )
    }

    private func makeBackgroundRestore(contextName: String? = nil) -> SubscriptionRestoreWideEventData {
        SubscriptionRestoreWideEventData(
            restorePlatform: .purchaseBackgroundTask,
            contextData: WideEventContextData(name: contextName)
        )
    }

    // MARK: - Journey 1: Apple Account

    func testAppleAccountRestore_Success() throws {
        let data = makeAppleRestore(contextName: "app_settings")
        wideEvent.startFlow(data)

        let started = try unwrapFlow(SubscriptionRestoreWideEventData.self, id: data.globalData.id)
        started.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0),
                                                                         end: Date(timeIntervalSince1970: 2.5)) // 2.5s -> 5000ms
        wideEvent.updateFlow(started)

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(started, status: .success) { success, error in
            XCTAssertTrue(success); XCTAssertNil(error); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertFalse(firedPixels.isEmpty)
        let params = firedPixels[0].parameters
        XCTAssertEqual(params["feature.status"], "SUCCESS")
        XCTAssertEqual(params["feature.data.ext.restore_platform"], "apple_account")
        XCTAssertEqual(params["feature.data.ext.apple_account_restore_latency_ms_bucketed"], "5000")
        XCTAssertEqual(params["context.name"], "app_settings")
        XCTAssertNotNil(params["app.name"])
        XCTAssertNotNil(params["app.version"])
    }

    func testAppleAccountRestore_Failure_WithErrorAndLatency() throws {
        let data = makeAppleRestore(contextName: "app_settings")
        wideEvent.startFlow(data)

        let failing = try unwrapFlow(SubscriptionRestoreWideEventData.self, id: data.globalData.id)
        failing.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0),
                                                                         end: Date(timeIntervalSince1970: 8.0)) // 8s -> 10000ms
        failing.errorData = WideEventErrorData(error: NSError(domain: "UseSubscriptionError", code: 1))
        wideEvent.updateFlow(failing)

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(failing, status: .failure) { success, error in
            XCTAssertTrue(success); XCTAssertNil(error); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let p = firedPixels[0].parameters
        XCTAssertEqual(p["feature.status"], "FAILURE")
        XCTAssertEqual(p["feature.data.ext.restore_platform"], "apple_account")
        XCTAssertEqual(p["feature.data.ext.apple_account_restore_latency_ms_bucketed"], "10000")
        XCTAssertEqual(p["feature.data.error.domain"], "UseSubscriptionError")
        XCTAssertEqual(p["context.name"], "app_settings")
    }

    // MARK: - Journey 2: Email Address

    func testEmailAddressRestore_Success_IncludesLastURL() throws {
        let data = makeEmailRestore(contextName: "offer_page", lastURL: .activationFlowSuccess)
        wideEvent.startFlow(data)

        let started = try unwrapFlow(SubscriptionRestoreWideEventData.self, id: data.globalData.id)
        started.emailAddressRestoreDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 10),
                                                                         end: Date(timeIntervalSince1970: 40)) // 30s -> 30000ms bucket
        wideEvent.updateFlow(started)

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(started, status: .success) { success, error in
            XCTAssertTrue(success); XCTAssertNil(error); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let p = firedPixels[0].parameters
        XCTAssertEqual(p["feature.status"], "SUCCESS")
        XCTAssertEqual(p["feature.data.ext.restore_platform"], "email_address")
        XCTAssertEqual(p["feature.data.ext.email_address_restore_latency_ms_bucketed"], "30000")
        XCTAssertEqual(p["feature.data.ext.email_address_restore_last_url"], "activation_flow_success")
        XCTAssertEqual(p["context.name"], "offer_page")
    }

    func testEmailAddressRestore_Failure_WithErrorAndLatency() throws {
        let data = makeEmailRestore(contextName: "app_settings")
        wideEvent.startFlow(data)

        let failing = try unwrapFlow(SubscriptionRestoreWideEventData.self, id: data.globalData.id)
        failing.emailAddressRestoreDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0),
                                                                         end: Date(timeIntervalSince1970: 600.0)) // 10 min -> 600000ms
        failing.errorData = WideEventErrorData(error: NSError(domain: "FailedToSetSubscription", code: 999))
        wideEvent.updateFlow(failing)

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(failing, status: .failure) { success, error in
            XCTAssertTrue(success); XCTAssertNil(error); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let p = firedPixels[0].parameters
        XCTAssertEqual(p["feature.status"], "FAILURE")
        XCTAssertEqual(p["feature.data.ext.restore_platform"], "email_address")
        XCTAssertEqual(p["feature.data.ext.email_address_restore_latency_ms_bucketed"], "600000")
        XCTAssertEqual(p["feature.data.error.domain"], "FailedToSetSubscription")
        XCTAssertEqual(p["context.name"], "app_settings")
    }

    // MARK: - Journey 3: Purchase Background Task

    func testPurchaseBackgroundTask_PreOrDuringPurchase_Success() throws {
        let data = makeBackgroundRestore(contextName: "purchase_flow")
        wideEvent.startFlow(data)

        let started = try unwrapFlow(SubscriptionRestoreWideEventData.self, id: data.globalData.id)
        started.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0),
                                                                         end: Date(timeIntervalSince1970: 1.0)) // 1s -> 5000ms
        wideEvent.updateFlow(started)

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(started, status: .success) { success, error in
            XCTAssertTrue(success); XCTAssertNil(error); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let p = firedPixels[0].parameters
        XCTAssertEqual(p["feature.status"], "SUCCESS")
        XCTAssertEqual(p["feature.data.ext.restore_platform"], "purchase_background_task")
        XCTAssertEqual(p["feature.data.ext.apple_account_restore_latency_ms_bucketed"], "5000")
        XCTAssertEqual(p["context.name"], "purchase_flow")
    }

    func testPurchaseBackgroundTask_PreOrDuringPurchase_Failure() throws {
        let data = makeBackgroundRestore(contextName: "purchase_flow")
        wideEvent.startFlow(data)

        let failing = try unwrapFlow(SubscriptionRestoreWideEventData.self, id: data.globalData.id)
        failing.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0),
                                                                         end: Date(timeIntervalSince1970: 20.0)) // 20s -> 30000ms
        failing.errorData = WideEventErrorData(error: NSError(domain: "AppStoreRestoreFlowErrorV2", code: 13001))
        wideEvent.updateFlow(failing)

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(failing, status: .failure) { success, error in
            XCTAssertTrue(success); XCTAssertNil(error); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let p = firedPixels[0].parameters
        XCTAssertEqual(p["feature.status"], "FAILURE")
        XCTAssertEqual(p["feature.data.ext.restore_platform"], "purchase_background_task")
        XCTAssertEqual(p["feature.data.ext.apple_account_restore_latency_ms_bucketed"], "30000")
        XCTAssertEqual(p["feature.data.error.domain"], "AppStoreRestoreFlowErrorV2")
        XCTAssertEqual(p["context.name"], "purchase_flow")
    }

    // MARK: - Unknown Pixels (Abandoned/Delayed)

    func testUnknownPixel_Abandoned_PartialData() {
        // No durations set
        let data = makeAppleRestore(contextName: "any")
        wideEvent.startFlow(data)

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(data, status: .unknown(reason: SubscriptionRestoreWideEventData.StatusReason.partialData.rawValue)) { success, error in
            XCTAssertTrue(success); XCTAssertNil(error); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let p = firedPixels[0].parameters
        XCTAssertEqual(p["feature.status"], "UNKNOWN")
        XCTAssertEqual(p["feature.status_reason"], "partial_data")
        XCTAssertEqual(p["feature.data.ext.restore_platform"], "apple_account")
    }

    func testUnknownPixel_Delayed_Timeout() {
        // Started but not completed interval
        let data = makeEmailRestore(contextName: "any")
        wideEvent.startFlow(data)

        let started = try? unwrapFlow(SubscriptionRestoreWideEventData.self, id: data.globalData.id)
        started?.emailAddressRestoreDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 901.0)) // > 15 min bucket top (-1) but we only encode when completed
        if let started { wideEvent.updateFlow(started) }

        let exp = expectation(description: "complete")
        wideEvent.completeFlow(data, status: .unknown(reason: SubscriptionRestoreWideEventData.StatusReason.timeout.rawValue)) { success, error in
            XCTAssertTrue(success); XCTAssertNil(error); exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        let p = firedPixels[0].parameters
        XCTAssertEqual(p["feature.status"], "UNKNOWN")
        XCTAssertEqual(p["feature.status_reason"], "timeout")
        XCTAssertEqual(p["feature.data.ext.restore_platform"], "email_address")
    }

    // MARK: - Bucket Boundary Checks

    func testAppleAccountLatencyBuckets() throws {
        let data = makeAppleRestore()
        wideEvent.startFlow(data)

        func assertBucket(ms: Double, expected: String) throws {
            let d = try unwrapFlow(SubscriptionRestoreWideEventData.self, id: data.globalData.id)
            d.appleAccountRestoreDuration = WideEvent.MeasuredInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: ms / 1000.0)
            )
            wideEvent.updateFlow(d)
            let exp = expectation(description: "complete")
            wideEvent.completeFlow(d, status: .success) { _, _ in exp.fulfill() }
            wait(for: [exp], timeout: 1.0)
            let p = self.firedPixels.removeFirst().parameters
            XCTAssertEqual(p["feature.data.ext.apple_account_restore_latency_ms_bucketed"], expected)
        }

        try assertBucket(ms: 999, expected: "1000")
        try assertBucket(ms: 1500, expected: "5000")
        try assertBucket(ms: 8000, expected: "10000")
        try assertBucket(ms: 20000, expected: "30000")
        try assertBucket(ms: 45000, expected: "60000")
        try assertBucket(ms: 120000, expected: "300000")
        try assertBucket(ms: 700000, expected: "600000")
    }

    func testEmailAddressLatencyBuckets() throws {
        let data = makeEmailRestore()
        wideEvent.startFlow(data)

        func assertBucket(ms: Double, expected: String) throws {
            let d = try unwrapFlow(SubscriptionRestoreWideEventData.self, id: data.globalData.id)
            d.emailAddressRestoreDuration = WideEvent.MeasuredInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: ms / 1000.0)
            )
            wideEvent.updateFlow(d)
            let exp = expectation(description: "complete")
            wideEvent.completeFlow(d, status: .success) { _, _ in exp.fulfill() }
            wait(for: [exp], timeout: 1.0)
            let p = self.firedPixels.removeFirst().parameters
            XCTAssertEqual(p["feature.data.ext.email_address_restore_latency_ms_bucketed"], expected)
        }

        try assertBucket(ms: 5000, expected: "10000")
        try assertBucket(ms: 20000, expected: "30000")
        try assertBucket(ms: 45000, expected: "60000")
        try assertBucket(ms: 120000, expected: "300000")
        try assertBucket(ms: 420000, expected: "600000")
        try assertBucket(ms: 850000, expected: "900000")
        try assertBucket(ms: 1_200_000, expected: "-1")
    }
}
