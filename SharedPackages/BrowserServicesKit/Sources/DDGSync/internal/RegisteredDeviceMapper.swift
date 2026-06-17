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

protocol RegisteredDeviceMapping {
    func registeredDevices(from entries: [RegisteredDeviceEntry], account: SyncAccount) async -> [RegisteredDevice]
    func registeredDevice(fromLegacyEntry entry: RegisteredDeviceEntry, account: SyncAccount) -> RegisteredDevice?
    func registeredDevice(fromDefaultCredentialLoginEntryWithID id: String,
                          encryptedName: String,
                          encryptedType: String?,
                          primaryKey: Data) -> RegisteredDevice?
    func registeredDevice(fromThirdPartyLoginEntryWithID id: String, encodedName: String, encodedType: String?) -> RegisteredDevice
}

/// Maps raw Sync device payloads into app-facing devices without hiding entries that cannot be decrypted locally.
struct RegisteredDeviceMapper: RegisteredDeviceMapping {

    private static let undecryptableThirdPartyDeviceName = "Browser"
    private static let undecryptableDeviceName = "Unknown"
    private static let undecryptableDeviceType = "unknown"

    let crypter: CryptingInternal
    let scopedAccess: ScopedAccessCredentialManaging?
    let cachedScopedPassword: () throws -> Data?
    let isScopedAccessCredentialsEnabled: () -> Bool
    private let jweCompactCodec: JWECompactCodec

    init(crypter: CryptingInternal,
         scopedAccess: ScopedAccessCredentialManaging? = nil,
         cachedScopedPassword: @escaping () throws -> Data? = { nil },
         isScopedAccessCredentialsEnabled: @escaping () -> Bool,
         jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.crypter = crypter
        self.scopedAccess = scopedAccess
        self.cachedScopedPassword = cachedScopedPassword
        self.isScopedAccessCredentialsEnabled = isScopedAccessCredentialsEnabled
        self.jweCompactCodec = jweCompactCodec
    }

    func registeredDevices(from entries: [RegisteredDeviceEntry], account: SyncAccount) async -> [RegisteredDevice] {
        let thirdPartyMainKey = await thirdPartyMainKeyIfNeeded(for: entries, account: account)
        return entries.map { registeredDevice(from: $0, account: account, thirdPartyMainKey: thirdPartyMainKey) }
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

    func registeredDevice(fromThirdPartyLoginEntryWithID id: String, encodedName: String, encodedType: String?) -> RegisteredDevice {
        // Login-response 3party fields are base64-encoded plaintext (not a JWE like device-list entries); fall back to the raw value if it isn't base64.
        RegisteredDevice(id: id,
                         name: Self.utf8String(fromBase64EncodedString: encodedName) ?? encodedName,
                         type: encodedType.flatMap { Self.utf8String(fromBase64EncodedString: $0) } ?? encodedType ?? "",
                         credentialId: SyncCredentialID.thirdParty)
    }

    private func registeredDevice(from entry: RegisteredDeviceEntry, account: SyncAccount, thirdPartyMainKey: Data?) -> RegisteredDevice {
        // Keep every server entry visible even if one encrypted field is malformed or uses a key we cannot recover.
        decryptedRegisteredDevice(from: entry, account: account, thirdPartyMainKey: thirdPartyMainKey) ?? fallbackRegisteredDevice(from: entry)
    }

    private func decryptedRegisteredDevice(from entry: RegisteredDeviceEntry, account: SyncAccount, thirdPartyMainKey: Data?) -> RegisteredDevice? {
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

    private static func utf8String(fromBase64EncodedString value: String) -> String? {
        guard let data = Data(base64Encoded: value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

struct RegisteredDeviceEntry: Decodable {
    let id: String
    let name: String?
    let type: String?
    let credentialId: String?
}
