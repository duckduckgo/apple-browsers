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

enum AuditLogEventType: String, Sendable {
    case login
    case logout
    case deviceInfoAdded = "device_info_added"
}

struct AuditLogEvent: Sendable {
    let id: String
    let type: AuditLogEventType
    let occurredAt: Date
    let device: RegisteredDevice
    let actor: RegisteredDevice?
    let hasDeviceInfo: Bool
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

    private let accountInfoKey: AccountInfoKey?
    private let deviceMapper: any RegisteredDeviceMapping
    private let thirdPartyPasswordRecoveryCache: ThirdPartyPasswordRecoveryCache?
    private let jweCompactCodec: JWECompactCodec
    private let timestampFormatter = ISO8601DateFormatter()
    private let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(accountInfoKey: AccountInfoKey?,
         deviceMapper: any RegisteredDeviceMapping,
         thirdPartyPasswordRecoveryCache: ThirdPartyPasswordRecoveryCache? = nil,
         jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.accountInfoKey = accountInfoKey
        self.deviceMapper = deviceMapper
        self.thirdPartyPasswordRecoveryCache = thirdPartyPasswordRecoveryCache
        self.jweCompactCodec = jweCompactCodec
    }

    func decode(_ entry: AuditLogEntry, for account: SyncAccount) async throws -> AuditLogEntryDecodingResult {
        guard entry.version == AuditLogEntry.supportedVersion else {
            return .unsupportedVersion(id: entry.id, version: entry.version)
        }

        let payloadData: Data
        switch decryptPayload(for: entry) {
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
                                                                           accountInfoKey: accountInfoKey,
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
                                      actor: actor,
                                      hasDeviceInfo: mapping.deviceInfoDeviceIDs.contains(device.id)))
    }

    private func decryptPayload(for entry: AuditLogEntry) -> PayloadDecryptionResult {
        do {
            guard try jweCompactCodec.protectedKeyID(in: entry.payload) != nil else {
                return .unreadable(.missingKeyID)
            }
        } catch {
            return .unreadable(.decryptionFailed)
        }
        guard let key = accountInfoKey else {
            return .unreadable(.keyUnavailable)
        }
        do {
            let data = try jweCompactCodec.decryptRSAOAEP256(token: entry.payload,
                                                            privateKey: key.privateKey,
                                                            expectedKid: key.kid)
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
              let occurredAt = parseTimestamp(payload.occurredAt) else {
            return .invalid
        }
        return .known(type, payload, occurredAt)
    }

    private func parseTimestamp(_ value: String) -> Date? {
        fractionalTimestampFormatter.date(from: value) ?? timestampFormatter.date(from: value)
    }
}
