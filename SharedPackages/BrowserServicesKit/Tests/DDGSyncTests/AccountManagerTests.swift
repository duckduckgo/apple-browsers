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

    func testWhenCreatingAccountWithUnifiedWriteEnabledThenSignupIncludesKeysAndDeviceInfo() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        let protectedKey = makeAccountInfoProtectedKey()
        accountInfoKeyFactory.makeProtectedKeysStub = [protectedKey]
        let deviceInfoCodec = DeviceInfoCodingMock()
        let events = UnifiedDeviceListEventMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            unifiedDeviceListEvents: events,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        let result = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        let keys = try XCTUnwrap(signupBody["keys"] as? [[String: Any]])
        let key = try XCTUnwrap(keys.first)
        XCTAssertEqual(signupBody["device_info"] as? String, deviceInfoCodec.encryptUsingProtectedKeyStub)
        XCTAssertEqual(signupBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(signupBody["device_type"] as? String, "encrypted_iOS")
        XCTAssertEqual(key["kid"] as? String, protectedKey.kid)
        XCTAssertEqual(key["purpose"] as? String, ProtectedKeyPurpose.accountInfo)
        XCTAssertEqual(key["encrypted_with"] as? String, SyncCredentialID.defaultCredential)
        XCTAssertEqual(accountInfoKeyFactory.makeProtectedKeysCalls.count, 1)
        XCTAssertNil(accountInfoKeyFactory.makeProtectedKeysCalls.first?.thirdPartyMainKey)
        XCTAssertEqual(deviceInfoCodec.encryptUsingProtectedKeyCalls.first?.deviceInfo,
                       DeviceInfo(name: "iPhone", type: "iOS"))
        XCTAssertEqual(deviceInfoCodec.encryptUsingProtectedKeyCalls.first?.protectedKey.kid, protectedKey.kid)
        XCTAssertTrue(result.didPublishDeviceInfo)
        XCTAssertEqual(events.events, [
            .accountInfoKeyCreateSuccess,
            .ownRowDeviceInfoFirstWriteSuccess
        ])
    }

    func testWhenCreatingAccountWithUnifiedWriteDisabledThenSignupOmitsKeysAndDeviceInfo() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        accountInfoKeyFactory.makeProtectedKeysStub = [makeAccountInfoProtectedKey()]
        let deviceInfoCodec = DeviceInfoCodingMock()
        let events = UnifiedDeviceListEventMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            unifiedDeviceListEvents: events,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { false })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        let result = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNil(signupBody["keys"])
        XCTAssertNil(signupBody["device_info"])
        XCTAssertEqual(signupBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(signupBody["device_type"] as? String, "encrypted_iOS")
        XCTAssertTrue(accountInfoKeyFactory.makeProtectedKeysCalls.isEmpty)
        XCTAssertTrue(deviceInfoCodec.encryptUsingProtectedKeyCalls.isEmpty)
        XCTAssertFalse(result.didPublishDeviceInfo)
        XCTAssertTrue(events.events.isEmpty)
    }

    func testWhenDeviceInfoEncryptionFailsThenSignupFallsBackToLegacyFields() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        accountInfoKeyFactory.makeProtectedKeysStub = [makeAccountInfoProtectedKey()]
        let deviceInfoCodec = DeviceInfoCodingMock()
        deviceInfoCodec.encryptUsingProtectedKeyError = DeviceInfoCodecError.invalidPayload
        let events = UnifiedDeviceListEventMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            unifiedDeviceListEvents: events,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        let result = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNil(signupBody["keys"])
        XCTAssertNil(signupBody["device_info"])
        XCTAssertEqual(signupBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(signupBody["device_type"] as? String, "encrypted_iOS")
        XCTAssertEqual(api.createRequestCallArgs.map(\.url), [endpoints.signup])
        XCTAssertFalse(result.didPublishDeviceInfo)
        XCTAssertEqual(events.events, [.ownRowDeviceInfoFirstWriteFailed(.encryptFailed)])
    }

    func testWhenAccountInfoKeyGenerationFailsThenSignupFallsBackToSingleLegacyRequest() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        accountInfoKeyFactory.makeProtectedKeysError = AccountManagerTestError.accountInfoKeyGenerationFailed
        let deviceInfoCodec = DeviceInfoCodingMock()
        let events = UnifiedDeviceListEventMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            unifiedDeviceListEvents: events,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        let result = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNil(signupBody["keys"])
        XCTAssertNil(signupBody["device_info"])
        XCTAssertEqual(signupBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(signupBody["device_type"] as? String, "encrypted_iOS")
        XCTAssertEqual(accountInfoKeyFactory.makeProtectedKeysCalls.count, 1)
        XCTAssertTrue(deviceInfoCodec.encryptUsingProtectedKeyCalls.isEmpty)
        XCTAssertEqual(api.createRequestCallArgs.map(\.url), [endpoints.signup])
        XCTAssertFalse(result.didPublishDeviceInfo)
        XCTAssertEqual(events.events, [.accountInfoKeyCreateFailed(.mintFailed)])
    }

    func testWhenEnrichedSignupRequestFailsThenErrorIsPropagatedWithoutLegacyRetry() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        accountInfoKeyFactory.makeProtectedKeysStub = [makeAccountInfoProtectedKey()]
        let deviceInfoCodec = DeviceInfoCodingMock()
        let events = UnifiedDeviceListEventMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            unifiedDeviceListEvents: events,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
        let signupRequest = HTTPRequestingMock()
        signupRequest.error = URLError(.timedOut)
        api.fakeRequests[endpoints.signup] = signupRequest

        do {
            _ = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")
            XCTFail("Expected signup request failure")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNotNil(signupBody["keys"])
        XCTAssertEqual(signupBody["device_info"] as? String, deviceInfoCodec.encryptUsingProtectedKeyStub)
        XCTAssertEqual(api.createRequestCallArgs.map(\.url), [endpoints.signup])
        XCTAssertEqual(signupRequest.executeCallCount, 1)
        XCTAssertEqual(events.events, [.accountInfoKeyCreateFailed(.requestFailed)])
    }

    func testWhenDeviceInfoExceedsServerLimitThenSignupFallsBackToLegacyFields() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        accountInfoKeyFactory.makeProtectedKeysStub = [makeAccountInfoProtectedKey()]
        let deviceInfoCodec = DeviceInfoCodingMock()
        deviceInfoCodec.encryptUsingProtectedKeyStub = String(repeating: "a",
                                                              count: DeviceInfo.maximumEncryptedLength + 1)
        let events = UnifiedDeviceListEventMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            unifiedDeviceListEvents: events,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        let result = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNil(signupBody["keys"])
        XCTAssertNil(signupBody["device_info"])
        XCTAssertEqual(signupBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(signupBody["device_type"] as? String, "encrypted_iOS")
        XCTAssertFalse(result.didPublishDeviceInfo)
        XCTAssertEqual(events.events, [.ownRowDeviceInfoFirstWriteFailed(.encryptFailed)])
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

    func testWhenUnifiedReadIsEnabledThenLoginMapsDevicesV2() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let mapper = RegisteredDeviceMappingMock()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        mapper.registeredDevicesHandler = {
            XCTAssertEqual(accountInfoKeys.preloadKeyCalls.count, 1)
        }
        var readFlagCallCount = 0
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            accountInfoKeys: accountInfoKeys,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: {
                                                readFlagCallCount += 1
                                                return true
                                            })
        api.fakeRequests[endpoints.login] = makeJSONRequest("""
        {
            "devices": [
                {
                    "id": "legacy-device",
                    "name": "encrypted_Legacy",
                    "type": "encrypted_desktop"
                }
            ],
            "devices_v2": [
                {
                    "id": "unified-device",
                    "name": "encrypted_Unified",
                    "type": "encrypted_browser",
                    "info": "encrypted-info",
                    "credential_id": "3party"
                }
            ],
            "token": "token-1",
            "protected_encryption_key": "",
            "keys": [
                {
                    "kid": "account-info-key",
                    "encrypted_private_key": "encrypted-private-key",
                    "public_key": {
                        "alg": "RSA-OAEP-256",
                        "e": "AQAB",
                        "kty": "RSA",
                        "n": "modulus"
                    },
                    "encrypted_with": "3party",
                    "purpose": "account_info"
                }
            ],
            "access_credentials": [
                {
                    "id": "3party",
                    "scope": "sync",
                    "encrypted_3party_credential": "encrypted-credential"
                }
            ]
        }
        """)

        let result = try await accountManager.login(.init(userId: "user-1", primaryKey: Data()),
                                                    deviceName: "iPhone",
                                                    deviceType: "iOS")

        XCTAssertEqual(mapper.registeredDevicesCallEntryIDs, ["unified-device"])
        XCTAssertEqual(mapper.unifiedReadEnabledValues, [true])
        XCTAssertTrue(mapper.defaultCredentialLoginEntryIDs.isEmpty)
        XCTAssertEqual(result.devices.map(\.id), ["unified-device"])
        XCTAssertEqual(readFlagCallCount, 1)
        let keyLoad = try XCTUnwrap(accountInfoKeys.preloadKeyCalls.first)
        XCTAssertEqual(accountInfoKeys.preloadKeyCalls.count, 1)
        XCTAssertEqual(keyLoad.protectedKeys.map(\.kid), ["account-info-key"])
        XCTAssertEqual(keyLoad.accessCredentials.map(\.id), ["3party"])
        XCTAssertEqual(keyLoad.account.userId, result.account.userId)
    }

    func testWhenUnifiedReadIsDisabledThenLoginMapsLegacyDevices() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let mapper = RegisteredDeviceMappingMock()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            accountInfoKeys: accountInfoKeys,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { false })
        api.fakeRequests[endpoints.login] = makeJSONRequest("""
        {
            "devices": [
                {
                    "id": "legacy-device",
                    "name": "encrypted_Legacy",
                    "type": "encrypted_desktop"
                }
            ],
            "devices_v2": [
                {
                    "id": "unified-device",
                    "name": "encrypted_Unified",
                    "type": "encrypted_browser",
                    "info": "encrypted-info",
                    "credential_id": "3party"
                }
            ],
            "token": "token-1",
            "protected_encryption_key": "",
            "keys": [
                {
                    "kid": "account-info-key",
                    "encrypted_private_key": "encrypted-private-key",
                    "public_key": {
                        "alg": "RSA-OAEP-256",
                        "e": "AQAB",
                        "kty": "RSA",
                        "n": "modulus"
                    },
                    "encrypted_with": "ddg",
                    "purpose": "account_info"
                }
            ]
        }
        """)

        let result = try await accountManager.login(.init(userId: "user-1", primaryKey: Data()),
                                                    deviceName: "iPhone",
                                                    deviceType: "iOS")

        XCTAssertTrue(mapper.registeredDevicesCallEntryIDs.isEmpty)
        XCTAssertEqual(mapper.defaultCredentialLoginEntryIDs, ["legacy-device"])
        XCTAssertEqual(result.devices.map(\.id), ["legacy-device"])
        XCTAssertTrue(accountInfoKeys.preloadKeyCalls.isEmpty)
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

    func testWhenLoggingInWithUnifiedWriteEnabledThenLoginUsesLegacyMetadataOnly() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        accountInfoKeyFactory.makeProtectedKeysStub = [makeAccountInfoProtectedKey()]
        let deviceInfoCodec = DeviceInfoCodingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
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
        XCTAssertNil(loginBody["keys"])
        XCTAssertNil(loginBody["device_info"])
        XCTAssertEqual(loginBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(loginBody["device_type"] as? String, "encrypted_iOS")
        XCTAssertTrue(accountInfoKeyFactory.makeProtectedKeysCalls.isEmpty)
        XCTAssertTrue(deviceInfoCodec.encryptUsingProtectedKeyCalls.isEmpty)
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

    func testWhenEncodingUpdateDevicesParametersThenUsesPatchContractShape() throws {
        let deviceUpdate = UpdateDevices.Update(
            id: "device-1",
            name: "encrypted-name",
            type: "encrypted-type",
            info: "encrypted-info")
        let parameters = UpdateDevices.Parameters(updates: [deviceUpdate])

        let data = try JSONEncoder.snakeCaseKeys.encode(parameters)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let updates = try XCTUnwrap(body["updates"] as? [[String: Any]])
        let encodedUpdate = try XCTUnwrap(updates.first)

        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(encodedUpdate["id"] as? String, "device-1")
        XCTAssertEqual(encodedUpdate["name"] as? String, "encrypted-name")
        XCTAssertEqual(encodedUpdate["type"] as? String, "encrypted-type")
        XCTAssertEqual(encodedUpdate["info"] as? String, "encrypted-info")
    }

    func testWhenEncodingUpdateDevicesParametersWithoutInfoThenOmitsInfo() throws {
        let deviceUpdate = UpdateDevices.Update(
            id: "device-1",
            name: "encrypted-name",
            type: "encrypted-type",
            info: nil)
        let parameters = UpdateDevices.Parameters(updates: [deviceUpdate])

        let data = try JSONEncoder.snakeCaseKeys.encode(parameters)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let updates = try XCTUnwrap(body["updates"] as? [[String: Any]])
        let encodedUpdate = try XCTUnwrap(updates.first)

        XCTAssertEqual(Set(encodedUpdate.keys), ["id", "name", "type"])
    }

    func testWhenDecodingUpdateDevicesResultThenMapsLegacyAndUnifiedDevices() throws {
        let json = """
        {
            "devices": [
                {
                    "id": "device-1",
                    "name": "encrypted-name",
                    "type": "encrypted-type",
                    "jwt_iat": "2026-06-23T10:00:00Z"
                }
            ],
            "devices_v2": [
                {
                    "id": "device-1",
                    "name": "encrypted-name",
                    "type": "encrypted-type",
                    "info": "encrypted-info",
                    "jwt_iat": "2026-06-23T10:00:00Z",
                    "credential_id": "ddg"
                }
            ]
        }
        """

        let result = try JSONDecoder.snakeCaseKeys.decode(UpdateDevices.Result.self, from: Data(json.utf8))

        XCTAssertEqual(result.devices.map(\.id), ["device-1"])
        XCTAssertNil(result.devices.first?.info)
        XCTAssertNil(result.devices.first?.credentialId)
        XCTAssertEqual(result.devicesV2.map(\.id), ["device-1"])
        XCTAssertEqual(result.devicesV2.first?.info, "encrypted-info")
        XCTAssertEqual(result.devicesV2.first?.credentialId, SyncCredentialID.defaultCredential)
    }

    func testWhenUpdatingDeviceThenUsesAuthenticatedPatchAndDecodesResponse() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let mapper = RegisteredDeviceMappingMock()
        var readFlagCallCount = 0
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: {
                                                readFlagCallCount += 1
                                                return true
                                            })
        api.fakeRequests[endpoints.devices] = makeJSONRequest("""
        {
            "devices": [
                {
                    "id": "legacy-device",
                    "name": "encrypted-legacy-name",
                    "type": "encrypted-legacy-type"
                }
            ],
            "devices_v2": [
                {
                    "id": "unified-device",
                    "name": "encrypted-name",
                    "type": "encrypted-type",
                    "info": "encrypted-info",
                    "jwt_iat": "2026-06-23T10:00:00Z",
                    "credential_id": "ddg"
                }
            ]
        }
        """)

        let result = try await accountManager.updateDevice(makeDeviceUpdate(), for: makeAccount(primaryKey: Data()))

        let requestArguments = try XCTUnwrap(api.createRequestCallArgs.last)
        let requestBody = try XCTUnwrap(requestArguments.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
        let updates = try XCTUnwrap(body["updates"] as? [[String: Any]])
        XCTAssertEqual(requestArguments.url, endpoints.devices)
        XCTAssertEqual(requestArguments.method, .patch)
        XCTAssertEqual(requestArguments.headers["Authorization"], "Bearer token-1")
        XCTAssertEqual(requestArguments.contentType, "application/json")
        XCTAssertEqual(updates.first?["id"] as? String, "device-1")
        XCTAssertEqual(updates.first?["name"] as? String, "encrypted-name")
        XCTAssertEqual(updates.first?["type"] as? String, "encrypted-type")
        XCTAssertEqual(updates.first?["info"] as? String, "encrypted-info")
        XCTAssertEqual(mapper.registeredDevicesCallEntryIDs, ["unified-device"])
        XCTAssertEqual(mapper.unifiedReadEnabledValues, [true])
        XCTAssertEqual(result.map(\.id), ["unified-device"])
        XCTAssertEqual(readFlagCallCount, 1)
    }

    func testWhenUnifiedReadIsDisabledThenUpdatingDeviceMapsLegacyResponse() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let mapper = RegisteredDeviceMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { false })
        api.fakeRequests[endpoints.devices] = makeJSONRequest("""
        {
            "devices": [
                {
                    "id": "legacy-device",
                    "name": "encrypted-legacy-name",
                    "type": "encrypted-legacy-type"
                }
            ],
            "devices_v2": [
                {
                    "id": "unified-device",
                    "name": "encrypted-name",
                    "type": "encrypted-type",
                    "info": "encrypted-info",
                    "credential_id": "ddg"
                }
            ]
        }
        """)

        let devices = try await accountManager.updateDevice(makeDeviceUpdate(), for: makeAccount(primaryKey: Data()))

        XCTAssertEqual(mapper.registeredDevicesCallEntryIDs, ["legacy-device"])
        XCTAssertEqual(devices.map(\.id), ["legacy-device"])
    }

    func testWhenUpdatingDeviceWithoutTokenThenThrowsNoToken() async {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })

        await assertThrowsError(SyncError.noToken) {
            try await accountManager.updateDevice(makeDeviceUpdate(),
                                                  for: makeAccount(primaryKey: Data(), token: nil))
        }

        XCTAssertTrue(api.createRequestCallArgs.isEmpty)
    }

    func testWhenUpdatingDeviceResponseHasNoBodyThenThrowsNoResponseBody() async {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.devices] = HTTPRequestingMock(result: .init(data: nil, response: .init()))

        await assertThrowsError(SyncError.noResponseBody) {
            try await accountManager.updateDevice(makeDeviceUpdate(), for: makeAccount(primaryKey: Data()))
        }
    }

    func testWhenUpdatingDeviceResponseIsInvalidThenThrowsUnableToDecodeResponse() async {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.devices] = makeJSONRequest("""
        {
            "devices": []
        }
        """)

        await assertThrowsError(SyncError.unableToDecodeResponse("Failed to decode devices update")) {
            try await accountManager.updateDevice(makeDeviceUpdate(), for: makeAccount(primaryKey: Data()))
        }
    }

    func testWhenFetchingDevicesWithScopedAccessEnabledThenPrefersEntriesV2OverLegacyEntries() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let mapper = RegisteredDeviceMappingMock()
        var readFlagCallCount = 0
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: {
                                                readFlagCallCount += 1
                                                return false
                                            })
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

        let result = try await accountManager.fetchDevicesForAccount(makeAccount(primaryKey: Data()))
        let devices = result.devices

        XCTAssertEqual(mapper.registeredDevicesCallEntryIDs, ["v2-device"])
        XCTAssertEqual(mapper.unifiedReadEnabledValues, [false])
        XCTAssertEqual(devices.map(\.id), ["v2-device"])
        XCTAssertEqual(readFlagCallCount, 1)
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

        let result = try await accountManager.fetchDevicesForAccount(makeAccount(primaryKey: Data()))
        let devices = result.devices

        XCTAssertEqual(mapper.registeredDevicesCallEntryIDs, ["legacy-device"])
        XCTAssertEqual(devices.map(\.id), ["legacy-device"])
        XCTAssertFalse(api.createRequestCallArgs.contains { $0.url == endpoints.logoutDevice })
    }

    func testWhenFetchingDevicesWithUnifiedReadEnabledThenFallsBackUndecryptableEntriesWithoutLogout() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._base64DecodeAndDecrypt = { _ in
            throw SyncError.failedToDecryptValue("test")
        }
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: crypter,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
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

        let result = try await accountManager.fetchDevicesForAccount(makeAccount(primaryKey: Data()))
        let devices = result.devices

        XCTAssertEqual(devices.map(\.id), ["third-party-device", "native-device"])
        XCTAssertEqual(devices.map(\.name), ["Browser", "Unknown"])
        XCTAssertEqual(devices.map(\.type), ["unknown", "unknown"])
        XCTAssertEqual(devices.map(\.credentialId), [SyncCredentialID.thirdParty, SyncCredentialID.defaultCredential])
        XCTAssertFalse(api.createRequestCallArgs.contains { $0.url == endpoints.logoutDevice })
    }

    func testWhenFetchingDevicesWithScopedAccessEnabledAndUnifiedReadDisabledThenRetainsFallbackEntriesWithoutLogout() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        var crypter = CryptingMock()
        crypter._base64DecodeAndDecrypt = { _ in
            throw SyncError.failedToDecryptValue("test")
        }
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: crypter,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { false })
        api.fakeRequests[devicesURL(for: endpoints)] = makeJSONRequest("""
        {
            "devices": {
                "entries_v2": [
                    {
                        "id": "third-party-device",
                        "name": "undecryptable-name",
                        "type": "undecryptable-type",
                        "info": "ignored-device-info",
                        "credential_id": "3party"
                    },
                    {
                        "id": "native-device",
                        "name": "undecryptable-name",
                        "type": "undecryptable-type",
                        "info": "ignored-device-info",
                        "credential_id": "ddg"
                    }
                ]
            }
        }
        """)
        let result = try await accountManager.fetchDevicesForAccount(makeAccount(primaryKey: Data()))

        XCTAssertEqual(result.devices.map(\.id), ["third-party-device", "native-device"])
        XCTAssertEqual(result.devices.map(\.name), ["Browser", "Unknown"])
        XCTAssertEqual(result.devices.map(\.type), ["unknown", "unknown"])
        XCTAssertEqual(result.devices.map(\.credentialId), [SyncCredentialID.thirdParty, SyncCredentialID.defaultCredential])
        XCTAssertFalse(result.needsCurrentDeviceInfoRepair)
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

        let result = try await accountManager.fetchDevicesForAccount(makeAccount(primaryKey: Data()))
        let devices = result.devices

        XCTAssertTrue(devices.isEmpty)
        XCTAssertTrue(api.createRequestCallArgs.contains { $0.url == endpoints.logoutDevice })
    }

    func testWhenFetchingAuditLogWithoutCursorThenSendsAuthenticatedRequestAndDecodesStringVersions() async throws {
        let fixture = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x01, count: 32))
        let validJWE = try fixture.entry(payload: Data("{}".utf8)).payload
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints, api: api, crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entries: [
            AuditLogEntry(id: "historical-event", version: "1", payload: validJWE),
            AuditLogEntry(id: "current-event", version: "2", payload: "current-jwe")
        ], after: "after-cursor")

        let page = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)

        let request = try XCTUnwrap(api.createRequestCallArgs.first)
        XCTAssertEqual(request.url, endpoints.auditLog)
        XCTAssertEqual(request.url.path, "/sync/account/audit-log")
        XCTAssertEqual(request.method, .get)
        XCTAssertEqual(request.headers["Authorization"], "Bearer token-1")
        XCTAssertEqual(request.parameters, [:])
        XCTAssertNil(request.body)
        XCTAssertEqual(page.entries.count, 2)
        guard case .unreadable(id: "historical-event", reason: .keyUnavailable) = page.entries[0],
              case .unsupportedVersion(id: "current-event", version: "2") = page.entries[1] else {
            return XCTFail("Expected decoded entry outcomes, including unsupported versions")
        }
        XCTAssertEqual(page.after, "after-cursor")
        XCTAssertNil(page.before)
    }

    func testWhenFetchingAuditLogWithCursorThenSendsCursorAndLimitParameters() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints, api: api, crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.auditLog] = makeJSONRequest("""
        { "audit_log": { "entries": [], "after": "next-after", "before": "next-before" } }
        """)

        _ = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()),
                                                   cursor: .after("opaque after"),
                                                   limit: 25)
        _ = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()),
                                                   cursor: .before("opaque before"),
                                                   limit: 10)

        XCTAssertEqual(api.createRequestCallArgs.map(\.parameters), [
            ["after": "opaque after", "limit": "25"],
            ["before": "opaque before", "limit": "10"]
        ])
    }

    func testWhenFetchingBackwardAuditLogPageWithoutAfterCursorThenSucceeds() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints, api: api, crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entries: [], after: nil, before: "previous-page")

        let page = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: .before("current-page"))

        XCTAssertNil(page.after)
        XCTAssertEqual(page.before, "previous-page")
    }

    func testWhenFetchingInitialOrForwardAuditLogPageWithoutAfterCursorThenThrows() async throws {
        for cursor in [AuditLogCursor?.none, .some(.after("forward-page"))] {
            let api = RemoteAPIRequestCreatingMock()
            let endpoints = Endpoints(baseURL: Self.baseURL)
            let accountManager = AccountManager(endpoints: endpoints, api: api, crypter: CryptingMock(),
                                                isScopedAccessCredentialsEnabled: { true })
            api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entries: [], after: nil)

            await assertThrowsError(AuditLogError.missingRequiredAfterCursor) {
                _ = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: cursor)
            }
        }
    }

    func testWhenAuditLogResponseHasWrongFieldTypeThenThrowsTypedError() async {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints, api: api, crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.auditLog] = makeJSONRequest("""
        { "audit_log": { "entries": [{ "id": "entry", "version": 2, "payload": "sensitive-encrypted-value" }], "after": "cursor" } }
        """)

        await assertThrowsError(AuditLogError.responseDecodingFailed) {
            _ = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)
        }
    }

    func testAuditLogErrorsBridgeToNSErrorWithSafeStableMetadata() {
        let decodingError = AuditLogError.responseDecodingFailed as NSError
        XCTAssertEqual(decodingError.domain, "com.duckduckgo.sync.audit-log")
        XCTAssertEqual(decodingError.code, 1)
        XCTAssertEqual(decodingError.localizedDescription, "Failed to decode the audit log response.")
        XCTAssertNil(decodingError.userInfo[NSUnderlyingErrorKey])

        let missingCursorError = AuditLogError.missingRequiredAfterCursor as NSError
        XCTAssertEqual(missingCursorError.domain, decodingError.domain)
        XCTAssertEqual(missingCursorError.code, 2)
        XCTAssertEqual(missingCursorError.localizedDescription, "Audit log response is missing the required after cursor.")
        XCTAssertNil(missingCursorError.userInfo[NSUnderlyingErrorKey])
    }

    func testWhenFetchingAuditLogThenDecryptsEntryWithConfiguredDeviceMapper() async throws {
        let fixture = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x01, count: 32))
        let deviceInfoCodec = DeviceInfoCodec()
        let encryptedInfo = try deviceInfoCodec.encrypt(DeviceInfo(name: "Decoded Mac", type: "desktop"),
                                                        using: fixture.protectedKey)
        let payload = Data(#"{"type":"login","occurred_at":"2026-09-02T14:03:11Z","device":{"id":"logged-in","info":"\#(encryptedInfo)"}}"#.utf8)
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: fixture.keyManager,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { false },
                                            canReadUnifiedDeviceList: { true })
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let api = RemoteAPIRequestCreatingMock()
        let entry = try fixture.entry(payload: payload)
        api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entry: entry)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            accountInfoKeys: fixture.keyManager,
                                            isScopedAccessCredentialsEnabled: { false })

        let page = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)

        guard case .decoded(let event) = try XCTUnwrap(page.entries.first) else {
            return XCTFail("Expected audit-log fetch to decrypt the entry")
        }
        XCTAssertEqual(event.id, "audit-entry")
        XCTAssertEqual(event.device.name, "Decoded Mac")
    }

    func testWhenFetchingAuditLogWithoutKeyManagerThenReturnsKeyUnavailableOutcome() async throws {
        let fixture = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x01, count: 32))
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let api = RemoteAPIRequestCreatingMock()
        let entry = try fixture.entry(payload: Data("{}".utf8))
        api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entry: entry)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { false })

        let page = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)

        guard case .unreadable(id: "audit-entry", reason: .keyUnavailable) = try XCTUnwrap(page.entries.first) else {
            return XCTFail("Expected missing key manager to be reported as unreadable")
        }
    }

    func testWhenAuditLogPageHasRepeatedUnknownKeyIDsThenRefreshesOnlyOnce() async throws {
        let initialKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x01, count: 32))
        let otherKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x04, count: 32))
        let payload = Data(#"{"type":"login","occurred_at":"2026-09-02T14:03:11Z","device":{"id":"device"}}"#.utf8)
        let codec = JWECompactCodec()
        let entries = try (0..<3).map { index in
            let encrypted = try codec.encryptRSAOAEP256(payload: payload,
                                                         recipientPublicKey: otherKey.key.publicKey,
                                                         kid: otherKey.key.kid)
            return AuditLogEntry(id: "entry-\(index)", version: "1", payload: encrypted)
        }
        initialKey.keyManager.refreshKeyError = AccountInfoKeyManagerError.missingProtectedKey
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let api = RemoteAPIRequestCreatingMock()
        api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entries: entries)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeys: initialKey.keyManager,
                                            isScopedAccessCredentialsEnabled: { false })

        let page = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)

        XCTAssertEqual(page.entries.count, 3)
        XCTAssertEqual(initialKey.keyManager.loadKeyCalls.count, 1)
        XCTAssertEqual(initialKey.keyManager.refreshKeyCalls.count, 1)
        for entry in page.entries {
            guard case .unreadable(_, reason: .keyIDMismatch) = entry else {
                return XCTFail("Expected each unknown key ID to remain unreadable")
            }
        }
    }

    func testWhenForcedAuditLogRefreshStillHasDifferentKeyThenDoesNotRepeat() async throws {
        let initialKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x01, count: 32))
        let refreshedKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x04, count: 32))
        let payloadKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x07, count: 32))
        let payload = Data("{}".utf8)
        let codec = JWECompactCodec()
        let entries = try (0..<2).map { index in
            AuditLogEntry(id: "entry-\(index)",
                          version: "1",
                          payload: try codec.encryptRSAOAEP256(payload: payload,
                                                               recipientPublicKey: payloadKey.key.publicKey,
                                                               kid: payloadKey.key.kid))
        }
        initialKey.keyManager.refreshKeyStub = refreshedKey.key
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let api = RemoteAPIRequestCreatingMock()
        api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entries: entries)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeys: initialKey.keyManager,
                                            isScopedAccessCredentialsEnabled: { false })

        let page = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)

        XCTAssertEqual(initialKey.keyManager.loadKeyCalls.count, 1)
        XCTAssertEqual(initialKey.keyManager.refreshKeyCalls.count, 1)
        for entry in page.entries {
            guard case .unreadable(_, reason: .keyIDMismatch) = entry else {
                return XCTFail("Expected refreshed key mismatch to remain unreadable")
            }
        }
    }

    func testWhenInitialAuditLogKeyLoadFailsThenAttemptsOnlyOncePerPage() async throws {
        let fixture = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x01, count: 32))
        fixture.keyManager.loadKeyError = AccountInfoKeyManagerError.missingProtectedKey
        let entries = try (0..<3).map { index in
            try fixture.entry(payload: Data("{}".utf8), id: "entry-\(index)")
        }
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let api = RemoteAPIRequestCreatingMock()
        api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entries: entries)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeys: fixture.keyManager,
                                            isScopedAccessCredentialsEnabled: { false })

        let page = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)

        XCTAssertEqual(page.entries.count, 3)
        XCTAssertEqual(fixture.keyManager.loadKeyCalls.count, 1)
        XCTAssertTrue(fixture.keyManager.refreshKeyCalls.isEmpty)
        for entry in page.entries {
            guard case .unreadable(_, reason: .keyUnavailable) = entry else {
                return XCTFail("Expected unavailable-key outcomes")
            }
        }
    }

    func testWhenAuditLogOuterAndDeviceKeysMismatchThenTheyShareRefreshBudget() async throws {
        let initialKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x01, count: 32))
        let refreshedKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x04, count: 32))
        let nestedKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x07, count: 32))
        let deviceInfo = try DeviceInfoCodec().encrypt(DeviceInfo(name: "Nested name", type: "desktop"),
                                                       using: nestedKey.protectedKey)
        let payload = Data(#"{"type":"login","occurred_at":"2026-09-02T14:03:11Z","device":{"id":"device","info":"\#(deviceInfo)"}}"#.utf8)
        let codec = JWECompactCodec()
        let first = AuditLogEntry(id: "outer-and-nested-mismatch",
                                  version: "1",
                                  payload: try codec.encryptRSAOAEP256(payload: payload,
                                                                       recipientPublicKey: refreshedKey.key.publicKey,
                                                                       kid: refreshedKey.key.kid))
        let second = AuditLogEntry(id: "second-outer-mismatch",
                                   version: "1",
                                   payload: try codec.encryptRSAOAEP256(payload: payload,
                                                                        recipientPublicKey: nestedKey.key.publicKey,
                                                                        kid: nestedKey.key.kid))
        let third = AuditLogEntry(id: "refreshed-key-reuse",
                                  version: "1",
                                  payload: try codec.encryptRSAOAEP256(payload: payload,
                                                                       recipientPublicKey: refreshedKey.key.publicKey,
                                                                       kid: refreshedKey.key.kid))
        initialKey.keyManager.refreshKeyStub = refreshedKey.key
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: initialKey.keyManager,
                                            isScopedAccessCredentialsEnabled: { false },
                                            canReadUnifiedDeviceList: { true })
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let api = RemoteAPIRequestCreatingMock()
        api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entries: [first, second, third])
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            accountInfoKeys: initialKey.keyManager,
                                            isScopedAccessCredentialsEnabled: { false })

        let page = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)

        XCTAssertEqual(initialKey.keyManager.loadKeyCalls.count, 1)
        XCTAssertEqual(initialKey.keyManager.refreshKeyCalls.count, 1)
        guard case .decoded(let event) = page.entries[0] else {
            return XCTFail("Expected event payload to decrypt with refreshed key")
        }
        XCTAssertEqual(event.device.name, "Unknown")
        guard case .unreadable(id: "second-outer-mismatch", reason: .keyIDMismatch) = page.entries[1] else {
            return XCTFail("Expected second outer mismatch to respect page refresh budget")
        }
        guard case .decoded(let reusedKeyEvent) = page.entries[2] else {
            return XCTFail("Expected refreshed key to be reused for later entries")
        }
        XCTAssertEqual(reusedKeyEvent.id, "refreshed-key-reuse")
    }

    func testWhenNestedDeviceRefreshHappensFirstThenOuterEntryUsesSameBudget() async throws {
        let initialKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x01, count: 32))
        let refreshedKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x04, count: 32))
        let nestedKey = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x07, count: 32))
        let encryptedInfo = try DeviceInfoCodec().encrypt(DeviceInfo(name: "Nested name", type: "desktop"),
                                                          using: nestedKey.protectedKey)
        let payloadWithStaleDevice = Data(#"{"type":"login","occurred_at":"2026-09-02T14:03:11Z","device":{"id":"device","info":"\#(encryptedInfo)"}}"#.utf8)
        let payload = Data(#"{"type":"login","occurred_at":"2026-09-02T14:03:11Z","device":{"id":"second-device"}}"#.utf8)
        let codec = JWECompactCodec()
        let entries = [
            AuditLogEntry(id: "nested-refresh-first",
                          version: "1",
                          payload: try codec.encryptRSAOAEP256(payload: payloadWithStaleDevice,
                                                               recipientPublicKey: initialKey.key.publicKey,
                                                               kid: initialKey.key.kid)),
            AuditLogEntry(id: "outer-refresh-after-nested",
                          version: "1",
                          payload: try codec.encryptRSAOAEP256(payload: payload,
                                                               recipientPublicKey: nestedKey.key.publicKey,
                                                               kid: nestedKey.key.kid))
        ]
        initialKey.keyManager.refreshKeyStub = refreshedKey.key
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: initialKey.keyManager,
                                            isScopedAccessCredentialsEnabled: { false },
                                            canReadUnifiedDeviceList: { true })
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let api = RemoteAPIRequestCreatingMock()
        api.fakeRequests[endpoints.auditLog] = try makeAuditLogRequest(entries: entries)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            accountInfoKeys: initialKey.keyManager,
                                            isScopedAccessCredentialsEnabled: { false })

        let page = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)

        XCTAssertEqual(initialKey.keyManager.loadKeyCalls.count, 1)
        XCTAssertEqual(initialKey.keyManager.refreshKeyCalls.count, 1)
        guard case .decoded(let event) = page.entries[0] else {
            return XCTFail("Expected the first outer entry to decode")
        }
        XCTAssertEqual(event.device.name, "Unknown")
        guard case .unreadable(id: "outer-refresh-after-nested", reason: .keyIDMismatch) = page.entries[1] else {
            return XCTFail("Expected nested key refresh to consume the page refresh budget")
        }
    }

    private func makeAuditLogRequest(entry: AuditLogEntry) throws -> HTTPRequestingMock {
        try makeAuditLogRequest(entries: [entry])
    }

    private func makeAuditLogRequest(entries: [AuditLogEntry], after: String? = "cursor", before: String? = nil) throws -> HTTPRequestingMock {
        var auditLog: [String: Any] = ["entries": entries.map { ["id": $0.id, "version": $0.version, "payload": $0.payload] }]
        if let after { auditLog["after"] = after }
        if let before { auditLog["before"] = before }
        let data = try JSONSerialization.data(withJSONObject: ["audit_log": auditLog])
        return HTTPRequestingMock(result: .init(data: data, response: .init()))
    }

    func testWhenFetchingAuditLogWithoutTokenThenThrowsWithoutMakingRequest() async {
        let api = RemoteAPIRequestCreatingMock()
        let accountManager = AccountManager(endpoints: Endpoints(baseURL: Self.baseURL),
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })

        await assertThrowsError(SyncError.noToken) {
            _ = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data(), token: nil), cursor: nil)
        }
        XCTAssertTrue(api.createRequestCallArgs.isEmpty)
    }

    func testWhenFetchingAuditLogWithMissingOrMalformedBodyThenThrows() async {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints, api: api, crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        api.fakeRequests[endpoints.auditLog] = HTTPRequestingMock(result: .init(data: nil, response: .init()))

        await assertThrowsError(SyncError.noResponseBody) {
            _ = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)
        }

        api.fakeRequests[endpoints.auditLog] = makeJSONRequest("{}")
        await assertThrowsError(AuditLogError.responseDecodingFailed) {
            _ = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)
        }
    }

    func testWhenFetchingAuditLogRequestFailsThenPropagatesError() async {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            isScopedAccessCredentialsEnabled: { true })
        let request = HTTPRequestingMock()
        request.error = SyncError.unexpectedStatusCode(418)
        api.fakeRequests[endpoints.auditLog] = request

        await assertThrowsError(SyncError.unexpectedStatusCode(418)) {
            _ = try await accountManager.fetchAuditLog(for: makeAccount(primaryKey: Data()), cursor: nil)
        }
    }

    func testWhenUpdatingBaseURLThenAuditLogEndpointUsesNewBaseURL() {
        let endpoints = Endpoints(baseURL: Self.baseURL)

        endpoints.updateBaseURL(for: .development)

        XCTAssertEqual(endpoints.auditLog, ServerEnvironment.development.baseURL.appendingPathComponent("sync/account/audit-log"))
    }

    private func makeDeviceUpdate() -> UpdateDevices.Update {
        UpdateDevices.Update(id: "device-1",
                             name: "encrypted-name",
                             type: "encrypted-type",
                             info: "encrypted-info")
    }

    private func makeAccount(primaryKey: Data, token: String? = "token-1") -> SyncAccount {
        SyncAccount(deviceId: "device-1",
                    deviceName: "iPhone",
                    deviceType: "ios",
                    userId: "user-1",
                    primaryKey: primaryKey,
                    secretKey: Data(repeating: 0x2, count: 32),
                    token: token,
                    state: .active)
    }

    private func makeAccountInfoProtectedKey() -> ProtectedKey {
        ProtectedKey(kid: "account-info-key",
                     encryptedPrivateKey: "encrypted-private-key",
                     publicKey: .mock,
                     encryptedWith: SyncCredentialID.defaultCredential,
                     purpose: ProtectedKeyPurpose.accountInfo)
    }

    private func makeJSONRequest(_ json: String) -> HTTPRequestingMock {
        HTTPRequestingMock(result: .init(data: Data(json.utf8), response: .init()))
    }

    private func devicesURL(for endpoints: Endpoints) -> URL {
        endpoints.devices
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

struct AuditLogTestFixture {
    let protectedKey: ProtectedKey
    let key: AccountInfoKey
    let keyManager: AccountInfoKeyManagingMock

    static func make(accountSecretKey: Data) throws -> AuditLogTestFixture {
        let crypter = CryptingMock()
        let protectedKey = try XCTUnwrap(DefaultAccountInfoKeyFactory(crypter: crypter)
            .makeProtectedKeys(accountSecretKey: accountSecretKey)
            .first)
        let encryptedPrivateKey = try XCTUnwrap(Base64URL.decode(protectedKey.encryptedPrivateKey))
        let privateKeyData = try crypter.decryptData(encryptedPrivateKey, using: accountSecretKey)
        let key = AccountInfoKey(kid: protectedKey.kid,
                                 publicKey: try RSAKeyImporter.makePublicKey(from: protectedKey.publicKey),
                                 privateKey: try RSAKeyImporter.makePrivateKey(fromPKCS8: privateKeyData))
        let keyManager = AccountInfoKeyManagingMock()
        keyManager.loadKeyStub = key
        return AuditLogTestFixture(protectedKey: protectedKey, key: key, keyManager: keyManager)
    }

    func entry(payload: Data, id: String = "audit-entry") throws -> AuditLogEntry {
        let token = try JWECompactCodec().encryptRSAOAEP256(payload: payload,
                                                            recipientPublicKey: key.publicKey,
                                                            kid: key.kid)
        return AuditLogEntry(id: id, version: "1", payload: token)
    }
}

private enum AccountManagerTestError: Error {
    case accountInfoKeyGenerationFailed
}

private final class DeviceInfoCodingMock: DeviceInfoCoding {

    private(set) var encryptUsingProtectedKeyCalls: [(deviceInfo: DeviceInfo, protectedKey: ProtectedKey)] = []
    var encryptUsingProtectedKeyStub = "encrypted-device-info"
    var encryptUsingProtectedKeyError: Error?

    func encrypt(_ deviceInfo: DeviceInfo, using protectedKey: ProtectedKey) throws -> String {
        encryptUsingProtectedKeyCalls.append((deviceInfo: deviceInfo, protectedKey: protectedKey))
        if let encryptUsingProtectedKeyError {
            throw encryptUsingProtectedKeyError
        }
        return encryptUsingProtectedKeyStub
    }

    func decrypt(_ encryptedDeviceInfo: String, using key: AccountInfoKey) throws -> DeviceInfo {
        throw DeviceInfoCodecError.invalidPayload
    }
}

private final class RegisteredDeviceMappingMock: RegisteredDeviceMapping {

    private(set) var registeredDevicesCallEntryIDs: [String] = []
    private(set) var unifiedReadEnabledValues: [Bool] = []
    private(set) var defaultCredentialLoginEntryIDs: [String] = []
    var registeredDevicesHandler: (() -> Void)?

    func registeredDevicesWithRepairState(from entries: [RegisteredDeviceEntry],
                                          account: SyncAccount,
                                          isUnifiedReadEnabled: Bool,
                                          accountInfoKeyProvider: (any AccountInfoKeyProviding)?) async -> RegisteredDeviceMappingResult {
        registeredDevicesHandler?()
        registeredDevicesCallEntryIDs = entries.map(\.id)
        unifiedReadEnabledValues.append(isUnifiedReadEnabled)
        let devices = entries.map { entry in
            RegisteredDevice(id: entry.id,
                             name: entry.name ?? "",
                             type: entry.type ?? "",
                             credentialId: entry.credentialId)
        }
        return RegisteredDeviceMappingResult(devices: devices,
                                             needsCurrentDeviceInfoRepair: false)
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
        defaultCredentialLoginEntryIDs.append(id)
        return RegisteredDevice(id: id,
                                name: encryptedName,
                                type: encryptedType ?? "",
                                credentialId: SyncCredentialID.defaultCredential)
    }

}
