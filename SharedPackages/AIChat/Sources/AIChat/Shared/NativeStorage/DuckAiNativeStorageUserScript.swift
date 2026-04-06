//
//  DuckAiNativeStorageUserScript.swift
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

import Common
import DuckAiDataStore
import Foundation
import os.log
import UserScript
import WebKit

public final class DuckAiNativeStorageUserScript: NSObject, Subfeature {

    // MARK: - Properties

    public weak var broker: UserScriptMessageBroker?
    public let featureName: String = "duckAiNativeStorage"
    public let messageOriginPolicy: MessageOriginPolicy

    private let handler: DuckAiNativeStorageHandling

    // MARK: - Initialization

    public init(handler: DuckAiNativeStorageHandling, originRules: [HostnameMatchingRule]) {
        self.handler = handler
        self.messageOriginPolicy = .only(rules: originRules)
        super.init()
        Logger.aiChat.debug("[NativeStorage] Created with origin rules: \(originRules.map { String(describing: $0) }.joined(separator: ", "))")
    }

    // MARK: - Subfeature

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
        Logger.aiChat.debug("[NativeStorage] Registered with broker (featureName='\(self.featureName)', originPolicy=\(String(describing: self.messageOriginPolicy)))")
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = DuckAiNativeStorageUserScriptMessages(rawValue: methodName) else {
            Logger.aiChat.debug("DuckAiNativeStorageUserScript: Unknown method '\(methodName)' — no handler")
            return nil
        }

        Logger.aiChat.debug("DuckAiNativeStorageUserScript: Resolving handler for '\(methodName)'")

