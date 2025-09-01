//
//  DefaultBrowserPromptActivityKeyValueFilesStore.swift
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
import Core
import class Common.EventMapping
import Persistence
import BrowserServicesKit
import SetDefaultBrowserCore

final class DefaultBrowserPromptActivityKeyValueFilesStore: DefaultBrowserPromptStorage {

    enum StorageKey: String {
        case lastModalShownDate = "com.duckduckgo.defaultBrowserPrompt.lastModalShownDate"
        case modalShownOccurrences = "com.duckduckgo.defaultBrowserPrompt.modalShownOccurrences"
        case promptPermanentlyDismissed = "com.duckduckgo.defaultBrowserPrompt.modalPermanentlyDismissed"
        case inactiveModalShown = "com.duckduckgo.defaultBrowserPrompt.inactiveModalShown"
    }

    private let keyValueFilesStore: ThrowingKeyValueStoring
    private let eventMapper: EventMapping<DefaultBrowserPromptActivityKeyValueFilesStore.DebugEvent>

    init(
        keyValueFilesStore: ThrowingKeyValueStoring,
        eventMapper: EventMapping<DefaultBrowserPromptActivityKeyValueFilesStore.DebugEvent> = DefaultBrowserPromptKeyValueFilesStorePixelHandlers.promptTypeDebugPixelHandler
    ) {
        self.keyValueFilesStore = keyValueFilesStore
        self.eventMapper = eventMapper
    }

    var lastModalShownDate: TimeInterval? {
        get {
            getValue(forKey: .lastModalShownDate)
        }
        set {
            write(value: newValue, forKey: .lastModalShownDate)
        }
    }

    var modalShownOccurrences: Int {
        get {
            getValue(forKey: .modalShownOccurrences) ?? 0
        }
        set {
            write(value: newValue, forKey: .modalShownOccurrences)
        }
    }

    var isPromptPermanentlyDismissed: Bool {
        get {
            getValue(forKey: .promptPermanentlyDismissed) ?? false
        }
        set {
            write(value: newValue, forKey: .promptPermanentlyDismissed)
        }
    }

    var hasInactiveModalShown: Bool {
        get {
            getValue(forKey: .inactiveModalShown) ?? false
        }
        set {
            write(value: newValue, forKey: .inactiveModalShown)
        }
    }

    private func getValue<T>(forKey key: StorageKey) -> T? {
        do {
            return try keyValueFilesStore.object(forKey: key.rawValue) as? T
        } catch {
            eventMapper.fire(.failedToRetrieveValue(.init(key: key, error: error)))
            return nil
        }
    }

    private func write<T>(value: T?, forKey key: StorageKey) {
        do {
            try keyValueFilesStore.set(value, forKey: key.rawValue)
        } catch {
            eventMapper.fire(.failedToSaveValue(.init(key: key, error: error)))
        }
    }

}

// MARK: - Event Mapper

extension DefaultBrowserPromptActivityKeyValueFilesStore {

    enum DebugEvent {
        enum Value {
            case lastModalShownDate(Error)
            case modalShownOccurrences(Error)
            case permanentlyDismissPrompt(Error)
            case inactiveModalShown(Error)
        }

        case failedToRetrieveValue(Value)
        case failedToSaveValue(Value)
    }

}

// MARK: - Helpers

private extension DefaultBrowserPromptActivityKeyValueFilesStore.DebugEvent.Value {

    init(key: DefaultBrowserPromptActivityKeyValueFilesStore.StorageKey, error: Error) {
        switch key {
        case .lastModalShownDate:
            self = .lastModalShownDate(error)
        case .modalShownOccurrences:
            self = .modalShownOccurrences(error)
        case .promptPermanentlyDismissed:
            self = .permanentlyDismissPrompt(error)
        case .inactiveModalShown:
            self = .inactiveModalShown(error)
        }
    }

}
