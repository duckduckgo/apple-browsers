//
//  RegisteredDeviceMapper.swift
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
import os.log

struct RegisteredDeviceMappingResult {
    let devices: [RegisteredDevice]
    let needsCurrentDeviceInfoRepair: Bool
    let unresolvedNativeDeviceIDs: [String]
    // Diagnostics for the Sync debug UI only; not used to drive device-list behaviour.
    let debugDevices: [RegisteredDeviceDebugInfo]

    init(devices: [RegisteredDevice],
         needsCurrentDeviceInfoRepair: Bool,
         unresolvedNativeDeviceIDs: [String] = [],
         debugDevices: [RegisteredDeviceDebugInfo] = []) {
        self.devices = devices
        self.needsCurrentDeviceInfoRepair = needsCurrentDeviceInfoRepair
        self.unresolvedNativeDeviceIDs = unresolvedNativeDeviceIDs
        self.debugDevices = debugDevices
    }
}

protocol RegisteredDeviceMapping {
    func registeredDevicesWithRepairState(from entries: [RegisteredDeviceEntry],
                                          account: SyncAccount,
                                          isUnifiedReadEnabled: Bool) async -> RegisteredDeviceMappingResult
    func registeredDevice(fromLegacyEntry entry: RegisteredDeviceEntry, account: SyncAccount) -> RegisteredDevice?
    func registeredDevice(fromDefaultCredentialLoginEntryWithID id: String,
                          encryptedName: String,
                          encryptedType: String?,
                          primaryKey: Data) -> RegisteredDevice?
}

extension RegisteredDeviceMapping {
    func registeredDevices(from entries: [RegisteredDeviceEntry],
                           account: SyncAccount,
                           isUnifiedReadEnabled: Bool) async -> [RegisteredDevice] {
        await registeredDevicesWithRepairState(from: entries,
                                               account: account,
                                               isUnifiedReadEnabled: isUnifiedReadEnabled).devices
    }
}

/// Maps raw Sync device payloads into app-facing devices without hiding entries that cannot be decrypted locally.
struct RegisteredDeviceMapper: RegisteredDeviceMapping {

    private static let undecryptableThirdPartyDeviceName = "Browser"
    private static let undecryptableDeviceName = "Unknown"
    private static let undecryptableDeviceType = "unknown"

    private enum UnifiedDeviceInfoFailure: Equatable {
        case missing
        case keyUnavailable
        case staleKey
        case corrupt

        var description: String {
            switch self {
            case .missing: return "Missing device_info"
            case .keyUnavailable: return "account_info key unavailable"
            case .staleKey: return "device_info uses a different account_info key"
            case .corrupt: return "Unable to decrypt device_info"
            }
        }
    }

    private enum UnifiedDeviceInfoReadResult {
        case notAttempted
        case decrypted(DeviceInfo)
        case failed(UnifiedDeviceInfoFailure)
    }

    private enum MappingSource: Equatable {
        case deviceInfo
        case legacy
        case placeholder

        var debugSource: RegisteredDeviceDebugInfo.Source {
            switch self {
            case .deviceInfo: return .deviceInfo
            case .legacy: return .legacy
            case .placeholder: return .placeholder
            }
        }
    }

    private struct MappingAttempt {
        let device: RegisteredDevice
        let source: MappingSource
        let unifiedDeviceInfoFailure: UnifiedDeviceInfoFailure?
    }

    let crypter: CryptingInternal
    let scopedAccess: ScopedAccessCredentialManaging?
    let accountInfoKeys: AccountInfoKeyManaging?
    let deviceInfoCodec: DeviceInfoCoding
    let cachedScopedPassword: () throws -> Data?
    let isScopedAccessCredentialsEnabled: () -> Bool
    let canReadUnifiedDeviceList: () -> Bool
    private let jweCompactCodec: JWECompactCodec

    init(crypter: CryptingInternal,
         scopedAccess: ScopedAccessCredentialManaging? = nil,
         accountInfoKeys: AccountInfoKeyManaging? = nil,
         deviceInfoCodec: DeviceInfoCoding = DeviceInfoCodec(),
         cachedScopedPassword: @escaping () throws -> Data? = { nil },
         isScopedAccessCredentialsEnabled: @escaping () -> Bool,
         canReadUnifiedDeviceList: @escaping () -> Bool = { false },
         jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.crypter = crypter
        self.scopedAccess = scopedAccess
        self.accountInfoKeys = accountInfoKeys
        self.deviceInfoCodec = deviceInfoCodec
        self.cachedScopedPassword = cachedScopedPassword
        self.isScopedAccessCredentialsEnabled = isScopedAccessCredentialsEnabled
        self.canReadUnifiedDeviceList = canReadUnifiedDeviceList
        self.jweCompactCodec = jweCompactCodec
    }

