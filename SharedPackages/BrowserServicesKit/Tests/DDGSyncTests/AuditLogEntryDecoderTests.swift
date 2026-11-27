//
//  AuditLogEntryDecoderTests.swift
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
import Testing

@testable import DDGSync

@Suite("Sync audit log entry decoder")
struct AuditLogEntryDecoderTests {

    private let accountSecretKey = Data(repeating: 0x01, count: 32)
    private let account = SyncAccount(deviceId: "local-device",
                                      deviceName: "Local device",
                                      deviceType: "desktop",
                                      userId: "user",
                                      primaryKey: Data(repeating: 0x02, count: 32),
                                      secretKey: Data(repeating: 0x03, count: 32),
                                      token: "token",
                                      state: .active)

    @available(iOS 16, macOS 13, *)
    @Test("Login and logout entries map device snapshots", .timeLimit(.minutes(1)))
    func testWhenDecodingLoginAndLogoutThenMapsDeviceSnapshots() async throws {
        let fixture = try makeFixture()
        let deviceInfoCodec = DeviceInfoCodec()
        let encryptedInfo = try deviceInfoCodec.encrypt(DeviceInfo(name: "Unified Mac", type: "desktop"),
                                                        using: fixture.protectedKey)
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: fixture.keyManager,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { false },
                                            canReadUnifiedDeviceList: { true })
        let decoder = AuditLogEntryDecoder(accountInfoKey: fixture.key, deviceMapper: mapper)
        let payload = """
        {"type":"logout","occurred_at":"2026-09-02T14:03:11.123Z","device":{"id":"logged-out","info":"\(encryptedInfo)"},"actor":{"id":"actor","name":"encrypted_Actor iPhone","type":"encrypted_mobile"}}
        """
        let result = try await decoder.decode(try fixture.entry(payload: Data(payload.utf8)), for: account)

