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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
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
                PixelKit.Parameters.test: "1",
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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
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
                PixelKit.Parameters.appVersion: "1.0.0",
                PixelKit.Parameters.test: "1"
            ]
        )
    }

    private func assertDailyAndCountPixel(baseName: String, expectedParameters: [String: String]) {
        let dailyName = baseName + "_daily"
        let countName = baseName + "_count"

        let daily = firedPixels.first(where: { $0.name == dailyName })
        let count = firedPixels.first(where: { $0.name == countName })

        XCTAssertNotNil(daily, "Expected daily pixel \(dailyName)")
        XCTAssertNotNil(count, "Expected count pixel \(countName)")

        assertParameters(expectedParameters, in: daily?.parameters)
        assertParameters(expectedParameters, in: count?.parameters)
    }

    private func assertLegacyDailyPixel(baseName: String, expectedParameters: [String: String]) {
        let legacyDailyName = baseName + "_d"
        let legacyDaily = firedPixels.first(where: { $0.name == legacyDailyName })

        XCTAssertNotNil(legacyDaily, "Expected legacy daily pixel \(legacyDailyName)")
        assertParameters(expectedParameters, in: legacyDaily?.parameters)
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

//    private let host = "improving.duckduckgo.com"
//    private let pixelStorageSuiteName = "com.duckduckgo.pixel.storage"
//    private let dailyPixelStorageSuiteName = "com.duckduckgo.daily.pixel.storage"
//
//    override func setUpWithError() throws {
//        try super.setUpWithError()
//        Pixel.isDryRun = false
//        clearPixelStorage()
//    }
//
//    override func tearDown() {
//        Pixel.isDryRun = true
//        HTTPStubs.removeAllStubs()
//        clearPixelStorage()
//        super.tearDown()
//    }
//
//    func testInvalidRefreshTokenDetectedPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue)
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionInvalidRefreshTokenDetected.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .invalidRefreshToken)
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    func testSubscriptionActivePixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = [
//            PixelParameters.appVersion: AppVersion.shared.versionNumber,
//            PixelParameters.test: PixelValues.test,
//            AuthVersion.key: AuthVersion.v2.rawValue
//        ]
//
//        let expectation = expectSinglePixel(
//            pixelName: Pixel.Event.subscriptionActive.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .subscriptionIsActive)
//        wait(for: [expectation], timeout: 2.0)
//    }
//
//    func testGetTokensErrorPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let tokenStatus = OAuthRequest.TokenStatus.reused
//        let error = OAuthClientError.invalidTokenRequest(tokenStatus)
//        let nsError = error as NSError
//        let underlyingError = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue).merging([
//            SubscriptionPixelHandler.Defaults.policyCacheKey: AuthTokensCachePolicy.localValid.description,
//            PixelParameters.errorCode: "\(error.errorCode)",
//            PixelParameters.errorDomain: error.errorDomain,
//            PixelParameters.underlyingErrorCode: "\(tokenStatus.errorCode)",
//            PixelParameters.underlyingErrorDomain: underlyingError?.domain ?? ""
//        ]) { $1 }
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionAuthV2GetTokensError2.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .getTokensError(.localValid, error))
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    func testInvalidRefreshTokenSignedOutPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue)
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionInvalidRefreshTokenSignedOut.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .invalidRefreshTokenSignedOut)
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    func testInvalidRefreshTokenRecoveredPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue)
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionInvalidRefreshTokenRecovered.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .invalidRefreshTokenRecovered)
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    func testPurchaseSuccessAfterPendingTransactionPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue)
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionPurchaseSuccessAfterPendingTransaction.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .purchaseSuccessAfterPendingTransaction)
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    func testPendingTransactionApprovedPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue)
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionPendingTransactionApproved.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .pendingTransactionApproved)
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    func testKeychainDataAddedToBacklogPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue)
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionKeychainManagerDataAddedToTheBacklog.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .dataAddedToTheBacklog)
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    func testKeychainDeallocatedWithBacklogPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue)
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionKeychainManagerDeallocatedWithBacklog.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .deallocatedWithBacklog)
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    func testKeychainDataWroteFromBacklogPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue)
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionKeychainManagerDataWroteFromBacklog.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .dataWroteFromBacklog)
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    func testKeychainFailedToWriteFromBacklogPixel() {
//        let handler = SubscriptionPixelHandler(source: .mainApp)
//        let expectedParams = baseExpectedParams(source: SubscriptionPixelHandler.Source.mainApp.rawValue)
//
//        let (dailyExpectation, countExpectation) = expectDailyAndCount(
//            pixelName: Pixel.Event.subscriptionKeychainManagerFailedToWriteDataFromBacklog.name,
//            expectedParams: expectedParams
//        )
//
//        handler.handle(pixel: .failedToWriteDataFromBacklog)
//        wait(for: [dailyExpectation, countExpectation], timeout: 2.0)
//    }
//
//    private func baseExpectedParams(source: String) -> [String: String] {
//        [
//            SubscriptionPixelHandler.Defaults.sourceKey: source,
//            PixelParameters.appVersion: AppVersion.shared.versionNumber,
//            PixelParameters.test: PixelValues.test
//        ]
//    }
//
//    private func expectDailyAndCount(pixelName: String,
//                                     expectedParams: [String: String]) -> (XCTestExpectation, XCTestExpectation) {
//        let dailyExpectation = expectation(description: "Daily pixel fired for \(pixelName)")
//        let countExpectation = expectation(description: "Count pixel fired for \(pixelName)")
//
//        stub(condition: { request in
//            self.matches(request: request, pixelName: pixelName, suffix: "_daily")
//        }) { request in
//            self.assertExpectedParams(expectedParams, in: request)
//            dailyExpectation.fulfill()
//            return HTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
//        }
//
//        stub(condition: { request in
//            self.matches(request: request, pixelName: pixelName, suffix: "_count")
//        }) { request in
//            self.assertExpectedParams(expectedParams, in: request)
//            countExpectation.fulfill()
//            return HTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
//        }
//
//        return (dailyExpectation, countExpectation)
//    }
//
//    private func expectSinglePixel(pixelName: String,
//                                   expectedParams: [String: String]) -> XCTestExpectation {
//        let expectation = expectation(description: "Pixel fired for \(pixelName)")
//        stub(condition: { request in
//            self.matches(request: request, pixelName: pixelName, suffix: nil)
//        }) { request in
//            self.assertExpectedParams(expectedParams, in: request)
//            expectation.fulfill()
//            return HTTPStubsResponse(data: Data(), statusCode: 200, headers: nil)
//        }
//        return expectation
//    }
//
//    private func matches(request: URLRequest, pixelName: String, suffix: String?) -> Bool {
//        guard let url = request.url,
//              url.host == host else { return false }
//        let fullName = suffix == nil ? pixelName : pixelName + suffix!
//        return url.path.contains("/t/\(fullName)")
//    }
//
//    private func assertExpectedParams(_ expectedParams: [String: String], in request: URLRequest) {
//        guard let params = request.url?.queryParameters() else {
//            XCTFail("Expected query parameters")
//            return
//        }
//
//        XCTAssertEqual(params.count, expectedParams.count, "Expected \(expectedParams.count) parameters but got \(params.count)")
//        for (key, value) in expectedParams {
//            XCTAssertEqual(params[key], value, "Expected |\(key)| to be |\(value)|")
//        }
//    }
//
//    private func clearPixelStorage() {
//        UserDefaults(suiteName: pixelStorageSuiteName)?.removePersistentDomain(forName: pixelStorageSuiteName)
//        UserDefaults(suiteName: dailyPixelStorageSuiteName)?.removePersistentDomain(forName: dailyPixelStorageSuiteName)
//    }
}