    func registeredDevicesWithRepairState(from entries: [RegisteredDeviceEntry],
                                          account: SyncAccount) async -> RegisteredDeviceMappingResult {
        await registeredDevicesWithRepairState(from: entries,
                                               account: account,
                                               isUnifiedReadEnabled: canReadUnifiedDeviceList())
    }

    func registeredDevices(from entries: [RegisteredDeviceEntry], account: SyncAccount) async -> [RegisteredDevice] {
        await registeredDevicesWithRepairState(from: entries, account: account).devices
    }

    func registeredDevicesWithRepairState(from entries: [RegisteredDeviceEntry],
                                          account: SyncAccount,
                                          isUnifiedReadEnabled: Bool) async -> RegisteredDeviceMappingResult {
        let accountInfoKey = await accountInfoKeyIfNeeded(for: entries,
                                                          account: account,
                                                          isUnifiedReadEnabled: isUnifiedReadEnabled)
        let initialMappings = entries.map {
            registeredDevice(from: $0,
                             account: account,
                             accountInfoKey: accountInfoKey,
                             thirdPartyMainKey: nil,
                             isUnifiedReadEnabled: isUnifiedReadEnabled)
        }
        let finalMappings: [MappingAttempt]
        if initialMappings.contains(where: { $0.unifiedDeviceInfoFailure == .staleKey }),
           let accountInfoKeys,
           let refreshedAccountInfoKey = try? await accountInfoKeys.refreshKey(for: account) {
            finalMappings = entries.map {
                registeredDevice(from: $0,
                                 account: account,
                                 accountInfoKey: refreshedAccountInfoKey,
                                 thirdPartyMainKey: nil,
                                 isUnifiedReadEnabled: isUnifiedReadEnabled)
            }
        } else {
            finalMappings = initialMappings
        }
        let resolvedMappings = await mappingsApplyingThirdPartyFallback(to: finalMappings,
                                                                        entries: entries,
                                                                        account: account)
        return RegisteredDeviceMappingResult(
            devices: resolvedMappings.map(\.device),
            needsCurrentDeviceInfoRepair: needsCurrentDeviceInfoRepair(in: resolvedMappings,
                                                                       entries: entries,
                                                                       account: account),
            unresolvedNativeDeviceIDs: zip(entries, resolvedMappings).compactMap { entry, mapping in
                guard entry.credentialId == nil || entry.credentialId == SyncCredentialID.defaultCredential,
                      mapping.source == .placeholder else {
                    return nil
                }
                return entry.id
            },
            debugDevices: resolvedMappings.map {
                RegisteredDeviceDebugInfo(device: $0.device,
                                          source: $0.source.debugSource,
                                          deviceInfoIssue: $0.unifiedDeviceInfoFailure?.description)
            })
    }

    func registeredDevice(fromLegacyEntry entry: RegisteredDeviceEntry, account: SyncAccount) -> RegisteredDevice? {
        decryptedDefaultCredentialRegisteredDevice(id: entry.id,
                                                   encryptedName: entry.name,
                                                   encryptedType: entry.type,
                                                   primaryKey: account.primaryKey,
                                                   credentialId: SyncCredentialID.defaultCredential)
    }

    func registeredDevice(fromDefaultCredentialLoginEntryWithID id: String,
                          encryptedName: String,
                          encryptedType: String?,
                          primaryKey: Data) -> RegisteredDevice? {
        guard let encryptedType else {
            return nil
        }

        return decryptedDefaultCredentialRegisteredDevice(id: id,
                                                         encryptedName: encryptedName,
                                                         encryptedType: encryptedType,
                                                         primaryKey: primaryKey,
                                                         credentialId: SyncCredentialID.defaultCredential)
    }

