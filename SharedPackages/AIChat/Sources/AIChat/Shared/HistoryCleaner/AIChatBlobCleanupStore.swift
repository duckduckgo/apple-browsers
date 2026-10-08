//
//  AIChatBlobCleanupStore.swift
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

/// Remembers that the leftover IndexedDB blob files were removed, so the cleanup runs once.
public protocol AIChatBlobCleanupStoring: AnyObject {
    var hasCompletedCleanup: Bool { get set }
}

public final class AIChatBlobCleanupStore: AIChatBlobCleanupStoring {

    enum Key: String {
        case hasCompletedCleanup = "aichat.indexeddb-blob-cleanup.completed"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    public init(keyValueStore: ThrowingKeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    public var hasCompletedCleanup: Bool {
        get { (try? keyValueStore.object(forKey: Key.hasCompletedCleanup.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.hasCompletedCleanup.rawValue) }
    }
}
