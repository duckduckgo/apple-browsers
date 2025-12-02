//
//  SubscriptionErrorReporterTests.swift
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
@testable import Subscription
@testable import DuckDuckGo_Privacy_Browser
@testable import PixelKit
import PixelKitTestingUtilities

final class SubscriptionErrorReporterTests: XCTestCase {

    private struct Constants {
        static let userDefaultsSuiteName = "SubscriptionErrorReporterTests"
    }

    var userDefaults: UserDefaults!
    var pixelKit: PixelKit!

    var reporter: SubscriptionEventReporter! = DefaultSubscriptionEventReporter()

    var pixelsFired = Set<String>()

    override func setUp() async throws {
        userDefaults = UserDefaults(suiteName: Constants.userDefaultsSuiteName)!
        userDefaults.removePersistentDomain(forName: Constants.userDefaultsSuiteName)

        pixelKit = PixelKit(dryRun: false,
                            appVersion: "1.0.0",
                            defaultHeaders: [:],
                            defaults: userDefaults) { pixelName, _, _, _, _, _ in
            self.pixelsFired.insert(pixelName)
        }
        pixelKit.clearFrequencyHistoryForAllPixels()
        PixelKit.setSharedForTesting(pixelKit: pixelKit)

        reporter = DefaultSubscriptionEventReporter()
    }

    override func tearDown() async throws {
        userDefaults = nil

        PixelKit.tearDown()
        pixelKit.clearFrequencyHistoryForAllPixels()

        pixelsFired.removeAll()

        reporter = nil
        pixelKit = nil
    }

    // MARK: - Tests for various subscription errors

    func testReporterForPurchaseFailedError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .purchaseFailed(NSError(domain: "error", code: 1))

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionPurchaseFailureStoreError(errorToBeHandled).name + "_d",
                                     SubscriptionPixel.subscriptionPurchaseFailureStoreError(errorToBeHandled).name + "_c"])
    }

    func testReporterForMissingEntitlementsError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .missingEntitlements

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionPurchaseFailureBackendError.name + "_d",
                                     SubscriptionPixel.subscriptionPurchaseFailureBackendError.name + "_c"])
    }

    func testReporterForFailedToGetSubscriptionOptionsError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .failedToGetSubscriptionOptions

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([])
    }

    func testReporterForFailedToSetSubscriptionError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .failedToSetSubscription

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([])
    }

    func testReporterForSubscriptionNotFoundError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .restoreFailedDueToNoSubscription

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionRestorePurchaseStoreFailureNotFound.name + "_d",
                                     SubscriptionPixel.subscriptionRestorePurchaseStoreFailureNotFound.name + "_c"])
    }

    func testReporterForSubscriptionExpiredError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .restoreFailedDueToExpiredSubscription

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionRestorePurchaseStoreFailureNotFound.name + "_d",
                                     SubscriptionPixel.subscriptionRestorePurchaseStoreFailureNotFound.name + "_c"])
    }

    func testReporterForHasActiveSubscriptionError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .activeSubscriptionAlreadyPresent

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([])
    }

    func testReporterForCancelledByUserError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .cancelledByUser

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([])
    }

    func testReporterForAccountCreationFailedError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .accountCreationFailed(NSError(domain: "error", code: 1))

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionPurchaseFailureAccountNotCreated(errorToBeHandled).name + "_d",
                                     SubscriptionPixel.subscriptionPurchaseFailureAccountNotCreated(errorToBeHandled).name + "_c"])
    }

    func testReporterForActiveSubscriptionAlreadyPresentError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .activeSubscriptionAlreadyPresent

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([])
    }

    func testReporterForGeneralError() async throws {
        // Given
        let errorToBeHandled: SubscriptionError = .otherPurchaseError

        // When
        reporter.report(subscriptionActivationError: errorToBeHandled)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionPurchaseFailureOther.name + "_d",
                                     SubscriptionPixel.subscriptionPurchaseFailureOther.name + "_c"])
    }

    // MARK: - Tests for Subscription Tier Option Events

    func testReporterForTierOptionsRequested() async throws {
        // Given
        let event = SubscriptionPixel.subscriptionTierOptionsRequested

        // When
        reporter.report(subscriptionTierOptionEvent: event)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionTierOptionsRequested.name])
    }

    func testReporterForTierOptionsSuccess() async throws {
        // Given
        let event = SubscriptionPixel.subscriptionTierOptionsSuccess

        // When
        reporter.report(subscriptionTierOptionEvent: event)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionTierOptionsSuccess.name])
    }

    func testReporterForTierOptionsFailure() async throws {
        // Given
        let error = NSError(domain: "TestError", code: 123)
        let event = SubscriptionPixel.subscriptionTierOptionsFailure(error: error)

        // When
        reporter.report(subscriptionTierOptionEvent: event)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionTierOptionsFailure(error: error).name])
    }

    func testReporterForTierOptionsUnexpectedProTier() async throws {
        // Given
        let event = SubscriptionPixel.subscriptionTierOptionsUnexpectedProTier

        // When
        reporter.report(subscriptionTierOptionEvent: event)

        // Then
        XCTAssertPrivacyPixelsFired([SubscriptionPixel.subscriptionTierOptionsUnexpectedProTier.name])
    }

    public func XCTAssertPrivacyPixelsFired(_ pixels: [String], file: StaticString = #file, line: UInt = #line) {
        let pixelsFired = Set(pixelsFired)
        let expectedPixels = Set(pixels)

        // Assert expected pixels were fired
        XCTAssertTrue(expectedPixels.isSubset(of: pixelsFired),
                      "Expected Subscription pixels were not fired: \(expectedPixels.subtracting(pixelsFired))",
                      file: file,
                      line: line)

        // Assert no other Subscription pixels were fired except the expected
#if APPSTORE
        let subscriptionPixelPrefix = "m_mac_store_privacy-pro"
#else
        let subscriptionPixelPrefix = "m_mac_direct_privacy-pro"
#endif
        let otherPixels = pixelsFired.subtracting(expectedPixels)
        let otherSubscriptionPixels = otherPixels.filter { $0.hasPrefix(subscriptionPixelPrefix) }
        XCTAssertTrue(otherSubscriptionPixels.isEmpty,
                      "Unexpected Subscription pixels fired: \(otherSubscriptionPixels)",
                      file: file,
                      line: line)
    }
}
