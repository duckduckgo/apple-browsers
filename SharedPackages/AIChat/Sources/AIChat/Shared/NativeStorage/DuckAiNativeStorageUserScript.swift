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
    }

    // MARK: - Subfeature

    public func with(broker: UserScriptMessageBroker) {
        self.broker = broker
    }

    public func handler(forMethodNamed methodName: String) -> Subfeature.Handler? {
        guard let message = DuckAiNativeStorageUserScriptMessages(rawValue: methodName) else {
            return nil
        }

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
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String,
              let value = dict["value"] else { return nil }
        do {
            try handler.putSetting(key: key, value: value)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putSetting failed for key '\(key)': \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func getSetting(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String else { return nil }
        do {
            let value = try handler.getSetting(key: key)
            return SettingValueResponse(value: AnyCodableValue(value ?? NSNull()))
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getSetting failed for key '\(key)': \(error.localizedDescription)")
            return SettingValueResponse(value: AnyCodableValue(NSNull()))
        }
    }

    @MainActor
    private func getAllSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        do {
            let settings = try handler.getAllSettings()
            return AllSettingsResponse(settings: settings.mapValues { AnyCodableValue($0) })
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getAllSettings failed: \(error.localizedDescription)")
            return AllSettingsResponse(settings: [:])
        }
    }

    @MainActor
    private func deleteSetting(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String else { return nil }
        do {
            try handler.deleteSetting(key: key)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteSetting failed for key '\(key)': \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func deleteAllSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        do {
            try handler.deleteAllSettings()
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteAllSettings failed: \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func replaceAllSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let settings = dict["settings"] as? [String: Any] else { return nil }
        do {
            try handler.replaceAllSettings(settings)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: replaceAllSettings failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Chat Handlers

    @MainActor
    private func putChat(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let chatId = dict["chatId"] as? String,
              let data = dict["data"] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return nil }
        do {
            try handler.putChat(chatId: chatId, data: jsonData)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putChat failed for \(chatId): \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func getAllChats(params: Any, message: UserScriptMessage) -> Encodable? {
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
        return AllChatsResponse(chats: chats)
    }

    @MainActor
    private func deleteChat(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let chatId = dict["chatId"] as? String else { return nil }
        do {
            try handler.deleteChat(chatId: chatId)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteChat failed for \(chatId): \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func deleteAllChats(params: Any, message: UserScriptMessage) -> Encodable? {
        do {
            try handler.deleteAllChats()
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteAllChats failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - File Handlers

    @MainActor
    private func putFile(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String,
              let chatId = dict["chatId"] as? String,
              let dataString = dict["data"] as? String,
              let data = dataString.data(using: .utf8) else { return nil }
        do {
            try handler.putFile(uuid: uuid, chatId: chatId, data: data)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putFile failed for \(uuid): \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func getFile(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String else { return nil }
        do {
            guard let fileContent = try handler.getFile(uuid: uuid) else {
                return FileValueResponse(value: nil)
            }
            let dataString = String(data: fileContent.data, encoding: .utf8) ?? ""
            return GetFileResponse(uuid: fileContent.uuid, chatId: fileContent.chatId, data: dataString)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getFile failed for \(uuid): \(error.localizedDescription)")
            return FileValueResponse(value: nil)
        }
    }

    @MainActor
    private func listFiles(params: Any, message: UserScriptMessage) -> Encodable? {
        do {
            let files = try handler.listFiles()
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
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String else { return nil }
        do {
            try handler.deleteFile(uuid: uuid)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteFile failed for \(uuid): \(error.localizedDescription)")
        }
        return nil
    }

    @MainActor
    private func deleteAllFiles(params: Any, message: UserScriptMessage) -> Encodable? {
        do {
            try handler.deleteAllFiles()
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteAllFiles failed: \(error.localizedDescription)")
        }
        return nil
    }

    // MARK: - Migration Handlers

    @MainActor
    private func isMigrationDone(params: Any, message: UserScriptMessage) -> Encodable? {
        do {
            let done = try handler.isMigrationDone()
            return MigrationDoneResponse(value: done)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: isMigrationDone failed: \(error.localizedDescription)")
            return MigrationDoneResponse(value: false)
        }
    }

    @MainActor
    private func markMigrationDone(params: Any, message: UserScriptMessage) -> Encodable? {
        do {
            try handler.markMigrationDone()
            Logger.aiChat.debug("DuckAiNativeStorage: migration marked as done")
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

private struct GetFileResponse: Encodable {
    let uuid: String
    let chatId: String
    let data: String
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
