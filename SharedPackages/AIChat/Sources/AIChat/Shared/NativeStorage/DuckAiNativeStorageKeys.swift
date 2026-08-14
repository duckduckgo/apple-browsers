//
//  DuckAiNativeStorageKeys.swift
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
import Persistence

public enum DuckAiNativeStorageKeyNames: String, StorageKeyDescribing {
    case migrationStatus = "duckAiNativeStorage-migrationStatus"
    case settings = "duckAiNativeStorage-settings"
}

public struct DuckAiNativeStorageSettings: StoringKeys {
    public init() {}

    public let migrationStatus = StorageKey<Data>(DuckAiNativeStorageKeyNames.migrationStatus)
    public let settings = StorageKey<Data>(DuckAiNativeStorageKeyNames.settings)
}

/// Well-known entry keys that carry a contract with the Duck.ai web app over the storage userscript bridge.
/// The direction differs per key — see each case.
public enum DuckAiNativeStorageReservedEntryKeys: String {
    /// Native-written, web-read via `getEntry`. Entry holding the JSON array of chat IDs deleted on the
    /// native side; the web app reads it to reconcile deletions it did not itself initiate. Value: `[String]`.
    case locallyDeletedChatIds

    /// Web-written via `putEntry`, native-read. Entry holding the Duck.ai usage-limit snapshot, rewritten by
    /// the web app on every usage-state update while it is running. Value: a JSON-encoded `String` of
    /// `{ daily?, weekly? }`, each window `{ percentUsed, resetsAt }`. Decode with `DuckAiUsageLimits.make`.
    case usageLimits
}
