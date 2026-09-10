//
//  RegisteredDeviceMapperTests.swift
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

final class RegisteredDeviceMapperTests: XCTestCase {

    func testWhenMappingDefaultCredentialEntryThenDecryptsWithPrimaryKeyAndSetsDefaultCredentialID() {
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(), isScopedAccessCredentialsEnabled: { true })
        let entry = RegisteredDeviceEntry(id: "native-device",
                                          name: "encrypted_Mac",
                                          type: "encrypted_desktop",
                                          info: nil,
                                          credentialId: SyncCredentialID.defaultCredential)

        let device = mapper.registeredDevice(fromLegacyEntry: entry, account: makeAccount())

        XCTAssertEqual(device?.id, "native-device")
        XCTAssertEqual(device?.name, "Mac")
        XCTAssertEqual(device?.type, "desktop")
        XCTAssertEqual(device?.credentialId, SyncCredentialID.defaultCredential)
    }

    func testWhenUnifiedReadIsEnabledThenPrefersDeviceInfoOverLegacyFields() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey()
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { encryptedDeviceInfo, _ in
            XCTAssertEqual(encryptedDeviceInfo, "encrypted-info")
            return DeviceInfo(name: "Unified Mac", type: "desktop")
        }
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entry = RegisteredDeviceEntry(id: "native-device",
                                          name: "encrypted_Legacy Mac",
                                          type: "encrypted_mobile",
                                          info: "encrypted-info",
                                          credentialId: SyncCredentialID.defaultCredential)

        let devices = await mapper.registeredDevices(from: [entry], account: account)

        XCTAssertEqual(devices.map(\.name), ["Unified Mac"])
        XCTAssertEqual(devices.map(\.type), ["desktop"])
        XCTAssertEqual(accountInfoKeys.loadKeyCalls.map(\.deviceId), [account.deviceId])
        XCTAssertEqual(deviceInfoCodec.decryptCalls, ["encrypted-info"])
    }

    func testWhenUnifiedThirdPartyInfoDecryptsThenDoesNotLoadLegacyThirdPartyKey() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey()
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { _, _ in
            DeviceInfo(name: "Python Client", type: "browser")
        }
        let scopedAccess = ScopedAccessCredentialManagingMock()
        var cachedScopedPasswordCalls = 0
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            scopedAccess: scopedAccess,
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            cachedScopedPassword: {
                                                cachedScopedPasswordCalls += 1
                                                return Data(repeating: 7, count: 32)
                                            },
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entry = RegisteredDeviceEntry(id: "third-party-device",
                                          name: "legacy-name",
                                          type: "legacy-type",
                                          info: "encrypted-info",
                                          credentialId: SyncCredentialID.thirdParty)

        let devices = await mapper.registeredDevices(from: [entry], account: account)

        XCTAssertEqual(devices.map(\.name), ["Python Client"])
        XCTAssertEqual(cachedScopedPasswordCalls, 0)
        XCTAssertTrue(scopedAccess.fetchAccessCredentialsCalls.isEmpty)
        XCTAssertTrue(scopedAccess.recoverScopedPasswordCalls.isEmpty)
    }

    func testWhenUnifiedThirdPartyInfoFailsThenLoadsLegacyThirdPartyKey() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey()
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { _, _ in
            throw DeviceInfoCodecError.invalidPayload
        }
        let scopedPassword = Data(repeating: 7, count: 32)
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let codec = JWECompactCodec()
        var cachedScopedPasswordCalls = 0
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            cachedScopedPassword: {
                                                cachedScopedPasswordCalls += 1
                                                return scopedPassword
                                            },
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true },
                                            jweCompactCodec: codec)
        let entry = RegisteredDeviceEntry(
            id: "third-party-device",
            name: try codec.encryptDirect(payload: Data("Python Client".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            type: try codec.encryptDirect(payload: Data("browser".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            info: "invalid-info",
            credentialId: SyncCredentialID.thirdParty)

        let devices = await mapper.registeredDevices(from: [entry], account: account)

        XCTAssertEqual(devices.map(\.name), ["Python Client"])
        XCTAssertEqual(devices.map(\.type), ["browser"])
        XCTAssertEqual(cachedScopedPasswordCalls, 1)
    }

    func testWhenUnifiedReadIsDisabledThenIgnoresDeviceInfoAndUsesLegacyFields() async {
        let accountInfoKeys = AccountInfoKeyManagingMock()
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { _, _ in
            XCTFail("Unified device info should not be decrypted while reads are disabled")
            throw DeviceInfoCodecError.invalidPayload
        }
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { false })
        let entry = RegisteredDeviceEntry(id: "native-device",
                                          name: "encrypted_Legacy Mac",
                                          type: "encrypted_desktop",
                                          info: "encrypted-info",
                                          credentialId: SyncCredentialID.defaultCredential)

        let result = await mapper.registeredDevicesWithRepairState(from: [entry], account: makeAccount())
        let devices = result.devices

        XCTAssertEqual(devices.map(\.name), ["Legacy Mac"])
        XCTAssertEqual(devices.map(\.type), ["desktop"])
        XCTAssertTrue(accountInfoKeys.loadKeyCalls.isEmpty)
        XCTAssertTrue(deviceInfoCodec.decryptCalls.isEmpty)
        XCTAssertFalse(result.needsCurrentDeviceInfoRepair)
        XCTAssertTrue(result.unifiedReadObservations.isEmpty)
    }

    func testWhenUnifiedReadIsDisabledAndNativeLegacyFieldsCannotBeDecryptedThenReturnsUnknownPlaceholder() async {
        var crypter = CryptingMock()
        crypter._base64DecodeAndDecrypt = { _ in
            throw SyncError.failedToDecryptValue("test")
        }
        let mapper = RegisteredDeviceMapper(crypter: crypter,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { false })
        let entry = RegisteredDeviceEntry(id: "native-device",
                                          name: "undecryptable-name",
                                          type: "undecryptable-type",
                                          info: "ignored-device-info",
                                          credentialId: SyncCredentialID.defaultCredential)

        let result = await mapper.registeredDevicesWithRepairState(from: [entry], account: makeAccount())

        XCTAssertEqual(result.devices.map(\.name), ["Unknown"])
        XCTAssertFalse(result.needsCurrentDeviceInfoRepair)
    }

    func testWhenUnifiedEntriesAreMixedThenEachEntryFallsBackIndependently() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey()
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { encryptedDeviceInfo, _ in
            guard encryptedDeviceInfo == "valid-info" else {
                throw DeviceInfoCodecError.invalidPayload
            }
            return DeviceInfo(name: "Future Browser", type: "browser")
        }
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entries = [
            RegisteredDeviceEntry(id: "future-device",
                                  name: nil,
                                  type: nil,
                                  info: "valid-info",
                                  credentialId: "future"),
            RegisteredDeviceEntry(id: "native-device",
                                  name: "encrypted_Legacy Mac",
                                  type: "encrypted_desktop",
                                  info: "invalid-info",
                                  credentialId: SyncCredentialID.defaultCredential),
            RegisteredDeviceEntry(id: "third-party-device",
                                  name: nil,
                                  type: nil,
                                  info: "invalid-info",
                                  credentialId: SyncCredentialID.thirdParty),
            RegisteredDeviceEntry(id: "legacy-native-device",
                                  name: nil,
                                  type: nil,
                                  info: "valid-info",
                                  credentialId: nil)
        ]

        let result = await mapper.registeredDevicesWithRepairState(from: entries, account: account)
        let devices = result.devices

        XCTAssertEqual(devices.map(\.id), ["future-device", "native-device", "third-party-device", "legacy-native-device"])
        XCTAssertEqual(devices.map(\.name), ["Future Browser", "Legacy Mac", "Browser", "Future Browser"])
        XCTAssertEqual(devices.map(\.type), ["browser", "desktop", "unknown", "browser"])
        XCTAssertEqual(devices.map(\.credentialId), [
            "future", SyncCredentialID.defaultCredential, SyncCredentialID.thirdParty, SyncCredentialID.defaultCredential
        ])
        XCTAssertEqual(accountInfoKeys.loadKeyCalls.count, 1)
        XCTAssertTrue(accountInfoKeys.refreshKeyCalls.isEmpty)
        XCTAssertEqual(deviceInfoCodec.decryptCalls, ["valid-info", "invalid-info", "invalid-info", "valid-info"])
        XCTAssertFalse(result.needsCurrentDeviceInfoRepair)
        XCTAssertEqual(result.unifiedReadObservations, [
            .event(.otherRowDeviceInfoFailedDecryption(.ddg)),
            .event(.otherRowDeviceInfoFailedDecryption(.thirdParty)),
            .event(.otherRowResolvedPlaceholder(.thirdParty))
        ])
    }

    func testWhenOtherRowUsesUnknownCredentialThenDoesNotEmitCredentialScopedObservations() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey()
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { _, _ in
            throw DeviceInfoCodecError.invalidPayload
        }
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entry = RegisteredDeviceEntry(id: "future-device",
                                          name: nil,
                                          type: nil,
                                          info: "invalid-info",
                                          credentialId: "future")

        let result = await mapper.registeredDevicesWithRepairState(from: [entry], account: account)

        XCTAssertTrue(result.unifiedReadObservations.isEmpty)
    }

    func testWhenOtherRowOmitsCredentialThenEmitsNoneCredentialObservations() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey()
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { _, _ in
            throw DeviceInfoCodecError.invalidPayload
        }
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entry = RegisteredDeviceEntry(id: "legacy-device",
                                          name: nil,
                                          type: nil,
                                          info: "invalid-info",
                                          credentialId: nil)

        let result = await mapper.registeredDevicesWithRepairState(from: [entry], account: account)

        XCTAssertEqual(result.unifiedReadObservations, [
            .event(.otherRowDeviceInfoFailedDecryption(.none)),
            .event(.otherRowResolvedPlaceholder(.none))
        ])
    }

    func testWhenUnifiedInfoUsesUnexpectedKeyIDThenRefreshesOnceAndRetriesAllEntries() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey(kid: "stale-key")
        accountInfoKeys.refreshKeyStub = try makeAccountInfoKey(kid: "current-key")
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { encryptedDeviceInfo, key in
            guard key.kid == "current-key" else {
                throw DeviceInfoCodecError.unexpectedKeyID
            }
            return DeviceInfo(name: "Unified \(encryptedDeviceInfo)", type: "desktop")
        }
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entries = [
            RegisteredDeviceEntry(id: "device-1",
                                  name: "encrypted_Legacy One",
                                  type: "encrypted_desktop",
                                  info: "info-one",
                                  credentialId: SyncCredentialID.defaultCredential),
            RegisteredDeviceEntry(id: "device-2",
                                  name: "encrypted_Legacy Two",
                                  type: "encrypted_desktop",
                                  info: "info-two",
                                  credentialId: SyncCredentialID.defaultCredential)
        ]

        let result = await mapper.registeredDevicesWithRepairState(from: entries, account: account)
        let devices = result.devices

        XCTAssertEqual(devices.map(\.name), ["Unified info-one", "Unified info-two"])
        XCTAssertEqual(accountInfoKeys.loadKeyCalls.map(\.deviceId), [account.deviceId])
        XCTAssertEqual(accountInfoKeys.refreshKeyCalls.map(\.deviceId), [account.deviceId])
        XCTAssertEqual(deviceInfoCodec.decryptCalls, ["info-one", "info-two", "info-one", "info-two"])
        XCTAssertFalse(result.needsCurrentDeviceInfoRepair)
        XCTAssertEqual(result.unifiedReadObservations, [
            .event(.ownRowResolvedDeviceInfo)
        ])
    }

    func testWhenStaleKeyRefreshIsRateLimitedThenReportsKeyUnavailableWithoutRefreshExhaustion() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey(kid: "stale-key")
        accountInfoKeys.refreshKeyError = SyncError.unexpectedStatusCode(429)
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { _, _ in
            throw DeviceInfoCodecError.unexpectedKeyID
        }
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entry = RegisteredDeviceEntry(id: account.deviceId,
                                          name: "encrypted_Legacy Mac",
                                          type: "encrypted_desktop",
                                          info: "encrypted-info",
                                          credentialId: SyncCredentialID.defaultCredential)

        let result = await mapper.registeredDevicesWithRepairState(from: [entry], account: account)

        XCTAssertEqual(result.devices.map(\.name), ["Legacy Mac"])
        XCTAssertEqual(accountInfoKeys.refreshKeyCalls.count, 1)
        XCTAssertEqual(result.unifiedReadObservations, [
            .event(.accountInfoKeyUnavailable(.rateLimited)),
            .event(.ownRowResolvedLegacy(.blobDecryptFailed))
        ])
    }

    func testWhenUnifiedInfoStillUsesUnexpectedKeyIDAfterRefreshThenFallsBackWithoutRefreshingAgain() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey(kid: "stale-key")
        accountInfoKeys.refreshKeyStub = try makeAccountInfoKey(kid: "refreshed-key")
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { _, _ in
            throw DeviceInfoCodecError.unexpectedKeyID
        }
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entry = RegisteredDeviceEntry(id: account.deviceId,
                                          name: "encrypted_Legacy Mac",
                                          type: "encrypted_desktop",
                                          info: "encrypted-info",
                                          credentialId: SyncCredentialID.defaultCredential)

        let result = await mapper.registeredDevicesWithRepairState(from: [entry], account: account)
        let devices = result.devices

        XCTAssertEqual(devices.map(\.name), ["Legacy Mac"])
        XCTAssertEqual(accountInfoKeys.loadKeyCalls.count, 1)
        XCTAssertEqual(accountInfoKeys.refreshKeyCalls.count, 1)
        XCTAssertEqual(deviceInfoCodec.decryptCalls, ["encrypted-info", "encrypted-info"])
        XCTAssertTrue(result.needsCurrentDeviceInfoRepair)
        XCTAssertEqual(result.unifiedReadObservations, [.event(.ownRowResolvedLegacy(.blobDecryptFailed))])
    }

    func testWhenCurrentDeviceUnifiedInfoIsCorruptThenRequestsRepair() async throws {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        accountInfoKeys.loadKeyStub = try makeAccountInfoKey()
        let deviceInfoCodec = DeviceInfoReadingMock()
        deviceInfoCodec.decryptHandler = { _, _ in
            throw DeviceInfoCodecError.invalidPayload
        }
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entry = RegisteredDeviceEntry(id: account.deviceId,
                                          name: "encrypted_Legacy Mac",
                                          type: "encrypted_desktop",
                                          info: "corrupt-info",
                                          credentialId: SyncCredentialID.defaultCredential)

        let result = await mapper.registeredDevicesWithRepairState(from: [entry], account: account)

        XCTAssertEqual(result.devices.map(\.name), ["Legacy Mac"])
        XCTAssertTrue(result.needsCurrentDeviceInfoRepair)
        XCTAssertEqual(result.unifiedReadObservations, [.event(.ownRowResolvedLegacy(.blobDecryptFailed))])
    }

    func testWhenCurrentDeviceAccountInfoKeyIsUnavailableThenDoesNotRequestRepair() async {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entry = RegisteredDeviceEntry(id: account.deviceId,
                                          name: "encrypted_Legacy Mac",
                                          type: "encrypted_desktop",
                                          info: "encrypted-info",
                                          credentialId: SyncCredentialID.defaultCredential)

        let result = await mapper.registeredDevicesWithRepairState(from: [entry], account: account)

        XCTAssertEqual(result.devices.map(\.name), ["Legacy Mac"])
        XCTAssertFalse(result.needsCurrentDeviceInfoRepair)
        XCTAssertEqual(result.unifiedReadObservations, [
            .event(.accountInfoKeyUnavailable(.noKeyOnServer))
        ])
    }

    func testWhenUnifiedReadIsEnabledButNoEntryHasInfoThenDoesNotLoadAccountInfoKey() async {
        let account = makeAccount()
        let accountInfoKeys = AccountInfoKeyManagingMock()
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: accountInfoKeys,
                                            isScopedAccessCredentialsEnabled: { true },
                                            canReadUnifiedDeviceList: { true })
        let entry = RegisteredDeviceEntry(id: account.deviceId,
                                          name: "encrypted_Mac",
                                          type: "encrypted_desktop",
                                          info: nil,
                                          credentialId: SyncCredentialID.defaultCredential)

        let result = await mapper.registeredDevicesWithRepairState(from: [entry], account: account)
        let devices = result.devices

        XCTAssertEqual(devices.map(\.name), ["Mac"])
        XCTAssertTrue(accountInfoKeys.loadKeyCalls.isEmpty)
        XCTAssertTrue(result.needsCurrentDeviceInfoRepair)
        XCTAssertEqual(result.unifiedReadObservations, [
            .ownRowMissingDeviceInfo(.legacy)
        ])
    }

    func testWhenMappingThirdPartyEntryWithCachedScopedPasswordThenDecryptsJWEFields() async throws {
        let account = makeAccount()
        let scopedPassword = Data(repeating: 7, count: 32)
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let codec = JWECompactCodec()
        let entry = RegisteredDeviceEntry(
            id: "third-party-device",
            name: try codec.encryptDirect(payload: Data("Python Client".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            type: try codec.encryptDirect(payload: Data("browser".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            info: nil,
            credentialId: SyncCredentialID.thirdParty)
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            cachedScopedPassword: { scopedPassword },
                                            isScopedAccessCredentialsEnabled: { true },
                                            jweCompactCodec: codec)

        let devices = await mapper.registeredDevices(from: [entry], account: account)

        XCTAssertEqual(devices.map { $0.id }, ["third-party-device"])
        XCTAssertEqual(devices.map { $0.name }, ["Python Client"])
        XCTAssertEqual(devices.map { $0.type }, ["browser"])
        XCTAssertEqual(devices.map { $0.credentialId }, [SyncCredentialID.thirdParty])
    }

    func testWhenMappingThirdPartyEntryWithoutCachedPasswordThenRecoversScopedPasswordAndDecryptsJWEFields() async throws {
        let account = makeAccount()
        let scopedPassword = Data(repeating: 7, count: 32)
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let codec = JWECompactCodec()
        let entry = RegisteredDeviceEntry(
            id: "third-party-device",
            name: try codec.encryptDirect(payload: Data("Python Client".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            type: try codec.encryptDirect(payload: Data("browser".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            info: nil,
            credentialId: SyncCredentialID.thirdParty)
        let accessCredentials = [AccessCredential(id: SyncCredentialID.thirdParty, scope: "sync", encrypted3PartyCredential: "encrypted")]
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchAccessCredentialsStub = accessCredentials
        scopedAccess.recoverScopedPasswordStub = scopedPassword
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            scopedAccess: scopedAccess,
                                            cachedScopedPassword: { nil },
                                            isScopedAccessCredentialsEnabled: { true },
                                            jweCompactCodec: codec)

        let devices = await mapper.registeredDevices(from: [entry], account: account)

        XCTAssertEqual(scopedAccess.fetchAccessCredentialsCalls.map { $0.deviceId }, [account.deviceId])
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.count, 1)
        XCTAssertEqual(scopedAccess.recoverScopedPasswordCalls.first?.accessCredentials?.map { $0.id }, [SyncCredentialID.thirdParty])
        XCTAssertEqual(devices.map { $0.id }, ["third-party-device"])
        XCTAssertEqual(devices.map { $0.name }, ["Python Client"])
        XCTAssertEqual(devices.map { $0.type }, ["browser"])
        XCTAssertEqual(devices.map { $0.credentialId }, [SyncCredentialID.thirdParty])
    }

    func testWhenCachedScopedPasswordCannotDecryptEveryThirdPartyEntryThenFallsBackWithoutPartiallyTrustingCache() async throws {
        let account = makeAccount()
        let scopedPassword = Data(repeating: 7, count: 32)
        let thirdPartyMainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let codec = JWECompactCodec()
        let decryptableEntry = RegisteredDeviceEntry(
            id: "decryptable-third-party-device",
            name: try codec.encryptDirect(payload: Data("Python Client".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            type: try codec.encryptDirect(payload: Data("browser".utf8),
                                          contentEncryptionKey: thirdPartyMainKey,
                                          kid: SyncCredentialID.thirdParty),
            info: nil,
            credentialId: SyncCredentialID.thirdParty)
        let undecryptableEntry = RegisteredDeviceEntry(id: "undecryptable-third-party-device",
                                                       name: "not-jwe",
                                                       type: "not-jwe",
                                                       info: nil,
                                                       credentialId: SyncCredentialID.thirdParty)
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            cachedScopedPassword: { scopedPassword },
                                            isScopedAccessCredentialsEnabled: { true },
                                            jweCompactCodec: codec)

        let devices = await mapper.registeredDevices(from: [decryptableEntry, undecryptableEntry], account: account)

        XCTAssertEqual(devices.map { $0.id }, ["decryptable-third-party-device", "undecryptable-third-party-device"])
        XCTAssertEqual(devices.map { $0.name }, ["Browser", "Browser"])
        XCTAssertEqual(devices.map { $0.type }, ["unknown", "unknown"])
        XCTAssertEqual(devices.map { $0.credentialId }, [SyncCredentialID.thirdParty, SyncCredentialID.thirdParty])
    }

    func testWhenMappingUnknownCredentialEntryThenFallsBackWithoutAttemptingDecryption() async {
        var crypter = CryptingMock()
        crypter._base64DecodeAndDecrypt = { _ in
            XCTFail("Unknown credential entries should not be decrypted")
            return ""
        }
        let mapper = RegisteredDeviceMapper(crypter: crypter, isScopedAccessCredentialsEnabled: { true })
        let entry = RegisteredDeviceEntry(id: "future-device",
                                          name: "encrypted_Future",
                                          type: "encrypted_browser",
                                          info: nil,
                                          credentialId: "future")

        let devices = await mapper.registeredDevices(from: [entry], account: makeAccount())

        XCTAssertEqual(devices.map { $0.id }, ["future-device"])
        XCTAssertEqual(devices.map { $0.name }, ["Unknown"])
        XCTAssertEqual(devices.map { $0.type }, ["unknown"])
        XCTAssertEqual(devices.map { $0.credentialId }, ["future"])
    }

    private func makeAccount() -> SyncAccount {
        SyncAccount(deviceId: "device-1",
                    deviceName: "Mac",
                    deviceType: "desktop",
                    userId: "user-1",
                    primaryKey: Data((0..<32).map(UInt8.init)),
                    secretKey: Data(repeating: 2, count: 32),
                    token: "token-1",
                    state: .active)
    }

    private func makeAccountInfoKey(kid: String = "account-info-key") throws -> AccountInfoKey {
        let keyPair = try RSAKeyPairGenerator.makeKeyPair()
        return AccountInfoKey(kid: kid,
                              publicKey: keyPair.publicKey,
                              privateKey: keyPair.privateKey)
    }
}

private final class DeviceInfoReadingMock: DeviceInfoCoding {

    private(set) var decryptCalls: [String] = []
    var decryptHandler: ((String, AccountInfoKey) throws -> DeviceInfo)?

    func encrypt(_ deviceInfo: DeviceInfo, using protectedKey: ProtectedKey) throws -> String {
        throw DeviceInfoCodecError.invalidProtectedKey
    }

    func encrypt(_ deviceInfo: DeviceInfo, using key: AccountInfoKey) throws -> String {
        throw DeviceInfoCodecError.invalidProtectedKey
    }

    func decrypt(_ encryptedDeviceInfo: String, using key: AccountInfoKey) throws -> DeviceInfo {
        decryptCalls.append(encryptedDeviceInfo)
        guard let decryptHandler else {
            throw DeviceInfoCodecError.invalidPayload
        }
        return try decryptHandler(encryptedDeviceInfo, key)
    }
}
