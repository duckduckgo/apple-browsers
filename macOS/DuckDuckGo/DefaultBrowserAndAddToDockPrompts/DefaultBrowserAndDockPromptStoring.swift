//
//  DefaultBrowserAndDockPromptStoring.swift
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
import Common

// MARK: - Legacy Store

protocol DefaultBrowserAndDockPromptLegacyStoring {
    func setPromptShown(_ shown: Bool)
    func didShowPrompt() -> Bool
}

final class DefaultBrowserAndDockPromptLegacyStore: DefaultBrowserAndDockPromptLegacyStoring {
    private static let promptShownKey = "DefaultBrowserAndDockPromptShown"

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func setPromptShown(_ shown: Bool) {
        userDefaults.set(shown, forKey: Self.promptShownKey)
    }

    func didShowPrompt() -> Bool {
        userDefaults.bool(forKey: Self.promptShownKey)
    }
}

// MARK: - New Store

protocol DefaultBrowserAndDockPromptStorageReading {
    var popoverShownDate: TimeInterval? { get }
    var bannerShownDate: TimeInterval? { get }
    var bannerShownOccurrences: Int { get }
    var isBannerPermanentlyDismissed: Bool { get }
}

protocol DefaultBrowserAndDockPromptStorageWriting: AnyObject {
    var popoverShownDate: TimeInterval? { get set }
    var bannerShownDate: TimeInterval? { get set }
    var isBannerPermanentlyDismissed: Bool { get set }
}

extension DefaultBrowserAndDockPromptStorageReading {

    var hasSeenPopover: Bool {
        popoverShownDate != nil
    }

    var hasSeenBanner: Bool {
        bannerShownDate != nil
    }

}

typealias DefaultBrowserAndDockPromptStorage = DefaultBrowserAndDockPromptStorageReading & DefaultBrowserAndDockPromptStorageWriting

final class DefaultBrowserAndDockPromptKeyValueStore: DefaultBrowserAndDockPromptStorage {

    enum StorageKey: String {
        case popoverShownDate = "com.duckduckgo.defaultBrowseAndDockPrompt.popoverShownDate"
        case bannerShownDate = "com.duckduckgo.defaultBrowseAndDockPrompt.bannerShownDate"
        case bannerShownOccurrences = "com.duckduckgo.defaultBrowseAndDockPrompt.bannerShownOccurrences"
        case bannerPermanentlyDismissed = "com.duckduckgo.defaultBrowseAndDockPrompt.bannerPermanentlyDismissed"
    }

    private let keyValueStoring: ThrowingKeyValueStoring
    private let eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent>

    init(
        keyValueStoring: ThrowingKeyValueStoring,
        eventMapper: EventMapping<DefaultBrowserAndDockPromptDebugEvent> = DefaultBrowserAndDockPromptDebugEventMapper.eventHandler
    ) {
        self.keyValueStoring = keyValueStoring
        self.eventMapper = eventMapper
    }

    var popoverShownDate: TimeInterval? {
        get {
            getValue(forKey: .popoverShownDate)
        }
        set {
            write(value: newValue, forKey: .popoverShownDate)
        }
    }

    var bannerShownDate: TimeInterval? {
        get {
            getValue(forKey: .bannerShownDate)
        }
        set {
            write(value: newValue, forKey: .bannerShownDate)
            // If value is not nil store the occurrence of the banner
            let numberOfBannersShown = newValue != nil ? bannerShownOccurrences + 1 : 0
            write(value: numberOfBannersShown, forKey: .bannerShownOccurrences)
        }
    }

    var isBannerPermanentlyDismissed: Bool {
        get {
            getValue(forKey: .bannerPermanentlyDismissed) ?? false
        }
        set {
            write(value: newValue, forKey: .bannerPermanentlyDismissed)
        }
    }

    var bannerShownOccurrences: Int {
        get {
            getValue(forKey: .bannerShownOccurrences) ?? 0
        }
        set {
            write(value: newValue, forKey: .bannerShownOccurrences)
        }
    }

    private func getValue<T>(forKey key: StorageKey) -> T? {
        do {
            return try keyValueStoring.object(forKey: key.rawValue) as? T
        } catch {
            eventMapper.fire(.storage(.failedToRetrieveValue(.init(key: key, error: error))))
            return nil
        }
    }

    private func write<T>(value: T?, forKey key: StorageKey) {
        do {
            try keyValueStoring.set(value, forKey: key.rawValue)
        } catch {
            eventMapper.fire(.storage(.failedToSaveValue(.init(key: key, error: error))))
        }
    }
}

// MARK: - Helpers

private extension DefaultBrowserAndDockPromptDebugEvent.Storage.Value {

    init(key: DefaultBrowserAndDockPromptKeyValueStore.StorageKey, error: Error) {
        switch key {
        case .popoverShownDate:
            self = .popoverShownDate(error)
        case .bannerShownDate:
            self = .bannerShownDate(error)
        case .bannerShownOccurrences:
            self = .bannerShownOccurrences(error)
        case .bannerPermanentlyDismissed:
            self = .permanentlyDismissPrompt(error)
        }
    }

}
