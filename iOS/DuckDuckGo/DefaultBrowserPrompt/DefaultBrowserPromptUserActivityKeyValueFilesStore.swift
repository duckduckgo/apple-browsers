//
//  DefaultBrowserPromptUserActivityKeyValueFilesStore.swift
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
import SetDefaultBrowserCore

final class DefaultBrowserPromptUserActivityKeyValueFilesStore: DefaultBrowserPromptUserActivityStorage {

    enum StorageKey {
        static let userActivity = "com.duckduckgo.defaultBrowserPrompt.userActivity"
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    private let keyValueFilesStore: ThrowingKeyValueStoring
    private let eventMapper: EventMapping<DefaultBrowserPromptUserActivityKeyValueFilesStore.DebugEvent>

    init(
        keyValueFilesStore: ThrowingKeyValueStoring,
        eventMapper: EventMapping<DefaultBrowserPromptUserActivityKeyValueFilesStore.DebugEvent> = DefaultBrowserPromptUserActivityKeyValueFilesStore.Mapper()
    ) {
        self.keyValueFilesStore = keyValueFilesStore
        self.eventMapper = eventMapper
    }

    func save(_ activity: DefaultBrowserPromptUserActivity) {
        do {
            let encodedActivity = try Self.encoder.encode(activity)
            try keyValueFilesStore.set(encodedActivity, forKey: StorageKey.userActivity)
        } catch {
            eventMapper.fire(.failedToSaveActivity, error: error)
        }
    }
    
    func deleteActivity() {
        do {
            try keyValueFilesStore.set(nil, forKey: StorageKey.userActivity)
        } catch {
            eventMapper.fire(.failedToDeleteActivity, error: error)
        }
    }
    
    func currentActivity() -> DefaultBrowserPromptUserActivity {
        do {
            guard let data = try keyValueFilesStore.object(forKey: StorageKey.userActivity) as? Data else { return .empty }
            return try Self.decoder.decode(DefaultBrowserPromptUserActivity.self, from: data)
        } catch {
            eventMapper.fire(.failedToRetrieveActivity, error: error)
            return DefaultBrowserPromptUserActivity.empty
        }
    }

}

// MARK: - Event Mapper

extension DefaultBrowserPromptUserActivityKeyValueFilesStore {

    enum DebugEvent {
        case failedToRetrieveActivity
        case failedToSaveActivity
        case failedToDeleteActivity
    }

    final class Mapper: EventMapping<DefaultBrowserPromptUserActivityKeyValueFilesStore.DebugEvent> {

        public init() {
            super.init { event, error, _, _ in
                switch event {
                case .failedToRetrieveActivity:
                    Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Retrieve Current Activity: \(error)")
                case .failedToSaveActivity:
                    Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Save Current Activity: \(error)")
                case .failedToDeleteActivity:
                    Logger.defaultBrowserPrompt.debug("[Default Browser Prompt] - Failed To Delete Current Activity: \(error)")
                }
            }
        }

        @available(*, unavailable, message: "Use init() instead")
        override init(mapping: @escaping EventMapping<DefaultBrowserPromptUserActivityKeyValueFilesStore.DebugEvent>.Mapping) {
            fatalError("Use init()")
        }
    }

}
