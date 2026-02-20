//
//  AIChatSyncHandlerTests.swift
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
@testable import AIChat
@testable import DDGSync

final class AIChatSyncHandlerTests: XCTestCase {

    private var mockSync: MockDDGSyncing!
    private var sut: AIChatSyncHandler!

    override func setUp() {
        super.setUp()
        mockSync = MockDDGSyncing()
    }

    override func tearDown() {
        mockSync = nil
        sut = nil
        super.tearDown()
    }

    private func makeSUT() -> AIChatSyncHandler {
        AIChatSyncHandler(sync: mockSync)
    }

    // MARK: - isSyncTurnedOn Tests

    func testGivenAuthStateInitializing_WhenIsSyncTurnedOn_ThenReturnsFalse() {
        // Given
        mockSync.authState = .initializing
        mockSync.account = MockSyncAccount.valid
        sut = makeSUT()

        // When
        let result = sut.isSyncTurnedOn()

        // Then
        XCTAssertFalse(result, "Should return false when auth state is initializing")
    }

    func testGivenAuthStateActiveButNoAccount_WhenIsSyncTurnedOn_ThenReturnsFalse() {
        // Given
        mockSync.authState = .active
        mockSync.account = nil
        sut = makeSUT()

        // When
        let result = sut.isSyncTurnedOn()

        // Then
        XCTAssertFalse(result, "Should return false when account is nil")
    }

    func testGivenAuthStateActiveWithAccount_WhenIsSyncTurnedOn_ThenReturnsTrue() {
        // Given
        mockSync.authState = .active
        mockSync.account = MockSyncAccount.valid
        sut = makeSUT()

        // When
        let result = sut.isSyncTurnedOn()

        // Then
        XCTAssertTrue(result, "Should return true when auth state is active and account exists")
    }

    func testGivenAuthStateInactiveWithAccount_WhenIsSyncTurnedOn_ThenReturnsTrue() {
        // Given
        mockSync.authState = .inactive
        mockSync.account = MockSyncAccount.valid
        sut = makeSUT()

        // When
        let result = sut.isSyncTurnedOn()

        // Then
        XCTAssertTrue(result, "Should return true when auth state is not initializing and account exists")
    }

    // MARK: - getSyncStatus Tests

    func testGivenFeatureNotAvailable_WhenGetSyncStatus_ThenReturnsSyncNotAvailable() throws {
        // Given
        mockSync.authState = .active
        mockSync.account = MockSyncAccount.valid
        sut = makeSUT()

        // When
        let status = try sut.getSyncStatus(featureAvailable: false)

        // Then
        XCTAssertFalse(status.syncAvailable, "syncAvailable should be false when feature is not available")
        XCTAssertNil(status.userId)
        XCTAssertNil(status.deviceId)
        XCTAssertNil(status.deviceName)
        XCTAssertNil(status.deviceType)
    }

    func testGivenAuthStateInitializing_WhenGetSyncStatus_ThenThrowsInternalError() {
        // Given
        mockSync.authState = .initializing
        sut = makeSUT()

        // When/Then
        XCTAssertThrowsError(try sut.getSyncStatus(featureAvailable: true)) { error in
            XCTAssertEqual(error as? AIChatSyncHandler.Errors, .internalError)
        }
    }

    func testGivenNoAccount_WhenGetSyncStatus_ThenReturnsSyncAvailableWithNilFields() throws {
        // Given
        mockSync.authState = .active
        mockSync.account = nil
        sut = makeSUT()

        // When
        let status = try sut.getSyncStatus(featureAvailable: true)

        // Then
        XCTAssertTrue(status.syncAvailable, "syncAvailable should be true when feature is available")
        XCTAssertNil(status.userId)
        XCTAssertNil(status.deviceId)
        XCTAssertNil(status.deviceName)
        XCTAssertNil(status.deviceType)
    }

    func testGivenAccountExists_WhenGetSyncStatus_ThenReturnsFullStatus() throws {
        // Given
        mockSync.authState = .active
        mockSync.account = MockSyncAccount.valid
        sut = makeSUT()

        // When
        let status = try sut.getSyncStatus(featureAvailable: true)

        // Then
        XCTAssertTrue(status.syncAvailable)
        XCTAssertEqual(status.userId, "test-user-id")
        XCTAssertEqual(status.deviceId, "test-device-id")
        XCTAssertEqual(status.deviceName, "Test Device")
        XCTAssertEqual(status.deviceType, "iPhone")
    }

    // MARK: - getScopedToken Tests

    func testGivenAuthStateInitializing_WhenGetScopedToken_ThenThrowsInternalError() async {
        // Given
        mockSync.authState = .initializing
        sut = makeSUT()

        // When/Then
        do {
            _ = try await sut.getScopedToken()
            XCTFail("Expected internalError to be thrown")
        } catch {
            XCTAssertEqual(error as? AIChatSyncHandler.Errors, .internalError)
        }
    }

    func testGivenRescopeReturnsNil_WhenGetScopedToken_ThenThrowsEmptyResponse() async {
        // Given
        mockSync.authState = .active
        mockSync.mainTokenRescopeResult = nil
        sut = makeSUT()

        // When/Then
        do {
            _ = try await sut.getScopedToken()
            XCTFail("Expected emptyResponse to be thrown")
        } catch {
            XCTAssertEqual(error as? AIChatSyncHandler.Errors, .emptyResponse)
        }
    }

