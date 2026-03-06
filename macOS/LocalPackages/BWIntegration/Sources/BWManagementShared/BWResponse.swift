//
//  BWResponse.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

public typealias Base64EncodedString = String
public typealias MessageId = String

public struct BWResponse: Codable {

    public let messageId: MessageId?
    public let version: Int?
    public let payload: Payload?
    public let command: BWCommand?
    public let encryptedCommand: Base64EncodedString?
    public let encryptedPayload: EncryptedPayload?

    public struct PayloadItem: Codable {
        public let error: String?

        // Handshake responce
        public let sharedKey: Base64EncodedString?

        // Status
        public let id: String?
        public let email: String?
        public let status: String?
        public let active: Bool?

        // Credential Retrieval
        public let userId: String?
        public let credentialId: String?
        public let userName: String?
        public let password: String?
        public let name: String?
    }

    public enum Payload: Codable {
        case array([PayloadItem])
        case item(PayloadItem)

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            do {
                self = try .array(container.decode(Array<PayloadItem>.self))
            } catch DecodingError.typeMismatch {
                do {
                    self = try .item(container.decode(PayloadItem.self))
                } catch DecodingError.typeMismatch {
                    throw DecodingError.typeMismatch(EncryptedPayload.self,
                                                     DecodingError.Context(codingPath: decoder.codingPath,
                                                                           debugDescription: "Encoded payload not of an expected type"))
                }
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .array(let array):
                try container.encode(array)
            case .item(let item):
                try container.encode(item)
            }
        }
    }

    public struct EncryptedPayload: Codable {

        public let encryptedString: String?
        public let encryptionType: Int?
        public let data: String?
        public let iv: String?
        public let mac: String?

    }

    public init?(from messageData: Data) {
        do {
            self = try JSONDecoder().decode(BWResponse.self, from: messageData)
        } catch {
            assertionFailure("Decoding the message failed")
            return nil
        }
    }

}
