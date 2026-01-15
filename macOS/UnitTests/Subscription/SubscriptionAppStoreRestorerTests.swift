//
//  SubscriptionAppStoreRestorerTests.swift
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
import SubscriptionTestingUtilities
@testable import DuckDuckGo_Privacy_Browser
@testable import PixelKit
import PixelKitTestingUtilities
import PrivacyConfig
import enum StoreKit.StoreKitError

@available(macOS 12.0, *)
final class SubscriptionAppStoreRestorerTests: XCTestCase {

    private struct Constants {
        static let userDefaultsSuiteName = "SubscriptionAppStoreRestorerTests"
        static let purchaseURL = URL(string: "https://duckduckgo.com/subscriptions")!
    }

    var userDefaults: UserDefaults!
    var pixelKit: PixelKit!
    var uiHandler: SubscriptionUIHandlerMock!

    var subscriptionManager: SubscriptionManagerMock!
    var storePurchaseManager: StorePurchaseManagerMock!
    var appStoreRestoreFlow: AppStoreRestoreFlowMock!
    var subscriptionEventReporter: MockSubscriptionEventReporter!
    var featureFlagger: MockFeatureFlagger!
    var wideEvent: WideEventMock!

    var subscriptionAppStoreRestorer: DefaultSubscriptionAppStoreRestorerV2!

    var pixelsFired = Set<String>()
    var uiEventsHappened: [SubscriptionUIHandlerMock.UIHandlerMockPerformedAction] = []

    override func setUp() async throws {
        try await super.setUp()
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

        uiHandler = await SubscriptionUIHandlerMock(didPerformActionCallback: { action in
            self.uiEventsHappened.append(action)
        })

        storePurchaseManager = StorePurchaseManagerMock()
        subscriptionManager = SubscriptionManagerMock()
        subscriptionManager.currentEnvironment = SubscriptionEnvironment(serviceEnvironment: .production,
                                                                         purchasePlatform: .appStore)
        subscriptionManager.resultStorePurchaseManager = storePurchaseManager
        subscriptionManager.resultURL = Constants.purchaseURL

        appStoreRestoreFlow = AppStoreRestoreFlowMock()
        subscriptionEventReporter = MockSubscriptionEventReporter()
        featureFlagger = MockFeatureFlagger()
        wideEvent = WideEventMock()

        subscriptionAppStoreRestorer = DefaultSubscriptionAppStoreRestorerV2(
            subscriptionManager: subscriptionManager,
            subscriptionErrorReporter: subscriptionEventReporter,
            appStoreRestoreFlow: appStoreRestoreFlow,
            uiHandler: uiHandler,
            subscriptionRestoreWideEventData: nil,
            featureFlagger: featureFlagger,
            wideEvent: wideEvent
        )
    }

    override func tearDown() async throws {
        userDefaults = nil

        PixelKit.tearDown()
        pixelKit.clearFrequencyHistoryForAllPixels()

        pixelsFired.removeAll()
        uiEventsHappened.removeAll()

        storePurchaseManager = nil
        subscriptionManager = nil
        appStoreRestoreFlow = nil
        subscriptionEventReporter = nil
        featureFlagger = nil
        wideEvent = nil
        uiHandler = nil

        subscriptionAppStoreRestorer = nil
        pixelKit = nil
    }

    // MARK: - Tests for restoreAppStoreSubscription

    func testRestoreAppStoreSubscriptionSuccess() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .success("")

        // When
        await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

        // Then
        XCTAssertEqual(uiEventsHappened, [.didPresentProgressViewController,
                                          .didDismissProgressViewController])

        let expectedPixels = Set([SubscriptionPixel.subscriptionRestorePurchaseStoreSuccess.name + "_d",
                                  SubscriptionPixel.subscriptionRestorePurchaseStoreSuccess.name + "_c"])

