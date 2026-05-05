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

/// 
public protocol DuckAiNativeStorageHandling {

    // MARK: - Entries

    func putEntry(key: String, value: Any) throws
    func getEntry(key: String) throws -> Any?
    func getAllEntries() throws -> [String: Any]
    func deleteEntry(key: String) throws
    func deleteAllEntries() throws
    func replaceAllEntries(_ entries: [String: Any]) throws

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

    // MARK: - Migration

    /// Returns `true` only when all migration keys have completed.
    func isMigrationDone() throws -> Bool
    /// Returns `true` when the migration for the given key has completed.
    func isMigrationDone(key: String) throws -> Bool
    /// Marks the migration for the given key as complete.
    func markMigrationDone(key: String) throws

    // MARK: - Lifecycle

    /// Non-blocking probe of any deferred initialization performed by the underlying
    /// store. `nil` means setup is still in flight, `true` means it completed
    /// successfully, `false` means it failed permanently. Bridge availability gates
    /// should treat `nil` optimistically (assume available) so the launch path is
    /// not blocked while the gate is evaluated, and only force the JS fallback once
    /// a definitive failure is known.
    var setupSucceeded: Bool? { get }
}

public extension DuckAiNativeStorageHandling {
    var setupSucceeded: Bool? { true }
}

public enum DuckAiMigrationKey {
    public static let chats = "chats"
    public static let files = "files"

    static let allKeys = [chats, files]
}
