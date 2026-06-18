//
//  SyncModels.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

public struct SyncAccount: Codable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let deviceType: String
    public let userId: String
    public let primaryKey: Data
    public let secretKey: Data
    public let token: String?
    public let state: SyncAuthState

    /// Legacy native/DDG V1 recovery code.
    public var legacyRecoveryCodeV1: String? {
        guard let data = try? SyncCode(recovery: .v1(.init(userId: userId, primaryKey: primaryKey))).toJSON() else {
            return nil
        }
        return data.base64EncodedString()
    }

    /// Native/DDG V2 recovery code.
    public var recoveryCodeV2: String? {
        let payload = SyncCode.RecoveryKeyV2(
            userId: userId,
            secret: Base64URL.encode(primaryKey),
            cid: SyncCredentialID.defaultCredential,
            v: SyncCode.RecoveryKeyV2.currentVersion
        )
        guard let data = try? SyncCode(recovery: .v2(payload)).toJSON() else {
            return nil
        }
        return Base64URL.encode(data)
    }

    @available(*, deprecated, message: "Use recoveryCodeV2 or legacyRecoveryCodeV1 explicitly.")
    public var recoveryCode: String? {
        legacyRecoveryCodeV1
    }

    init(
        deviceId: String,
        deviceName: String,
        deviceType: String,
        userId: String,
        primaryKey: Data,
        secretKey: Data,
        token: String?,
        state: SyncAuthState
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.deviceType = deviceType
        self.userId = userId
        self.primaryKey = primaryKey
        self.secretKey = secretKey
        self.token = token
        self.state = state
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.deviceId = try container.decode(String.self, forKey: .deviceId)
        self.deviceName = try container.decode(String.self, forKey: .deviceName)
        self.deviceType = try container.decode(String.self, forKey: .deviceType)
        self.userId = try container.decode(String.self, forKey: .userId)
        self.primaryKey = try container.decode(Data.self, forKey: .primaryKey)
        self.secretKey = try container.decode(Data.self, forKey: .secretKey)
        self.token = try container.decodeIfPresent(String.self, forKey: .token)
        if let state: SyncAuthState = try container.decodeIfPresent(SyncAuthState.self, forKey: .state) {
            self.state = state
        } else {
            self.state = SyncAuthState.active
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.deviceId, forKey: .deviceId)
        try container.encode(self.deviceName, forKey: .deviceName)
        try container.encode(self.deviceType, forKey: .deviceType)
        try container.encode(self.userId, forKey: .userId)
        try container.encode(self.primaryKey, forKey: .primaryKey)
        try container.encode(self.secretKey, forKey: .secretKey)
        try container.encodeIfPresent(self.token, forKey: .token)
        try container.encode(self.state, forKey: .state)
    }

    enum CodingKeys: CodingKey {
        case deviceId
        case deviceName
        case deviceType
        case userId
        case primaryKey
        case secretKey
        case token
        case state
    }
}

public struct RegisteredDevice: Codable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let credentialId: String?

    public init(id: String, name: String, type: String, credentialId: String? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.credentialId = credentialId
    }
}

public struct AccountCreationKeys {
    public let primaryKey: Data
    public let secretKey: Data
    public let protectedSecretKey: Data
    public let passwordHash: Data
}

public struct ExtractedLoginInfo {
    public let userId: String
    public let primaryKey: Data
    public let passwordHash: Data
    public let stretchedPrimaryKey: Data
}

public struct ConnectInfo {
    public let deviceID: String
    public let publicKey: Data
    public let secretKey: Data
}

public struct ExchangeInfo {
    public let keyId: String
    public let publicKey: Data
    public let secretKey: Data
}

public struct ExchangeMessage: Codable, Sendable {
    public let keyId: String
    public let publicKey: Data
    public let deviceName: String
}

public struct PairingInfo {
    enum Kind {
        case legacy
        case pairingV2(URL)
    }

    enum Keys {
        static let code = "code"
        static let deviceName = "deviceName"
    }

    public let base64Code: String
    public let deviceName: String
    let kind: Kind

    public init?(url: URL) {
        guard Self.isPairing(url: url) else {
            return nil
        }
        guard let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            return nil
        }
        let params = fragment
            .split(separator: "&")
            .compactMap { part -> (String, String)? in
                let keyValue = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard keyValue.count == 2 else { return nil }
                return (keyValue[0], keyValue[1].removingPercentEncoding ?? keyValue[1])
            }

