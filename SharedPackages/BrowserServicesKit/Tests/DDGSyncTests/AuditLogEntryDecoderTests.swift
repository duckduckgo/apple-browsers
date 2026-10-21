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
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager, deviceMapper: mapper)
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
    @Test("Unknown event types remain skippable with future schemas", .timeLimit(.minutes(1)))
    func testWhenEventTypeIsUnknownThenReturnsUnknownEvenIfSchemaHasChanged() async throws {
        let fixture = try makeFixture()
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data(#"{"type":"future_event"}"#.utf8)), for: account)

        guard case .unknownType(id: "audit-entry", type: "future_event") = result else {
            Issue.record("Expected unknown event type to be preserved")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unsupported versions do not load the account key", .timeLimit(.minutes(1)))
    func testWhenVersionIsUnsupportedThenDoesNotLoadKey() async throws {
        let fixture = try makeFixture()
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())
        let entry = AuditLogEntry(id: "audit-entry", version: "2", payload: "unused")

        let result = try await decoder.decode(entry, for: account)

        guard case .unsupportedVersion(id: "audit-entry", version: "2") = result else {
            Issue.record("Expected unsupported version outcome")
            return
        }
        #expect(fixture.keyManager.loadKeyCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Unavailable account keys produce an unreadable outcome", .timeLimit(.minutes(1)))
    func testWhenKeyIsUnavailableThenReturnsUnreadableOutcome() async throws {
        let fixture = try makeFixture()
        fixture.keyManager.loadKeyError = AccountInfoKeyManagerError.missingProtectedKey
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)

        guard case .unreadable(id: "audit-entry", reason: .keyUnavailable) = result else {
            Issue.record("Expected key unavailable outcome")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("Key loading cancellation propagates", .timeLimit(.minutes(1)))
    func testWhenLoadingKeyIsCancelledThenPropagatesCancellation() async throws {
        let fixture = try makeFixture()
        fixture.keyManager.loadKeyError = CancellationError()
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        await #expect(throws: CancellationError.self) {
            try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A stale key refreshes before decrypting", .timeLimit(.minutes(1)))
    func testWhenCachedKeyDoesNotMatchThenRefreshesAndDecrypts() async throws {
        let fixture = try makeFixture()
        let otherKey = try makeFixture()
        fixture.keyManager.loadKeyStub = otherKey.key
        fixture.keyManager.refreshKeyStub = fixture.key
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())
        let payload = Data(#"{"type":"login","occurred_at":"2026-09-02T14:03:11Z","device":{"id":"device"}}"#.utf8)

        let result = try await decoder.decode(try fixture.entry(payload: payload), for: account)

        guard case .decoded(let event) = result else {
            Issue.record("Expected refreshed key to decrypt the entry")
            return
        }
        #expect(event.type == .login)
        #expect(fixture.keyManager.refreshKeyCalls.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A refreshed key with the wrong ID remains a mismatch", .timeLimit(.minutes(1)))
    func testWhenRefreshedKeyStillHasWrongKidThenPreservesMismatchOutcome() async throws {
        let fixture = try makeFixture()
        let otherKey = try makeFixture()
        fixture.keyManager.loadKeyStub = otherKey.key
        fixture.keyManager.refreshKeyStub = otherKey.key
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)

        guard case .unreadable(id: "audit-entry", reason: .keyIDMismatch) = result else {
            Issue.record("Expected key ID mismatch after refresh")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A JWE without a key ID does not refresh keys", .timeLimit(.minutes(1)))
    func testWhenAuditLogJWEHasNoKeyIDThenDoesNotRefresh() async throws {
        let fixture = try makeFixture()
        let keyedToken = try fixture.entry(payload: Data("{}".utf8)).payload
        let components = keyedToken.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let header = Base64URL.encode(Data(#"{"alg":"RSA-OAEP-256","enc":"A256GCM"}"#.utf8))
        let tokenWithoutKeyID = ([header] + components.dropFirst()).joined(separator: ".")
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(AuditLogEntry(id: "no-kid", version: "1", payload: tokenWithoutKeyID), for: account)

        guard case .unreadable(id: "no-kid", reason: .missingKeyID) = result else {
            Issue.record("Expected missing key ID to remain explicitly unreadable")
            return
        }
        #expect(fixture.keyManager.loadKeyCalls.isEmpty)
        #expect(fixture.keyManager.refreshKeyCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Malformed JWE is rejected before checking key availability", .timeLimit(.minutes(1)))
    func testWhenAuditLogJWEIsMalformedThenRejectsBeforeCheckingKeyAvailability() async throws {
        let fixture = try makeFixture()
        fixture.keyManager.loadKeyError = AccountInfoKeyManagerError.missingProtectedKey
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(AuditLogEntry(id: "malformed", version: "1", payload: "not-a-jwe"), for: account)

        guard case .unreadable(id: "malformed", reason: .decryptionFailed) = result else {
            Issue.record("Expected malformed JWE to remain a decryption failure")
            return
        }
        #expect(fixture.keyManager.loadKeyCalls.isEmpty)
        #expect(fixture.keyManager.refreshKeyCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Malformed JWE is rejected without a key provider", .timeLimit(.minutes(1)))
    func testWhenAuditLogJWEIsMalformedWithoutKeyProviderThenReturnsDecryptionFailure() async throws {
        let decoder = AuditLogEntryDecoder(accountInfoKeys: nil,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(AuditLogEntry(id: "malformed", version: "1", payload: "not-a-jwe"), for: account)

        guard case .unreadable(id: "malformed", reason: .decryptionFailed) = result else {
            Issue.record("Expected malformed JWE to be identified before missing keys")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A matching refreshed key ID with the wrong key fails decryption", .timeLimit(.minutes(1)))
    func testWhenRefreshedKidMatchesButPrivateKeyIsWrongThenReportsDecryptionFailure() async throws {
        let fixture = try makeFixture()
        let otherKey = try makeFixture()
        fixture.keyManager.loadKeyStub = otherKey.key
        fixture.keyManager.refreshKeyStub = AccountInfoKey(kid: fixture.key.kid,
                                                           publicKey: otherKey.key.publicKey,
                                                           privateKey: otherKey.key.privateKey)
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)

        guard case .unreadable(id: "audit-entry", reason: .decryptionFailed) = result else {
            Issue.record("Expected decryption failure when refreshed key id matches but private key does not")
            return
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test("A matching key ID with the wrong private key fails decryption", .timeLimit(.minutes(1)))
    func testWhenJWEKidMatchesButPrivateKeyIsWrongThenReportsDecryptionFailure() async throws {
        let fixture = try makeFixture()
        let otherKey = try makeFixture()
        fixture.keyManager.loadKeyStub = AccountInfoKey(kid: fixture.key.kid,
                                                        publicKey: fixture.key.publicKey,
                                                        privateKey: otherKey.key.privateKey)
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)

        guard case .unreadable(id: "audit-entry", reason: .decryptionFailed) = result else {
            Issue.record("Expected decryption failure when the matching kid has the wrong private key")
            return
        }
        #expect(fixture.keyManager.refreshKeyCalls.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Snapshots without readable fields use the device-list placeholder", .timeLimit(.minutes(1)))
    func testWhenSnapshotHasNoReadableFieldsThenUsesDeviceListPlaceholder() async throws {
        let fixture = try makeFixture()
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: fixture.keyManager,
                                            isScopedAccessCredentialsEnabled: { false },
                                            canReadUnifiedDeviceList: { true })
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager, deviceMapper: mapper)
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
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
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

    private func makeFixture() throws -> AuditLogTestFixture {
        try AuditLogTestFixture.make(accountSecretKey: accountSecretKey)
    }
}

private struct RegisteredDeviceMappingTestDouble: RegisteredDeviceMapping {
    func registeredDevicesWithRepairState(from entries: [RegisteredDeviceEntry],
                                          account: SyncAccount,
                                          isUnifiedReadEnabled: Bool,
                                          accountInfoKeyProvider: (any AccountInfoKeyProviding)?) async -> RegisteredDeviceMappingResult {
        let devices = entries.map { RegisteredDevice(id: $0.id, name: $0.name ?? "Unknown", type: $0.type ?? "unknown") }
        return RegisteredDeviceMappingResult(devices: devices, needsCurrentDeviceInfoRepair: false)
    }

    func registeredDevice(fromLegacyEntry entry: RegisteredDeviceEntry, account: SyncAccount) -> RegisteredDevice? { nil }

    func registeredDevice(fromDefaultCredentialLoginEntryWithID id: String,
                          encryptedName: String,
                          encryptedType: String?,
                          primaryKey: Data) -> RegisteredDevice? { nil }
}
