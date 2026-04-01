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
        try? handler.putSetting(key: key, value: value)
        return nil
    }

    @MainActor
    private func getSetting(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String else { return nil }
        let value = try? handler.getSetting(key: key)
        return SettingValueResponse(value: AnyCodableValue(value ?? NSNull()))
    }

    @MainActor
    private func getAllSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let settings = try? handler.getAllSettings() else {
            return AllSettingsResponse(settings: [:])
        }
        return AllSettingsResponse(settings: settings.mapValues { AnyCodableValue($0) })
    }

    @MainActor
    private func deleteSetting(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String else { return nil }
        try? handler.deleteSetting(key: key)
        return nil
    }

    @MainActor
    private func deleteAllSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        try? handler.deleteAllSettings()
        return nil
    }

    @MainActor
    private func replaceAllSettings(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let settings = dict["settings"] as? [String: Any] else { return nil }
        try? handler.replaceAllSettings(settings)
        return nil
    }

    // MARK: - Chat Handlers

    @MainActor
    private func putChat(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let chatId = dict["chatId"] as? String,
              let data = dict["data"] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: data) else { return nil }
        try? handler.putChat(chatId: chatId, data: jsonData)
        return nil
    }

    @MainActor
    private func getAllChats(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let chatRecords = try? handler.getAllChats() else {
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
        try? handler.deleteChat(chatId: chatId)
        return nil
    }

    @MainActor
    private func deleteAllChats(params: Any, message: UserScriptMessage) -> Encodable? {
        try? handler.deleteAllChats()
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
        try? handler.putFile(uuid: uuid, chatId: chatId, data: data)
        return nil
    }

    @MainActor
    private func getFile(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String else { return nil }
        guard let fileContent = try? handler.getFile(uuid: uuid) else {
            return FileValueResponse(value: nil)
        }
        let dataString = String(data: fileContent.data, encoding: .utf8) ?? ""
        return GetFileResponse(uuid: fileContent.uuid, chatId: fileContent.chatId, data: dataString)
    }

    @MainActor
    private func listFiles(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let files = try? handler.listFiles() else {
            return ListFilesResponse(files: [])
        }
        return ListFilesResponse(files: files.map {
            FileMetadataResponse(uuid: $0.uuid, chatId: $0.chatId, dataSize: $0.dataSize)
        })
    }

    @MainActor
    private func deleteFile(params: Any, message: UserScriptMessage) -> Encodable? {
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String else { return nil }
        try? handler.deleteFile(uuid: uuid)
        return nil
    }

    @MainActor
    private func deleteAllFiles(params: Any, message: UserScriptMessage) -> Encodable? {
        try? handler.deleteAllFiles()
        return nil
    }

    // MARK: - Migration Handlers

    @MainActor
    private func isMigrationDone(params: Any, message: UserScriptMessage) -> Encodable? {
        let done = (try? handler.isMigrationDone()) ?? false
        return MigrationDoneResponse(value: done)
    }

    @MainActor
    private func markMigrationDone(params: Any, message: UserScriptMessage) -> Encodable? {
        try? handler.markMigrationDone()
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
