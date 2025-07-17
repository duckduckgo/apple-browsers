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

public struct SyncAccount: Codable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let deviceType: String
    public let userId: String
    public let primaryKey: Data
    public let secretKey: Data
    public let token: String?
    public let state: SyncAuthState

    /// Convenience var which calls `SyncCode().toJSON().base64EncodedString()`
    public var recoveryCode: String? {
        do {
            let json = try SyncCode(recovery: .init(userId: userId, primaryKey: primaryKey)).toJSON()
            return json.base64EncodedString()
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
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
    enum Keys {
        static let code = "code"
        static let deviceName = "deviceName"
    }

    public let base64Code: String
    public let deviceName: String

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

    init(base64Code: String, deviceName: String) {
        self.base64Code = base64Code
        self.deviceName = deviceName
    }

    public func toURL(baseURL: URL) -> URL {
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

public struct SyncCode: Codable {

    public enum Base64Error: Error {
        case error
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

    public var recovery: RecoveryKey?
    public var connect: ConnectCode?
    public var exchangeKey: ExchangeKey?

    public static func decode(_ data: Data) throws -> Self {
        return try JSONDecoder.snakeCaseKeys.decode(self, from: data)
    }

    public func toJSON() throws -> Data {
        return try JSONEncoder.snakeCaseKeys.encode(self)
    }

    public static func decodeBase64String(_ string: String) throws -> Self {
        guard let data = Data(base64Encoded: string) else {
            throw Base64Error.error
        }
        return try Self.decode(data)
    }

}
