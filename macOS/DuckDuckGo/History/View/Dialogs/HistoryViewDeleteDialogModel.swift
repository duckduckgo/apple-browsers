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

protocol HistoryViewDeleteDialogSettingsPersisting: AnyObject {
    var shouldBurnHistoryWhenDeleting: Bool { get set }
}

final class UserDefaultsHistoryViewDeleteDialogSettingsPersistor: HistoryViewDeleteDialogSettingsPersisting {
    enum Keys {
        static let shouldBurnHistoryWhenDeleting = "history.delete.should-burn"
    }

    private let keyValueStore: KeyValueStoring

    init(_ keyValueStore: KeyValueStoring = UserDefaults.standard) {
        self.keyValueStore = keyValueStore
    }

    var shouldBurnHistoryWhenDeleting: Bool {
        get { return keyValueStore.object(forKey: Keys.shouldBurnHistoryWhenDeleting) as? Bool ?? true }
        set { keyValueStore.set(newValue, forKey: Keys.shouldBurnHistoryWhenDeleting) }
    }
}

final class HistoryViewDeleteDialogModel: ObservableObject {
    enum Response {
        case unknown, noAction, delete, burn
    }

    enum DeleteMode: Equatable {
        case all, today, yesterday, date(Date), formattedDate(String), unspecified

        var date: Date? {
            guard case let .date(date) = self else {
                return nil
            }
            return date
        }
    }

    var title: String {
        switch mode {
        case .all:
            return UserText.deleteAllHistory
        case .today:
            return UserText.deleteAllHistoryFromToday
        case .yesterday:
            return UserText.deleteAllHistoryFromYesterday
        case .unspecified:
            return UserText.deleteHistory
        case .date(let date):
            return UserText.deleteHistory(for: Self.dateFormatter.string(from: date))
        case .formattedDate(let stringDate):
            return UserText.deleteHistory(for: stringDate)
        }
    }

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
    @Published private(set) var response: Response = .unknown

    init(
        entriesCount: Int,
        mode: DeleteMode = .unspecified,
        settingsPersistor: HistoryViewDeleteDialogSettingsPersisting = UserDefaultsHistoryViewDeleteDialogSettingsPersistor()
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
    }

    func cancel() {
        response = .noAction
    }

    func delete() {
        response = shouldBurn ? .burn : .delete
    }

    private let mode: DeleteMode
    private let settingsPersistor: HistoryViewDeleteDialogSettingsPersisting

    private static let dateFormatter: DateFormatter = {
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
