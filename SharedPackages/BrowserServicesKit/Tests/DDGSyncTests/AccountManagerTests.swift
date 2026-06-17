//
//  AccountManagerTests.swift
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

final class AccountManagerTests: XCTestCase {

    private static let baseURL = URL(string: "https://dev.null")!

    func testWhenDecodingSignupResultWithoutScopedFieldsThenDecodingSucceeds() throws {
        let json = """
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """

        let result = try JSONDecoder.snakeCaseKeys.decode(AccountManager.Signup.Result.self, from: Data(json.utf8))

        XCTAssertEqual(result.userId, "user-1")
        XCTAssertEqual(result.token, "token-1")
    }

    func testWhenCreatingAccountWithScopedAccessCredentialsEnabledThenSignupRequestIncludesCredentialId() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints, api: api, crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        _ = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertEqual(signupBody["credential_id"] as? String, "ddg")
    }

    func testWhenCreatingAccountWithScopedAccessCredentialsDisabledThenSignupRequestOmitsCredentialId() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints, api: api, crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { false })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        _ = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNil(signupBody["credential_id"])
    }

    func testWhenDecodingLoginResultWithoutScopedFieldsThenDecodingSucceeds() throws {
        let json = """
        {
            "devices": [],
            "token": "token-1",
            "protected_encryption_key": ""
        }
        """

        let result = try JSONDecoder.snakeCaseKeys.decode(AccountManager.Login.Result.self, from: Data(json.utf8))

        XCTAssertTrue(result.devices.isEmpty)
        XCTAssertEqual(result.token, "token-1")
        XCTAssertEqual(result.protectedEncryptionKey, "")
        XCTAssertNil(result.accessCredentials)
        XCTAssertNil(result.keys)
    }

    func testWhenDecodingProtectedKeyWithNewShapeThenFieldsAreMapped() throws {
        let json = """
        {
            "kid": "key-new",
            "purpose": "browser",
            "encrypted_private_key": "encrypted-private",
            "public_key": {
                "alg": "RSA-OAEP-256",
                "e": "AQAB",
                "ext": true,
                "key_ops": ["encrypt"],
                "kty": "RSA",
                "n": "modulus",
                "use": "enc"
            },
            "encrypted_with": "3party"
        }
        """

        let key = try JSONDecoder.snakeCaseKeys.decode(ProtectedKey.self, from: Data(json.utf8))

        XCTAssertEqual(key.kid, "key-new")
        XCTAssertEqual(key.encryptedPrivateKey, "encrypted-private")
        XCTAssertEqual(key.publicKey.alg, "RSA-OAEP-256")
        XCTAssertEqual(key.publicKey.e, "AQAB")
        XCTAssertEqual(key.publicKey.kty, "RSA")
        XCTAssertEqual(key.publicKey.use, "enc")
        XCTAssertEqual(key.encryptedWith, "3party")
        XCTAssertEqual(key.purpose, "browser")
    }

    func testWhenDecodingProtectedKeyWithStringPublicKeyThenDecodingFails() {
        let json = """
        {
            "kid": "key-webcrypto",
            "purpose": "browser",
            "encrypted_private_key": "encrypted-private",
            "public_key": "public-key",
            "encrypted_with": "3party"
        }
        """

        XCTAssertThrowsError(try JSONDecoder.snakeCaseKeys.decode(ProtectedKey.self, from: Data(json.utf8)))
    }

    func testWhenDecodingProtectedKeyWithoutEncryptedWithThenDefaultsToDefaultCredential() throws {
        let json = """
        {
            "kid": "key-missing-encrypted-with",
            "purpose": "browser",
            "encrypted_private_key": "encrypted-private-key",
            "public_key": {
                "alg": "RSA-OAEP-256",
                "e": "AQAB",
                "ext": true,
                "key_ops": ["encrypt"],
                "kty": "RSA",
                "n": "modulus"
            }
        }
        """

        let key = try JSONDecoder.snakeCaseKeys.decode(ProtectedKey.self, from: Data(json.utf8))

        XCTAssertEqual(key.encryptedWith, SyncCredentialID.defaultCredential)
    }

    func testWhenDecodingProtectedKeyWithEmptyEncryptedWithThenDefaultsToDefaultCredential() throws {
        let json = """
        {
            "kid": "key-empty-encrypted-with",
            "purpose": "browser",
            "encrypted_private_key": "encrypted-private-key",
            "public_key": {
                "alg": "RSA-OAEP-256",
                "e": "AQAB",
                "ext": true,
                "key_ops": ["encrypt"],
                "kty": "RSA",
                "n": "modulus"
            },
            "encrypted_with": ""
        }
        """

        let key = try JSONDecoder.snakeCaseKeys.decode(ProtectedKey.self, from: Data(json.utf8))

        XCTAssertEqual(key.encryptedWith, SyncCredentialID.defaultCredential)
    }

    func testWhenDecodingProtectedKeysWithMissingEncryptedWithAndValidSiblingThenBothSurvive() throws {
        let json = """
        [
            {
                "kid": "key-missing-encrypted-with",
                "purpose": "browser",
                "encrypted_private_key": "encrypted-private-key",
                "public_key": {
                    "alg": "RSA-OAEP-256",
                    "e": "AQAB",
                    "ext": true,
                    "key_ops": ["encrypt"],
                    "kty": "RSA",
                    "n": "modulus"
                }
            },
            {
                "kid": "key-3party",
                "purpose": "browser",
                "encrypted_private_key": "encrypted-private-key",
                "public_key": {
                    "alg": "RSA-OAEP-256",
                    "e": "AQAB",
                    "ext": true,
                    "key_ops": ["encrypt"],
                    "kty": "RSA",
                    "n": "modulus"
                },
                "encrypted_with": "3party"
            }
        ]
        """

        let keys = try JSONDecoder.snakeCaseKeys.decode([ProtectedKey].self, from: Data(json.utf8))

        XCTAssertEqual(keys.map(\.kid), ["key-missing-encrypted-with", "key-3party"])
        XCTAssertEqual(keys.map(\.encryptedWith), [SyncCredentialID.defaultCredential, SyncCredentialID.thirdParty])
    }

    func testWhenDecodingAccessCredentialFromServerResponseThenFieldsAreMapped() throws {
        let json = """
        {
            "id": "credential-1",
            "scope": "sync",
            "encrypted_3party_credential": "encrypted-credential"
        }
        """

        let credential = try JSONDecoder.snakeCaseKeys.decode(AccessCredential.self, from: Data(json.utf8))

        XCTAssertEqual(credential.id, "credential-1")
        XCTAssertEqual(credential.scope, "sync")
        XCTAssertEqual(credential.encrypted3PartyCredential, "encrypted-credential")
    }

    func testWhenDecodingAccessCredentialFromMinimalServerResponseThenOptionalFieldsAreNil() throws {
        let json = """
        {
            "id": "ddg"
        }
        """

        let credential = try JSONDecoder.snakeCaseKeys.decode(AccessCredential.self, from: Data(json.utf8))

        XCTAssertEqual(credential.id, "ddg")
        XCTAssertNil(credential.scope)
        XCTAssertNil(credential.encrypted3PartyCredential)
    }

    func testWhenLoginResponseIncludesAccessCredentialsThenTheyAreReturned() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.login] = makeJSONRequest("""
        {
            "devices": [],
            "token": "token-1",
            "protected_encryption_key": "",
            "access_credentials": [
                {
                    "id": "3party",
                    "scope": "sync",
                    "encrypted_3party_credential": "encrypted"
                }
            ]
        }
        """)

        let result = try await accountManager.login(.init(userId: "user-1", primaryKey: Data()),
                                                   deviceName: "iPhone",
                                                   deviceType: "iOS")

        XCTAssertEqual(result.accessCredentials?.first?.id, "3party")
        XCTAssertEqual(result.accessCredentials?.first?.encrypted3PartyCredential, "encrypted")
    }

    func testWhenLoginResponseIncludesDeviceWithoutTypeThenDeviceIsSkipped() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.login] = makeJSONRequest("""
        {
            "devices": [
                {
                    "id": "valid-device",
                    "name": "encrypted_iPhone",
                    "type": "encrypted_iOS"
                },
                {
                    "id": "missing-type-device",
                    "name": "Python client",
                    "type": null
                }
            ],
            "token": "token-1",
            "protected_encryption_key": ""
        }
        """)

        let result = try await accountManager.login(.init(userId: "user-1", primaryKey: Data()),
                                                   deviceName: "iPhone",
                                                   deviceType: "iOS")

        XCTAssertEqual(result.devices.map(\.id), ["valid-device"])
        XCTAssertEqual(result.devices.map(\.name), ["iPhone"])
        XCTAssertEqual(result.devices.map(\.type), ["iOS"])
    }

    func testWhenLoggingInWithScopedAccessCredentialsEnabledThenLoginRequestIncludesSyncScope() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.login] = makeJSONRequest("""
        {
            "devices": [],
            "token": "token-1",
            "protected_encryption_key": ""
        }
        """)

        _ = try await accountManager.login(.init(userId: "user-1", primaryKey: Data()),
                                           deviceName: "iPhone",
                                           deviceType: "iOS")

        let loginBody = try makeLoginBody(from: api)
        XCTAssertEqual(loginBody["scope"] as? String, "sync")
    }

    func testWhenLoggingInWithScopedAccessCredentialsDisabledThenLoginRequestOmitsSyncScope() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { false })
        api.fakeRequests[endpoints.login] = makeJSONRequest("""
        {
            "devices": [],
            "token": "token-1",
            "protected_encryption_key": ""
        }
        """)

        _ = try await accountManager.login(.init(userId: "user-1", primaryKey: Data()),
                                           deviceName: "iPhone",
                                           deviceType: "iOS")

        let loginBody = try makeLoginBody(from: api)
        XCTAssertNil(loginBody["scope"])
    }

    func testWhenRefreshingTokenWithoutAccessCredentialsThenResultAccessCredentialsIsNil() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.login] = makeJSONRequest("""
        {
            "devices": [],
            "token": "token-1",
            "protected_encryption_key": ""
        }
        """)

        let result = try await accountManager.refreshToken(makeAccount(primaryKey: Data()), deviceName: "Updated iPhone")

        XCTAssertNil(result.accessCredentials)
    }

    func testWhenFetchingDevicesWithScopedAccessEnabledThenPrefersEntriesV2OverLegacyEntries() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let mapper = RegisteredDeviceMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[devicesURL(for: endpoints)] = makeJSONRequest("""
        {
            "devices": {
                "entries": [
                    {
                        "id": "legacy-device",
                        "name": "encrypted_Legacy",
                        "type": "encrypted_desktop"
                    }
                ],
                "entries_v2": [
                    {
                        "id": "v2-device",
                        "name": "encrypted_V2",
                        "type": "encrypted_browser",
                        "credential_id": "3party"
                    }
                ]
            }
        }
        """)

        let devices = try await accountManager.fetchDevicesForAccount(makeAccount(primaryKey: Data()))

        XCTAssertEqual(mapper.registeredDevicesCallEntryIDs, ["v2-device"])
        XCTAssertEqual(devices.map(\.id), ["v2-device"])
        XCTAssertFalse(api.createRequestCallArgs.contains { $0.url == endpoints.logoutDevice })
    }

    func testWhenFetchingDevicesWithScopedAccessEnabledAndEntriesV2IsEmptyThenFallsBackToLegacyEntries() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let mapper = RegisteredDeviceMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[devicesURL(for: endpoints)] = makeJSONRequest("""
        {
            "devices": {
                "entries": [
                    {
                        "id": "legacy-device",
                        "name": "encrypted_Legacy",
                        "type": "encrypted_desktop"
                    }
                ],
                "entries_v2": []
            }
        }
        """)

        let devices = try await accountManager.fetchDevicesForAccount(makeAccount(primaryKey: Data()))

        XCTAssertEqual(mapper.registeredDevicesCallEntryIDs, ["legacy-device"])
        XCTAssertEqual(devices.map(\.id), ["legacy-device"])
        XCTAssertFalse(api.createRequestCallArgs.contains { $0.url == endpoints.logoutDevice })
    }

    func testWhenFetchingDevicesWithScopedAccessEnabledThenFallsBackUndecryptableEntriesWithoutLogout() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._base64DecodeAndDecrypt = { _ in
            throw SyncError.failedToDecryptValue("test")
        }
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: crypter,
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[devicesURL(for: endpoints)] = makeJSONRequest("""
        {
            "devices": {
                "entries_v2": [
                    {
                        "id": "third-party-device",
                        "name": "undecryptable-name",
                        "type": "undecryptable-type",
                        "credential_id": "3party"
                    },
                    {
                        "id": "native-device",
                        "name": "undecryptable-name",
                        "type": "undecryptable-type",
                        "credential_id": "ddg"
                    }
                ]
            }
        }
        """)

        let devices = try await accountManager.fetchDevicesForAccount(makeAccount(primaryKey: Data()))

        XCTAssertEqual(devices.map(\.id), ["third-party-device", "native-device"])
        XCTAssertEqual(devices.map(\.name), ["Browser", "Unknown"])
        XCTAssertEqual(devices.map(\.type), ["unknown", "unknown"])
        XCTAssertEqual(devices.map(\.credentialId), [SyncCredentialID.thirdParty, SyncCredentialID.defaultCredential])
        XCTAssertFalse(api.createRequestCallArgs.contains { $0.url == endpoints.logoutDevice })
    }

    func testWhenFetchingDevicesWithScopedAccessDisabledThenLegacyUndecryptableDeviceIsLoggedOut() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._base64DecodeAndDecrypt = { _ in
            throw SyncError.failedToDecryptValue("test")
        }
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: crypter,
                                            isScopedAccessCredentialsEnabled: { false })
        api.fakeRequests[devicesURL(for: endpoints)] = makeJSONRequest("""
        {
            "devices": {
                "entries": [
                    {
                        "id": "invalid-native-device",
                        "name": "undecryptable-name",
                        "type": "undecryptable-type"
                    }
                ]
            }
        }
        """)
        api.fakeRequests[endpoints.logoutDevice] = makeJSONRequest("""
        {
            "device_id": "invalid-native-device"
        }
        """)

        let devices = try await accountManager.fetchDevicesForAccount(makeAccount(primaryKey: Data()))

        XCTAssertTrue(devices.isEmpty)
        XCTAssertTrue(api.createRequestCallArgs.contains { $0.url == endpoints.logoutDevice })
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

    private func makeJSONRequest(_ json: String) -> HTTPRequestingMock {
        HTTPRequestingMock(result: .init(data: Data(json.utf8), response: .init()))
    }

    private func devicesURL(for endpoints: Endpoints) -> URL {
        endpoints.syncGet.appendingPathComponent("devices")
    }

    private func makeSignupBody(from api: RemoteAPIRequestCreatingMock) throws -> [String: Any] {
        let requestBody = try XCTUnwrap(api.createRequestCallArgs.last?.body)
        let json = try JSONSerialization.jsonObject(with: requestBody)
        return try XCTUnwrap(json as? [String: Any])
    }

    private func makeLoginBody(from api: RemoteAPIRequestCreatingMock) throws -> [String: Any] {
        let requestBody = try XCTUnwrap(api.createRequestCallArgs.last?.body)
        let json = try JSONSerialization.jsonObject(with: requestBody)
        return try XCTUnwrap(json as? [String: Any])
    }

}

private final class RegisteredDeviceMappingMock: RegisteredDeviceMapping {

    private(set) var registeredDevicesCallEntryIDs: [String] = []

    func registeredDevices(from entries: [RegisteredDeviceEntry], account: SyncAccount) async -> [RegisteredDevice] {
        registeredDevicesCallEntryIDs = entries.map(\.id)
        return entries.map { entry in
            RegisteredDevice(id: entry.id,
                             name: entry.name ?? "",
                             type: entry.type ?? "",
                             credentialId: entry.credentialId)
        }
    }

    func registeredDevice(fromLegacyEntry entry: RegisteredDeviceEntry, account: SyncAccount) -> RegisteredDevice? {
        RegisteredDevice(id: entry.id,
                         name: entry.name ?? "",
                         type: entry.type ?? "",
                         credentialId: entry.credentialId)
    }

    func registeredDevice(fromDefaultCredentialLoginEntryWithID id: String,
                          encryptedName: String,
                          encryptedType: String?,
                          primaryKey: Data) -> RegisteredDevice? {
        RegisteredDevice(id: id,
                         name: encryptedName,
                         type: encryptedType ?? "",
                         credentialId: SyncCredentialID.defaultCredential)
    }

}
