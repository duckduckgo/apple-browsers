//
//  AuditLogEntryDecoder.swift
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
import DDGError

/// Retains every key loaded for the page so refreshing for a newer entry does not discard
/// a key needed by an older entry.
/// The initial load result and one forced refresh are also shared across the page.
/// The fetch loop uses this instance sequentially; it is intentionally not Sendable.
final class PageScopedAccountInfoKeys: AccountInfoKeyProviding {
    enum RefreshLimitError: DDGError {
        case forcedRefreshAlreadyAttempted

        static var errorDomain: String { "com.duckduckgo.sync.audit-log.account-info-keys" }

        var errorCode: Int { 1 }

        var description: String { "The account-info key refresh was already attempted for this audit-log page." }
    }

    private let manager: any AccountInfoKeyProviding
    private var currentKeyResult: Result<AccountInfoKey, Swift.Error>?
    private var didAttemptForcedRefresh = false
    private var keysByID: [String: AccountInfoKey] = [:]

    init(manager: any AccountInfoKeyProviding) {
        self.manager = manager
    }

    func loadKey(for account: SyncAccount) async throws -> AccountInfoKey {
        if let currentKeyResult {
            return try currentKeyResult.get()
        }
        do {
            let key = try await manager.loadKey(for: account)
            cache(key)
            return key
        } catch {
            currentKeyResult = .failure(error)
            throw error
        }
    }

    func refreshKey(for account: SyncAccount) async throws -> AccountInfoKey {
        guard !didAttemptForcedRefresh else {
            throw RefreshLimitError.forcedRefreshAlreadyAttempted
        }
        didAttemptForcedRefresh = true
        let key = try await manager.refreshKey(for: account)
        cache(key)
        return key
    }

    func cachedKey(matching keyID: String) -> AccountInfoKey? {
        keysByID[keyID]
    }

    private func cache(_ key: AccountInfoKey) {
        keysByID[key.kid] = key
        currentKeyResult = .success(key)
    }
}

enum AuditLogEventType: String {
    case login
    case logout
}

struct AuditLogEvent {
    let id: String
    let type: AuditLogEventType
    let occurredAt: Date
    let device: RegisteredDevice
    let actor: RegisteredDevice?
}

enum AuditLogUnreadableReason {
    case keyUnavailable
    case keyIDMismatch
    case missingKeyID
    case decryptionFailed
    case invalidPayload
}

enum AuditLogEntryDecodingResult {
    case decoded(AuditLogEvent)
    case unsupportedVersion(id: String, version: String)
    case unknownType(id: String, type: String)
    case unreadable(id: String, reason: AuditLogUnreadableReason)
}

struct AuditLogEntryDecoder {

    private enum PayloadDecryptionResult {
        case decrypted(Data)
        case unreadable(AuditLogUnreadableReason)
    }

    private enum PayloadInterpretation {
        case known(AuditLogEventType, Payload, Date)
        case unknownType(String)
        case invalid
    }

    private struct TypeProbe: Decodable {
        let type: String
    }

    private struct Payload: Decodable {
        let occurredAt: String
        let device: RegisteredDeviceEntry
        let actor: RegisteredDeviceEntry?
    }

    private let accountInfoKeys: (any AccountInfoKeyProviding)?
    private let deviceMapper: any RegisteredDeviceMapping
    private let thirdPartyPasswordRecoveryCache: ThirdPartyPasswordRecoveryCache?
    private let jweCompactCodec: JWECompactCodec

    init(accountInfoKeys: (any AccountInfoKeyProviding)?,
         deviceMapper: any RegisteredDeviceMapping,
         thirdPartyPasswordRecoveryCache: ThirdPartyPasswordRecoveryCache? = nil,
         jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.accountInfoKeys = accountInfoKeys
        self.deviceMapper = deviceMapper
        self.thirdPartyPasswordRecoveryCache = thirdPartyPasswordRecoveryCache
        self.jweCompactCodec = jweCompactCodec
    }

