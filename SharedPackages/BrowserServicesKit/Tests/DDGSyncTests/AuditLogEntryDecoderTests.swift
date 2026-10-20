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
import XCTest

@testable import DDGSync

final class AuditLogEntryDecoderTests: XCTestCase {

    private let accountSecretKey = Data(repeating: 0x01, count: 32)
    private let account = SyncAccount(deviceId: "local-device",
                                      deviceName: "Local device",
                                      deviceType: "desktop",
                                      userId: "user",
                                      primaryKey: Data(repeating: 0x02, count: 32),
                                      secretKey: Data(repeating: 0x03, count: 32),
                                      token: "token",
                                      state: .active)

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
            return XCTFail("Expected a decoded logout event")
        }
        XCTAssertEqual(event.type, .logout)
        XCTAssertEqual(event.id, "audit-entry")
        XCTAssertEqual(event.device.id, "logged-out")
        XCTAssertEqual(event.device.name, "Unified Mac")
        XCTAssertEqual(event.device.type, "desktop")
        XCTAssertEqual(event.actor?.id, "actor")
        XCTAssertEqual(event.actor?.name, "Actor iPhone")
        XCTAssertEqual(event.actor?.type, "mobile")
        let expectedTimestamp = ISO8601DateFormatter()
        expectedTimestamp.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(event.occurredAt, expectedTimestamp.date(from: "2026-09-02T14:03:11.123Z"))
    }

    func testWhenEventTypeIsUnknownThenReturnsUnknownEvenIfSchemaHasChanged() async throws {
        let fixture = try makeFixture()
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data(#"{"type":"future_event"}"#.utf8)), for: account)

        guard case .unknownType(id: "audit-entry", type: "future_event") = result else {
            return XCTFail("Expected unknown event type to be preserved")
        }
    }

    func testWhenVersionIsUnsupportedThenDoesNotLoadKey() async throws {
        let fixture = try makeFixture()
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())
        let entry = AuditLogEntry(id: "audit-entry", version: "2", payload: "unused")

        let result = try await decoder.decode(entry, for: account)

        guard case .unsupportedVersion(id: "audit-entry", version: "2") = result else {
            return XCTFail("Expected unsupported version outcome")
        }
        XCTAssertTrue(fixture.keyManager.loadKeyCalls.isEmpty)
    }

    func testWhenKeyIsUnavailableThenReturnsUnreadableOutcome() async throws {
        let fixture = try makeFixture()
        fixture.keyManager.loadKeyError = AccountInfoKeyManagerError.missingProtectedKey
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)

        guard case .unreadable(id: "audit-entry", reason: .keyUnavailable) = result else {
            return XCTFail("Expected key unavailable outcome")
        }
    }

    func testWhenLoadingKeyIsCancelledThenPropagatesCancellation() async throws {
        let fixture = try makeFixture()
        fixture.keyManager.loadKeyError = CancellationError()
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        do {
            _ = try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)
            XCTFail("Expected cancellation to propagate")
        } catch is CancellationError {
            // Expected.
        }
    }

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
            return XCTFail("Expected refreshed key to decrypt the entry")
        }
        XCTAssertEqual(event.type, .login)
        XCTAssertEqual(fixture.keyManager.refreshKeyCalls.count, 1)
    }

    func testWhenRefreshedKeyStillHasWrongKidThenPreservesMismatchOutcome() async throws {
        let fixture = try makeFixture()
        let otherKey = try makeFixture()
        fixture.keyManager.loadKeyStub = otherKey.key
        fixture.keyManager.refreshKeyStub = otherKey.key
        let decoder = AuditLogEntryDecoder(accountInfoKeys: fixture.keyManager,
                                           deviceMapper: RegisteredDeviceMappingTestDouble())

        let result = try await decoder.decode(try fixture.entry(payload: Data("{}".utf8)), for: account)

        guard case .unreadable(id: "audit-entry", reason: .keyIDMismatch) = result else {
            return XCTFail("Expected key ID mismatch after refresh")
        }
    }

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
            return XCTFail("Expected decryption failure when refreshed key id matches but private key does not")
        }
    }

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
            return XCTFail("Expected decryption failure when the matching kid has the wrong private key")
        }
        XCTAssertTrue(fixture.keyManager.refreshKeyCalls.isEmpty)
    }

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
            return XCTFail("Expected unreadable device details to retain the audit event")
        }
        XCTAssertEqual(event.device.id, "lost-device")
        XCTAssertEqual(event.device.name, "Unknown")
        XCTAssertEqual(event.device.type, "unknown")
        XCTAssertEqual(event.device.credentialId, SyncCredentialID.defaultCredential)
    }

    func testAccountManagerDebugDecodeUsesEncryptedAuditEntryAndConfiguredDeviceMapper() async throws {
        let fixture = try makeFixture()
        let deviceInfoCodec = DeviceInfoCodec()
        let encryptedInfo = try deviceInfoCodec.encrypt(DeviceInfo(name: "Decoded Mac", type: "desktop"),
                                                        using: fixture.protectedKey)
        let mapper = RegisteredDeviceMapper(crypter: CryptingMock(),
                                            accountInfoKeys: fixture.keyManager,
                                            deviceInfoCodec: deviceInfoCodec,
                                            isScopedAccessCredentialsEnabled: { false },
                                            canReadUnifiedDeviceList: { true })
        let manager = AccountManager(endpoints: Endpoints(baseURL: URL(string: "https://dev.null")!),
                                     api: RemoteAPIRequestCreatingMock(),
                                     crypter: CryptingMock(),
                                     registeredDeviceMapper: mapper,
                                     accountInfoKeys: fixture.keyManager,
                                     isScopedAccessCredentialsEnabled: { false })
        let payload = Data(#"{"type":"login","occurred_at":"2026-09-02T14:03:11Z","device":{"id":"logged-in","info":"\#(encryptedInfo)"}}"#.utf8)

        let results = try await manager.decodeAuditLogEntriesForDebug([try fixture.entry(payload: payload)], for: account)

        guard case .decoded(let event) = try XCTUnwrap(results.first) else {
            return XCTFail("Expected production AccountManager decode path to decrypt the audit entry")
        }
        XCTAssertEqual(event.id, "audit-entry")
        XCTAssertEqual(event.device.name, "Decoded Mac")
        XCTAssertEqual(event.deviceMapping?.source, .deviceInfo)
    }

    func testAccountManagerDebugDecodeWithoutKeyManagerReturnsExplicitKeyUnavailable() async throws {
        let manager = AccountManager(endpoints: Endpoints(baseURL: URL(string: "https://dev.null")!),
                                     api: RemoteAPIRequestCreatingMock(),
                                     crypter: CryptingMock(),
                                     isScopedAccessCredentialsEnabled: { false })
        let entry = AuditLogEntry(id: "audit-entry", version: "1", payload: "encrypted-payload")

        let results = try await manager.decodeAuditLogEntriesForDebug([entry], for: account)

        guard case .unreadable(id: "audit-entry", reason: .keyUnavailable) = try XCTUnwrap(results.first) else {
            return XCTFail("Expected missing key manager to be reported as unreadable")
        }
    }

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
            return XCTFail("Expected malformed entry outcomes")
        }
    }

    private func makeFixture() throws -> Fixture {
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
        return Fixture(protectedKey: protectedKey, key: key, keyManager: keyManager)
    }

    private struct Fixture {
        let protectedKey: ProtectedKey
        let key: AccountInfoKey
        let keyManager: AccountInfoKeyManagingMock

        func entry(payload: Data) throws -> AuditLogEntry {
            let token = try JWECompactCodec().encryptRSAOAEP256(payload: payload,
                                                                recipientPublicKey: key.publicKey,
                                                                kid: key.kid)
            return AuditLogEntry(id: "audit-entry", version: "1", payload: token)
        }
    }
}

private struct RegisteredDeviceMappingTestDouble: RegisteredDeviceMapping {
    func registeredDevicesWithRepairState(from entries: [RegisteredDeviceEntry],
                                          account: SyncAccount,
                                          isUnifiedReadEnabled: Bool) async -> RegisteredDeviceMappingResult {
        let devices = entries.map { RegisteredDevice(id: $0.id, name: $0.name ?? "Unknown", type: $0.type ?? "unknown") }
        return RegisteredDeviceMappingResult(devices: devices, needsCurrentDeviceInfoRepair: false)
    }

    func registeredDevice(fromLegacyEntry entry: RegisteredDeviceEntry, account: SyncAccount) -> RegisteredDevice? { nil }

    func registeredDevice(fromDefaultCredentialLoginEntryWithID id: String,
                          encryptedName: String,
                          encryptedType: String?,
                          primaryKey: Data) -> RegisteredDevice? { nil }
}
