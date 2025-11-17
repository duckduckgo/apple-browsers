//
//  AIChatMigrationStore.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
//
//  Shared logic for handling AIChat migration data across iOS and macOS.
//
//  This code is platform-agnostic and intentionally thread-unsafe because
//  the message handlers are guaranteed to receive on the main actor.
//

import Foundation

/// Migration data payload transferred between web and native during migration flows.
public struct AIChatMigrationData: Codable, Equatable {
    public let serializedMigrationFile: String?
    public init(serializedMigrationFile: String?) {
        self.serializedMigrationFile = serializedMigrationFile
    }
}

/// Simple OK response payload used by user-script handlers.
public struct AIChatOKResponse: Codable, Equatable {
    public let ok: Bool
    public init(ok: Bool = true) { self.ok = ok }
}

/// Count response payload used to return number of stored migration items.
public struct AIChatCountResponse: Codable, Equatable {
    public let count: Int
    public init(count: Int) { self.count = count }
}

/// Error payload used by user-script handlers when a request cannot be fulfilled.
public struct AIChatErrorResponse: Codable, Equatable {
    public let ok: Bool
    public let reason: String
    public init(reason: String) {
        self.ok = false
        self.reason = reason
    }
}

/// In-memory store for AI Chat migration data exchanged via user-script handlers.
public final class AIChatMigrationStore {
    private var items: [AIChatMigrationData] = []

    public init() {}

    /// Append a new serialized migration file to the in-memory list.
    /// - Parameter serialized: The string content of the migration file.
    /// - Returns: `AIChatOKResponse` indicating success.
    @discardableResult
    public func store(_ serialized: String?) -> AIChatOKResponse {
        items.append(AIChatMigrationData(serializedMigrationFile: serialized))
        return AIChatOKResponse()
    }

    /// Return the item at `index` if it exists, otherwise `nil`.
    /// - Parameter index: The zero-based index of the stored migration item.
    /// - Returns: The `AIChatMigrationData` at the given index, or `nil` if out of bounds or `index` is `nil`.
    public func item(at index: Int?) -> AIChatMigrationData? {
        guard let index, index >= 0, index < items.count else {
            return nil
        }
        return items[index]
    }

    /// Return the current count of stored items.
    /// - Returns: `AIChatCountResponse` containing the number of stored migration items.
    public func info() -> AIChatCountResponse {
        return AIChatCountResponse(count: items.count)
    }

    /// Remove all stored migration items.
    /// - Returns: `AIChatOKResponse` indicating success.
    @discardableResult
    public func clear() -> AIChatOKResponse {
        items.removeAll()
        return AIChatOKResponse()
    }
}

/// Parameter keys expected from user-script messages related to migration.
public enum AIChatMigrationParamKeys {
    public static let serializedMigrationFile = "serializedMigrationFile"
    public static let index = "index"
}
