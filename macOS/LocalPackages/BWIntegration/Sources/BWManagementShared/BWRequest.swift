//
//  BWRequest.swift
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

public struct BWRequest: Codable {

    static let version = 1

    public static func makeHandshakeRequest(with publicKey: String, messageId: String, applicationName: String) -> BWRequest {
        let payload = Payload(publicKey: publicKey,
                              applicationName: applicationName)

        return BWRequest(messageId: messageId,
                         version: version,
                         command: .handshake,
                         payload: payload)
    }

    public static func makeEncryptedCommandRequest(encryptedCommand: String, messageId: String) -> BWRequest {
        return BWRequest(messageId: messageId,
                         version: version,
                         encryptedCommand: encryptedCommand)
    }

    public let messageId: MessageId?
    public let version: Int?
    public let command: BWCommand?
    public let payload: Payload?
    public let encryptedCommand: Base64EncodedString?

    public init(messageId: String? = nil,
                version: Int? = nil,
                command: BWCommand? = nil,
                payload: BWRequest.Payload? = nil,
                encryptedCommand: String? = nil) {
        self.messageId = messageId
        self.version = version
        self.command = command
        self.payload = payload
        self.encryptedCommand = encryptedCommand
    }

    public struct Payload: Codable {

        public init(publicKey: Base64EncodedString? = nil,
                    applicationName: String? = nil
        ) {
            self.publicKey = publicKey
            self.applicationName = applicationName
        }

        // Handshake request
        public let publicKey: Base64EncodedString?
        public let applicationName: String?
    }

    // Need encryption before inserting into encryptedCommand
    public struct EncryptedCommand: Codable {

        public let command: BWCommand?
        public let payload: Payload?

        public init(command: BWCommand?, payload: Payload?) {
            self.command = command
            self.payload = payload
        }

        public struct Payload: Codable {
            public init(uri: String? = nil,
                        userId: String? = nil,
                        userName: String? = nil,
                        password: String? = nil,
                        name: String? = nil,
                        credentialId: String? = nil) {
                self.uri = uri
                self.userId = userId
                self.userName = userName
                self.password = password
                self.name = name
                self.credentialId = credentialId
            }

            // Credential Retrieval
            public let uri: String?

            // Credential Creation
            public let userId: String?
            public let userName: String?
            public let password: String?
            public let name: String?

            // Credential Update
            public let credentialId: String?
        }

        public var data: Data? {
            let jsonData: Data
            do {
                jsonData = try JSONEncoder().encode(self)
            } catch {
                assertionFailure("BWRequest: Can't encode the message")
                return nil
            }
            return jsonData
        }

    }

    public var data: Data? {
        let jsonData: Data
        do {
            jsonData = try JSONEncoder().encode(self)
        } catch {
            assertionFailure("BWRequest: Can't encode the message")
            return nil
        }
        return jsonData
    }

}
