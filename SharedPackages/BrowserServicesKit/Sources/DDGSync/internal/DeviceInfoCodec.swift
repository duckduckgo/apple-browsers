//
//  DeviceInfoCodec.swift
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
import Security

struct DeviceInfo: Codable, Equatable, Sendable {
    static let maximumEncryptedLength = 2_000

    let name: String
    let type: String
}

enum DeviceInfoCodecError: Error, Equatable {
    case invalidProtectedKey
    case invalidPayload
}

protocol DeviceInfoCoding {
    func encrypt(_ deviceInfo: DeviceInfo, using protectedKey: ProtectedKey) throws -> String
    func encrypt(_ deviceInfo: DeviceInfo, using key: AccountInfoKeyMaterial) throws -> String
    func decrypt(_ encryptedDeviceInfo: String, using key: AccountInfoKeyMaterial) throws -> DeviceInfo
}

struct DeviceInfoCodec: DeviceInfoCoding {

    private let jweCompactCodec: JWECompactCodec

    init(jweCompactCodec: JWECompactCodec = JWECompactCodec()) {
        self.jweCompactCodec = jweCompactCodec
    }

    func encrypt(_ deviceInfo: DeviceInfo, using protectedKey: ProtectedKey) throws -> String {
        guard protectedKey.purpose == ProtectedKeyPurpose.accountInfo, !protectedKey.kid.isEmpty else {
            throw DeviceInfoCodecError.invalidProtectedKey
        }
        let publicKey = try RSAKeyImporter.makePublicKey(from: protectedKey.publicKey)
        return try encrypt(deviceInfo, publicKey: publicKey, keyID: protectedKey.kid)
    }

    func encrypt(_ deviceInfo: DeviceInfo, using key: AccountInfoKeyMaterial) throws -> String {
        try encrypt(deviceInfo, publicKey: key.publicKey, keyID: key.kid)
    }

    func decrypt(_ encryptedDeviceInfo: String, using key: AccountInfoKeyMaterial) throws -> DeviceInfo {
        let payload = try jweCompactCodec.decryptRSAOAEP256(token: encryptedDeviceInfo,
                                                           privateKey: key.privateKey,
                                                           expectedKid: key.kid)
        do {
            return try JSONDecoder().decode(DeviceInfo.self, from: payload)
        } catch {
            throw DeviceInfoCodecError.invalidPayload
        }
    }

    private func encrypt(_ deviceInfo: DeviceInfo, publicKey: SecKey, keyID: String) throws -> String {
        guard !keyID.isEmpty else {
            throw DeviceInfoCodecError.invalidProtectedKey
        }
        let payload = try JSONEncoder().encode(deviceInfo)
        return try jweCompactCodec.encryptRSAOAEP256(payload: payload,
                                                     recipientPublicKey: publicKey,
                                                     kid: keyID)
    }
}
