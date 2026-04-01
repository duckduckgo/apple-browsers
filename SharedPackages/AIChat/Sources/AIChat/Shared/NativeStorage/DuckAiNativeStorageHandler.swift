//
//  DuckAiNativeStorageHandler.swift
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
import Persistence

public final class DuckAiNativeStorageHandler: DuckAiNativeStorageHandling {

    private let settingsStore: any ThrowingKeyedStoring<DuckAiNativeStorageSettings>
    private let dataStore: DuckAiNativeDataStoring

    public init(
        settingsStore: any ThrowingKeyedStoring<DuckAiNativeStorageSettings>,
        dataStore: DuckAiNativeDataStoring
    ) {
        self.settingsStore = settingsStore
        self.dataStore = dataStore
    }

    // MARK: - Settings

    public func putSetting(key: String, value: Any) throws {
        var settings = try loadSettingsBlob()
        settings[key] = value
        try saveSettingsBlob(settings)
    }

    public func getSetting(key: String) throws -> Any? {
        let settings = try loadSettingsBlob()
        return settings[key]
    }

    public func getAllSettings() throws -> [String: Any] {
        return try loadSettingsBlob()
    }

    public func deleteSetting(key: String) throws {
        var settings = try loadSettingsBlob()
        settings.removeValue(forKey: key)
        try saveSettingsBlob(settings)
    }

    public func deleteAllSettings() throws {
        try settingsStore.set(nil, for: \.settings)
    }

    public func replaceAllSettings(_ settings: [String: Any]) throws {
        try saveSettingsBlob(settings)
    }

    // MARK: - Chats (delegation)

    public func putChat(chatId: String, data: Data) throws {
        try dataStore.putChat(chatId: chatId, data: data)
    }

    public func getAllChats() throws -> [DuckAiChatRecord] {
        try dataStore.getAllChats()
    }

    public func deleteChat(chatId: String) throws {
        try dataStore.deleteChat(chatId: chatId)
    }

    public func deleteAllChats() throws {
        try dataStore.deleteAllChats()
    }

    // MARK: - Files (delegation)

    public func putFile(uuid: String, chatId: String, data: Data) throws {
        try dataStore.putFile(uuid: uuid, chatId: chatId, data: data)
    }

    public func getFile(uuid: String) throws -> DuckAiFileContent? {
        try dataStore.getFile(uuid: uuid)
    }

    public func listFiles() throws -> [DuckAiFileMetadata] {
        try dataStore.listFiles()
    }

    public func deleteFile(uuid: String) throws {
        try dataStore.deleteFile(uuid: uuid)
    }

    public func deleteAllFiles() throws {
        try dataStore.deleteAllFiles()
    }

    // MARK: - Migration

    public func isMigrationDone() throws -> Bool {
        return try settingsStore.value(for: \.migrationDone) ?? false
    }

    public func markMigrationDone() throws {
        try settingsStore.set(true, for: \.migrationDone)
    }

    // MARK: - Private helpers

    private func loadSettingsBlob() throws -> [String: Any] {
        guard let data = try settingsStore.value(for: \.settings) else {
            return [:]
        }
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return dict
    }

    private func saveSettingsBlob(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [])
        try settingsStore.set(data, for: \.settings)
    }
}