    private func registeredDevice(from entry: RegisteredDeviceEntry,
                                  account: SyncAccount,
                                  accountInfoKey: AccountInfoKey?,
                                  thirdPartyMainKey: Data?,
                                  isUnifiedReadEnabled: Bool) -> MappingAttempt {
        let unifiedDeviceInfo = readUnifiedDeviceInfo(from: entry,
                                                      accountInfoKey: accountInfoKey,
                                                      isUnifiedReadEnabled: isUnifiedReadEnabled)
        if case .decrypted(let deviceInfo) = unifiedDeviceInfo {
            return MappingAttempt(
                device: RegisteredDevice(id: entry.id,
                                         name: deviceInfo.name,
                                         type: deviceInfo.type,
                                         credentialId: entry.credentialId ?? SyncCredentialID.defaultCredential),
                source: .deviceInfo,
                unifiedDeviceInfoFailure: nil)
        }

        // Keep every server entry visible even if one encrypted field is malformed or uses a key we cannot recover.
        let legacyDevice = decryptedLegacyRegisteredDevice(from: entry, account: account, thirdPartyMainKey: thirdPartyMainKey)
        let device = legacyDevice ?? fallbackRegisteredDevice(from: entry)
        let failure: UnifiedDeviceInfoFailure?
        if case .failed(let unifiedDeviceInfoFailure) = unifiedDeviceInfo {
            failure = unifiedDeviceInfoFailure
        } else {
            failure = nil
        }
        return MappingAttempt(device: device,
                              source: legacyDevice == nil ? .placeholder : .legacy,
                              unifiedDeviceInfoFailure: failure)
    }

    private func mappingsApplyingThirdPartyFallback(to mappings: [MappingAttempt],
                                                    entries: [RegisteredDeviceEntry],
                                                    account: SyncAccount) async -> [MappingAttempt] {
        let fallbackEntryIndices = entries.indices.filter {
            entries[$0].credentialId == SyncCredentialID.thirdParty
                && mappings[$0].source != .deviceInfo
        }
        let fallbackEntries = fallbackEntryIndices.map { entries[$0] }
        guard !fallbackEntries.isEmpty,
              let thirdPartyMainKey = await thirdPartyMainKeyIfNeeded(for: fallbackEntries, account: account) else {
            return mappings
        }

        var mappings = mappings
        for index in fallbackEntryIndices {
            let entry = entries[index]
            guard let device = decryptedThirdPartyRegisteredDevice(from: entry, thirdPartyMainKey: thirdPartyMainKey) else {
                continue
            }
            mappings[index] = MappingAttempt(device: device,
                                             source: .legacy,
                                             unifiedDeviceInfoFailure: mappings[index].unifiedDeviceInfoFailure)
        }
        return mappings
    }

    private func needsCurrentDeviceInfoRepair(in mappings: [MappingAttempt],
                                              entries: [RegisteredDeviceEntry],
                                              account: SyncAccount) -> Bool {
        zip(entries, mappings).contains { entry, mapping in
            guard entry.id == account.deviceId else {
                return false
            }
            guard let failure = mapping.unifiedDeviceInfoFailure else {
                return false
            }
            switch failure {
            case .missing, .staleKey, .corrupt:
                return true
            case .keyUnavailable:
                return false
            }
        }
    }

    private func readUnifiedDeviceInfo(from entry: RegisteredDeviceEntry,
                                       accountInfoKey: AccountInfoKey?,
                                       isUnifiedReadEnabled: Bool) -> UnifiedDeviceInfoReadResult {
        guard isUnifiedReadEnabled else {
            return .notAttempted
        }
        guard let encryptedDeviceInfo = entry.info else {
            return .failed(.missing)
        }
        guard let accountInfoKey else {
            return .failed(.keyUnavailable)
        }
        do {
            return .decrypted(try deviceInfoCodec.decrypt(encryptedDeviceInfo, using: accountInfoKey))
        } catch DeviceInfoCodecError.unexpectedKeyID {
            return .failed(.staleKey)
        } catch {
            return .failed(.corrupt)
        }
    }

    private func decryptedLegacyRegisteredDevice(from entry: RegisteredDeviceEntry,
                                                 account: SyncAccount,
                                                 thirdPartyMainKey: Data?) -> RegisteredDevice? {
        switch entry.credentialId {
        case SyncCredentialID.thirdParty:
            return decryptedThirdPartyRegisteredDevice(from: entry, thirdPartyMainKey: thirdPartyMainKey)
        case SyncCredentialID.defaultCredential, nil:
            // A nil credentialId is a legacy native entry; treat it as the default (ddg) credential.
            return decryptedDefaultCredentialRegisteredDevice(id: entry.id,
                                                             encryptedName: entry.name,
                                                             encryptedType: entry.type,
                                                             primaryKey: account.primaryKey,
                                                             credentialId: SyncCredentialID.defaultCredential)
        default:
            // Unknown credential kind (e.g. a future type): fall back rather than guess at decryption.
            return nil
        }
    }

    private func decryptedDefaultCredentialRegisteredDevice(id: String,
                                                            encryptedName: String?,
                                                            encryptedType: String?,
                                                            primaryKey: Data,
                                                            credentialId: String?) -> RegisteredDevice? {
        guard let encryptedName,
              let encryptedType,
              let name = try? crypter.base64DecodeAndDecrypt(encryptedName, using: primaryKey),
              let type = try? crypter.base64DecodeAndDecrypt(encryptedType, using: primaryKey) else {
            return nil
        }

        return RegisteredDevice(id: id, name: name, type: type, credentialId: credentialId)
    }

