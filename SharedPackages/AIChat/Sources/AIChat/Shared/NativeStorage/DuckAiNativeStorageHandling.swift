//
//  DuckAiNativeStorageHandling.swift
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
import DuckAiDataStore

public protocol DuckAiNativeStorageHandling {

    // MARK: - Settings

    func putSetting(key: String, value: Any) throws
    func getSetting(key: String) throws -> Any?
    func getAllSettings() throws -> [String: Any]
    func deleteSetting(key: String) throws
    func deleteAllSettings() throws
    func replaceAllSettings(_ settings: [String: Any]) throws

    // MARK: - Chats

    func putChat(chatId: String, data: Data) throws
    func putChats(_ chats: [DuckAiChatRecord]) throws
    func getAllChats() throws -> [DuckAiChatRecord]
    func deleteChat(chatId: String) throws
    func deleteAllChats() throws

    // MARK: - Files

    func putFile(uuid: String, chatId: String, data: Data) throws
    func getFile(uuid: String) throws -> DuckAiFileContent?
    func listFiles() throws -> [DuckAiFileMetadata]
    func deleteFile(uuid: String) throws
    func deleteAllFiles() throws

    // MARK: - Migration

    func isMigrationDone() throws -> Bool
    func markMigrationDone() throws
}
