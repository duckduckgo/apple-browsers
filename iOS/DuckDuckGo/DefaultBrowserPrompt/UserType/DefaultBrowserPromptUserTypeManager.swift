//
//  DefaultBrowserPromptUserTypeManager.swift
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
import BrowserServicesKit
import Persistence
import class Common.EventMapping
import SetDefaultBrowserCore

final class DefaultBrowserPromptUserTypeManager {
    private let store: DefaultBrowserPromptUserTypeStoring
    private let statisticsStore: StatisticsStore

    init(store: DefaultBrowserPromptUserTypeStoring, statisticsStore: StatisticsStore = StatisticsUserDefaults()) {
        self.store = store
        self.statisticsStore = statisticsStore
    }

    func persistUserType() {
        // Save value only on first launch.
        guard store.userType() == nil else { return }

        let userType: DefaultBrowserPromptUserType = if statisticsStore.hasInstallStatistics {
            .existing
        } else if statisticsStore.variant == VariantIOS.returningUser.name {
            .returning
        } else {
            .new
        }
        store.save(userType: userType)
    }
}

// MARK: - DefaultBrowserPromptUserTypeProviding

extension DefaultBrowserPromptUserTypeManager: DefaultBrowserPromptUserTypeProviding {

    func currentUserType() -> DefaultBrowserPromptUserType? {
        store.userType()
    }

}

// MARK: - Store

protocol DefaultBrowserPromptUserTypeStoring: AnyObject {
    func userType() -> DefaultBrowserPromptUserType?
    func save(userType: DefaultBrowserPromptUserType)
}

final class DefaultBrowserPromptUserTypeStore: DefaultBrowserPromptUserTypeStoring {
    enum StorageKey {
        static let userType = "com.duckduckgo.defaultBrowserPrompt.userType"
    }

    private let keyValueFilesStore: ThrowingKeyValueStoring
    private let eventMapper: EventMapping<DefaultBrowserPromptUserTypeStore.DebugEvent>

    init(keyValueFilesStore: ThrowingKeyValueStoring, eventMapper: EventMapping<DefaultBrowserPromptUserTypeStore.DebugEvent> = DefaultBrowserPromptKeyValueFilesStorePixelHandlers.userTypeDebugPixelHandler) {
        self.keyValueFilesStore = keyValueFilesStore
        self.eventMapper = eventMapper
    }

    func userType() -> DefaultBrowserPromptUserType? {
        do {
            let rawValue = try keyValueFilesStore.object(forKey: StorageKey.userType) as? String
            return rawValue.flatMap(DefaultBrowserPromptUserType.init)
        } catch {
            // Fire an event
            eventMapper.fire(DebugEvent.failedToRetrieveUserType, error: error)
            return nil
        }
    }

    func save(userType: DefaultBrowserPromptUserType) {
        do {
            try keyValueFilesStore.set(userType.rawValue, forKey: StorageKey.userType)
        } catch {
            // Fire an event
            eventMapper.fire(DebugEvent.failedToSaveUserType, error: error)
        }
    }
}

extension DefaultBrowserPromptUserTypeStore {

    enum DebugEvent {
        case failedToRetrieveUserType
        case failedToSaveUserType
    }
}