    private func decryptedThirdPartyRegisteredDevice(from entry: RegisteredDeviceEntry, thirdPartyMainKey: Data?) -> RegisteredDevice? {
        guard let thirdPartyMainKey,
              let name = decryptThirdPartyDeviceField(entry.name, using: thirdPartyMainKey),
              let type = decryptThirdPartyDeviceField(entry.type, using: thirdPartyMainKey) else {
            return nil
        }

        return RegisteredDevice(id: entry.id, name: name, type: type, credentialId: entry.credentialId)
    }

    private func decryptThirdPartyDeviceField(_ value: String?, using thirdPartyMainKey: Data) -> String? {
        guard let value,
              let plaintext = try? jweCompactCodec.decryptDirect(token: value, contentEncryptionKey: thirdPartyMainKey) else {
            return nil
        }

        // 3party device fields are direct JWE plaintext strings, not base64-wrapped values.
        return String(data: plaintext, encoding: .utf8)
    }

    private func accountInfoKeyIfNeeded(for entries: [RegisteredDeviceEntry],
                                        account: SyncAccount,
                                        isUnifiedReadEnabled: Bool) async -> AccountInfoKey? {
        guard isUnifiedReadEnabled,
              entries.contains(where: { $0.info != nil }),
              let accountInfoKeys else {
            return nil
        }
        return try? await accountInfoKeys.loadKey(for: account)
    }

    private func thirdPartyMainKeyIfNeeded(for entries: [RegisteredDeviceEntry], account: SyncAccount) async -> Data? {
        guard entries.contains(where: { $0.credentialId == SyncCredentialID.thirdParty }) else {
            return nil
        }
        guard isScopedAccessCredentialsEnabled() else {
            return nil
        }

        if let cachedMainKey = cachedThirdPartyMainKey(for: entries, account: account) {
            return cachedMainKey
        }

        return await recoveredScopedPassword(for: account)
            .map { ScopedAccessKeyDerivation.mainKey(from: $0, userID: account.userId) }
    }

    private func cachedThirdPartyMainKey(for entries: [RegisteredDeviceEntry], account: SyncAccount) -> Data? {
        guard let scopedPassword = try? cachedScopedPassword(), !scopedPassword.isEmpty else {
            return nil
        }

        let mainKey = ScopedAccessKeyDerivation.mainKey(from: scopedPassword, userID: account.userId)
        let thirdPartyEntries = entries.filter { $0.credentialId == SyncCredentialID.thirdParty }
        // A cached scoped password is only trusted if it can decrypt the 3party fields in this response.
        guard thirdPartyEntries.allSatisfy({ canDecryptThirdPartyDeviceEntry($0, using: mainKey) }) else {
            return nil
        }

        return mainKey
    }

    private func canDecryptThirdPartyDeviceEntry(_ entry: RegisteredDeviceEntry, using thirdPartyMainKey: Data) -> Bool {
        // Probe with `type` only: a decryptable type is the signal that this 3party key matches the entry.
        decryptThirdPartyDeviceField(entry.type, using: thirdPartyMainKey) != nil
    }

    private func recoveredScopedPassword(for account: SyncAccount) async -> Data? {
        guard let scopedAccess else {
            return nil
        }

        do {
            let accessCredentials = try await scopedAccess.fetchAccessCredentials(account)
            guard let scopedPassword = try scopedAccess.recoverScopedPassword(from: accessCredentials,
                                                                              primaryKey: account.primaryKey,
                                                                              userID: account.userId) else {
                return nil
            }
            return scopedPassword
        } catch {
            Logger.sync.debug("Unable to recover 3party scoped password for device list: \(String(reflecting: error))")
            return nil
        }
    }

    private func fallbackRegisteredDevice(from entry: RegisteredDeviceEntry) -> RegisteredDevice {
        let credentialId = entry.credentialId ?? SyncCredentialID.defaultCredential
        // Preserve undecryptable entries so a bad encrypted field cannot hide a device from the list.
        let name = credentialId == SyncCredentialID.thirdParty
            ? Self.undecryptableThirdPartyDeviceName
            : Self.undecryptableDeviceName
        return RegisteredDevice(id: entry.id,
                                name: name,
                                type: Self.undecryptableDeviceType,
                                credentialId: credentialId)
    }

}

struct RegisteredDeviceEntry: Decodable {
    let id: String
    let name: String?
    let type: String?
    let info: String?
    let credentialId: String?
}
