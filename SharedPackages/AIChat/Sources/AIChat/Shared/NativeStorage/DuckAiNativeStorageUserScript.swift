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

    private static let unavailableFireModeHandler: DuckAiNativeStorageHandling = NullDuckAiNativeStorageHandler()

    private let diskHandler: DuckAiNativeStorageHandling
    private let pixelFiring: DuckAiNativeStoragePixelFiring
    private let storageQueue = DispatchQueue(label: "com.duckduckgo.native-storage", qos: .userInitiated)
    private var didLogUnavailableFireModeHandler = false

    /// Returns the fire-mode storage state for the surrounding webview.
    /// `.notFireMode` uses the normal on-disk store, `.available` uses the isolated
    /// fire-mode handler, and `.unavailable` resolves to empty storage rather than
    /// falling back to disk.
    public var fireModeStorageProvider: (() -> DuckAiFireModeStorage)?

    private var handler: DuckAiNativeStorageHandling {
        switch fireModeStorageProvider?() ?? .notFireMode {
        case .notFireMode:
            return diskHandler
        case .unavailable:
            if !didLogUnavailableFireModeHandler {
                didLogUnavailableFireModeHandler = true
                Logger.aiChat.error("[NativeStorage] Fire-mode handler unavailable; using null storage to preserve mode isolation")
            }
            return Self.unavailableFireModeHandler
        case .available(let fireModeHandler):
            return fireModeHandler
        }
    }

    // MARK: - Initialization

    public init(
        handler: DuckAiNativeStorageHandling,
        originRules: [HostnameMatchingRule],
        pixelFiring: DuckAiNativeStoragePixelFiring = NullDuckAiNativeStoragePixelFiring()
    ) {
        self.diskHandler = handler
        self.pixelFiring = pixelFiring
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
        // Entries
        case .putEntry: return putEntry
        case .getEntry: return getEntry
        case .getAllEntries: return getAllEntries
        case .deleteEntry: return deleteEntry
        case .deleteAllEntries: return deleteAllEntries
        case .replaceAllEntries: return replaceAllEntries

        // Chats
        case .putChat: return putChat
        case .putChats: return putChats
        case .getChat: return getChat
        case .getAllChats: return getAllChats
        case .deleteChat: return deleteChat
        case .deleteAllChats: return deleteAllChats

        // Files
        case .putFile: return putFile
        case .getFile: return getFile
        case .listFiles: return listFiles
        case .deleteFile: return deleteFile
        case .deleteFiles: return deleteFiles
        case .deleteAllFiles: return deleteAllFiles

        // Migration
        case .isMigrationDone: return isMigrationDone
        case .markMigrationDone: return markMigrationDone
        case .migrateChats: return migrateChats
        }
    }

    // MARK: - Background Storage Helper

    private func performStorageOperation<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            storageQueue.async {
                do {
                    let result = try operation()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Entry Handlers

    private func putEntry(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← putEntry called")
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String,
              let value = dict["value"] else {
            Logger.aiChat.error("DuckAiNativeStorage: putEntry — invalid params")
            return nil
        }
        do {
            try await performStorageOperation {
                try self.handler.putEntry(key: key, value: value)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: putEntry '\(key)' succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putEntry failed for key '\(key)': \(error.localizedDescription)")
            pixelFiring.fire(.settingsPutError(error))
        }
        return nil
    }

    private func getEntry(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← getEntry called")
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: getEntry — invalid params")
            return nil
        }
        do {
            let value = try await performStorageOperation {
                try self.handler.getEntry(key: key)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: getEntry '\(key)' → \(value == nil ? "nil" : "found")")
            return EntryValueResponse(value: AnyCodableValue(value ?? NSNull()))
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getEntry failed for key '\(key)': \(error.localizedDescription)")
            pixelFiring.fire(.settingsGetError(error))
            return EntryValueResponse(value: AnyCodableValue(NSNull()))
        }
    }

    private func getAllEntries(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← getAllEntries called")
        do {
            let entries = try await performStorageOperation {
                try self.handler.getAllEntries()
            }
            Logger.aiChat.debug("DuckAiNativeStorage: getAllEntries → \(entries.count) keys")
            return AllEntriesResponse(entries: entries.mapValues { AnyCodableValue($0) })
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getAllEntries failed: \(error.localizedDescription)")
            pixelFiring.fire(.settingsGetError(error))
            return AllEntriesResponse(entries: [:])
        }
    }

    private func deleteEntry(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteEntry called")
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: deleteEntry — invalid params")
            return nil
        }
        do {
            try await performStorageOperation {
                try self.handler.deleteEntry(key: key)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: deleteEntry '\(key)' succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteEntry failed for key '\(key)': \(error.localizedDescription)")
            pixelFiring.fire(.settingsDeleteError(error))
        }
        return nil
    }

    private func deleteAllEntries(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteAllEntries called")
        do {
            try await performStorageOperation {
                try self.handler.deleteAllEntries()
            }
            Logger.aiChat.debug("DuckAiNativeStorage: deleteAllEntries succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteAllEntries failed: \(error.localizedDescription)")
            pixelFiring.fire(.settingsDeleteError(error))
        }
        return nil
    }

    private func replaceAllEntries(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← replaceAllEntries called")
        guard let dict = params as? [String: Any],
              let entries = dict["entries"] as? [String: Any] else {
            Logger.aiChat.error("DuckAiNativeStorage: replaceAllEntries — invalid params")
            return nil
        }
        do {
            try await performStorageOperation {
                try self.handler.replaceAllEntries(entries)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: replaceAllEntries succeeded with \(entries.count) keys")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: replaceAllEntries failed: \(error.localizedDescription)")
            pixelFiring.fire(.settingsDeleteError(error))
        }
        return nil
    }

    // MARK: - Chat Handlers

    private func putChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← putChat called")
        guard let dict = params as? [String: Any],
              let chatId = dict["chatId"] as? String,
              let data = dict["data"] as? [String: Any],
              let jsonData = try? JSONSerialization.data(withJSONObject: data) else {
            Logger.aiChat.error("DuckAiNativeStorage: putChat — invalid params")
            return nil
        }
        do {
            try await performStorageOperation {
                try self.handler.putChat(chatId: chatId, data: jsonData)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: putChat '\(chatId)' succeeded (\(jsonData.count) bytes)")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putChat failed for \(chatId): \(error.localizedDescription)")
            pixelFiring.fire(.chatPutError(error))
        }
        return nil
    }

    private func putChats(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← putChats called")
        guard let dict = params as? [String: Any],
              let chatsArray = dict["chats"] as? [[String: Any]] else {
            Logger.aiChat.error("DuckAiNativeStorage: putChats — invalid params")
            return SuccessResponse(success: false)
        }
        let records: [DuckAiChatRecord] = chatsArray.compactMap { entry in
            guard let chatId = entry["chatId"] as? String, !chatId.isEmpty,
                  let data = entry["data"] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: data) else {
                return nil
            }
            return DuckAiChatRecord(chatId: chatId, data: jsonData)
        }
        do {
            try await performStorageOperation {
                try self.handler.putChats(records)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: putChats succeeded (\(records.count) chats)")
            return SuccessResponse(success: true)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putChats failed: \(error.localizedDescription)")
            pixelFiring.fire(.chatPutError(error))
            return SuccessResponse(success: false)
        }
    }

    private func getChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← getChat called")
        guard let dict = params as? [String: Any],
              let chatId = dict["chatId"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: getChat — invalid params")
            return GetChatResponse(chat: nil)
        }
        do {
            guard let record = try await performStorageOperation({
                try self.handler.getChat(chatId: chatId)
            }) else {
                Logger.aiChat.debug("DuckAiNativeStorage: getChat '\(chatId)' → not found")
                return GetChatResponse(chat: nil)
            }
            guard let obj = try? JSONSerialization.jsonObject(with: record.data) as? [String: Any] else {
                Logger.aiChat.error("DuckAiNativeStorage: getChat '\(chatId)' — stored data is not valid JSON")
                return GetChatResponse(chat: nil)
            }
            var dict = obj.mapValues { AnyCodableValue($0) }
            dict["chatId"] = AnyCodableValue(record.chatId)
            Logger.aiChat.debug("DuckAiNativeStorage: getChat '\(chatId)' → found (\(record.data.count) bytes)")
            return GetChatResponse(chat: dict)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getChat failed for \(chatId): \(error.localizedDescription)")
            pixelFiring.fire(.chatGetError(error))
            return GetChatResponse(chat: nil)
        }
    }

    private func getAllChats(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← getAllChats called")
        let chatRecords: [DuckAiChatRecord]
        do {
            chatRecords = try await performStorageOperation {
                try self.handler.getAllChats()
            }
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getAllChats failed: \(error.localizedDescription)")
            pixelFiring.fire(.chatGetError(error))
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

    private func deleteChat(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteChat called")
        guard let dict = params as? [String: Any],
              let chatId = dict["chatId"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: deleteChat — invalid params")
            return nil
        }
        do {
            try await performStorageOperation {
                try self.handler.deleteChat(chatId: chatId)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: deleteChat '\(chatId)' succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteChat failed for \(chatId): \(error.localizedDescription)")
            pixelFiring.fire(.chatDeleteError(error))
        }
        return nil
    }

    private func deleteAllChats(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteAllChats called")
        do {
            try await performStorageOperation {
                try self.handler.deleteAllChats()
            }
            Logger.aiChat.debug("DuckAiNativeStorage: deleteAllChats succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteAllChats failed: \(error.localizedDescription)")
            pixelFiring.fire(.chatDeleteError(error))
        }
        return nil
    }

    // MARK: - File Handlers

    private func putFile(params: Any, message: UserScriptMessage) async -> Encodable? {
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
            try await performStorageOperation {
                try self.handler.putFile(uuid: uuid, chatId: chatId, data: paramsData)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: putFile '\(uuid)' stored successfully")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: putFile failed for \(uuid): \(error.localizedDescription)")
            pixelFiring.fire(.filePutError(error))
        }
        return nil
    }

    private func getFile(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← getFile called")
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: getFile — invalid params")
            return nil
        }
        do {
            guard let fileContent = try await performStorageOperation({
                try self.handler.getFile(uuid: uuid)
            }) else {
                Logger.aiChat.debug("DuckAiNativeStorage: getFile '\(uuid)' → not found")
                return EntryValueResponse(value: AnyCodableValue(NSNull()))
            }
            // Return the stored JSON opaquely — preserves all FE fields exactly as stored
            guard let storedDict = try? JSONSerialization.jsonObject(with: fileContent.data) as? [String: Any] else {
                Logger.aiChat.error("DuckAiNativeStorage: getFile '\(uuid)' — stored data is not valid JSON")
                return nil
            }
            Logger.aiChat.debug("DuckAiNativeStorage: getFile '\(uuid)' → \(fileContent.data.count) bytes, keys: \(storedDict.keys.sorted().joined(separator: ", "))")
            return storedDict.mapValues { AnyCodableValue($0) }
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: getFile failed for \(uuid): \(error.localizedDescription)")
            pixelFiring.fire(.fileGetError(error))
            return nil
        }
    }

    private func listFiles(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← listFiles called")
        do {
            let files = try await performStorageOperation {
                try self.handler.listFiles()
            }
            Logger.aiChat.debug("DuckAiNativeStorage: listFiles → \(files.count) files")
            return ListFilesResponse(files: files.map {
                FileMetadataResponse(uuid: $0.uuid, chatId: $0.chatId, dataSize: $0.dataSize)
            })
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: listFiles failed: \(error.localizedDescription)")
            pixelFiring.fire(.fileListError(error))
            return ListFilesResponse(files: [])
        }
    }

    private func deleteFile(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteFile called")
        guard let dict = params as? [String: Any],
              let uuid = dict["uuid"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: deleteFile — invalid params")
            return nil
        }
        do {
            try await performStorageOperation {
                try self.handler.deleteFile(uuid: uuid)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: deleteFile '\(uuid)' succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteFile failed for \(uuid): \(error.localizedDescription)")
            pixelFiring.fire(.fileDeleteError(error))
        }
        return nil
    }

    private func deleteFiles(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteFiles called")
        guard let dict = params as? [String: Any],
              let chatId = dict["chatId"] as? String, !chatId.isEmpty else {
            Logger.aiChat.error("DuckAiNativeStorage: deleteFiles — invalid params (missing chatId)")
            return nil
        }
        do {
            try await performStorageOperation {
                try self.handler.deleteFiles(chatId: chatId)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: deleteFiles '\(chatId)' succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteFiles failed for \(chatId): \(error.localizedDescription)")
            pixelFiring.fire(.fileDeleteError(error))
        }
        return nil
    }

    private func deleteAllFiles(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← deleteAllFiles called")
        do {
            try await performStorageOperation {
                try self.handler.deleteAllFiles()
            }
            Logger.aiChat.debug("DuckAiNativeStorage: deleteAllFiles succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: deleteAllFiles failed: \(error.localizedDescription)")
            pixelFiring.fire(.fileDeleteError(error))
        }
        return nil
    }

    // MARK: - Migration Handlers

    private func isMigrationDone(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← isMigrationDone called")
        guard let dict = params as? [String: Any],
              let key = dict["key"] as? String else {
            Logger.aiChat.error("DuckAiNativeStorage: isMigrationDone — invalid params (missing key)")
            return MigrationDoneResponse(value: false)
        }
        do {
            let done = try await performStorageOperation {
                try self.handler.isMigrationDone(key: key)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: isMigrationDone('\(key)') → \(done)")
            if done {
                pixelFiring.fire(.migrationAlreadyDone)
            }
            return MigrationDoneResponse(value: done)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: isMigrationDone failed: \(error.localizedDescription)")
            pixelFiring.fire(.migrationError(error))
            return MigrationDoneResponse(value: false)
        }
    }

    private func markMigrationDone(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← markMigrationDone called")
        pixelFiring.fire(.migrationStarted)
        let key = (params as? [String: Any])?["key"] as? String ?? ""
        guard !key.isEmpty else {
            Logger.aiChat.error("DuckAiNativeStorage: markMigrationDone — invalid params (missing key)")
            pixelFiring.fire(.migrationDoneBlankKey)
            return nil
        }
        do {
            try await performStorageOperation {
                try self.handler.markMigrationDone(key: key)
            }
            pixelFiring.fire(.migrationDone(key: key))
            Logger.aiChat.debug("DuckAiNativeStorage: markMigrationDone('\(key)') succeeded")
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: markMigrationDone failed: \(error.localizedDescription)")
            pixelFiring.fire(.migrationError(error))
        }
        return nil
    }

    private func migrateChats(params: Any, message: UserScriptMessage) async -> Encodable? {
        Logger.aiChat.debug("DuckAiNativeStorage: ← migrateChats called")
        guard let dict = params as? [String: Any],
              let chatsArray = dict["chats"] as? [[String: Any]] else {
            Logger.aiChat.error("DuckAiNativeStorage: migrateChats — invalid params")
            return SuccessResponse(success: false)
        }
        let records: [DuckAiChatRecord] = chatsArray.compactMap { entry in
            guard let chatId = entry["chatId"] as? String, !chatId.isEmpty,
                  let data = entry["data"] as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: data) else {
                return nil
            }
            return DuckAiChatRecord(chatId: chatId, data: jsonData)
        }
        do {
            try await performStorageOperation {
                try self.handler.putChats(records)
            }
            Logger.aiChat.debug("DuckAiNativeStorage: migrateChats succeeded (\(records.count) chats)")
            return SuccessResponse(success: true)
        } catch {
            Logger.aiChat.error("DuckAiNativeStorage: migrateChats failed: \(error.localizedDescription)")
            return SuccessResponse(success: false)
        }
    }
}

// MARK: - Response Models

private struct EntryValueResponse: Encodable {
    let value: AnyCodableValue?
}

private struct AllEntriesResponse: Encodable {
    let entries: [String: AnyCodableValue]
}

private struct AllChatsResponse: Encodable {
    let chats: [[String: AnyCodableValue]]
}

private struct GetChatResponse: Encodable {
    let chat: [String: AnyCodableValue]?
}

private struct FileMetadataResponse: Encodable {
    let uuid: String
    let chatId: String
    let dataSize: Int
}

private struct ListFilesResponse: Encodable {
    let files: [FileMetadataResponse]
}

private struct SuccessResponse: Encodable {
    let success: Bool
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
