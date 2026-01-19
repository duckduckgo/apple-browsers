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
import PixelKit
@testable import Subscription

final class SubscriptionRestoreWideEventTests: XCTestCase {

    // MARK: - Pixel Parameters

    func testPixelParameters_withAppleAccountFlows() {
        let contextData = WideEventContextData(name: "test-context")
        let eventData = SubscriptionRestoreWideEventData(
            restorePlatform: .appleAccount,
            contextData: contextData
        )

        let base = Date()
        eventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(2.5) // 5000ms
        )

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.name"], "subscription-restore")
        XCTAssertEqual(parameters["feature.data.ext.restore_platform"], "apple_account")
        XCTAssertEqual(parameters["feature.data.ext.apple_account_restore_latency_ms_bucketed"], "5000")

        XCTAssertNil(parameters["feature.data.ext.email_address_restore_latency_ms_bucketed"])
        XCTAssertNil(parameters["feature.data.ext.email_address_restore_last_url"])
    }

    func testPixelParameters_withEmailAddressFlows() {
        let contextData = WideEventContextData(name: "test-context")
        let eventData = SubscriptionRestoreWideEventData(
            restorePlatform: .emailAddress,
            contextData: contextData
        )

        let base = Date()
        eventData.emailAddressRestoreDuration = WideEvent.MeasuredInterval(
            start: base,
            end: base.addingTimeInterval(2.5) // 5000ms
        )
        eventData.emailAddressRestoreLastURL = .activationFlowActivateEmailOTP

        let parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.name"], "subscription-restore")
        XCTAssertEqual(parameters["feature.data.ext.restore_platform"], "email_address")
        XCTAssertEqual(parameters["feature.data.ext.email_address_restore_latency_ms_bucketed"], "10000")
        XCTAssertEqual(parameters["feature.data.ext.email_address_restore_last_url"], "activation_flow_activate_email_otp")

        XCTAssertNil(parameters["feature.data.ext.apple_account_restore_latency_ms_bucketed"])
    }

    // MARK: - Interval Bucketing

    func testPixelParameters_withAppleAccountDuration_bucketing() {
        let contextData = WideEventContextData(name: "test-context")
        let cases: [(ms: Int, expected: String)] = [
            (500, "1000"), // normal
            (4999, "5000"), // higher edge
            (5000, "10000"), // lower edge
            (300000, "600000"), // lower edge
            (800000, "600000") // default
        ]
        let base = Date()

        for (ms, expected) in cases {
            let eventData = SubscriptionRestoreWideEventData(restorePlatform: .appleAccount, contextData: contextData)
            eventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval(
                start: base,
                end: base.addingTimeInterval(Double(ms) / 1000.0)
            )

            let parameters = eventData.pixelParameters()
            XCTAssertEqual(parameters["feature.data.ext.apple_account_restore_latency_ms_bucketed"], expected)
        }
    }

    // MARK: - Interval Bucketing

    func testPixelParameters_withEmailAddressDuration_bucketing() {
        let contextData = WideEventContextData(name: "test-context")
        let base = Date()
        let cases: [(ms: Int, expected: String)] = [
            (5000, "10000"), // normal
            (29999, "30000"), // higher edge
            (60000, "300000"), // lower edge
            (900000, "-1"), // default
            (1200000, "-1") // default
        ]

        for (ms, expected) in cases {
            let eventData = SubscriptionRestoreWideEventData(restorePlatform: .emailAddress, contextData: contextData)
            eventData.emailAddressRestoreDuration = WideEvent.MeasuredInterval(
                start: base,
                end: base.addingTimeInterval(Double(ms) / 1000.0)
            )

            let parameters = eventData.pixelParameters()
            XCTAssertEqual(parameters["feature.data.ext.email_address_restore_latency_ms_bucketed"], expected)
        }
    }

    // MARK: - URL Mapping

    func test_EmailAddressRestoreURL_mapAllRecognizedURLS() {
        let cases: [(url: URL, expected: SubscriptionRestoreWideEventData.EmailAddressRestoreURL)] = [
            (URL(string: "https://duckduckgo.com/subscriptions/activation-flow")!, .activationFlow),
            (URL(string: "https://duckduckgo.com/subscriptions/activation-flow/this-device/email")!, .activationFlowEmail),
            (URL(string: "https://duckduckgo.com/subscriptions/activation-flow/this-device/activate-by-email")!, .activationFlowActivateEmail),
            (URL(string: "https://duckduckgo.com/subscriptions/activation-flow/this-device/activate-by-email/otp")!, .activationFlowActivateEmailOTP),
            (URL(string: "https://duckduckgo.com/subscriptions/activation-flow/this-device/activate-by-email/success")!, .activationFlowSuccess)
        ]

        for (route, expected) in cases {
            XCTAssertEqual(SubscriptionRestoreWideEventData.EmailAddressRestoreURL.from(route), expected)
        }
    }

    func test_EmailAddressRestoreURL_mapNonRecognizedURL_returnsNil() {
        let unknownURL = URL(string: "https://duckduckgo.com/subscriptions/activation-flow/manage")!
        XCTAssertNil(SubscriptionRestoreWideEventData.EmailAddressRestoreURL.from(unknownURL))
    }

    // MARK: - Abandoned & Delayed Flows

    func testPixelParameters_withAbandonedFlows() {
        let contextData = WideEventContextData(name: "test-context")
        let base = Date()
        let eventData = SubscriptionRestoreWideEventData(restorePlatform: .appleAccount, contextData: contextData)

        // no started interval
        var parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.apple_account_restore_latency_ms_bucketed"])

        // has ended interval
        eventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: base, end: base.addingTimeInterval(2.5)) // 5000ms
        parameters = eventData.pixelParameters()
        XCTAssertEqual(parameters["feature.data.ext.apple_account_restore_latency_ms_bucketed"], "5000")
    }

    func testPixelParameters_withDelayedFlows() {
        let contextData = WideEventContextData(name: "test-context")
        let base = Date()
        let eventData = SubscriptionRestoreWideEventData(restorePlatform: .emailAddress, contextData: contextData)

        // start only
        eventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: base, end: nil)
        var parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.apple_account_restore_latency_ms_bucketed"])

        // end only
        eventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: nil, end: base)
        parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.apple_account_restore_latency_ms_bucketed"])
    }

    func testCompletionDecision_noIntervalStart_returnsPartialData() async {
        let eventData = SubscriptionRestoreWideEventData(restorePlatform: .appleAccount, contextData: WideEventContextData())

        let decision = await eventData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: SubscriptionRestoreWideEventData.StatusReason.partialData.rawValue))
        case .keepPending:
            XCTFail("Expected completion with partial data")
        }
    }

    func testCompletionDecision_intervalAlreadyCompleted_returnsPartialData() async {
        let eventData = SubscriptionRestoreWideEventData(restorePlatform: .appleAccount, contextData: WideEventContextData())
        let start = Date()
        eventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: start, end: start.addingTimeInterval(1))

        let decision = await eventData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: SubscriptionRestoreWideEventData.StatusReason.partialData.rawValue))
        case .keepPending:
            XCTFail("Expected completion with partial data")
        }
    }

    func testCompletionDecision_restoreTimeoutExceeded_returnsTimeout() async {
        let eventData = SubscriptionRestoreWideEventData(restorePlatform: .appleAccount, contextData: WideEventContextData())
        let start = Date().addingTimeInterval(-SubscriptionRestoreWideEventData.restoreTimeout - 1)
        eventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: start, end: nil)

        let decision = await eventData.completionDecision(for: .appLaunch)

        switch decision {
        case .complete(let status):
            XCTAssertEqual(status, .unknown(reason: SubscriptionRestoreWideEventData.StatusReason.timeout.rawValue))
        case .keepPending:
            XCTFail("Expected completion with timeout")
        }
    }

    func testCompletionDecision_withinTimeout_returnsKeepPending() async {
        let eventData = SubscriptionRestoreWideEventData(restorePlatform: .appleAccount, contextData: WideEventContextData())
        let start = Date().addingTimeInterval(-SubscriptionRestoreWideEventData.restoreTimeout + 1)
        eventData.appleAccountRestoreDuration = WideEvent.MeasuredInterval(start: start, end: nil)

        let decision = await eventData.completionDecision(for: .appLaunch)

        switch decision {
        case .keepPending:
            break
        case .complete:
            XCTFail("Expected keep pending")
        }
    }
}
