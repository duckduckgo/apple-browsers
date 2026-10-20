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

enum AuditLogEventType: String, Equatable {
    case login
    case logout
}

struct AuditLogEvent {
    let id: String
    let type: AuditLogEventType
    let occurredAt: Date
    let device: RegisteredDevice
    let actor: RegisteredDevice?
    let deviceMapping: RegisteredDeviceDebugInfo?
    let actorMapping: RegisteredDeviceDebugInfo?
}

enum AuditLogUnreadableReason {
    case keyUnavailable
    case keyIDMismatch
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

    private let accountInfoKeys: (any AccountInfoKeyManaging)?
    private let deviceMapper: any RegisteredDeviceMapping
    private let jweCompactCodec: JWECompactCodec

    init(accountInfoKeys: (any AccountInfoKeyManaging)?,
         deviceMapper: any RegisteredDeviceMapping,
         jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.accountInfoKeys = accountInfoKeys
        self.deviceMapper = deviceMapper
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
        let mapping = await deviceMapper.registeredDevicesWithRepairState(from: snapshots,
                                                                           account: account,
                                                                           isUnifiedReadEnabled: true)
        try Task.checkCancellation()
        guard let device = mapping.devices.first else {
            return .unreadable(id: entry.id, reason: .invalidPayload)
        }
        let actor = payload.actor == nil ? nil : mapping.devices.dropFirst().first
        guard payload.actor == nil || actor != nil else {
            return .unreadable(id: entry.id, reason: .invalidPayload)
        }
        let actorMapping = payload.actor == nil ? nil : mapping.debugDevices.dropFirst().first

        return .decoded(AuditLogEvent(id: entry.id,
                                      type: type,
                                      occurredAt: occurredAt,
                                      device: device,
                                      actor: actor,
                                      deviceMapping: mapping.debugDevices.first,
                                      actorMapping: actorMapping))
    }

    private func decryptPayload(for entry: AuditLogEntry, account: SyncAccount) async throws -> PayloadDecryptionResult {
        guard let accountInfoKeys else {
            return .unreadable(.keyUnavailable)
        }
        let key: AccountInfoKey
        do {
            key = try await accountInfoKeys.loadKey(for: account)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .unreadable(.keyUnavailable)
        }
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
                                               accountInfoKeys: any AccountInfoKeyManaging) async throws -> PayloadDecryptionResult {
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