        switch message {
        // Settings
        case .putSetting: return putSetting
        case .getSetting: return getSetting
        case .getAllSettings: return getAllSettings
        case .deleteSetting: return deleteSetting
        case .deleteAllSettings: return deleteAllSettings
        case .replaceAllSettings: return replaceAllSettings

        // Chats
        case .putChat: return putChat
        case .getAllChats: return getAllChats
        case .deleteChat: return deleteChat
        case .deleteAllChats: return deleteAllChats

        // Files
        case .putFile: return putFile
        case .getFile: return getFile
        case .listFiles: return listFiles
        case .deleteFile: return deleteFile
        case .deleteAllFiles: return deleteAllFiles

        // Migration
        case .isMigrationDone: return isMigrationDone
        case .markMigrationDone: return markMigrationDone
        }
    }

    // MARK: - Settings Handlers

    @MainActor
    private func putSetting(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← putSetting called")
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String,
              let value = dict["value"] else {
            Logger.aiChat.error("DuckAiNativeStorage: putSetting — invalid params")
            return nil
        }
        do {
            try handler.putSetting(key: key, value: value)
            Logger.aiChat.debug("DuckAiNativeStorage: putSetting '\(key)' succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putSetting failed for key '\(key)': \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func getSetting(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← getSetting called")
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: getSetting — invalid params")
            return nil
        }
        do {
            let value = try handler.getSetting(key: key)
            Logger.aiChat.debug("DuckAiNativeStorage: getSetting '\(key)' → \(value == nil ? "nil" : "found")")
            return SettingValueResponse(value: AnyCodableValue(value ?? NSNull()))
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getSetting failed for key '\(key)': \(error.localizedDescription)")
            return SettingValueResponse(value: AnyCodableValue(NSNull()))
        }
    }

    @MainActor
    private func getAllSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← getAllSettings called")
        do {
            let settings = try handler.getAllSettings()
            Logger.aiChat.debug("DuckAiNativeStorage: getAllSettings → \(settings.count) keys")
            return AllSettingsResponse(settings: settings.mapValues { AnyCodableValue($0) })
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getAllSettings failed: \(error.localizedDescription)")
            return AllSettingsResponse(settings: [:])
        }
    }

    @MainActor
    private func deleteSetting(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteSetting called")
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: deleteSetting — invalid params")
            return nil
        }
        do {
            try handler.deleteSetting(key: key)
            Logger.aiChat.debug("DuckAiNativeStorage: deleteSetting '\(key)' succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteSetting failed for key '\(key)': \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func deleteAllSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteAllSettings called")
        do {
            try handler.deleteAllSettings()
            Logger.aiChat.debug("DuckAiNativeStorage: deleteAllSettings succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteAllSettings failed: \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func replaceAllSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← replaceAllSettings called")
        guard let dict = params as? [String: Any],
              let settings = dict["settings"] as? [String: Any] else {
            Logger.aiChat.error("DuckAiNativeStorage: replaceAllSettings — invalid params")
            return nil
        }
        do {
            try handler.replaceAllSettings(settings)
            Logger.aiChat.debug("DuckAiNativeStorage: replaceAllSettings succeeded with \(settings.count) keys")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: replaceAllSettings failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Chat Handlers

    @MainActor
    private func putChat(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← putChat called")
        guard let dict = params as? [String: Any],
              let chatId = dict["chatId"] as? String,
              let data = dict["data"] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: data) else {
            Logger.aiChat.error("DuckAiNativeStorage: putChat — invalid params")
            return nil
        }
        do {
            try handler.putChat(chatId: chatId, data: jsonData)
            Logger.aiChat.debug("DuckAiNativeStorage: putChat '\(chatId)' succeeded (\(jsonData.count) bytes)")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putChat failed for \(chatId): \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func getAllChats(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← getAllChats called")
        let chatRecords: [DuckAiChatRecord]
        do {
            chatRecords = try handler.getAllChats()
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getAllChats failed: \(error.localizedDescription)")
            return AllChatsResponse(chats: [])
        }
        let chats: [[String: AnyCodableValue]] = chatRecords.compactMap { record in
            guard let obj = try? JSONSerialization.jsonObject(with: record.data) as? [String: Any] else { return nil }
            var dict = obj.mapValues { AnyCodableValue($0) }
            dict["chatId"] = AnyCodableValue(record.chatId)
            return dict
        }
        Logger.aiChat.debug("DuckAiNativeStorage: getAllChats → \(chats.count) chats")
        return AllChatsResponse(chats: chats)
    }

    @MainActor
    private func deleteChat(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteChat called")
        guard let dict = params as? [String: Any],
              let chatId = dict["chatId"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: deleteChat — invalid params")
            return nil
        }
        do {
            try handler.deleteChat(chatId: chatId)
            Logger.aiChat.debug("DuckAiNativeStorage: deleteChat '\(chatId)' succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteChat failed for \(chatId): \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func deleteAllChats(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteAllChats called")
        do {
            try handler.deleteAllChats()
            Logger.aiChat.debug("DuckAiNativeStorage: deleteAllChats succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteAllChats failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - File Handlers

    @MainActor
    private func putFile(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← putFile called")
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String,
              let chatId = dict["chatId"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: putFile — invalid params (missing uuid or chatId)")
            return nil
        }
        // Store the entire params JSON opaquely — preserves all FE fields (data, mimeType, fileName, etc.)
        guard let paramsData = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            Logger.aiChat.error("DuckAiNativeStorage: putFile — failed to serialize params")
            return nil
        }
        Logger.aiChat.debug("DuckAiNativeStorage: putFile '\(uuid)' for chat '\(chatId)' (\(paramsData.count) bytes, keys: \(dict.keys.sorted().joined(separator: ", ")))")
        do {
            try handler.putFile(uuid: uuid, chatId: chatId, data: paramsData)
            Logger.aiChat.debug("DuckAiNativeStorage: putFile '\(uuid)' stored successfully")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putFile failed for \(uuid): \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func getFile(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← getFile called")
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: getFile — invalid params")
            return nil
        }
        do {
            guard let fileContent = try handler.getFile(uuid: uuid) else {
                Logger.aiChat.debug("DuckAiNativeStorage: getFile '\(uuid)' → not found")
                return FileValueResponse(value: nil)
            }
            // Return the stored JSON opaquely — preserves all FE fields exactly as stored
            guard let storedDict = try? JSONSerialization.jsonObject(with: fileContent.data) as? [String: Any] else {
                Logger.aiChat.error("DuckAiNativeStorage: getFile '\(uuid)' — stored data is not valid JSON")
                return FileValueResponse(value: nil)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: getFile '\(uuid)' → \(fileContent.data.count) bytes, keys: \(storedDict.keys.sorted().joined(separator: ", "))")
            return storedDict.mapValues { AnyCodableValue($0) }
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getFile failed for \(uuid): \(error.localizedDescription)")
            return FileValueResponse(value: nil)
        }
    }

    @MainActor
    private func listFiles(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← listFiles called")
        do {
            let files = try handler.listFiles()
            Logger.aiChat.debug("DuckAiNativeStorage: listFiles → \(files.count) files")
            return ListFilesResponse(files: files.map {
                FileMetadataResponse(uuid: $0.uuid, chatId: $0.chatId, dataSize: $0.dataSize)
            })
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: listFiles failed: \(error.localizedDescription)")
            return ListFilesResponse(files: [])
        }
    }

    @MainActor
    private func deleteFile(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteFile called")
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: deleteFile — invalid params")
            return nil
        }
        do {
            try handler.deleteFile(uuid: uuid)
            Logger.aiChat.debug("DuckAiNativeStorage: deleteFile '\(uuid)' succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteFile failed for \(uuid): \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func deleteAllFiles(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteAllFiles called")
        do {
            try handler.deleteAllFiles()
            Logger.aiChat.debug("DuckAiNativeStorage: deleteAllFiles succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteAllFiles failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Migration Handlers

    @MainActor
    private func isMigrationDone(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← isMigrationDone called")
        do {
            let done = try handler.isMigrationDone()
            Logger.aiChat.debug("DuckAiNativeStorage: isMigrationDone → \(done)")
            return MigrationDoneResponse(value: done)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: isMigrationDone failed: \(error.localizedDescription)")
            return MigrationDoneResponse(value: false)
        }
    }

    @MainActor
    private func markMigrationDone(params: Any, message: UserScriptMessage) -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← markMigrationDone called")
        do {
            try handler.markMigrationDone()
            Logger.aiChat.debug("DuckAiNativeStorage: markMigrationDone succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: markMigrationDone failed: \(error.localizedDescription)")
        }
        return nil
    }
}

// MARK: - Response Models

private struct SettingValueResponse: Encodable {
    let value: AnyCodableValue?
}

private struct AllSettingsResponse: Encodable {
    let settings: [String: AnyCodableValue]
}

private struct AllChatsResponse: Encodable {
    let chats: [[String: AnyCodableValue]]
}

private struct FileValueResponse: Encodable {
    let value: String?
}

private struct FileMetadataResponse: Encodable {
    let uuid: String
    let chatId: String
    let dataSize: Int
}

private struct ListFilesResponse: Encodable {
    let files: [FileMetadataResponse]
}

private struct MigrationDoneResponse: Encodable {
    let value: Bool
}

// MARK: - AnyCodableValue

private struct AnyCodableValue: Encodable {
    private let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodableValue($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodableValue($0) })
        default:
            try container.encodeNil()
        }
    }
}