        guard case .decoded(let event) = result else {
            Issue.record("Expected a decoded logout event")
            return
        }
        #expect(event.type == .logout)
        #expect(event.id == "audit-entry")
        #expect(event.device.id == "logged-out")
        #expect(event.device.name == "Unified Mac")
        #expect(event.device.type == "desktop")
        #expect(event.actor?.id == "actor")
        #expect(event.actor?.name == "Actor iPhone")
        #expect(event.actor?.type == "mobile")
        let expectedTimestamp = ISO8601DateFormatter()
        expectedTimestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(event.occurredAt == expectedTimestamp.date(from: "2026-09-02T14:03:11.123Z"))
    }

    @available(iOS 16, macOS 13, *)
    @Test("A page recovers a historical third-party key once", .timeLimit(.minutes(1)))
    func testWhenFetchingPageWithHistoricalThirdPartyEntriesThenRecoversScopedPasswordOnce() async throws {
        let fixture = try makeFixture()
        let scopedAccess = ScopedAccessCredentialManagingMock()
        let scopedPassword = Data(repeating: 0x04, count: 32)
        scopedAccess.recoverScopedPasswordStub = scopedPassword
        let entries = try ["first", "second"].map {
            try makeThirdPartyEntry(id: $0, name: "Recovered browser", password: scopedPassword, fixture: fixture)
        }
        let mapper = makeMapper(scopedAccess: scopedAccess,
                                accountInfoKeys: fixture.keyManager,
                                cachedScopedPassword: { nil })
        let (accountManager, api, endpoint) = makeAccountManager(fixture: fixture, mapper: mapper)
        api.fakeRequests[endpoint] = try makeAuditLogRequest(entries)

        let page = try await accountManager.fetchAuditLog(for: account, cursor: nil)

        #expect(scopedAccess.fetchAccessCredentialsCalls.count == 1)
        #expect(scopedAccess.recoverScopedPasswordCalls.count == 1)
        guard page.entries.count == 2,
              case .decoded(let first) = page.entries[0],
              case .decoded(let second) = page.entries[1] else {
            Issue.record("Expected both historical entries to decode")
            return
        }
        #expect(first.id == "first")
        #expect(second.id == "second")
        #expect(first.device.name == "Recovered browser")
        #expect(second.device.name == "Recovered browser")
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cached password is checked for each entry and failed recovery is reused", .timeLimit(.minutes(1)))
    func testWhenCachedPasswordOnlyDecryptsFirstEntryThenKeepsItsDetailsAndReusesRecoveryResult() async throws {
        let fixture = try makeFixture()
        let cachedPassword = Data(repeating: 0x05, count: 32)
        let historicalPassword = Data(repeating: 0x06, count: 32)
        for recoveryFails in [true, false] {
            let scopedAccess = ScopedAccessCredentialManagingMock()
            if recoveryFails {
                scopedAccess.recoverScopedPasswordError = AuditLogRecoveryTestError.expected
            }
            let entries = [
                try makeThirdPartyEntry(id: "cached", name: "Native browser", password: cachedPassword, fixture: fixture),
                try makeThirdPartyEntry(id: "historical-one", name: "Old browser one", password: historicalPassword, fixture: fixture, malformedFields: true),
                try makeThirdPartyEntry(id: "historical-two", name: "Old browser two", password: historicalPassword, fixture: fixture)
            ]
            let mapper = makeMapper(scopedAccess: scopedAccess,
                                    accountInfoKeys: fixture.keyManager,
                                    cachedScopedPassword: { cachedPassword })
            let (accountManager, api, endpoint) = makeAccountManager(fixture: fixture, mapper: mapper)
            api.fakeRequests[endpoint] = try makeAuditLogRequest(entries)

            let page = try await accountManager.fetchAuditLog(for: account, cursor: nil)

            #expect(scopedAccess.fetchAccessCredentialsCalls.count == 1)
            #expect(scopedAccess.recoverScopedPasswordCalls.count == 1)
            guard page.entries.count == 3,
                  case .decoded(let cached) = page.entries[0],
                  case .decoded(let historicalOne) = page.entries[1],
                  case .decoded(let historicalTwo) = page.entries[2] else {
                Issue.record("Expected audit events to remain present when scoped recovery fails")
                return
            }
            #expect(cached.device.name == "Native browser")
            #expect(historicalOne.device.name == "Browser")
            #expect(historicalTwo.device.name == "Browser")
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A historical password is recovered without replacing a valid cached password", .timeLimit(.minutes(1)))
    func testWhenEntriesUseCachedAndHistoricalThirdPartyPasswordsThenBothRemainReadable() async throws {
        let fixture = try makeFixture()
        let scopedAccess = ScopedAccessCredentialManagingMock()
        let cachedPassword = Data(repeating: 0x05, count: 32)
        let recoveredPassword = Data(repeating: 0x06, count: 32)
        scopedAccess.recoverScopedPasswordStub = recoveredPassword
        let entries = [
            try makeThirdPartyEntry(id: "cached", name: "Current browser", password: cachedPassword, fixture: fixture),
            try makeThirdPartyEntry(id: "historical", name: "Historical browser", password: recoveredPassword, fixture: fixture)
        ]
        let mapper = makeMapper(scopedAccess: scopedAccess,
                                accountInfoKeys: fixture.keyManager,
                                cachedScopedPassword: { cachedPassword })
        let (accountManager, api, endpoint) = makeAccountManager(fixture: fixture, mapper: mapper)
        api.fakeRequests[endpoint] = try makeAuditLogRequest(entries)

        let page = try await accountManager.fetchAuditLog(for: account, cursor: nil)

        #expect(scopedAccess.fetchAccessCredentialsCalls.count == 1)
        #expect(scopedAccess.recoverScopedPasswordCalls.count == 1)
        guard page.entries.count == 2,
              case .decoded(let cached) = page.entries[0],
              case .decoded(let historical) = page.entries[1] else {
            Issue.record("Expected cached and recovered password entries to decode")
            return
        }
        #expect(cached.device.name == "Current browser")
        #expect(historical.device.name == "Historical browser")
        #expect(historical.device.type == "desktop")
    }

    @available(iOS 16, macOS 13, *)
    @Test("Device and actor snapshots use the page key without refreshing", .timeLimit(.minutes(1)))
    func testWhenActorInfoUsesDifferentKeyThenKeepsDeviceAndUsesActorPlaceholder() async throws {
        let firstFixture = try makeFixture()
        let secondFixture = try AuditLogTestFixture.make(accountSecretKey: Data(repeating: 0x07, count: 32))
        firstFixture.keyManager.refreshKeyError = AccountInfoKeyManagerError.missingProtectedKey
        let codec = DeviceInfoCodec()
        let deviceInfo = try codec.encrypt(DeviceInfo(name: "K1 device", type: "desktop"), using: firstFixture.protectedKey)
        let actorInfo = try codec.encrypt(DeviceInfo(name: "K2 actor", type: "mobile"), using: secondFixture.protectedKey)
        let payload = try JSONSerialization.data(withJSONObject: [
            "type": "login",
            "occurred_at": "2026-09-02T14:03:11Z",
            "device": ["id": "device", "info": deviceInfo],
            "actor": ["id": "actor", "info": actorInfo]
        ])
        let entry = try encryptedAuditEntry(id: "mixed-keys", payload: payload, key: firstFixture.key)
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: firstFixture.keyManager,
                                            deviceInfoCodec: codec,
                                            isScopedAccessCredentialsEnabled: { false },
                                            canReadUnifiedDeviceList: { true })
        let (accountManager, api, endpoint) = makeAccountManager(fixture: firstFixture, mapper: mapper)
        api.fakeRequests[endpoint] = try makeAuditLogRequest([entry])

        let page = try await accountManager.fetchAuditLog(for: account, cursor: nil)

        #expect(firstFixture.keyManager.loadKeyCalls.count == 1)
        #expect(firstFixture.keyManager.refreshKeyCalls.isEmpty)
        guard page.entries.count == 1,
              case .decoded(let event) = page.entries[0] else {
            Issue.record("Expected the event to remain readable with a placeholder for the actor")
            return
        }
        #expect(event.device.name == "K1 device")
        #expect(event.device.type == "desktop")
        #expect(event.actor?.name == "Unknown")
    }

    @available(iOS 16, macOS 13, *)
    @Test("device_info_added decodes and preserves readable device-info provenance", .timeLimit(.minutes(1)))
    func testWhenDeviceInfoIsAddedThenDecodesDeviceInfoEvent() async throws {
        let fixture = try makeFixture()
        let codec = DeviceInfoCodec()
        let info = try codec.encrypt(DeviceInfo(name: "Added info", type: "desktop"), using: fixture.protectedKey)
        let payload = Data(#"{"type":"device_info_added","occurred_at":"2026-09-02T14:03:11Z","device":{"id":"device","info":"\#(info)"}}"#.utf8)
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            deviceInfoCodec: codec,
                                            isScopedAccessCredentialsEnabled: { false },
                                            canReadUnifiedDeviceList: { true })
        let decoder = AuditLogEntryDecoder(accountInfoKey: fixture.key, deviceMapper: mapper)

        let result = try await decoder.decode(try fixture.entry(payload: payload), for: account)

        guard case .decoded(let event) = result else {
            Issue.record("Expected a readable device_info_added event")
            return
        }
        #expect(event.type == .deviceInfoAdded)
        #expect(event.device.name == "Added info")
        #expect(event.hasDeviceInfo)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unknown event types remain skippable with future schemas", .timeLimit(.minutes(1)))
    func testWhenEventTypeIsUnknownThenReturnsUnknownEvenIfSchemaHasChanged() async throws {
        let fixture = try makeFixture()
        let decoder = AuditLogEntryDecoder(accountInfoKey: fixture.key,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data(#"{"type":"future_event"}"#.utf8)), for: account)

        guard case .unknownType(id: "audit-entry", type: "future_event") = result else {
            Issue.record("Expected unknown event type to be preserved")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unsupported versions do not need the account key", .timeLimit(.minutes(1)))
    func testWhenVersionIsUnsupportedThenDoesNotNeedKey() async throws {
        let decoder = AuditLogEntryDecoder(accountInfoKey: nil,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())
        let entry = AuditLogEntry(id: "audit-entry", version: "2", payload: "unused")

        let result = try await decoder.decode(entry, for: account)

        guard case .unsupportedVersion(id: "audit-entry", version: "2") = result else {
            Issue.record("Expected unsupported version outcome")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("An entry referencing a different key ID remains unreadable", .timeLimit(.minutes(1)))
    func testWhenEntryUsesDifferentKeyIDThenReturnsMismatch() async throws {
        let fixture = try makeFixture()
        let otherKey = try makeFixture()
        let decoder = AuditLogEntryDecoder(accountInfoKey: otherKey.key,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)

        guard case .unreadable(id: "audit-entry", reason: .keyIDMismatch) = result else {
            Issue.record("Expected the entry key ID mismatch to remain explicit")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A JWE without a key ID has an explicit unreadable reason", .timeLimit(.minutes(1)))
    func testWhenAuditLogJWEHasNoKeyIDThenReturnsMissingKeyID() async throws {
        let fixture = try makeFixture()
        let keyedToken = try fixture.entry(payload: Data("{}".utf8)).payload
        let components = keyedToken.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let header = Base64URL.encode(Data(#"{"alg":"RSA-OAEP-256","enc":"A256GCM"}"#.utf8))
        let tokenWithoutKeyID = ([header] + components.dropFirst()).joined(separator: ".")
        let decoder = AuditLogEntryDecoder(accountInfoKey: fixture.key,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(AuditLogEntry(id: "no-kid", version: "1", payload: tokenWithoutKeyID), for: account)

        guard case .unreadable(id: "no-kid", reason: .missingKeyID) = result else {
            Issue.record("Expected missing key ID to remain explicitly unreadable")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Malformed JWE remains a decryption failure", .timeLimit(.minutes(1)))
    func testWhenAuditLogJWEIsMalformedThenReturnsDecryptionFailure() async throws {
        let fixture = try makeFixture()
        let decoder = AuditLogEntryDecoder(accountInfoKey: fixture.key,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(AuditLogEntry(id: "malformed", version: "1", payload: "not-a-jwe"), for: account)

        guard case .unreadable(id: "malformed", reason: .decryptionFailed) = result else {
            Issue.record("Expected malformed JWE to remain a decryption failure")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Malformed JWE is rejected without a resolved key", .timeLimit(.minutes(1)))
    func testWhenAuditLogJWEIsMalformedWithoutKeyThenReturnsDecryptionFailure() async throws {
        let decoder = AuditLogEntryDecoder(accountInfoKey: nil,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(AuditLogEntry(id: "malformed", version: "1", payload: "not-a-jwe"), for: account)

        guard case .unreadable(id: "malformed", reason: .decryptionFailed) = result else {
            Issue.record("Expected malformed JWE to be identified before missing keys")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A matching key ID with the wrong private key fails decryption", .timeLimit(.minutes(1)))
    func testWhenJWEKidMatchesButPrivateKeyIsWrongThenReportsDecryptionFailure() async throws {
        let fixture = try makeFixture()
        let otherKey = try makeFixture()
        let wrongKey = AccountInfoKey(kid: fixture.key.kid,
                                      publicKey: fixture.key.publicKey,
                                      privateKey: otherKey.key.privateKey)
        let decoder = AuditLogEntryDecoder(accountInfoKey: wrongKey,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)

        guard case .unreadable(id: "audit-entry", reason: .decryptionFailed) = result else {
            Issue.record("Expected decryption failure when the matching kid has the wrong private key")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Snapshots without readable fields use the device-list placeholder", .timeLimit(.minutes(1)))
    func testWhenSnapshotHasNoReadableFieldsThenUsesDeviceListPlaceholder() async throws {
        let fixture = try makeFixture()
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: fixture.keyManager,
                                            isScopedAccessCredentialsEnabled: { false },
                                            canReadUnifiedDeviceList: { true })
        let decoder = AuditLogEntryDecoder(accountInfoKey: fixture.key, deviceMapper: mapper)
        let payload = Data(#"{"type":"login","occurred_at":"2026-09-02T14:03:11Z","device":{"id":"lost-device"}}"#.utf8)

        let result = try await decoder.decode(try fixture.entry(payload: payload), for: account)

        guard case .decoded(let event) = result else {
            Issue.record("Expected unreadable device details to retain the audit event")
            return
        }
        #expect(event.device.id == "lost-device")
        #expect(event.device.name == "Unknown")
        #expect(event.device.type == "unknown")
        #expect(event.device.credentialId == SyncCredentialID.defaultCredential)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Malformed JWE and known payloads remain unreadable", .timeLimit(.minutes(1)))
    func testWhenJWEOrKnownPayloadIsMalformedThenReturnsUnreadableOutcome() async throws {
        let fixture = try makeFixture()
        let decoder = AuditLogEntryDecoder(accountInfoKey: fixture.key,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let malformedJWE = try await decoder.decode(AuditLogEntry(id: "bad-jwe", version: "1", payload: "not-a-jwe"), for: account)
        let malformedJSON = try await decoder.decode(try fixture.entry(payload: Data("not-json".utf8)), for: account)
        let malformedTimestamp = try await decoder.decode(try fixture.entry(payload: Data(#"{"type":"login","occurred_at":"tomorrow","device":{"id":"device"}}"#.utf8)), for: account)

        guard case .unreadable(id: "bad-jwe", reason: .decryptionFailed) = malformedJWE,
              case .unreadable(id: "audit-entry", reason: .invalidPayload) = malformedJSON,
              case .unreadable(id: "audit-entry", reason: .invalidPayload) = malformedTimestamp else {
            Issue.record("Expected malformed entry outcomes")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Audit key loading preserves the shared cache", .timeLimit(.minutes(1)))
    func testAuditKeyLoadingDoesNotPersistFetchedKeys() async throws {
        let fixture = try makeFixture()
        let secureStore = SecureStorageStub()
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = [fixture.protectedKey]
        let keyManager = AccountInfoKeyManager(secureStore: secureStore, scopedAccess: scopedAccess, crypter: CryptingMock())
        let (manager, api, endpoint) = makeAccountManager(fixture: fixture, mapper: RegisteredDeviceMappingTestDouble(), keyManager: keyManager)
        api.fakeRequests[endpoint] = try makeAuditLogRequest([AuditLogEntry(id: "entry", version: "1", payload: "unreadable")])

        _ = try await manager.fetchAuditLog(for: account, cursor: nil)

        #expect(secureStore.theProtectedKeysData == nil)
        #expect(secureStore.theScopedPassword == nil)
        #expect(scopedAccess.fetchProtectedKeysCalls.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("An inaccessible audit key cache stops the page without fetching", .timeLimit(.minutes(1)))
    func testAuditKeyLoadingPropagatesKeychainFailure() async throws {
        let fixture = try makeFixture()
        let secureStore = SecureStorageStub()
        secureStore.mockReadError = .failedToReadSecureStore(status: -25308)
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = [fixture.protectedKey]
        let keyManager = AccountInfoKeyManager(secureStore: secureStore, scopedAccess: scopedAccess, crypter: CryptingMock())
        let (manager, api, endpoint) = makeAccountManager(fixture: fixture, mapper: RegisteredDeviceMappingTestDouble(), keyManager: keyManager)
        api.fakeRequests[endpoint] = try makeAuditLogRequest([AuditLogEntry(id: "entry", version: "1", payload: "unreadable")])

        await #expect(throws: SyncError.failedToReadSecureStore(status: -25308)) {
            _ = try await manager.fetchAuditLog(for: account, cursor: nil)
        }
        #expect(scopedAccess.fetchProtectedKeysCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Incomplete third-party snapshots do not trigger credential recovery", .timeLimit(.minutes(1)),
          arguments: [["name"], ["type"], ["name", "type"]], [false, true])
    func testIncompleteThirdPartySnapshotsSkipCredentialRecovery(missingFields: [String], includesReadableSnapshot: Bool) async throws {
        let fixture = try makeFixture()
        let password = Data(repeating: 4, count: 32)
        let mainKey = ScopedAccessKeyDerivation.mainKey(from: password, userID: account.userId)
        let codec = JWECompactCodec()
        let encryptedName = try codec.encryptDirect(payload: Data("Readable browser".utf8), contentEncryptionKey: mainKey,
                                                     kid: SyncCredentialID.thirdParty)
        let encryptedType = try codec.encryptDirect(payload: Data("desktop".utf8), contentEncryptionKey: mainKey,
                                                     kid: SyncCredentialID.thirdParty)
        let incomplete = RegisteredDeviceEntry(id: "incomplete", name: missingFields.contains("name") ? nil : encryptedName,
                                                type: missingFields.contains("type") ? nil : encryptedType, info: nil,
                                                credentialId: SyncCredentialID.thirdParty)
        let readable = RegisteredDeviceEntry(id: "readable", name: encryptedName, type: encryptedType, info: nil,
                                              credentialId: SyncCredentialID.thirdParty)
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchAccessCredentialsError = SyncError.unexpectedStatusCode(401)
        var passwordReads = 0
        let mapper = makeMapper(scopedAccess: scopedAccess, accountInfoKeys: fixture.keyManager, cachedScopedPassword: {
            passwordReads += 1
            return password
        })

        let result = try await mapper.registeredAuditLogDevices(from: includesReadableSnapshot ? [readable, incomplete] : [incomplete],
                                                                account: account, accountInfoKey: fixture.key,
                                                                thirdPartyPasswordRecoveryCache: nil)

        #expect(result.devices.map(\.id) == (includesReadableSnapshot ? ["readable", "incomplete"] : ["incomplete"]))
        #expect(result.devices.map(\.name) == (includesReadableSnapshot ? ["Readable browser", "Browser"] : ["Browser"]))
        #expect(result.devices.map(\.type) == (includesReadableSnapshot ? ["desktop", "unknown"] : ["unknown"]))
        #expect(result.devices.allSatisfy { $0.credentialId == SyncCredentialID.thirdParty })
        #expect(scopedAccess.fetchAccessCredentialsCalls.isEmpty)
        #expect(passwordReads == (includesReadableSnapshot ? 1 : 0))
    }

    @available(iOS 16, macOS 13, *)
    @Test("An audit credential request failure stops the whole page", .timeLimit(.minutes(1)))
    func testAuditCredentialRequestPropagatesUnauthorizedError() async throws {
        let fixture = try makeFixture()
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchAccessCredentialsError = SyncError.unexpectedStatusCode(401)
        let mapper = makeMapper(scopedAccess: scopedAccess, accountInfoKeys: fixture.keyManager, cachedScopedPassword: { nil })
        let (manager, api, endpoint) = makeAccountManager(fixture: fixture, mapper: mapper)
        let entry = try makeThirdPartyEntry(id: "entry", name: "Browser", password: Data(repeating: 1, count: 32), fixture: fixture)
        api.fakeRequests[endpoint] = try makeAuditLogRequest([entry])

        await #expect(throws: SyncError.unexpectedStatusCode(401)) {
            _ = try await manager.fetchAuditLog(for: account, cursor: nil)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("An unreadable historical-password cache stops the audit page", .timeLimit(.minutes(1)))
    func testAuditPasswordCacheFailureDoesNotFetchCredentials() async throws {
        let fixture = try makeFixture()
        let scopedAccess = ScopedAccessCredentialManagingMock()
        let mapper = makeMapper(scopedAccess: scopedAccess, accountInfoKeys: fixture.keyManager,
                                cachedScopedPassword: { throw SyncError.failedToReadSecureStore(status: -25308) })
        let (manager, api, endpoint) = makeAccountManager(fixture: fixture, mapper: mapper)
        let entry = try makeThirdPartyEntry(id: "entry", name: "Browser", password: Data(repeating: 1, count: 32), fixture: fixture)
        api.fakeRequests[endpoint] = try makeAuditLogRequest([entry])

        await #expect(throws: SyncError.failedToReadSecureStore(status: -25308)) {
            _ = try await manager.fetchAuditLog(for: account, cursor: nil)
        }
        #expect(scopedAccess.fetchAccessCredentialsCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Audit key and name decoding share one credential recovery per page", .timeLimit(.minutes(1)), arguments: [false, true])
    func testAuditPageSharesCredentialRecovery(hasStaleCachedKey: Bool) async throws {
        let fixture = try makeFixture()
        let password = Data(repeating: 4, count: 32)
        let mainKey = ScopedAccessKeyDerivation.mainKey(from: password, userID: account.userId)
        let encryptedPrivateKey = try #require(Base64URL.decode(fixture.protectedKey.encryptedPrivateKey))
        let privateKey = try CryptingMock().decryptData(encryptedPrivateKey, using: accountSecretKey)
        let wrappedPrivateKey = try JWECompactCodec().encryptDirect(payload: privateKey, contentEncryptionKey: mainKey, kid: SyncCredentialID.thirdParty)
        let protectedKey = ProtectedKey(kid: fixture.protectedKey.kid, encryptedPrivateKey: wrappedPrivateKey,
                                         publicKey: fixture.protectedKey.publicKey, encryptedWith: SyncCredentialID.thirdParty,
                                         purpose: ProtectedKeyPurpose.accountInfo)
        let secureStore = SecureStorageStub()
        if hasStaleCachedKey {
            let staleKey = ProtectedKey(kid: protectedKey.kid, encryptedPrivateKey: "invalid-jwe",
                                       publicKey: protectedKey.publicKey, encryptedWith: SyncCredentialID.thirdParty,
                                       purpose: ProtectedKeyPurpose.accountInfo)
            secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([staleKey])
        }
        let cachedData = secureStore.theProtectedKeysData
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = [protectedKey]
        scopedAccess.recoverScopedPasswordStub = password
        let keyManager = AccountInfoKeyManager(secureStore: secureStore, scopedAccess: scopedAccess, crypter: CryptingMock())
        let mapper = makeMapper(scopedAccess: scopedAccess, accountInfoKeys: keyManager, cachedScopedPassword: { nil })
        let (manager, api, endpoint) = makeAccountManager(fixture: fixture, mapper: mapper, keyManager: keyManager)
        let entry = try makeThirdPartyEntry(id: "entry", name: "Recovered browser", password: password, fixture: fixture)
        api.fakeRequests[endpoint] = try makeAuditLogRequest([entry])

        let page = try await manager.fetchAuditLog(for: account, cursor: nil)

        guard case .decoded(let event) = page.entries.first else {
            Issue.record("Expected the recovered key and password to decode the event")
            return
        }
        #expect(event.device.name == "Recovered browser")
        #expect(scopedAccess.fetchAccessCredentialsCalls.count == 1)
        #expect(scopedAccess.recoverScopedPasswordCalls.count == 1)
        #expect(secureStore.theProtectedKeysData == cachedData)
        #expect(secureStore.theScopedPassword == nil)

        _ = try await manager.fetchAuditLog(for: account, cursor: .before("older"))
        #expect(scopedAccess.fetchAccessCredentialsCalls.count == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A completed nil recovery is shared with name decoding", .timeLimit(.minutes(1)))
    func testAuditPageSharesNilRecoveryAfterDefaultKeyFallback() async throws {
        let fixture = try makeFixture()
        let staleKey = ProtectedKey(kid: fixture.protectedKey.kid, encryptedPrivateKey: "invalid-jwe",
                                   publicKey: fixture.protectedKey.publicKey, encryptedWith: SyncCredentialID.thirdParty,
                                   purpose: ProtectedKeyPurpose.accountInfo)
        let secureStore = SecureStorageStub()
        secureStore.theProtectedKeysData = try JSONEncoder.snakeCaseKeys.encode([staleKey])
        let scopedAccess = ScopedAccessCredentialManagingMock()
        scopedAccess.fetchProtectedKeysStub = [fixture.protectedKey]
        let keyManager = AccountInfoKeyManager(secureStore: secureStore, scopedAccess: scopedAccess, crypter: CryptingMock())
        let mapper = makeMapper(scopedAccess: scopedAccess, accountInfoKeys: keyManager, cachedScopedPassword: { nil })
        let (manager, api, endpoint) = makeAccountManager(fixture: fixture, mapper: mapper, keyManager: keyManager)
        let entry = try makeThirdPartyEntry(id: "entry", name: "Unavailable name", password: Data(repeating: 4, count: 32), fixture: fixture)
        api.fakeRequests[endpoint] = try makeAuditLogRequest([entry])

        let page = try await manager.fetchAuditLog(for: account, cursor: nil)

        guard case .decoded(let event) = page.entries.first else {
            Issue.record("Expected the event with a fallback name")
            return
        }
        #expect(event.device.name == "Browser")
        #expect(scopedAccess.fetchAccessCredentialsCalls.count == 1)
        #expect(scopedAccess.recoverScopedPasswordCalls.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Empty recovered passwords are treated as a completed nil result", .timeLimit(.minutes(1)))
    func testEmptyRecoveredPasswordIsNotUsed() async throws {
        let cache = ThirdPartyPasswordRecoveryCache()
        let password = try await cache.recoverPasswordOnce { Data() }
        #expect(password == nil)
        _ = try await cache.recoverPasswordOnce {
            Issue.record("An empty result must not repeat credential recovery")
            return Data([1])
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A thrown recovery remains retryable but a completed nil result is cached", .timeLimit(.minutes(1)))
    func testPasswordRecoveryCanRetryAfterThrowing() async throws {
        let cache = ThirdPartyPasswordRecoveryCache()
        await #expect(throws: AuditLogRecoveryTestError.self) {
            try await cache.recoverPasswordOnce { throw AuditLogRecoveryTestError.expected }
        }
        var retryCount = 0
        let password = try await cache.recoverPasswordOnce {
            retryCount += 1
            return nil
        }
        #expect(password == nil)
        #expect(retryCount == 1)
        _ = try await cache.recoverPasswordOnce {
            Issue.record("A completed recovery must not be repeated")
            return Data([1])
        }
    }

    private func makeFixture() throws -> AuditLogTestFixture {
        try AuditLogTestFixture.make(accountSecretKey: accountSecretKey)
    }

    private func makeMapper(scopedAccess: ScopedAccessCredentialManagingMock,
                            accountInfoKeys: AccountInfoKeyManaging,
                            cachedScopedPassword: @escaping () throws -> Data?) -> RegisteredDeviceMapper {
        RegisteredDeviceMapper(crypter: CryptingMock(),
                               scopedAccess: scopedAccess,
                               accountInfoKeys: accountInfoKeys,
                               cachedScopedPassword: cachedScopedPassword,
                               isScopedAccessCredentialsEnabled: { true },
                               canReadUnifiedDeviceList: { true })
    }

    private func makeAccountManager(fixture: AuditLogTestFixture,
                                    mapper: any RegisteredDeviceMapping,
                                    keyManager: AccountInfoKeyManaging? = nil) -> (AccountManager, RemoteAPIRequestCreatingMock, URL) {
        let api = RemoteAPIRequestCreatingMock()
        let endpoint = URL(string: "https://dev.null/sync/account/audit-log")!
        let accountManager = AccountManager(endpoints: Endpoints(baseURL: URL(string: "https://dev.null")!),
                                            api: api,
                                            crypter: CryptingMock(),
                                            registeredDeviceMapper: mapper,
                                            accountInfoKeys: keyManager ?? fixture.keyManager,
                                            isScopedAccessCredentialsEnabled: { true })
        return (accountManager, api, endpoint)
    }

    private func makeThirdPartyEntry(id: String,
                                     name: String,
                                     password: Data,
                                     fixture: AuditLogTestFixture,
                                     malformedFields: Bool = false) throws -> AuditLogEntry {
        let key = ScopedAccessKeyDerivation.mainKey(from: password, userID: account.userId)
        let codec = JWECompactCodec()
        let encryptedName = try malformedFields ? "not-jwe" : codec.encryptDirect(payload: Data(name.utf8),
                                                                                    contentEncryptionKey: key,
                                                                                    kid: SyncCredentialID.thirdParty)
        let encryptedType = try malformedFields ? "not-jwe" : codec.encryptDirect(payload: Data("desktop".utf8),
                                                                                    contentEncryptionKey: key,
                                                                                    kid: SyncCredentialID.thirdParty)
        return try encryptedAuditEntry(id: id,
                                       payload: auditPayload(device: ["id": id,
                                                                      "credential_id": SyncCredentialID.thirdParty,
                                                                      "name": encryptedName,
                                                                      "type": encryptedType]),
                                       key: fixture.key)
    }

    private func auditPayload(device: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["type": "login",
                                                    "occurred_at": "2026-09-02T14:03:11Z",
                                                    "device": device])
    }

    private func encryptedAuditEntry(id: String, payload: Data, key: AccountInfoKey) throws -> AuditLogEntry {
        let encryptedPayload = try JWECompactCodec().encryptRSAOAEP256(payload: payload,
                                                                       recipientPublicKey: key.publicKey,
                                                                       kid: key.kid)
        return AuditLogEntry(id: id, version: "1", payload: encryptedPayload)
    }

    private func makeAuditLogRequest(_ entries: [AuditLogEntry]) throws -> HTTPRequestingMock {
        let body = try JSONSerialization.data(withJSONObject: ["audit_log": [
            "entries": entries.map { ["id": $0.id, "version": $0.version, "payload": $0.payload] },
            "after": "next-page"
        ]])
        return HTTPRequestingMock(result: .init(data: body, response: .init()))
    }
}

private struct RegisteredDeviceMappingTestDouble: RegisteredDeviceMapping {
    func registeredDevicesWithRepairState(from entries: [RegisteredDeviceEntry],
                                          account: SyncAccount,
                                          isUnifiedReadEnabled: Bool) async -> RegisteredDeviceMappingResult {
        let devices = entries.map { RegisteredDevice(id: $0.id, name: $0.name ?? "Unknown", type: $0.type ?? "unknown") }
        return RegisteredDeviceMappingResult(devices: devices, needsCurrentDeviceInfoRepair: false)
    }

    func registeredAuditLogDevices(from entries: [RegisteredDeviceEntry],
                                   account: SyncAccount,
                                   accountInfoKey: AccountInfoKey?,
                                   thirdPartyPasswordRecoveryCache: ThirdPartyPasswordRecoveryCache?) async throws -> RegisteredDeviceMappingResult {
        await registeredDevicesWithRepairState(from: entries, account: account, isUnifiedReadEnabled: true)
    }

    func registeredDevice(fromLegacyEntry entry: RegisteredDeviceEntry, account: SyncAccount) -> RegisteredDevice? { nil }

    func registeredDevice(fromDefaultCredentialLoginEntryWithID id: String,
                          encryptedName: String,
                          encryptedType: String?,
                          primaryKey: Data) -> RegisteredDevice? { nil }
}

private enum AuditLogRecoveryTestError: Error {
    case expected
}
