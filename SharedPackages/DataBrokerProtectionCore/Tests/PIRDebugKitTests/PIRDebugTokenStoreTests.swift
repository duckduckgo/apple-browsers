//
//  PIRDebugTokenStoreTests.swift
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

import Networking
import NetworkingTestingUtils
import XCTest
@testable import PIRDebugKit

final class PIRDebugTokenStoreTests: XCTestCase {

    private var directory: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        storeURL = directory.appendingPathComponent("nested/token.json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    private func makeContainer() -> TokenContainer {
        OAuthTokensFactory.makeValidTokenContainer()
    }

    func testStoreStartsEmpty() throws {
        let store = PIRDebugTokenStore(url: storeURL)

        XCTAssertFalse(store.hasToken)
        XCTAssertNil(try store.getTokenContainer())
    }

    func testSaveThenGetRoundTripsTheContainer() throws {
        let store = PIRDebugTokenStore(url: storeURL)
        let container = makeContainer()

        try store.saveTokenContainer(container)

        XCTAssertTrue(store.hasToken)
        let loaded = try XCTUnwrap(try store.getTokenContainer())
        XCTAssertEqual(loaded.accessToken, container.accessToken)
        XCTAssertEqual(loaded.refreshToken, container.refreshToken)
    }

    /// `OAuthClient.getTokens(policy: .localValid)` decides whether to refresh from the *deserialized*
    /// `exp` claim, so a store that skews dates on the way through would leave the CLI using an
    /// expired access token forever (401s from every service). Encoding and decoding must agree.
    func testRoundTripPreservesTokenExpiryDates() throws {
        let store = PIRDebugTokenStore(url: storeURL)
        let container = makeContainer()

        try store.saveTokenContainer(container)
        let loaded = try XCTUnwrap(try store.getTokenContainer())

        XCTAssertEqual(loaded.decodedAccessToken.expirationDate.timeIntervalSince1970,
                       container.decodedAccessToken.expirationDate.timeIntervalSince1970,
                       accuracy: 1)
        XCTAssertEqual(loaded.decodedRefreshToken.expirationDate.timeIntervalSince1970,
                       container.decodedRefreshToken.expirationDate.timeIntervalSince1970,
                       accuracy: 1)
    }

    /// The same contract from the other side: an already-expired token must still read as expired
    /// after a round-trip, or the client silently skips the refresh it needs.
    func testRoundTripPreservesExpiredState() throws {
        let store = PIRDebugTokenStore(url: storeURL)
        let expired = OAuthTokensFactory.makeExpiredTokenContainer()
        XCTAssertTrue(expired.decodedAccessToken.isExpired())

        try store.saveTokenContainer(expired)
        let loaded = try XCTUnwrap(try store.getTokenContainer())

        XCTAssertTrue(loaded.decodedAccessToken.isExpired())
    }

    func testSaveCreatesIntermediateDirectoriesAndWritesOwnerOnly() throws {
        let store = PIRDebugTokenStore(url: storeURL)

        try store.saveTokenContainer(makeContainer())

        // The file holds a refresh token: owner read/write only, never group- or world-readable.
        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.int16Value & 0o777, 0o600)
    }

    func testSaveOverwritesAndKeepsOwnerOnlyPermissions() throws {
        let store = PIRDebugTokenStore(url: storeURL)
        try store.saveTokenContainer(makeContainer())
        // Simulate a file whose mode was loosened after the first export.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: storeURL.path)

        try store.saveTokenContainer(makeContainer())

        let attributes = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let permissions = try XCTUnwrap(attributes[.posixPermissions] as? NSNumber)
        XCTAssertEqual(permissions.int16Value & 0o777, 0o600)
    }

    func testSavingNilDeletesTheFile() throws {
        let store = PIRDebugTokenStore(url: storeURL)
        try store.saveTokenContainer(makeContainer())

        try store.saveTokenContainer(nil)

        XCTAssertFalse(store.hasToken)
        XCTAssertNil(try store.getTokenContainer())
    }

    func testSavingNilOnAnEmptyStoreIsNotAnError() throws {
        let store = PIRDebugTokenStore(url: storeURL)

        XCTAssertNoThrow(try store.saveTokenContainer(nil))
    }

    func testGarbageContentsThrowsUndecodable() throws {
        try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(),
                                               withIntermediateDirectories: true)
        try Data("not a token container".utf8).write(to: storeURL)
        let store = PIRDebugTokenStore(url: storeURL)

        do {
            _ = try store.getTokenContainer()
            XCTFail("Expected an undecodable failure")
        } catch let error as PIRDebugTokenStore.StoreError {
            guard case .undecodable = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testDefaultURLIsUnderTheUsersConfigDirectory() {
        XCTAssertEqual(PIRDebugTokenStore.defaultURL.path,
                       FileManager.default.homeDirectoryForCurrentUser
                           .appendingPathComponent(".config/pir-debug/token.json").path)
    }

    func testAuthEnvironmentFollowsTheServicesEndpoint() {
        // A token issued by staging auth is rejected by production services, so these must agree.
        XCTAssertEqual(PIRAuthEnvironment(servicesEndpoint: .staging).oAuthEnvironment, .staging)
        XCTAssertEqual(PIRAuthEnvironment(servicesEndpoint: .production).oAuthEnvironment, .production)
        // A custom (e.g. localhost) services endpoint still authenticates against production.
        XCTAssertEqual(PIRAuthEnvironment(servicesEndpoint: .custom(URL(string: "http://localhost:3001")!)).oAuthEnvironment,
                       .production)
    }
}
