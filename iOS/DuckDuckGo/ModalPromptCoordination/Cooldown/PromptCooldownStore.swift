//
//  PromptCooldownStore.swift
//  DuckDuckGo
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

import Foundation
import Persistence
import class Common.EventMapping

/// A type that stores last prompt presentation date.
protocol PromptCooldownStore: AnyObject {
    /// The timestamp when a prompt was last presented to the user.
    /// Returns `nil` if no prompt has been presented yet.
    var lastPresentationTimestamp: TimeInterval? { get set }
}

final class PromptCooldownKeyValueFilesStore: PromptCooldownStore {

    enum StorageKey {
        static let lastPromptShownTimestamp = "com.duckduckgo.prompts.lastPromptShownTimestamp"
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let eventMapper: EventMapping<PromptCooldownKeyValueFilesStore.DebugEvent>

    init(keyValueStore: ThrowingKeyValueStoring, eventMapper: EventMapping<PromptCooldownKeyValueFilesStore.DebugEvent>) {
        self.keyValueStore = keyValueStore
        self.eventMapper = eventMapper
    }

    var lastPresentationTimestamp: TimeInterval? {
        get {
            do {
                return try keyValueStore.object(forKey: StorageKey.lastPromptShownTimestamp) as? TimeInterval
            } catch {
                eventMapper.fire(DebugEvent.failedToRetrieveLastPresentationTimestamp, error: error)
                return nil
            }
        }
        set {
            do {
                try keyValueStore.set(newValue, forKey: StorageKey.lastPromptShownTimestamp)
            } catch {
                eventMapper.fire(DebugEvent.failedToSaveLastPresentationTimestamp, error: error)
            }
        }
    }

}

extension PromptCooldownKeyValueFilesStore {

    enum DebugEvent {
        case failedToRetrieveLastPresentationTimestamp
        case failedToSaveLastPresentationTimestamp
    }
    
}
