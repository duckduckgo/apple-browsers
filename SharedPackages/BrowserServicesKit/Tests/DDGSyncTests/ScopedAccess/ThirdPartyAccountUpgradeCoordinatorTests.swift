//
//  ThirdPartyAccountUpgradeCoordinatorTests.swift
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

import Foundation
import XCTest

@testable import DDGSync

final class ThirdPartyAccountUpgradeCoordinatorTests: XCTestCase {

    private static let baseURL = URL(string: "https://dev.null")!
    private let userId = "user-1"
    private let scopedPassword = Data((32..<64).map(UInt8.init))
    private let defaultPrimaryKey = Data((64..<96).map(UInt8.init))
    private let defaultSecretKey = Data((96..<128).map(UInt8.init))
    private let protectedSecretKey = Data((128..<160).map(UInt8.init))
    private let defaultPasswordHash = Data([0xAB, 0xCD])
    private let extractedSecretKey = Data((160..<192).map(UInt8.init))

    func testWhenUpgradeSucceedsThenReturnsNativeAccountDevicesScopedPasswordAndRewrappedKeys() async throws {
        let setup = try makeSUT()

        let result = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
            recoveryCode(),
            deviceName: "Mac",
            deviceType: "desktop")

        XCTAssertEqual(result.account.userId, userId)
        XCTAssertEqual(result.account.primaryKey, defaultPrimaryKey)
        XCTAssertEqual(result.account.secretKey, extractedSecretKey)
        XCTAssertEqual(result.account.token, "native-token")
        XCTAssertEqual(result.devices.map(\.id), ["native-device"])
        XCTAssertEqual(result.devices.map(\.name), ["Mac"])
        XCTAssertEqual(result.devices.map(\.type), ["desktop"])
        XCTAssertEqual(result.scopedPassword, scopedPassword)
        XCTAssertEqual(result.protectedKeys.map(\.encryptedWith), [SyncCredentialID.defaultCredential])
        XCTAssertEqual(result.protectedKeys.map(\.kid), ["key-1"])

        let postBody = try body(for: setup.endpoints.accessCredential(SyncCredentialID.defaultCredential), in: setup.api)
        let postPayload = try decodeJSONObject(postBody)
        XCTAssertEqual(postPayload["protected_encryption_key"] as? String, protectedSecretKey.base64EncodedString())
        XCTAssertEqual(postPayload["credential_hashed_password"] as? String, defaultPasswordHash.base64EncodedString())

        let encryptedCredential = try XCTUnwrap(postPayload["encrypted_3party_credential"] as? String)
        let defaultCredentialMainKey = ScopedAccessKeyDerivation.mainKey(from: defaultPrimaryKey, userID: userId)
        let decryptedCredential = try ScopedAccessCredentialEnvelope().decryptScopedPassword(from: encryptedCredential,
                                                                                            using: defaultCredentialMainKey)
        XCTAssertEqual(decryptedCredential, scopedPassword)

