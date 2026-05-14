//
//  SubscriptionPixelHandlerTests.swift
//  DuckDuckGoTests
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
import OHHTTPStubs
import OHHTTPStubsSwift
import Networking
@testable import Core
@testable import DuckDuckGo
import Common
import Subscription
import PixelKit

final class SubscriptionPixelHandlerTests: XCTestCase {

    private struct FiredPixel {
        let name: String
        let parameters: [String: String]
    }

    private var firedPixels: [FiredPixel] = []
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var pixelKit: PixelKit!
    private let pixelSource = "test-source"
    private let subscriptionSource: SubscriptionPixelHandler.Source = .mainApp

    override func setUp() {
        super.setUp()
        let suiteName = "SubscriptionPixelHandlerTests.\(UUID().uuidString)"
        defaultsSuiteName = suiteName
        defaults = UserDefaults(suiteName: suiteName)!

        let fireRequest: PixelKit.FireRequest = { pixelName, _, parameters, _, _, onComplete in
            self.firedPixels.append(FiredPixel(name: pixelName, parameters: parameters))
            DispatchQueue.main.async {
                onComplete(true, nil)
            }
        }

        pixelKit = PixelKit(
            dryRun: false,
            appVersion: "1.0.0",
            source: pixelSource,
            defaultHeaders: [:],
            defaults: defaults,
            fireRequest: fireRequest
        )
    }

    override func tearDown() {
        pixelKit = nil
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        firedPixels.removeAll()
        super.tearDown()
    }

    func testInvalidRefreshTokenDetectedPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .invalidRefreshToken)

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionInvalidRefreshTokenDetected(subscriptionSource).name,
            expectedParameters: [
                "source": subscriptionSource.rawValue,
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    func testSubscriptionActivePixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .subscriptionIsActive)

        assertLegacyDailyPixel(
            baseName: SubscriptionPixel.subscriptionActive.name,
            expectedParameters: [
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    func testGetTokensErrorPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        let error = OAuthClientError.invalidTokenRequest(.reused)
        handler.handle(pixel: .getTokensError(.localValid, error))

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionAuthV2GetTokensError(.localValid, subscriptionSource, error).name,
            expectedParameters: [
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.underlyingErrorCode: "2",
                PixelKit.Parameters.errorCode: "11003",
                PixelKit.Parameters.underlyingErrorDomain: OAuthRequest.TokenStatus.errorDomain,
                PixelKit.Parameters.errorDomain: OAuthClientError.errorDomain,
                "source": subscriptionSource.rawValue,
                "policycache": AuthTokensCachePolicy.localValid.description
            ]
        )
    }

    func testInvalidRefreshTokenSignedOutPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .invalidRefreshTokenSignedOut)

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionInvalidRefreshTokenSignedOut.name,
            expectedParameters: [
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    func testInvalidRefreshTokenRecoveredPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .invalidRefreshTokenRecovered)

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionInvalidRefreshTokenRecovered.name,
            expectedParameters: [
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    func testPurchaseSuccessAfterPendingTransactionPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .purchaseSuccessAfterPendingTransaction)

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionPurchaseSuccessAfterPendingTransaction(subscriptionSource).name,
            expectedParameters: [
                "source": subscriptionSource.rawValue,
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    func testPendingTransactionApprovedPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .pendingTransactionApproved)

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionPendingTransactionApproved(subscriptionSource).name,
            expectedParameters: [
                "source": subscriptionSource.rawValue,
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    func testKeychainDataAddedToBacklogPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .dataAddedToTheBacklog)

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionKeychainManagerDataAddedToTheBacklog(subscriptionSource).name,
            expectedParameters: [
                "source": subscriptionSource.rawValue,
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    func testKeychainDeallocatedWithBacklogPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .deallocatedWithBacklog)

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionKeychainManagerDeallocatedWithBacklog(subscriptionSource).name,
            expectedParameters: [
                "source": subscriptionSource.rawValue,
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    func testKeychainDataWroteFromBacklogPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .dataWroteFromBacklog)

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionKeychainManagerDataWroteFromBacklog(subscriptionSource).name,
            expectedParameters: [
                "source": subscriptionSource.rawValue,
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    func testKeychainFailedToWriteFromBacklogPixel() {
        let handler = SubscriptionPixelHandler(source: subscriptionSource, pixelKit: pixelKit)
        handler.handle(pixel: .failedToWriteDataFromBacklog)

        assertDailyAndCountPixel(
            baseName: SubscriptionPixel.subscriptionKeychainManagerFailedToWriteDataFromBacklog(subscriptionSource).name,
            expectedParameters: [
                "source": subscriptionSource.rawValue,
                PixelKit.Parameters.pixelSource: pixelSource,
                PixelKit.Parameters.appVersion: "1.0.0"
            ]
        )
    }

    private func assertDailyAndCountPixel(baseName: String, expectedParameters: [String: String]) {
        let dailyName = baseName + "_daily"
        let countName = baseName + "_count"

        var modifiedExpectedParameters = expectedParameters
        let daily = firedPixels.first(where: { $0.name == dailyName })
        let count = firedPixels.first(where: { $0.name == countName })

        XCTAssertNotNil(daily, "Expected daily pixel \(dailyName)")
        XCTAssertNotNil(count, "Expected count pixel \(countName)")

        if let test = daily?.parameters[PixelKit.Parameters.test] {
            modifiedExpectedParameters[PixelKit.Parameters.test] = "1"
        }

        assertParameters(modifiedExpectedParameters, in: daily?.parameters)
        assertParameters(modifiedExpectedParameters, in: count?.parameters)
    }

    private func assertLegacyDailyPixel(baseName: String, expectedParameters: [String: String]) {
        let legacyDailyName = baseName + "_d"
        let legacyDaily = firedPixels.first(where: { $0.name == legacyDailyName })

        var modifiedExpectedParameters = expectedParameters
        if let test = legacyDaily?.parameters[PixelKit.Parameters.test] {
            modifiedExpectedParameters[PixelKit.Parameters.test] = "1"
        }
        XCTAssertNotNil(legacyDaily, "Expected legacy daily pixel \(legacyDailyName)")
        assertParameters(modifiedExpectedParameters, in: legacyDaily?.parameters)
    }

    private func assertParameters(_ expected: [String: String], in actual: [String: String]?) {
        guard let actual else {
            XCTFail("Expected parameters but got nil")
            return
        }

        XCTAssertEqual(actual.count, expected.count, "Expected \(expected.count) parameters but got \(actual.count)")
        for (key, value) in expected {
            XCTAssertEqual(actual[key], value, "Expected parameter |\(key)| to be |\(value)|")
        }
    }
}
