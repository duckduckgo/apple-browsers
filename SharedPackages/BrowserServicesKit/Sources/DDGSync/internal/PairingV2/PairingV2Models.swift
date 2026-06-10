//
//  PairingV2Models.swift
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

enum PairingV2ApplicationMessage: Equatable {
    case hello(PairingV2HelloMessage)
    case recoveryCodeAvailable(PairingV2RecoveryCodeStatusMessage)
    case recoveryCodeRequest(PairingV2RecoveryCodeStatusMessage)
    case recoveryCodeAwaitingConfirmation(PairingV2RecoveryCodeTerminalMessage)
    case recoveryCodeConfirmed(PairingV2RecoveryCodeTerminalMessage)
    case recoveryCodeDenied(PairingV2RecoveryCodeTerminalMessage)
    case recoveryCodeUnavailable(PairingV2RecoveryCodeTerminalMessage)
    case recoveryCodeResponse(PairingV2RecoveryCodeResponseMessage)
}

/// The Pairing V2 protocol version this client emits and the peer major version it accepts.
enum PairingV2ProtocolVersion {
    static let current = "2"
    /// Only peers whose major version equals this are supported.
    static let supportedMajor = 2

    static func supports(_ version: String) -> Bool {
        SyncProtocolVersion.parseMajor(version) == supportedMajor
    }
}

/// The payload encoded in a Pairing V2 QR code / pairing URL: protocol version, presenter's relay channel, and its public key.
struct PairingV2QRCodePayload: Codable, Equatable {
    let version: String
    /// Presenter's relay channel the scanner sends its first message to.
    let channelId: String
    let publicKey: String

    init(version: String = PairingV2ProtocolVersion.current, channelId: String, publicKey: String) {
        self.version = version
        self.channelId = channelId
        self.publicKey = publicKey
    }

    init?(url: URL) {
        guard let decoded = Self.decodedPayload(from: url),
              PairingV2ProtocolVersion.supports(decoded.version) else {
            return nil
        }

        self = decoded
    }

    static func unsupportedMajorVersion(in url: URL) -> String? {
        guard let decoded = Self.decodedPayload(from: url),
              let major = SyncProtocolVersion.parseMajor(decoded.version),
              major > PairingV2ProtocolVersion.supportedMajor else {
            return nil
        }

        return decoded.version
    }

    func toURL(baseURL: URL) throws -> URL {
        let url = baseURL.appendingPathComponent("sync/pairing/")
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        urlComponents?.fragment = "&code2=\(Base64URL.encode(try JSONEncoder.snakeCaseKeys.encode(self)))"
        return urlComponents?.url ?? url
    }

    private static func isPairing(url: URL) -> Bool {
        url.pathComponents.contains("sync") && url.pathComponents.last == "pairing" && url.isPart(ofDomain: "duckduckgo.com")
    }

    private static func decodedPayload(from url: URL) -> Self? {
        guard Self.isPairing(url: url),
              let fragment = URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment else {
            return nil
        }

        let dict = Self.fragmentParameters(from: fragment)
        guard let payload = dict["code2"],
              let payloadData = Self.decodePayload(payload) else {
            return nil
        }

        return try? JSONDecoder.snakeCaseKeys.decode(Self.self, from: payloadData)
    }

    private static func fragmentParameters(from fragment: String) -> [String: String] {
        let params = fragment
            .split(separator: "&")
            .compactMap { part -> (String, String)? in
                let keyValue = part.split(separator: "=", maxSplits: 1).map(String.init)
                guard keyValue.count == 2 else { return nil }
                return (keyValue[0], keyValue[1].removingPercentEncoding ?? keyValue[1])
            }

        return Dictionary(uniqueKeysWithValues: params)
    }

    private static func decodePayload(_ value: String) -> Data? {
        if let data = Data(base64Encoded: value) {
            return data
        }
        return Base64URL.decode(value)
    }

}

struct PairingV2EncryptedMessage: Codable, Equatable {
    let version: String
    let payload: String

    init(version: String = PairingV2ProtocolVersion.current, payload: String) {
        self.version = version
        self.payload = payload
    }
}

/// An encrypted message fetched from the relay, tagged with its server-assigned sequence number for ordering and de-duplication.
struct PairingV2SequencedMessage: Codable, Equatable {
    let seq: Int
    let version: String
    let payload: String

    var encryptedMessage: PairingV2EncryptedMessage {
        PairingV2EncryptedMessage(version: version, payload: payload)
    }
}

/// First message a peer sends after opening its channel, announcing its channel ID and public key so the other side can reply.
struct PairingV2HelloMessage: Codable, Equatable {
    static let messageType = "hello"

    let type: String
    let channelId: String
    let publicKey: String
    let version: String

    init(channelId: String, publicKey: String, version: String = PairingV2ProtocolVersion.current) {
        self.type = Self.messageType
        self.channelId = channelId
        self.publicKey = publicKey
        self.version = version
    }
}

/// Announces whether a peer already has an account (`recovery_code_available`) or needs one (`recovery_code_request`); drives role election.
struct PairingV2RecoveryCodeStatusMessage: Codable, Equatable {
    let type: String
    let name: String?
    let kind: PairingV2DeviceKind
    /// Account user ID, present only when the peer already has an account; used to detect same-account pairing.
    let userId: String?

    init(type: String, name: String? = nil, kind: PairingV2DeviceKind, userId: String? = nil) {
        self.type = type
        self.name = name
        self.kind = kind
        self.userId = userId
    }
}

struct PairingV2RecoveryCodeTerminalMessage: Codable, Equatable {
    let type: String
}

struct PairingV2RecoveryCodeResponseMessage: Codable, Equatable {
    static let messageType = "recovery_code_response"

    let type: String
    let recoveryCode: String

    init(recoveryCode: String) {
        self.type = Self.messageType
        self.recoveryCode = recoveryCode
    }
}

extension PairingV2ApplicationMessage {

    enum MessageType {
        static let recoveryCodeAvailable = "recovery_code_available"
        static let recoveryCodeRequest = "recovery_code_request"
        static let recoveryCodeAwaitingConfirmation = "recovery_code_awaiting_confirmation"
        static let recoveryCodeConfirmed = "recovery_code_confirmed"
        static let recoveryCodeDenied = "recovery_code_denied"
        static let recoveryCodeUnavailable = "recovery_code_unavailable"
    }

    var type: String {
        switch self {
        case .hello(let message):
            return message.type
        case .recoveryCodeAvailable(let message),
                .recoveryCodeRequest(let message):
            return message.type
        case .recoveryCodeAwaitingConfirmation(let message),
                .recoveryCodeConfirmed(let message):
            return message.type
        case .recoveryCodeDenied(let message),
                .recoveryCodeUnavailable(let message):
            return message.type
        case .recoveryCodeResponse(let message):
            return message.type
        }
    }
}
