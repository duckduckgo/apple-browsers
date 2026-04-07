//
//  DuckAiNativeStorageProvider.swift
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

import DuckAiDataStore
import Foundation
import os.log
import Persistence

/// Creates and holds the shared DuckAiNativeStorage handler and its backing stores.
///
/// The handler must be shared because `KeyValueFileStore` enforces single-file access —
/// creating multiple instances for the same path crashes. Since `UserScripts` is instantiated
/// per tab, the stores must be created once at app level and shared across all tabs.
public final class DuckAiNativeStorageProvider {

    public static let directoryName = "DuckAiNativeStorage"

    public let handler: DuckAiNativeStorageHandling

    public init(containerURL: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: containerURL, withIntermediateDirectories: true)

        let settingsStore = try KeyValueFileStore(
            location: containerURL,
            name: "settings.plist"
        )
        let dataStore = try DuckAiNativeDataStore(
            databaseURL: containerURL.appendingPathComponent("chats.db"),
            filesDirectoryURL: containerURL.appendingPathComponent("files")
        )
        self.handler = DuckAiNativeStorageHandler(
            settingsStore: settingsStore.throwingKeyedStoring(),
            dataStore: dataStore
        )
        Logger.aiChat.debug("DuckAiNativeStorageProvider: Initialized at \(containerURL.path)")
    }
}