        XCTAssertTrue(expectedPixels.isSubset(of: pixelsFired))
        XCTAssertTrue(assertNoOtherSubscriptionPixelsExcept(expectedPixels), "Unexpected Subscription pixels fired")
    }

    func testRestoreAppStoreSubscriptionWhenUserCancelsSyncAppleID() async throws {
        // Given
        storePurchaseManager.syncAppleIDAccountResultError = StoreKitError.userCancelled

        // When
        await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

        // Then
        XCTAssertEqual(uiEventsHappened, [.didPresentProgressViewController,
                                          .didDismissProgressViewController])

        XCTAssertTrue(pixelsFired.isEmpty)
    }

    func testRestoreAppStoreSubscriptionSuccessWhenSyncAppleIDFailsButUserProceedsRegardeless() async throws {
        // Given
        storePurchaseManager.syncAppleIDAccountResultError = StoreKitError.unknown
        await uiHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .success("")

        // When
        await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

        // Then
        XCTAssertEqual(uiEventsHappened, [.didPresentProgressViewController,
                                          .didDismissProgressViewController,
                                          .didShowAlert(.appleIDSyncFailed),
                                          .didPresentProgressViewController,
                                          .didDismissProgressViewController])

        let expectedPixels = Set([SubscriptionPixel.subscriptionRestorePurchaseStoreSuccess.name + "_d",
                                  SubscriptionPixel.subscriptionRestorePurchaseStoreSuccess.name + "_c"])

        XCTAssertTrue(expectedPixels.isSubset(of: pixelsFired))
        XCTAssertTrue(assertNoOtherSubscriptionPixelsExcept(expectedPixels), "Unexpected Subscription pixels fired")
    }

    // MARK: - Tests for different restore failures

    func testRestoreAppStoreSubscriptionWhenRestoreFailsDueToMissingAccountOrTransactions() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.missingAccountOrTransactions)
        await uiHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)

        // When
        await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

        // Then
        XCTAssertEqual(uiEventsHappened, [.didPresentProgressViewController,
                                          .didDismissProgressViewController,
                                          .didShowAlert(.subscriptionNotFound),
                                          .didShowTab(.subscription(Constants.purchaseURL))])

        let expectedPixels = Set([SubscriptionPixel.subscriptionOfferScreenImpression.name])
        XCTAssertTrue(expectedPixels.isSubset(of: pixelsFired))

        XCTAssertTrue(subscriptionEventReporter.reportedActivationErrors.contains(where: { error in
            switch error {
            case SubscriptionError.restoreFailedDueToNoSubscription:
                return true
            default:
                return false
            }
        }))

        XCTAssertTrue(assertNoOtherSubscriptionPixelsExcept(expectedPixels), "Unexpected Subscription pixels fired")
    }

    func testRestoreAppStoreSubscriptionWhenRestoreFailsDueToPastTransactionAuthenticationError() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.pastTransactionAuthenticationError)
        await uiHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)

        // When
        await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

        // Then
        XCTAssertEqual(uiEventsHappened, [.didPresentProgressViewController,
                                          .didDismissProgressViewController,
                                          .didShowAlert(.subscriptionNotFound),
                                          .didShowTab(.subscription(Constants.purchaseURL))])

        let expectedPixels = Set([SubscriptionPixel.subscriptionOfferScreenImpression.name])

        XCTAssertTrue(expectedPixels.isSubset(of: pixelsFired))
        XCTAssertTrue(subscriptionEventReporter.reportedActivationErrors.contains(where: { error in
            switch error {
            case SubscriptionError.otherRestoreError:
                return true
            default:
                return false
            }
        }))
        XCTAssertTrue(assertNoOtherSubscriptionPixelsExcept(expectedPixels), "Unexpected Subscription pixels fired")
    }

    func testRestoreAppStoreSubscriptionWhenRestoreFailsDueToFailedToObtainAccessToken() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.failedToObtainAccessToken)
        await uiHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)

        // When
        await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

        // Then
        XCTAssertEqual(uiEventsHappened, [.didPresentProgressViewController,
                                          .didDismissProgressViewController,
                                          .didShowAlert(.somethingWentWrong)])
        XCTAssertTrue(subscriptionEventReporter.reportedActivationErrors.contains(where: { error in
            switch error {
            case SubscriptionError.otherRestoreError:
                return true
            default:
                return false
            }
        }))
    }

    func testRestoreAppStoreSubscriptionWhenRestoreFailsDueToFailedToFetchAccountDetails() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.failedToFetchAccountDetails)
        await uiHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)

        // When
        await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

        // Then
        XCTAssertEqual(uiEventsHappened, [.didPresentProgressViewController,
                                          .didDismissProgressViewController,
                                          .didShowAlert(.somethingWentWrong)])
        XCTAssertTrue(subscriptionEventReporter.reportedActivationErrors.contains(where: { error in
            switch error {
            case SubscriptionError.otherRestoreError:
                return true
            default:
                return false
            }
        }))
    }

    func testRestoreAppStoreSubscriptionWhenRestoreFailsDueToFailedToFetchSubscriptionDetails() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.failedToFetchSubscriptionDetails)
        await uiHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)

        // When
        await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

        // Then
        XCTAssertEqual(uiEventsHappened, [.didPresentProgressViewController,
                                          .didDismissProgressViewController,
                                          .didShowAlert(.somethingWentWrong)])
        XCTAssertTrue(subscriptionEventReporter.reportedActivationErrors.contains(where: { error in
            switch error {
            case SubscriptionError.otherRestoreError:
                return true
            default:
                return false
            }
        }))
    }

    func testRestoreAppStoreSubscriptionWhenRestoreFailsDueToSubscriptionBeingExpired() async throws {
        // Given
        appStoreRestoreFlow.restoreAccountFromPastPurchaseResult = .failure(.subscriptionExpired)
        await uiHandler.setAlertResponse(alertResponse: .alertFirstButtonReturn)

        // When
        await subscriptionAppStoreRestorer.restoreAppStoreSubscription()

        // Then
        XCTAssertEqual(uiEventsHappened, [.didPresentProgressViewController,
                                          .didDismissProgressViewController,
                                          .didShowAlert(.subscriptionInactive),
                                          .didShowTab(.subscription(Constants.purchaseURL))])

        let expectedPixels = Set([SubscriptionPixel.subscriptionOfferScreenImpression.name])
        XCTAssertTrue(subscriptionEventReporter.reportedActivationErrors.contains(where: { error in
            switch error {
            case SubscriptionError.restoreFailedDueToExpiredSubscription:
                return true
            default:
                return false
            }
        }))
        XCTAssertTrue(expectedPixels.isSubset(of: pixelsFired))
        XCTAssertTrue(assertNoOtherSubscriptionPixelsExcept(expectedPixels), "Unexpected Subscription pixels fired")
    }

    private func assertNoOtherSubscriptionPixelsExcept(_ expectedPixels: Set<String>) -> Bool {
#if APPSTORE
        let appDistribution = "store"
#else
        let appDistribution = "direct"
#endif
        let subscriptionPixelPrefix = "m_mac_\(appDistribution)_privacy-pro"

        let otherPixels = pixelsFired.subtracting(expectedPixels)
        return !otherPixels.contains { $0.hasPrefix(subscriptionPixelPrefix) }
    }
}
