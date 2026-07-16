//
//  ScopedAccessCredentialManagerTests.swift
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

import CryptoKit
import Foundation
import XCTest

@testable import DDGSync

final class ScopedAccessCredentialManagerTests: XCTestCase {

    private static let baseURL = URL(string: "https://dev.null")!

    func testWhenEnsuringScopedPasswordAndCredentialExistsThenRecoversPasswordWithoutCreatingCredential() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())

        let scopedPassword = Data(repeating: 8, count: 32)
        let account = makeAccount(primaryKey: Data((0..<32).map(UInt8.init)))
        let defaultCredentialMainKey = hkdf(input: account.primaryKey, salt: account.userId, info: "Main Key")
        let encryptedCredential = try ScopedAccessCredentialEnvelope().encryptScopedPassword(scopedPassword,
                                                                                           using: defaultCredentialMainKey,
                                                                                           kid: "ddg")
        let accessCredentials = [AccessCredential(id: "3party", scope: "sync", encrypted3PartyCredential: encryptedCredential)]
        api.fakeRequests[endpoints.accessCredentials] = makeRequest(statusCode: 200, body: try accessCredentialsBody(accessCredentials))

        let result = try await manager.ensureThirdPartyScopedPassword(for: account,
                                                                      purpose: "ai_chats",
                                                                      cachedScopedPassword: {
                                                                          XCTFail("Existing credentials should not read cached scoped password")
                                                                          return nil
                                                                      })

        XCTAssertEqual(result.scopedPassword, scopedPassword)
        XCTAssertTrue(result.protectedKeysToCache.isEmpty)
        XCTAssertEqual(api.createRequestCallArgs.map(\.url), [endpoints.accessCredentials])
    }

    func testWhenEnsuringScopedPasswordAndCredentialIsMissingThenCreatesCredentialUsingProtectedKeys() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0xAB]),
                               stretchedPrimaryKey: Data())
        }
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)

        let scopedPassword = Data((32..<64).map(UInt8.init))
        let account = makeAccount(primaryKey: Data((0..<32).map(UInt8.init)))
        let protectedKey = try makeNativeEncryptedProtectedKey(privateKey: Data("default-private-key".utf8), account: account, crypter: crypter)
        api.fakeRequests[endpoints.accessCredentials] = makeRequest(statusCode: 200, body: try accessCredentialsBody([]))
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200, body: try protectedKeysBody([protectedKey]))
        api.fakeRequests[endpoints.accessCredential("3party")] = makeRequest(statusCode: 201)

        let result = try await manager.ensureThirdPartyScopedPassword(for: account,
                                                                      purpose: "ai_chats",
                                                                      cachedScopedPassword: { scopedPassword })

        XCTAssertEqual(result.scopedPassword, scopedPassword)
        XCTAssertEqual(result.protectedKeysToCache.map(\.kid), [protectedKey.kid])

        let requestBody = try XCTUnwrap(api.createRequestCallArgs.last?.body)
        let payload = try decodeJSONObject(requestBody)
        let keys = try XCTUnwrap(payload["keys"] as? [[String: Any]])
        XCTAssertEqual(keys.count, 1)
        XCTAssertEqual(keys.first?["kid"] as? String, protectedKey.kid)
        XCTAssertEqual(keys.first?["encrypted_with"] as? String, "3party")
    }

    func testWhenEnsuringScopedPasswordAndNoDefaultKeyExistsThenUploadsDefaultAndThirdPartyKeys() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0xAB]),
                               stretchedPrimaryKey: Data())
        }
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)

        let scopedPassword = Data((32..<64).map(UInt8.init))
        let account = makeAccount(primaryKey: Data((0..<32).map(UInt8.init)))
        api.fakeRequests[endpoints.accessCredentials] = makeRequest(statusCode: 200, body: try accessCredentialsBody([]))
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200, body: try protectedKeysBody([]))
        api.fakeRequests[endpoints.accessCredential("3party")] = makeRequest(statusCode: 201)

        let result = try await manager.ensureThirdPartyScopedPassword(for: account,
                                                                      purpose: "ai_chats",
                                                                      cachedScopedPassword: { scopedPassword })

        let protectedKey = try XCTUnwrap(result.protectedKeysToCache.first)
        XCTAssertEqual(protectedKey.encryptedWith, "ddg")
        XCTAssertEqual(protectedKey.purpose, "ai_chats")

        let requestBody = try XCTUnwrap(api.createRequestCallArgs.last?.body)
        let payload = try decodeJSONObject(requestBody)
        let keys = try XCTUnwrap(payload["keys"] as? [[String: Any]])
        XCTAssertEqual(keys.count, 2)
        XCTAssertNotNil(keys.first { $0["encrypted_with"] as? String == "ddg" })
        XCTAssertNotNil(keys.first { $0["encrypted_with"] as? String == "3party" })
    }

    func testWhenFetchingAccessCredentialsReturns404ThenReturnsEmptyCredentials() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data((0..<32).map(UInt8.init)))
        api.fakeRequests[endpoints.accessCredentials] = makeFailingRequest(statusCode: 404)

        let credentials = try await manager.fetchAccessCredentials(account)

        XCTAssertTrue(credentials.isEmpty)
    }

    func testWhenFetchingProtectedKeysReturns404ThenReturnsEmptyKeys() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data((0..<32).map(UInt8.init)))
        api.fakeRequests[endpoints.keys] = makeFailingRequest(statusCode: 404)

        let keys = try await manager.fetchProtectedKeys(account)

        XCTAssertTrue(keys.isEmpty)
    }

    func testWhenEnsuringThirdPartyScopedPasswordThenUsesHKDFAndJWEAndPostsThirdPartyKeysOnly() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0xAB]),
                               stretchedPrimaryKey: Data())
        }
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)

        let accountPrimaryKey = Data((0..<32).map(UInt8.init))
        let scopedPassword = Data((32..<64).map(UInt8.init))
        let account = makeAccount(primaryKey: accountPrimaryKey)
        let defaultCredentialMainKey = hkdf(input: accountPrimaryKey, salt: account.userId, info: "Main Key")
        let ddgWrappedProtectedKey = try makeNativeEncryptedProtectedKey(privateKey: Data("default-private-key".utf8), account: account, crypter: crypter)
        let thirdPartyWrappedProtectedKey = ProtectedKey(kid: ddgWrappedProtectedKey.kid,
                                                         encryptedPrivateKey: "rewrapped-private-key",
                                                         publicKey: ddgWrappedProtectedKey.publicKey,
                                                         encryptedWith: "3party",
                                                         purpose: ddgWrappedProtectedKey.purpose)
        api.fakeRequests[endpoints.accessCredentials] = makeRequest(statusCode: 200, body: try accessCredentialsBody([]))
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200,
                                                       body: try protectedKeysBody([ddgWrappedProtectedKey, thirdPartyWrappedProtectedKey]))
        api.fakeRequests[endpoints.accessCredential("3party")] = makeRequest(statusCode: 201)

        let result = try await manager.ensureThirdPartyScopedPassword(for: account,
                                                                      purpose: "ai_chats",
                                                                      cachedScopedPassword: { scopedPassword })

        XCTAssertEqual(result.scopedPassword, scopedPassword)

        let requestBody = try XCTUnwrap(api.createRequestCallArgs.last?.body)
        let payload = try decodeJSONObject(requestBody)

        XCTAssertEqual(payload["hashed_password"] as? String, Data([0xAB]).base64EncodedString())
        XCTAssertEqual(payload["credential_hashed_password"] as? String, Base64URL.encode(hkdf(input: scopedPassword, salt: account.userId, info: "Password")))

        let encryptedCredential = try XCTUnwrap(payload["encrypted_3party_credential"] as? String)
        let decryptedCredential = try ScopedAccessCredentialEnvelope().decryptScopedPassword(from: encryptedCredential, using: defaultCredentialMainKey)
        XCTAssertEqual(decryptedCredential, scopedPassword)

        let keys = try XCTUnwrap(payload["keys"] as? [[String: Any]])
        XCTAssertEqual(keys.count, 1)
        XCTAssertNil(keys.first { $0["encrypted_with"] as? String == "ddg" })
        let keyPayload = try XCTUnwrap(keys.first)
        XCTAssertEqual(keyPayload["kid"] as? String, ddgWrappedProtectedKey.kid)
        XCTAssertEqual(keyPayload["purpose"] as? String, "ai_chats")
        XCTAssertEqual(keyPayload["encrypted_with"] as? String, "3party")
    }

    func testWhenEnsuringThirdPartyScopedPasswordWithExistingDefaultKeyThenPostsRewrappedKeyOnly() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0xAB]),
                               stretchedPrimaryKey: Data())
        }
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)

        let accountPrimaryKey = Data((0..<32).map(UInt8.init))
        let scopedPassword = Data((32..<64).map(UInt8.init))
        let account = makeAccount(primaryKey: accountPrimaryKey)
        let thirdPartyMainKey = hkdf(input: scopedPassword, salt: account.userId, info: "Main Key")
        let originalPrivateKey = Data("default-private-key".utf8)
        let ddgWrappedProtectedKey = try makeNativeEncryptedProtectedKey(privateKey: originalPrivateKey, account: account, crypter: crypter)
        api.fakeRequests[endpoints.accessCredentials] = makeRequest(statusCode: 200, body: try accessCredentialsBody([]))
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200, body: try protectedKeysBody([ddgWrappedProtectedKey]))
        api.fakeRequests[endpoints.accessCredential("3party")] = makeRequest(statusCode: 201)

        _ = try await manager.ensureThirdPartyScopedPassword(for: account,
                                                             purpose: "ai_chats",
                                                             cachedScopedPassword: { scopedPassword })

        let requestBody = try XCTUnwrap(api.createRequestCallArgs.last?.body)
        let payload = try decodeJSONObject(requestBody)
        let keys = try XCTUnwrap(payload["keys"] as? [[String: Any]])
        XCTAssertEqual(keys.count, 1)
        XCTAssertNil(keys.first { $0["encrypted_with"] as? String == "ddg" })

        let rewrappedKeyPayload = try XCTUnwrap(keys.first { $0["encrypted_with"] as? String == "3party" })
        XCTAssertEqual(rewrappedKeyPayload["kid"] as? String, ddgWrappedProtectedKey.kid)
        XCTAssertEqual(rewrappedKeyPayload["purpose"] as? String, "ai_chats")

        let rewrappedEncryptedPrivateKey = try XCTUnwrap(rewrappedKeyPayload["encrypted_private_key"] as? String)
        let decryptedRewrappedPrivateKey = try JWECompactCodec().decryptDirect(token: rewrappedEncryptedPrivateKey, contentEncryptionKey: thirdPartyMainKey)
        XCTAssertEqual(decryptedRewrappedPrivateKey, originalPrivateKey)
    }

    func testWhenCreatingThirdPartyScopedPasswordReturns409ThenRefetchesAndRecoversScopedPassword() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0xAB]),
                               stretchedPrimaryKey: Data())
        }
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)

        let accountPrimaryKey = Data((0..<32).map(UInt8.init))
        let localScopedPassword = Data((32..<64).map(UInt8.init))
        let recoveredScopedPassword = Data((64..<96).map(UInt8.init))
        let account = makeAccount(primaryKey: accountPrimaryKey)
        let defaultCredentialMainKey = hkdf(input: accountPrimaryKey, salt: account.userId, info: "Main Key")
        let encryptedCredential = try ScopedAccessCredentialEnvelope().encryptScopedPassword(recoveredScopedPassword,
                                                                                           using: defaultCredentialMainKey,
                                                                                           kid: "ddg")
        let accessCredentials = [AccessCredential(id: "3party", scope: "sync", encrypted3PartyCredential: encryptedCredential)]
        api.fakeRequests[endpoints.accessCredentials] = SequencedHTTPRequestingMock(results: [
            .init(data: Data(try accessCredentialsBody([]).utf8), response: makeHTTPURLResponse(statusCode: 200)),
            .init(data: Data(try accessCredentialsBody(accessCredentials).utf8), response: makeHTTPURLResponse(statusCode: 200))
        ])
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200, body: try protectedKeysBody([]))
        api.fakeRequests[endpoints.accessCredential("3party")] = makeFailingRequest(statusCode: 409)

        let result = try await manager.ensureThirdPartyScopedPassword(for: account,
                                                                      purpose: "ai_chats",
                                                                      cachedScopedPassword: { localScopedPassword })

        XCTAssertEqual(result.scopedPassword, recoveredScopedPassword)
        XCTAssertEqual(api.createRequestCallArgs.map(\.url), [
            endpoints.accessCredentials,
            endpoints.keys,
            endpoints.accessCredential("3party"),
            endpoints.accessCredentials
        ])
    }

    func testWhenDefaultCredentialProtectedKeyIsDirectJWEThenThrowsAccountExtendFailed() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._extractLoginInfo = { recoveryKey in
            ExtractedLoginInfo(userId: recoveryKey.userId,
                               primaryKey: recoveryKey.primaryKey,
                               passwordHash: Data([0xAB]),
                               stretchedPrimaryKey: Data())
        }
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: crypter)

        let accountPrimaryKey = Data((0..<32).map(UInt8.init))
        let scopedPassword = Data((32..<64).map(UInt8.init))
        let account = makeAccount(primaryKey: accountPrimaryKey)
        let defaultCredentialMainKey = hkdf(input: accountPrimaryKey, salt: account.userId, info: "Main Key")
        let ddgWrappedProtectedKey = try ScopedAccessKeyFactory.makeJWEProtectedKey(wrappingKey: defaultCredentialMainKey,
                                                                                    encryptedWith: "ddg",
                                                                                    purpose: "ai_chats")
        api.fakeRequests[endpoints.accessCredentials] = makeRequest(statusCode: 200, body: try accessCredentialsBody([]))
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200, body: try protectedKeysBody([ddgWrappedProtectedKey]))

        do {
            _ = try await manager.ensureThirdPartyScopedPassword(for: account,
                                                                 purpose: "ai_chats",
                                                                 cachedScopedPassword: { scopedPassword })
            XCTFail("Expected direct-JWE ddg source key to be rejected")
        } catch ScopedAccessCredentialError.accountExtendFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWhenSetKeyIfAbsentReturns409ThenRefetchesAndReconciles() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x1, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested", encryptedWith: "ddg", purpose: "ai_chats")

        let conflictRequest = HTTPRequestingMock()
        conflictRequest.error = SyncError.unexpectedStatusCode(409)
        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = conflictRequest
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200,
                                                       body: """
                                                       {
                                                         "keys": [
                                                           {
                                                             "kid": "requested",
                                                             "encrypted_private_key": "enc-private",
                                                             "public_key": {
                                                               "kty": "RSA",
                                                               "alg": "RSA-OAEP-256",
                                                               "use": "enc",
                                                               "n": "mod",
                                                               "e": "AQAB"
                                                             },
                                                             "encrypted_with": "ddg",
                                                             "purpose": "ai_chats"
                                                           }
                                                         ]
                                                       }
                                                       """)

        let result = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)

        XCTAssertEqual(result?.kid, "requested")
        XCTAssertEqual(result?.encryptedWith, "ddg")
        XCTAssertEqual(result?.purpose, "ai_chats")
        XCTAssertEqual(api.createRequestCallArgs.count, 2)
    }

    func testWhenSetKeyIfAbsentReturns409WithOnlyPurposeMatchThenThrows() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x1, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested", encryptedWith: "ddg", purpose: "ai_chats")

        let conflictRequest = HTTPRequestingMock()
        conflictRequest.error = SyncError.unexpectedStatusCode(409)
        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = conflictRequest
        api.fakeRequests[endpoints.keys] = makeRequest(statusCode: 200,
                                                       body: """
                                                       {
                                                         "keys": [
                                                           {
                                                             "kid": "server-3party",
                                                             "encrypted_private_key": "enc-private",
                                                             "public_key": {
                                                               "kty": "RSA",
                                                               "alg": "RSA-OAEP-256",
                                                               "use": "enc",
                                                               "n": "mod",
                                                               "e": "AQAB"
                                                             },
                                                             "encrypted_with": "3party",
                                                             "purpose": "ai_chats"
                                                           }
                                                         ]
                                                       }
                                                       """)

        do {
            _ = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)
            XCTFail("Expected setKeyIfAbsent to throw")
        } catch SyncError.invalidDataInResponse(let message) {
            XCTAssertTrue(message.contains("no matching key"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.createRequestCallArgs.count, 2)
    }

    func testWhenSetKeyIfAbsentReturnsWrappedKeysThenMatchingKeyIsReturned() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x3, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested", encryptedWith: "ddg", purpose: "ai_chats")

        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = makeRequest(statusCode: 201,
                                                                                       body: """
                                                                                       {
                                                                                         "keys": [
                                                                                           {
                                                                                             "kid": "server-other",
                                                                                             "encrypted_private_key": "enc-private-other",
                                                                                             "public_key": {
                                                                                               "kty": "RSA",
                                                                                               "alg": "RSA-OAEP-256",
                                                                                               "use": "enc",
                                                                                               "n": "mod",
                                                                                               "e": "AQAB"
                                                                                             },
                                                                                             "encrypted_with": "3party",
                                                                                             "purpose": "bookmarks"
                                                                                           },
                                                                                           {
                                                                                             "kid": "requested",
                                                                                             "encrypted_private_key": "enc-private",
                                                                                             "public_key": {
                                                                                               "kty": "RSA",
                                                                                               "alg": "RSA-OAEP-256",
                                                                                               "use": "enc",
                                                                                               "n": "mod",
                                                                                               "e": "AQAB"
                                                                                             },
                                                                                             "encrypted_with": "ddg",
                                                                                             "purpose": "ai_chats"
                                                                                           }
                                                                                         ]
                                                                                       }
                                                                                       """)

        let result = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)

        XCTAssertEqual(result?.kid, "requested")
        XCTAssertEqual(result?.encryptedWith, "ddg")
        XCTAssertEqual(result?.purpose, "ai_chats")
    }

    func testWhenSetKeyIfAbsentReturns200ThenThrowsUnexpectedStatusCode() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x4, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested", encryptedWith: "ddg", purpose: "ai_chats")

        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = makeRequest(statusCode: 200)

        do {
            _ = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)
            XCTFail("Expected setKeyIfAbsent to throw")
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            XCTAssertEqual(statusCode, 200)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.createRequestCallArgs.count, 1)
    }

    func testWhenKeysPayloadIsRejectedThenThrowsUnexpectedStatusCode() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data(repeating: 0x9, count: 32))
        let requestedKey = makeProtectedKey(kid: "requested",
                                            encryptedWith: "ddg",
                                            purpose: "ai_chats")

        let rejectingRequest = HTTPRequestingMock()
        rejectingRequest.error = SyncError.unexpectedStatusCode(422)
        api.fakeRequests[endpoints.setKeyIfAbsent(purpose: "ai_chats")] = rejectingRequest

        do {
            _ = try await manager.setKeyIfAbsent(purpose: "ai_chats", key: requestedKey, for: account)
            XCTFail("Expected setKeyIfAbsent to throw")
        } catch SyncError.unexpectedStatusCode(let statusCode) {
            XCTAssertEqual(statusCode, 422)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.createRequestCallArgs.count, 1)
    }

    func testWhenFetchingProtectedKeysFailsThenCachedKeysAreNotUsedForThirdPartyCredentialCreation() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let manager = ScopedAccessCredentialManager(endpoints: endpoints, api: api, crypter: CryptingMock())
        let account = makeAccount(primaryKey: Data((0..<32).map(UInt8.init)))
        api.fakeRequests[endpoints.accessCredentials] = makeRequest(statusCode: 200, body: try accessCredentialsBody([]))
        api.fakeRequests[endpoints.keys] = makeFailingRequest(statusCode: 500)

        do {
            _ = try await manager.ensureThirdPartyScopedPassword(for: account,
                                                                 purpose: "ai_chats",
                                                                 cachedScopedPassword: { Data((32..<64).map(UInt8.init)) })
            XCTFail("Expected fetchProtectedKeys failure to become account extend failure")
        } catch ScopedAccessCredentialError.accountExtendFailed {
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(api.createRequestCallArgs.map(\.url), [
            endpoints.accessCredentials,
            endpoints.keys
        ])
    }

    private func makeAccount(primaryKey: Data) -> SyncAccount {
        SyncAccount(deviceId: "device-1",
                    deviceName: "iPhone",
                    deviceType: "ios",
                    userId: "user-1",
                    primaryKey: primaryKey,
                    secretKey: Data(repeating: 0x2, count: 32),
                    token: "token-1",
                    state: .active)
    }

    private func makeProtectedKey(kid: String,
                                  encryptedWith: String,
                                  purpose: String,
                                  publicKey: ProtectedKeyPublicKey = .mock) -> ProtectedKey {
        ProtectedKey(kid: kid,
                     encryptedPrivateKey: "enc-private",
                     publicKey: publicKey,
                     encryptedWith: encryptedWith,
                     purpose: purpose)
    }

    private func makeNativeEncryptedProtectedKey(privateKey: Data,
                                                 account: SyncAccount,
                                                 crypter: CryptingInternal) throws -> ProtectedKey {
        let encryptedPrivateKey = try crypter.encrypt(privateKey, using: account.secretKey)
        return ProtectedKey(kid: UUID().uuidString,
                            encryptedPrivateKey: Base64URL.encode(encryptedPrivateKey),
                            publicKey: .mock,
                            encryptedWith: "ddg",
                            purpose: "ai_chats")
    }

    private func makeRequest(statusCode: Int, body: String? = nil) -> HTTPRequestingMock {
        HTTPRequestingMock(result: .init(data: body.map { Data($0.utf8) },
                                         response: makeHTTPURLResponse(statusCode: statusCode)))
    }

    private func makeFailingRequest(statusCode: Int) -> HTTPRequestingMock {
        let request = HTTPRequestingMock()
        request.error = SyncError.unexpectedStatusCode(statusCode)
        return request
    }

    private func makeHTTPURLResponse(statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://dev.null/test")!,
                        statusCode: statusCode,
                        httpVersion: nil,
                        headerFields: nil)!
    }

    private func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            XCTFail("Expected dictionary JSON payload")
            return [:]
        }
        return object
    }

    private func accessCredentialsBody(_ accessCredentials: [AccessCredential]) throws -> String {
        let body = FetchAccessCredentialsBody(accessCredentials: accessCredentials.map(AccessCredentialResponse.init))
        let data = try JSONEncoder.snakeCaseKeys.encode(body)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func protectedKeysBody(_ keys: [ProtectedKey]) throws -> String {
        let body = FetchProtectedKeysBody(keys: keys)
        let data = try JSONEncoder.snakeCaseKeys.encode(body)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func hkdf(input: Data, salt: String, info: String) -> Data {
        let derivedKey = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: input),
                                                salt: Data(salt.utf8),
                                                info: Data(info.utf8),
                                                outputByteCount: 32)
        return derivedKey.withUnsafeBytes { Data($0) }
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

    func setKeyIfAbsent(purpose: String) -> URL {
        keys
            .appendingPathComponent("purpose")
            .appendingPathComponent(purpose)
            .appendingPathComponent("set-if-absent")
    }
}
