//
//  AuthMigratorTests.swift
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
@testable import Subscription
@testable import Networking
import SubscriptionTestingUtilities
import NetworkingTestingUtils

final class AuthMigratorTests: XCTestCase {

    class TestPixelHandler: SubscriptionPixelHandling {
        var lastPixelType: Subscription.SubscriptionPixelType?

        func handle(pixel: Subscription.SubscriptionPixelType) {
            lastPixelType = pixel
        }

        func handle(pixel: Subscription.KeychainManager.Pixel) {}
    }

    var mockOAuthClient: MockOAuthClient!
    var testPixelHandler: TestPixelHandler!

    override func setUp() {
        super.setUp()
        mockOAuthClient = MockOAuthClient()
        testPixelHandler = TestPixelHandler()
    }

    // MARK: - isReadyToUseAuthV2 tests

    func test_isReadyToUseAuthV2_whenAuthV2Enabled_andUserAuthenticated_returnsTrue() {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()
        let sut = AuthMigrator(oAuthClient: mockOAuthClient,
                               pixelHandler: testPixelHandler,
                               isAuthV2Enabled: true)

        XCTAssertTrue(sut.isReadyToUseAuthV2)
    }

    func test_isReadyToUseAuthV2_whenAuthV2Enabled_andUserNotAuthenticated_andV1TokenPresent_returnsFalse() {
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.isV1TokenPresent = true

        let sut = AuthMigrator(oAuthClient: mockOAuthClient,
                               pixelHandler: testPixelHandler,
                               isAuthV2Enabled: true)

        XCTAssertFalse(sut.isReadyToUseAuthV2)
    }

    func test_isReadyToUseAuthV2_whenAuthV2Enabled_andUserNotAuthenticated_andNoV1Token_returnsTrue() {
        mockOAuthClient.internalCurrentTokenContainer = nil
        mockOAuthClient.isV1TokenPresent = false

        let sut = AuthMigrator(oAuthClient: mockOAuthClient,
                               pixelHandler: testPixelHandler,
                               isAuthV2Enabled: true)

        XCTAssertTrue(sut.isReadyToUseAuthV2)
    }

    func test_isReadyToUseAuthV2_whenAuthV2Disabled_returnsFalse_evenIfUserIsAuthenticated() {
        mockOAuthClient.internalCurrentTokenContainer = OAuthTokensFactory.makeValidTokenContainer()

        let sut = AuthMigrator(oAuthClient: mockOAuthClient,
                               pixelHandler: testPixelHandler,
                               isAuthV2Enabled: false)

        XCTAssertFalse(sut.isReadyToUseAuthV2)
    }

    // MARK: - migrateAuthV1toAuthV2IfNeeded tests

    func test_migrateAuthV1toAuthV2IfNeeded_whenAuthV2Disabled_doesNothing() async {
        let sut = AuthMigrator(oAuthClient: mockOAuthClient,
                               pixelHandler: testPixelHandler,
                               isAuthV2Enabled: false)

        await sut.migrateAuthV1toAuthV2IfNeeded()

        XCTAssertNil(testPixelHandler.lastPixelType)
    }

    func test_migrateAuthV1toAuthV2IfNeeded_whenMigrationSucceeds_firesSuccessPixel() async {
        mockOAuthClient.migrateV1TokenResponseError = nil
        let sut = AuthMigrator(oAuthClient: mockOAuthClient,
                               pixelHandler: testPixelHandler,
                               isAuthV2Enabled: true)

        await sut.migrateAuthV1toAuthV2IfNeeded()

        XCTAssertEqual(testPixelHandler.lastPixelType, .migrationSucceeded)
    }

    func test_migrateAuthV1toAuthV2IfNeeded_whenMigrationNotNeeded_doesNotFirePixel() async {
        mockOAuthClient.migrateV1TokenResponseError = OAuthClientError.authMigrationNotPerformed
        let sut = AuthMigrator(oAuthClient: mockOAuthClient,
                               pixelHandler: testPixelHandler,
                               isAuthV2Enabled: true)

        await sut.migrateAuthV1toAuthV2IfNeeded()

        XCTAssertNil(testPixelHandler.lastPixelType)
    }

    func test_migrateAuthV1toAuthV2IfNeeded_whenMigrationFails_firesFailurePixel() async {
        struct TestError: Error, Equatable {}
        let error = TestError()
        mockOAuthClient.migrateV1TokenResponseError = error
        let sut = AuthMigrator(oAuthClient: mockOAuthClient,
                               pixelHandler: testPixelHandler,
                               isAuthV2Enabled: true)

        await sut.migrateAuthV1toAuthV2IfNeeded()

        guard case .migrationFailed(let firedError)? = testPixelHandler.lastPixelType else {
            return XCTFail("Expected .migrationFailed to be fired")
        }

        XCTAssertEqual(firedError as? TestError, error)
    }
}
