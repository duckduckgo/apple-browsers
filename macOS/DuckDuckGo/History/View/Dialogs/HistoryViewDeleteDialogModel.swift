//
//  HistoryViewDeleteDialogModel.swift
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
import BrowserServicesKit

protocol HistoryViewDeleteDialogSettingsPersisting: AnyObject {
    var shouldBurnHistoryWhenDeleting: Bool { get set }
    var shouldClearChatHistoryWhenDeleting: Bool { get set }
}

final class UserDefaultsHistoryViewDeleteDialogSettingsPersistor: HistoryViewDeleteDialogSettingsPersisting {
    enum Keys {
        static let shouldBurnHistoryWhenDeleting = "history.delete.should-burn"
        static let shouldClearChatHistoryWhenDeleting = "history.delete.should-clear-chat"
    }

    private let keyValueStore: KeyValueStoring

    init(_ keyValueStore: KeyValueStoring = UserDefaults.standard,
         featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger) {
        self.keyValueStore = keyValueStore
    }

    var shouldBurnHistoryWhenDeleting: Bool {
        get { return keyValueStore.object(forKey: Keys.shouldBurnHistoryWhenDeleting) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Keys.shouldBurnHistoryWhenDeleting) }
    }

    var shouldClearChatHistoryWhenDeleting: Bool {
        get { return keyValueStore.object(forKey: Keys.shouldClearChatHistoryWhenDeleting) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Keys.shouldClearChatHistoryWhenDeleting) }
    }
}

final class HistoryViewDeleteDialogModel: ObservableObject {
    enum Response {
        case noAction, delete(includeChats: Bool), burn(includeChats: Bool)
    }

    enum DeleteMode: Equatable {
        case all, today, yesterday, date(Date), sites(Set<String>), older, unspecified

        var date: Date? {
            guard case let .date(date) = self else {
                return nil
            }
            return date
        }

        var title: String {
            switch self {
            case .all:
                return UserText.deleteAllHistory
            case .today:
                return UserText.deleteAllHistoryFromToday
            case .yesterday:
                return UserText.deleteAllHistoryFromYesterday
            case .older:
                return UserText.deleteOlderHistory
            case .unspecified:
                return UserText.deleteHistory
            case .date(let date):
                return UserText.deleteHistory(for: HistoryViewDeleteDialogModel.dateFormatter.string(from: date))
            case .sites(let domains) where domains.count == 1:
                return UserText.deleteHistory(for: domains.first!)
            case .sites:
                return UserText.deleteHistory
            }
        }

        var canClearChatHistory: Bool {
            switch self {
            case .all: return true
            case .today, .yesterday, .date, .sites, .older, .unspecified: return false
            }
        }
    }

    var title: String { mode.title }

    let message: String

    var dataClearingExplanation: String {
        switch mode {
        case .all, .today:
            return UserText.deleteCookiesAndSiteDataExplanationWithClosingTabs
        default:
            return UserText.deleteCookiesAndSiteDataExplanation
        }
    }

    @Published var shouldBurn: Bool {
        didSet {
            settingsPersistor.shouldBurnHistoryWhenDeleting = shouldBurn
        }
    }

    /// indicates whether the option to delete chat history should be shown
    let canClearChatHistory: Bool

    /// when true, chat history will also be deleted when deleting browsing history
    @Published var shouldClearChatHistory: Bool {
        didSet {
            settingsPersistor.shouldClearChatHistoryWhenDeleting = shouldClearChatHistory
        }
    }

    @Published private(set) var response: Response?

    init(
        entriesCount: Int,
        mode: DeleteMode,
        settingsPersistor: HistoryViewDeleteDialogSettingsPersisting = UserDefaultsHistoryViewDeleteDialogSettingsPersistor(),
        aiChatHistoryCleaner: AIChatHistoryCleaner = AIChatHistoryCleaner(featureFlagger: Application.appDelegate.featureFlagger,
                                                                          aiChatMenuConfiguration: Application.appDelegate.aiChatMenuConfiguration,
                                                                          featureDiscovery: DefaultFeatureDiscovery(),
                                                                          privacyConfig: Application.appDelegate.privacyFeatures.contentBlocking.privacyConfigurationManager)
    ) {
        self.message = {
            guard entriesCount > 1 else {
                return UserText.delete1HistoryItemMessage
            }
            let entriesCount = Self.numberFormatter.string(from: .init(value: entriesCount)) ?? String(entriesCount)
            return UserText.deleteHistoryMessage(items: entriesCount)
        }()
        self.mode = mode
        self.settingsPersistor = settingsPersistor
        shouldBurn = settingsPersistor.shouldBurnHistoryWhenDeleting
        let canClearChatHistory = mode.canClearChatHistory && aiChatHistoryCleaner.shouldDisplayCleanAIChatHistoryOption
        self.canClearChatHistory = canClearChatHistory
        shouldClearChatHistory = canClearChatHistory ? settingsPersistor.shouldClearChatHistoryWhenDeleting : false
    }

    func cancel() {
        response = .noAction
    }

    func delete() {
        if shouldBurn {
            response = .burn(includeChats: shouldClearChatHistory)
        } else {
            response = .delete(includeChats: shouldClearChatHistory)
        }
    }

    private let mode: DeleteMode
    private let settingsPersistor: HistoryViewDeleteDialogSettingsPersisting

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.formattingContext = .middleOfSentence
        return formatter
    }()

    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()
}
