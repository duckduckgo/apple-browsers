//
//  DuckAiNativeDataStoring.swift
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

public protocol DuckAiNativeDataStoring {

    // MARK: - Chats

    func putChat(chatId: String, data: Data) throws
    func putChats(_ chats: [DuckAiChatRecord]) throws
    func getChat(chatId: String) throws -> DuckAiChatRecord?
    func getAllChats() throws -> [DuckAiChatRecord]
    func deleteChat(chatId: String) throws
    func deleteAllChats() throws

    // MARK: - Files

    func putFile(uuid: String, chatId: String, data: Data) throws
    func getFile(uuid: String) throws -> DuckAiFileContent?
    func listFiles() throws -> [DuckAiFileMetadata]
    func deleteFile(uuid: String) throws
    func deleteFiles(chatId: String) throws
    func deleteAllFiles() throws
}

public struct DuckAiChatRecord: Equatable {
    public let chatId: String
    public let data: Data

    public init(chatId: String, data: Data) {
        self.chatId = chatId
        self.data = data
    }
}

public struct DuckAiFileContent: Equatable {
    public let uuid: String
    public let chatId: String
    public let data: Data

    public init(uuid: String, chatId: String, data: Data) {
        self.uuid = uuid
        self.chatId = chatId
        self.data = data
    }
}

public struct DuckAiFileMetadata: Equatable {
    public let uuid: String
    public let chatId: String
    public let dataSize: Int

    public init(uuid: String, chatId: String, dataSize: Int) {
        self.uuid = uuid
        self.chatId = chatId
        self.dataSize = dataSize
    }
}
