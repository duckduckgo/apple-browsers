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
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        _ = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

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
    }

    func testWhenCreatingAccountWithUnifiedWriteDisabledThenSignupOmitsKeysAndDeviceInfo() async throws {
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
                                            canWriteUnifiedDeviceList: { false })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        _ = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNil(signupBody["keys"])
        XCTAssertNil(signupBody["device_info"])
        XCTAssertEqual(signupBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(signupBody["device_type"] as? String, "encrypted_iOS")
        XCTAssertTrue(accountInfoKeyFactory.makeProtectedKeysCalls.isEmpty)
        XCTAssertTrue(deviceInfoCodec.encryptUsingProtectedKeyCalls.isEmpty)
    }

    func testWhenDeviceInfoEncryptionFailsThenSignupFallsBackToLegacyFields() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        accountInfoKeyFactory.makeProtectedKeysStub = [makeAccountInfoProtectedKey()]
        let deviceInfoCodec = DeviceInfoCodingMock()
        deviceInfoCodec.encryptUsingProtectedKeyError = DeviceInfoCodecError.invalidPayload
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        _ = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNil(signupBody["keys"])
        XCTAssertNil(signupBody["device_info"])
        XCTAssertEqual(signupBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(signupBody["device_type"] as? String, "encrypted_iOS")
        XCTAssertEqual(api.createRequestCallArgs.map(\.url), [endpoints.signup])
    }

    func testWhenAccountInfoKeyGenerationFailsThenSignupFallsBackToSingleLegacyRequest() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        accountInfoKeyFactory.makeProtectedKeysError = AccountManagerTestError.accountInfoKeyGenerationFailed
        let deviceInfoCodec = DeviceInfoCodingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        _ = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNil(signupBody["keys"])
        XCTAssertNil(signupBody["device_info"])
        XCTAssertEqual(signupBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(signupBody["device_type"] as? String, "encrypted_iOS")
        XCTAssertEqual(accountInfoKeyFactory.makeProtectedKeysCalls.count, 1)
        XCTAssertTrue(deviceInfoCodec.encryptUsingProtectedKeyCalls.isEmpty)
        XCTAssertEqual(api.createRequestCallArgs.map(\.url), [endpoints.signup])
    }

    func testWhenEnrichedSignupRequestFailsThenErrorIsPropagatedWithoutLegacyRetry() async throws {
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
    }

    func testWhenDeviceInfoExceedsServerLimitThenSignupFallsBackToLegacyFields() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let accountInfoKeyFactory = AccountInfoKeyFactoryMock()
        accountInfoKeyFactory.makeProtectedKeysStub = [makeAccountInfoProtectedKey()]
        let deviceInfoCodec = DeviceInfoCodingMock()
        deviceInfoCodec.encryptUsingProtectedKeyStub = String(repeating: "a",
                                                              count: DeviceInfo.maximumEncryptedLength + 1)
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            accountInfoKeyFactory: accountInfoKeyFactory,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canWriteUnifiedDeviceList: { true })
        api.fakeRequests[endpoints.signup] = makeJSONRequest("""
        {
            "user_id": "user-1",
            "token": "token-1"
        }
        """)

        _ = try await accountManager.createAccount(deviceName: "iPhone", deviceType: "iOS")

        let signupBody = try makeSignupBody(from: api)
        XCTAssertNil(signupBody["keys"])
        XCTAssertNil(signupBody["device_info"])
        XCTAssertEqual(signupBody["device_name"] as? String, "encrypted_iPhone")
        XCTAssertEqual(signupBody["device_type"] as? String, "encrypted_iOS")
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
            "protected_encryption_key": ""
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
    }

    func testWhenUnifiedReadIsDisabledThenLoginMapsLegacyDevices() async throws {
        let api = RemoteAPIRequestCreatingMock()
        let endpoints = Endpoints(baseURL: Self.baseURL)
        let mapper = RegisteredDeviceMappingMock()
        let accountManager = AccountManager(endpoints: endpoints,
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
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
            "protected_encryption_key": ""
        }
        """)

        let result = try await accountManager.login(.init(userId: "user-1", primaryKey: Data()),
                                                    deviceName: "iPhone",
                                                    deviceType: "iOS")

        XCTAssertTrue(mapper.registeredDevicesCallEntryIDs.isEmpty)
        XCTAssertEqual(mapper.defaultCredentialLoginEntryIDs, ["legacy-device"])
        XCTAssertEqual(result.devices.map(\.id), ["legacy-device"])
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

    func registeredDevicesWithRepairState(from entries: [RegisteredDeviceEntry],
                                          account: SyncAccount,
                                          isUnifiedReadEnabled: Bool) async -> RegisteredDeviceMappingResult {
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