    func decode(_ entry: AuditLogEntry, for account: SyncAccount) async throws -> AuditLogEntryDecodingResult {
        guard entry.version == "1" else {
            return .unsupportedVersion(id: entry.id, version: entry.version)
        }

        let payloadData: Data
        switch try await decryptPayload(for: entry, account: account) {
        case .decrypted(let data): payloadData = data
        case .unreadable(let reason): return .unreadable(id: entry.id, reason: reason)
        }
        let type: AuditLogEventType
        let payload: Payload
        let occurredAt: Date
        switch interpret(payloadData) {
        case .known(let eventType, let decodedPayload, let timestamp):
            type = eventType
            payload = decodedPayload
            occurredAt = timestamp
        case .unknownType(let rawType): return .unknownType(id: entry.id, type: rawType)
        case .invalid: return .unreadable(id: entry.id, reason: .invalidPayload)
        }

        let snapshots = [payload.device] + (payload.actor.map { [$0] } ?? [])
        try Task.checkCancellation()
        // Audit-log snapshots describe historical events and use the unified payload schema regardless of the current device-list flag.
        let mapping = await deviceMapper.registeredDevicesWithRepairState(from: snapshots,
                                                                           account: account,
                                                                           isUnifiedReadEnabled: true,
                                                                           accountInfoKeyProvider: accountInfoKeys,
                                                                           thirdPartyPasswordRecoveryCache: thirdPartyPasswordRecoveryCache)
        try Task.checkCancellation()
        guard let device = mapping.devices.first else {
            return .unreadable(id: entry.id, reason: .invalidPayload)
        }
        let actor = payload.actor == nil ? nil : mapping.devices.dropFirst().first
        guard payload.actor == nil || actor != nil else {
            return .unreadable(id: entry.id, reason: .invalidPayload)
        }
        return .decoded(AuditLogEvent(id: entry.id,
                                      type: type,
                                      occurredAt: occurredAt,
                                      device: device,
                                      actor: actor))
    }

    private func decryptPayload(for entry: AuditLogEntry, account: SyncAccount) async throws -> PayloadDecryptionResult {
        let keyID: String
        do {
            guard let protectedKeyID = try jweCompactCodec.protectedKeyID(in: entry.payload) else {
                return .unreadable(.missingKeyID)
            }
            keyID = protectedKeyID
        } catch {
            return .unreadable(.decryptionFailed)
        }
        guard let accountInfoKeys else {
            return .unreadable(.keyUnavailable)
        }
        let loadedKey: AccountInfoKey
        do {
            loadedKey = try await accountInfoKeys.loadKey(for: account)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unreadable(.keyUnavailable)
        }
        let key = accountInfoKeys.cachedKey(matching: keyID) ?? loadedKey
        do {
            let data = try jweCompactCodec.decryptRSAOAEP256(token: entry.payload,
                                                            privateKey: key.privateKey,
                                                            expectedKid: key.kid)
            return .decrypted(data)
        } catch JWECompactCodecError.unexpectedKeyID {
            return try await decryptPayloadAfterKeyRefresh(for: entry, account: account, accountInfoKeys: accountInfoKeys)
        } catch {
            return .unreadable(.decryptionFailed)
        }
    }

    private func decryptPayloadAfterKeyRefresh(for entry: AuditLogEntry,
                                               account: SyncAccount,
                                               accountInfoKeys: any AccountInfoKeyProviding) async throws -> PayloadDecryptionResult {
        let refreshedKey: AccountInfoKey
        do {
            refreshedKey = try await accountInfoKeys.refreshKey(for: account)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unreadable(.keyIDMismatch)
        }
        do {
            let data = try jweCompactCodec.decryptRSAOAEP256(token: entry.payload,
                                                            privateKey: refreshedKey.privateKey,
                                                            expectedKid: refreshedKey.kid)
            return .decrypted(data)
        } catch JWECompactCodecError.unexpectedKeyID {
            return .unreadable(.keyIDMismatch)
        } catch {
            return .unreadable(.decryptionFailed)
        }
    }

    private func interpret(_ payloadData: Data) -> PayloadInterpretation {
        // Read type first so unknown event types can be skipped without decoding the rest of the payload.
        guard let typeProbe = try? JSONDecoder.snakeCaseKeys.decode(TypeProbe.self, from: payloadData) else {
            return .invalid
        }
        guard let type = AuditLogEventType(rawValue: typeProbe.type) else {
            return .unknownType(typeProbe.type)
        }
        guard let payload = try? JSONDecoder.snakeCaseKeys.decode(Payload.self, from: payloadData),
              let occurredAt = Self.parseTimestamp(payload.occurredAt) else {
            return .invalid
        }
        return .known(type, payload, occurredAt)
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