        let dict = Dictionary(uniqueKeysWithValues: params)
        guard let code = dict[Keys.code], let deviceName = dict[Keys.deviceName] else {
            return nil
        }
        self.init(base64Code: Self.restoreBase64(from: code),
                  deviceName: deviceName)
    }

    init(base64Code: String, deviceName: String, kind: Kind = .legacy) {
        self.base64Code = base64Code
        self.deviceName = deviceName
        self.kind = kind
    }

    init(pairingV2URL: URL, deviceName: String) {
        self.init(base64Code: pairingV2URL.absoluteString, deviceName: deviceName, kind: .pairingV2(pairingV2URL))
    }

    public func toURL(baseURL: URL) -> URL {
        if case .pairingV2(let url) = kind {
            return url
        }

        let url = baseURL.appendingPathComponent("sync/pairing/")
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let fragment = "&\(Keys.code)=\(base64URLCode)&\(Keys.deviceName)=\(deviceName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? deviceName)"
        urlComponents?.fragment = fragment
        return urlComponents?.url ?? url
    }

    private static func isPairing(url: URL) -> Bool {
        url.pathComponents.contains("sync") && url.pathComponents.last == "pairing" && url.isPart(ofDomain: "duckduckgo.com")
    }

    private static func restoreBase64(from base64URLCode: String) -> String {
        let paddingLength = (4 - (base64URLCode.count % 4)) % 4
        let padding = String(repeating: "=", count: paddingLength)
        return base64URLCode.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/").appending(padding)
    }

    private var base64URLCode: String {
        base64Code.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Scoped Access Credentials

public enum SyncCredentialID {
    public static let defaultCredential = "ddg"
    public static let thirdParty = "3party"
}

// AccessCredential is decoded from API responses using JSONDecoder.snakeCaseKeys. The server key
// is "encrypted_3party_credential", and .convertFromSnakeCase maps that to encrypted3PartyCredential.
// Adding a CodingKeys raw value for the literal server key would make decoding return nil.
public struct AccessCredential: Decodable, Sendable {
    public let id: String
    public let scope: String?
    public let encrypted3PartyCredential: String?
}

public struct ProtectedKey: Codable, Sendable {
    public let kid: String
    public let encryptedPrivateKey: String
    public let publicKey: ProtectedKeyPublicKey
    public let encryptedWith: String
    public let purpose: String

    enum CodingKeys: String, CodingKey {
        case kid
        case encryptedPrivateKey
        case publicKey
        case encryptedWith
        case purpose
    }

    public init(kid: String,
                encryptedPrivateKey: String,
                publicKey: ProtectedKeyPublicKey,
                encryptedWith: String,
                purpose: String) {
        self.kid = kid
        self.encryptedPrivateKey = encryptedPrivateKey
        self.publicKey = publicKey
        self.encryptedWith = encryptedWith
        self.purpose = purpose
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        kid = try container.decode(String.self, forKey: .kid)
        encryptedPrivateKey = try container.decode(String.self, forKey: .encryptedPrivateKey)
        publicKey = try container.decode(ProtectedKeyPublicKey.self, forKey: .publicKey)
        purpose = try container.decode(String.self, forKey: .purpose)

        if let encryptedWith = try container.decodeIfPresent(String.self, forKey: .encryptedWith), !encryptedWith.isEmpty {
            self.encryptedWith = encryptedWith
        } else {
            // Legacy/server compatibility: treat missing/empty encrypted_with as the default credential.
            Logger.sync.error("Protected key response missing encrypted_with; defaulting to ddg for compatibility")
            encryptedWith = SyncCredentialID.defaultCredential
        }
    }
}

public struct ProtectedKeyPublicKey: Codable, Sendable, Equatable {
    public let alg: String
    public let e: String?
    public let ext: Bool?
    public let keyOps: [String]?
    public let kty: String
    public let n: String?
    public let use: String?
}

private struct ProtectedKeyWrappingIdentity: Hashable {
    let kid: String
    let encryptedWith: String
    let purpose: String

    init(key: ProtectedKey) {
        self.kid = key.kid
        self.encryptedWith = key.encryptedWith
        self.purpose = key.purpose
    }
}

extension ProtectedKey {
    func hasSameWrappingIdentity(as other: ProtectedKey) -> Bool {
        kid == other.kid && encryptedWith == other.encryptedWith && purpose == other.purpose
    }
}

extension Sequence where Element == ProtectedKey {
    func removingDuplicateWrappingIdentities() -> [ProtectedKey] {
        var seenIdentities: Set<ProtectedKeyWrappingIdentity> = []
        return filter { key in
            seenIdentities.insert(ProtectedKeyWrappingIdentity(key: key)).inserted
        }
    }
}

enum SyncProtocolVersion {
    static func parseMajor(_ raw: String) -> Int? {
        guard let majorString = raw.split(separator: ".").first,
              let major = Int(majorString),
              major >= 0 else {
            return nil
        }
        return major
    }
}

public struct SyncCode: Codable {

    public enum Base64Error: Error {
        case error
    }

    public enum RecoveryCodeVersionError: Error, Equatable {
        case malformed(String)
        case unsupported(String)
    }

    public struct RecoveryKey: Codable, Sendable, Equatable {
        let userId: String
        let primaryKey: Data
    }

    public struct ConnectCode: Codable, Sendable {
        let deviceId: String
        let secretKey: Data
    }

    public struct ExchangeKey: Codable, Sendable {
        let keyId: String
        let publicKey: Data
    }

    /// V2 recovery code payload. All fields are snake_case on the wire.
    /// `secret` is base64URL of the raw default-credential secret (`cid == "ddg"`) or scoped-password bytes (`cid == "3party"`).
    /// `v` is `"major.minor"` to allow additive minor schema changes.
    public struct RecoveryKeyV2: Codable, Sendable, Equatable {
        static let currentVersion = "2.0"
        static let thirdPartyCredentialId = SyncCredentialID.thirdParty

        let userId: String
        let secret: String
        let cid: String
        let v: String
    }

    /// Versioned `recovery` payload. Distinguishes v1 (no `v` field — current native shape
    /// with `primary_key`) from v2 (`v: "2.0"` — scoped credential payload with `secret`/`cid`).
    ///
    /// Per versioning rules:
    /// - missing `v` field is treated as v1
    /// - `v` major == `Self.supportedMajor` is accepted; unknown fields are ignored for minor versions
    /// - `v` major > `Self.supportedMajor` is rejected with `RecoveryCodeVersionError.unsupported`,
    ///   even if the payload is otherwise structurally parseable
    public enum Recovery: Codable, Sendable, Equatable {
        case v1(RecoveryKey)
        case v2(RecoveryKeyV2)

        /// Highest major version of the recovery payload this client understands.
        public static let supportedMajor = 2

        private enum ProbeKeys: CodingKey {
            case v
        }

        public init(from decoder: Decoder) throws {
            let probe = try decoder.container(keyedBy: ProbeKeys.self)
            let rawVersion = try probe.decodeIfPresent(String.self, forKey: .v)
            switch rawVersion {
            case nil:
                self = .v1(try RecoveryKey(from: decoder))
            case let raw?:
                guard let major = SyncProtocolVersion.parseMajor(raw) else {
                    throw RecoveryCodeVersionError.malformed(raw)
                }
                guard major <= Self.supportedMajor else {
                    throw RecoveryCodeVersionError.unsupported(raw)
                }
                self = .v2(try RecoveryKeyV2(from: decoder))
            }
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .v1(let v1):
                try v1.encode(to: encoder)
            case .v2(let v2):
                try v2.encode(to: encoder)
            }
        }

        public func defaultCredentialRecoveryKey() throws -> RecoveryKey {
            switch self {
            case .v1(let recoveryKey):
                return recoveryKey
            case .v2(let recoveryKey):
                guard recoveryKey.cid == SyncCredentialID.defaultCredential,
                      let primaryKey = Base64URL.decode(recoveryKey.secret),
                      !primaryKey.isEmpty else {
                    throw SyncError.invalidRecoveryKey
                }
                return RecoveryKey(userId: recoveryKey.userId, primaryKey: primaryKey)
            }
        }

    }

    public var recovery: Recovery?
    public var connect: ConnectCode?
    public var exchangeKey: ExchangeKey?

    public static func decode(_ data: Data) throws -> Self {
        return try JSONDecoder.snakeCaseKeys.decode(self, from: data)
    }

    public func toJSON() throws -> Data {
        return try JSONEncoder.snakeCaseKeys.encode(self)
    }

    /// Decodes a `SyncCode` payload from either encoding. Tries standard base64
    /// first (the v1 wire format), then tries base64URL (the v2 wire format).
    /// The second decode attempt is unambiguous because Foundation's
    /// `Data(base64Encoded:)` strictly rejects the URL-safe alphabet (`-`/`_`),
    /// so the second branch only matches inputs the first one couldn't decode.
    public static func decodeBase64String(_ string: String) throws -> Self {
        if let data = Data(base64Encoded: string) {
            return try Self.decode(data)
        }
        if let data = Base64URL.decode(string) {
            return try Self.decode(data)
        }
        throw Base64Error.error
    }

    /// Decodes a strictly base64URL-encoded `SyncCode` payload. Most callers
    /// should use `decodeBase64String(_:)` instead, which accepts both encodings.
    public static func decodeBase64URLString(_ string: String) throws -> Self {
        guard let data = Base64URL.decode(string) else {
            throw Base64Error.error
        }
        return try Self.decode(data)
    }

}