        let keys = try XCTUnwrap(postPayload["keys"] as? [[String: Any]])
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys.first?["kid"] as? String, "key-1")
        XCTAssertEqual(keys.first?["encrypted_with"] as? String, SyncCredentialID.defaultCredential)
    }

    func testWhenUpgradeRunsThenTemporaryLoginUsesAIChatsScopeAndFinalNativeLoginUsesSyncScope() async throws {
        let setup = try makeSUT()

        _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
            recoveryCode(),
            deviceName: "Mac",
            deviceType: "desktop")

        let loginBodies = setup.api.createRequestCallArgs
            .filter { $0.url == setup.endpoints.login }
            .compactMap(\.body)
        XCTAssertEqual(loginBodies.count, 2)

        let temporaryLoginPayload = try decodeJSONObject(try XCTUnwrap(loginBodies.first))
        let finalLoginPayload = try decodeJSONObject(try XCTUnwrap(loginBodies.last))
        XCTAssertEqual(temporaryLoginPayload["scope"] as? String, "ai_chats")
        XCTAssertEqual(finalLoginPayload["scope"] as? String, "sync")
    }

    func testWhenUpgradeSucceedsThenTemporaryThirdPartyDeviceIsLoggedOut() async throws {
        let setup = try makeSUT()

        _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
            recoveryCode(),
            deviceName: "Mac",
            deviceType: "desktop")

        let loginBody = try XCTUnwrap(setup.api.createRequestCallArgs.first { $0.url == setup.endpoints.login }?.body)
        let loginPayload = try decodeJSONObject(loginBody)
        let temporaryDeviceId = try XCTUnwrap(loginPayload["device_id"] as? String)

        XCTAssertEqual(setup.account.logoutCalls.map(\.deviceId), [temporaryDeviceId])
        XCTAssertEqual(setup.account.logoutCalls.map(\.token), ["third-party-token"])
    }

    func testWhenTemporaryThirdPartyDeviceLogoutFailsThenUpgradeStillReturnsNativeAccount() async throws {
        let setup = try makeSUT()
        setup.account.logoutError = SyncError.unexpectedStatusCode(500)

        let result = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
            recoveryCode(),
            deviceName: "Mac",
            deviceType: "desktop")

        XCTAssertEqual(setup.account.logoutCalls.map(\.token), ["third-party-token"])
        XCTAssertEqual(result.account.token, "native-token")
    }

    func testWhenUpgradeAbortsAfterTemporaryLoginThenTemporaryThirdPartyDeviceIsLoggedOut() async throws {
        let accessCredentials = [AccessCredential(id: SyncCredentialID.defaultCredential, scope: "sync", encrypted3PartyCredential: nil)]
        let setup = try makeSUT(accessCredentials: accessCredentials)

        do {
            _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
                recoveryCode(),
                deviceName: "Mac",
                deviceType: "desktop")
            XCTFail("Expected existing ddg credential to abort upgrade")
        } catch ThirdPartyAccountUpgradeError.nativeCredentialAlreadyPresent {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(setup.account.logoutCalls.map(\.token), ["third-party-token"])
    }

    func testWhenFinalNativeLoginFailsTransientlyThenRetriesAndReturnsNativeAccount() async throws {
        let setup = try makeSUT(finalNativeLoginRetryDelays: [0, 0])
        setup.api.fakeRequests[setup.endpoints.login] = SequencedThrowingHTTPRequestingMock(results: [
            .success(.init(data: Data(thirdPartyLoginBody().utf8), response: makeHTTPURLResponse(statusCode: 200))),
            .failure(SyncError.unexpectedStatusCode(500)),
            .success(.init(data: Data(finalNativeLoginBody().utf8), response: makeHTTPURLResponse(statusCode: 200)))
        ])

        let result = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
            recoveryCode(),
            deviceName: "Mac",
            deviceType: "desktop")

        let loginCalls = setup.api.createRequestCallArgs.filter { $0.url == setup.endpoints.login }
        XCTAssertEqual(loginCalls.count, 3)
        XCTAssertEqual(setup.account.logoutCalls.map(\.token), ["third-party-token"])
        XCTAssertEqual(result.account.token, "native-token")
    }

    func testWhenFinalNativeLoginKeepsFailingThenRetriesAndLogsOutTemporaryThirdPartyDevice() async throws {
        let setup = try makeSUT(finalNativeLoginRetryDelays: [0, 0])
        setup.api.fakeRequests[setup.endpoints.login] = SequencedThrowingHTTPRequestingMock(results: [
            .success(.init(data: Data(thirdPartyLoginBody().utf8), response: makeHTTPURLResponse(statusCode: 200))),
            .failure(SyncError.unexpectedStatusCode(500)),
            .failure(SyncError.unexpectedStatusCode(500)),
            .failure(SyncError.unexpectedStatusCode(500))
        ])

        do {
            _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
                recoveryCode(),
                deviceName: "Mac",
                deviceType: "desktop")
            XCTFail("Expected persistent final native login failure")
        } catch ThirdPartyAccountUpgradeError.finalNativeLoginFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let loginCalls = setup.api.createRequestCallArgs.filter { $0.url == setup.endpoints.login }
        XCTAssertEqual(loginCalls.count, 4)
        XCTAssertEqual(setup.account.logoutCalls.map(\.token), ["third-party-token"])
    }

    func testWhenFinalNativeLoginReturnsUnauthorizedThenDoesNotRetryAndLogsOutTemporaryThirdPartyDevice() async throws {
        let setup = try makeSUT(finalNativeLoginRetryDelays: [0, 0])
        setup.api.fakeRequests[setup.endpoints.login] = SequencedThrowingHTTPRequestingMock(results: [
            .success(.init(data: Data(thirdPartyLoginBody().utf8), response: makeHTTPURLResponse(statusCode: 200))),
            .failure(SyncError.unexpectedStatusCode(401))
        ])

        do {
            _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
                recoveryCode(),
                deviceName: "Mac",
                deviceType: "desktop")
            XCTFail("Expected unauthorized final native login failure")
        } catch ThirdPartyAccountUpgradeError.finalNativeLoginFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let loginCalls = setup.api.createRequestCallArgs.filter { $0.url == setup.endpoints.login }
        XCTAssertEqual(loginCalls.count, 2)
        XCTAssertEqual(setup.account.logoutCalls.map(\.token), ["third-party-token"])
    }

    func testWhenDDGCredentialAlreadyExistsThenUpgradeAborts() async throws {
        let accessCredentials = [AccessCredential(id: SyncCredentialID.defaultCredential, scope: "sync", encrypted3PartyCredential: nil)]
        let setup = try makeSUT(accessCredentials: accessCredentials)

        do {
            _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
                recoveryCode(),
                deviceName: "Mac",
                deviceType: "desktop")
            XCTFail("Expected existing ddg credential to abort upgrade")
        } catch ThirdPartyAccountUpgradeError.nativeCredentialAlreadyPresent {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(setup.api.createRequestCallArgs.contains { $0.url == setup.endpoints.accessCredential(SyncCredentialID.defaultCredential) })
    }

    func testWhenNoUsableThirdPartyProtectedKeysExistThenUpgradeAborts() async throws {
        let setup = try makeSUT(protectedKeys: [])

        do {
            _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
                recoveryCode(),
                deviceName: "Mac",
                deviceType: "desktop")
            XCTFail("Expected missing 3party keys to abort upgrade")
        } catch ThirdPartyAccountUpgradeError.noUsableThirdPartyProtectedKeys {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(setup.api.createRequestCallArgs.contains { $0.url == setup.endpoints.accessCredential(SyncCredentialID.defaultCredential) })
    }

    func testWhenAccessCredentialsFetchFailsThenUpgradeAbortsWithTypedError() async throws {
        let setup = try makeSUT()
        let request = HTTPRequestingMock()
        request.error = SyncError.unexpectedStatusCode(500)
        setup.api.fakeRequests[setup.endpoints.accessCredentials] = request

        do {
            _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
                recoveryCode(),
                deviceName: "Mac",
                deviceType: "desktop")
            XCTFail("Expected access credential fetch failure to abort upgrade")
        } catch ThirdPartyAccountUpgradeError.accessCredentialsFetchFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWhenProtectedKeysFetchFailsThenUpgradeAbortsWithTypedError() async throws {
        let setup = try makeSUT()
        let request = HTTPRequestingMock()
        request.error = SyncError.unexpectedStatusCode(500)
        setup.api.fakeRequests[setup.endpoints.keys] = request

        do {
            _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
                recoveryCode(),
                deviceName: "Mac",
                deviceType: "desktop")
            XCTFail("Expected protected key fetch failure to abort upgrade")
        } catch ThirdPartyAccountUpgradeError.protectedKeysFetchFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWhenProtectedKeyRewrapFailsThenUpgradeAbortsWithTypedError() async throws {
        let invalidProtectedKey = ProtectedKey(kid: "key-1",
                                               encryptedPrivateKey: "not-jwe",
                                               publicKey: .mock,
                                               encryptedWith: SyncCode.RecoveryKeyV2.thirdPartyCredentialId,
                                               purpose: "ai_chats")
        let setup = try makeSUT(protectedKeys: [invalidProtectedKey])

        do {
            _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
                recoveryCode(),
                deviceName: "Mac",
                deviceType: "desktop")
            XCTFail("Expected protected key rewrap failure to abort upgrade")
        } catch ThirdPartyAccountUpgradeError.protectedKeyRewrapFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWhenNativeCredentialCreationReturnsUnexpectedStatusThenUpgradeAbortsWithTypedError() async throws {
        let setup = try makeSUT()
        setup.api.fakeRequests[setup.endpoints.accessCredential(SyncCredentialID.defaultCredential)] = makeRequest(statusCode: 500)

        do {
            _ = try await setup.coordinator.upgradeThirdPartyAccountToDefaultCredential(
                recoveryCode(),
                deviceName: "Mac",
                deviceType: "desktop")
            XCTFail("Expected native credential creation failure to abort upgrade")
        } catch ThirdPartyAccountUpgradeError.nativeCredentialCreationFailed(let statusCode) {
            XCTAssertEqual(statusCode, 500)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeSUT(accessCredentials: [AccessCredential] = [],
                         protectedKeys: [ProtectedKey]? = nil,
                         finalNativeLoginRetryDelays: [UInt64] = []) throws -> (coordinator: ThirdPartyAccountUpgradeCoordinator,
                                                                                 api: RemoteAPIRequestCreatingMock,
                                                                                 account: AccountManagingMock,
                                                                                 endpoints: Endpoints) {
        let api = RemoteAPIRequestCreatingMock()
        let account = AccountManagingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let userId = self.userId
        let defaultPrimaryKey = self.defaultPrimaryKey
        let defaultSecretKey = self.defaultSecretKey
        let protectedSecretKey = self.protectedSecretKey
        let defaultPasswordHash = self.defaultPasswordHash
        let extractedSecretKey = self.extractedSecretKey
        var crypter = CryptingMock()
        crypter._createAccountCreationKeys = { receivedUserId, _ in
            XCTAssertEqual(receivedUserId, userId)
            return AccountCreationKeys(primaryKey: defaultPrimaryKey,
                                       secretKey: defaultSecretKey,
                                       protectedSecretKey: protectedSecretKey,
                                       passwordHash: defaultPasswordHash)
        }
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0x99]),
                               stretchedPrimaryKey: Data([0x88]))
        }
        crypter._extractSecretKey = { _, _ in extractedSecretKey }

        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)
        let coordinator = ThirdPartyAccountUpgradeCoordinator(endpoints: endpoints,
                                                              api: api,
                                                              crypter: crypter,
                                                              scopedAccess: manager,
                                                              account: account,
                                                              finalNativeLoginRetryDelays: finalNativeLoginRetryDelays)
        let keys = try protectedKeys ?? [thirdPartyProtectedKey()]

        api.fakeRequests[endpoints.login] = SequencedHTTPRequestingMock(results: [
            .init(data: Data(thirdPartyLoginBody().utf8), response: makeHTTPURLResponse(statusCode: 200)),
            .init(data: Data(finalNativeLoginBody().utf8), response: makeHTTPURLResponse(statusCode: 200))
        ])
        api.fakeRequests[endpoints.accessCredentials] = makeRequest(statusCode: 200, body: try accessCredentialsBody(accessCredentials))
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200, body: try protectedKeysBody(keys))
        api.fakeRequests[endpoints.accessCredential(SyncCredentialID.defaultCredential)] = makeRequest(statusCode: 201)

        return (coordinator, api, account, endpoints)
    }

    private func recoveryCode() throws -> String {
        let payload = SyncCode.RecoveryKeyV2(userId: userId,
                                            secret: Base64URL.encode(scopedPassword),
                                            cid: SyncCode.RecoveryKeyV2.thirdPartyCredentialId,
                                            v: SyncCode.RecoveryKeyV2.currentVersion)
        return Base64URL.encode(try SyncCode(recovery: .v2(payload)).toJSON())
    }

    private func thirdPartyProtectedKey() throws -> ProtectedKey {
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: userId)
        let encryptedPrivateKey = try JWECompactCodec().encryptDirect(payload: Data("private-key".utf8),
                                                                      contentEncryptionKey: thirdPartyMainKey,
                                                                      kid: SyncCode.RecoveryKeyV2.thirdPartyCredentialId)
        return ProtectedKey(kid: "key-1",
                            encryptedPrivateKey: encryptedPrivateKey,
                            publicKey: .mock,
                            encryptedWith: SyncCode.RecoveryKeyV2.thirdPartyCredentialId,
                            purpose: "ai_chats")
    }

    private func thirdPartyLoginBody() -> String {
        """
        {
          "token": "third-party-token",
          "devices": [
            {
              "id": "third-party-device",
              "name": "\(Data("Third Party".utf8).base64EncodedString())",
              "type": "\(Data("third-party".utf8).base64EncodedString())"
            }
          ]
        }
        """
    }

    private func finalNativeLoginBody() -> String {
        """
        {
          "devices": [
            {
              "id": "native-device",
              "name": "encrypted_Mac",
              "type": "encrypted_desktop"
            }
          ],
          "token": "native-token",
          "protected_encryption_key": "\(Data([0x01, 0x02, 0x03]).base64EncodedString())",
          "access_credentials": [],
          "keys": []
        }
        """
    }

    private func makeRequest(statusCode: Int, body: String? = nil) -> HTTPRequestingMock {
        HTTPRequestingMock(result: .init(data: body.map { Data($0.utf8) },
                                         response: makeHTTPURLResponse(statusCode: statusCode)))
    }

    private func makeHTTPURLResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://dev.null/test")!,
                        statusCode: statusCode,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    private func accessCredentialsBody(_ accessCredentials: [AccessCredential]) throws -> String {
        let data = try JSONEncoder.snakeCaseKeys.encode(FetchAccessCredentialsBody(accessCredentials: accessCredentials.map(AccessCredentialResponse.init)))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func protectedKeysBody(_ keys: [ProtectedKey]) throws -> String {
        let data = try JSONEncoder.snakeCaseKeys.encode(FetchProtectedKeysBody(keys: keys))
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func body(for url: URL, in api: RemoteAPIRequestCreatingMock) throws -> Data {
        let call = try XCTUnwrap(api.createRequestCallArgs.first { $0.url == url })
        return try XCTUnwrap(call.body)
    }

    private func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Expected dictionary JSON payload")
            return [:]
        }
        return object
    }

    private struct FetchAccessCredentialsBody: Encodable {
        let accessCredentials: [AccessCredentialResponse]
    }

    private struct AccessCredentialResponse: Encodable {
        let id: String
        let scope: String?
        let encrypted3PartyCredential: String?

        init(_ accessCredential: AccessCredential) {
            id = accessCredential.id
            scope = accessCredential.scope
            encrypted3PartyCredential = accessCredential.encrypted3PartyCredential
        }

        enum CodingKeys: String, CodingKey {
            case id
            case scope
            case encrypted3PartyCredential = "encrypted_3party_credential"
        }
    }

    private struct FetchProtectedKeysBody: Encodable {
        let keys: [ProtectedKey]
    }
}

private extension Endpoints {
    func accessCredential(_ id: String) -> URL {
        accessCredentials.appendingPathComponent(id)
    }
}

private final class SequencedThrowingHTTPRequestingMock: HTTPRequestingMock {
    private var results: [Result<HTTPResult, Error>]

    init(results: [Result<HTTPResult, Error>]) {
        self.results = results
        super.init(result: (try? results.last?.get()) ?? .init(data: Data(), response: HTTPURLResponse()))
    }

    override func execute() async throws -> HTTPResult {
        executeCallCount += 1
        if results.count > 1 {
            return try results.removeFirst().get()
        }
        return try results.first?.get() ?? result
    }
}