    func testGivenRescopeReturnsEmptyString_WhenGetScopedToken_ThenThrowsEmptyResponse() async {
        // Given
        mockSync.authState = .active
        mockSync.mainTokenRescopeResult = ""
        sut = makeSUT()

        // When/Then
        do {
            _ = try await sut.getScopedToken()
            XCTFail("Expected emptyResponse to be thrown")
        } catch {
            XCTAssertEqual(error as? AIChatSyncHandler.Errors, .emptyResponse)
        }
    }

    func testGivenRescopeReturnsToken_WhenGetScopedToken_ThenReturnsToken() async throws {
        // Given
        mockSync.authState = .active
        mockSync.mainTokenRescopeResult = "scoped-token-abc123"
        sut = makeSUT()

        // When
        let result = try await sut.getScopedToken()

        // Then
        XCTAssertEqual(result.token, "scoped-token-abc123")
        XCTAssertEqual(mockSync.mainTokenRescopeScope, "ai_chats")
    }

    // MARK: - encrypt Tests

    func testGivenAuthStateInitializing_WhenEncrypt_ThenThrowsInternalError() {
        // Given
        mockSync.authState = .initializing
        sut = makeSUT()

        // When/Then
        XCTAssertThrowsError(try sut.encrypt("hello")) { error in
            XCTAssertEqual(error as? AIChatSyncHandler.Errors, .internalError)
        }
    }

    func testGivenValidState_WhenEncrypt_ThenReturnsEncryptedData() throws {
        // Given
        mockSync.authState = .active
        mockSync.encryptResult = ["encrypted-data"]
        sut = makeSUT()

        // When
        let result = try sut.encrypt("hello")

        // Then
        XCTAssertEqual(result.encryptedData, "encrypted-data")
        XCTAssertEqual(mockSync.encryptInput, ["hello"])
    }

    func testGivenEncryptionReturnsEmpty_WhenEncrypt_ThenReturnsEmptyString() throws {
        // Given
        mockSync.authState = .active
        mockSync.encryptResult = []
        sut = makeSUT()

        // When
        let result = try sut.encrypt("hello")

        // Then
        XCTAssertEqual(result.encryptedData, "")
    }

    func testGivenEncryptionFails_WhenEncrypt_ThenThrowsError() {
        // Given
        mockSync.authState = .active
        mockSync.encryptError = NSError(domain: "test", code: 1, userInfo: nil)
        sut = makeSUT()

        // When/Then
        XCTAssertThrowsError(try sut.encrypt("hello"))
    }

    // MARK: - decrypt Tests

    func testGivenAuthStateInitializing_WhenDecrypt_ThenThrowsInternalError() {
        // Given
        mockSync.authState = .initializing
        sut = makeSUT()

        // When/Then
        XCTAssertThrowsError(try sut.decrypt("encrypted")) { error in
            XCTAssertEqual(error as? AIChatSyncHandler.Errors, .internalError)
        }
    }

    func testGivenValidState_WhenDecrypt_ThenReturnsDecryptedData() throws {
        // Given
        mockSync.authState = .active
        mockSync.decryptResult = ["decrypted-data"]
        sut = makeSUT()

        // When
        let result = try sut.decrypt("encrypted")

        // Then
        XCTAssertEqual(result.decryptedData, "decrypted-data")
        XCTAssertEqual(mockSync.decryptInput, ["encrypted"])
    }

    func testGivenDecryptionReturnsEmpty_WhenDecrypt_ThenReturnsEmptyString() throws {
        // Given
        mockSync.authState = .active
        mockSync.decryptResult = []
        sut = makeSUT()

        // When
        let result = try sut.decrypt("encrypted")

        // Then
        XCTAssertEqual(result.decryptedData, "")
    }

    func testGivenDecryptionFails_WhenDecrypt_ThenThrowsError() {
        // Given
        mockSync.authState = .active
        mockSync.decryptError = NSError(domain: "test", code: 1, userInfo: nil)
        sut = makeSUT()

        // When/Then
        XCTAssertThrowsError(try sut.decrypt("encrypted"))
    }

    // MARK: - setAIChatHistoryEnabled Tests

    func testWhenSetAIChatHistoryEnabledTrue_ThenDelegatesToSync() {
        // Given
        sut = makeSUT()

        // When
        sut.setAIChatHistoryEnabled(true)

        // Then
        XCTAssertTrue(mockSync.isAIChatHistoryEnabled)
        XCTAssertEqual(mockSync.setAIChatHistoryEnabledCallCount, 1)
    }

    func testWhenSetAIChatHistoryEnabledFalse_ThenDelegatesToSync() {
        // Given
        mockSync.isAIChatHistoryEnabled = true
        sut = makeSUT()

        // When
        sut.setAIChatHistoryEnabled(false)

        // Then
        XCTAssertFalse(mockSync.isAIChatHistoryEnabled)
        XCTAssertEqual(mockSync.setAIChatHistoryEnabledCallCount, 1)
    }
}
