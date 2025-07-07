//
//  NewTabPageProtectionsReportModel.swift
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

import Combine
import Common
import Foundation
import os.log
import Persistence
import PrivacyStats

public protocol NewTabPageProtectionsReportSettingsPersisting: AnyObject {
    var activeFeed: NewTabPageDataModel.Feed { get set }
    var isViewExpanded: Bool { get set }
}

final class UserDefaultsNewTabPageProtectionsReportSettingsPersistor: NewTabPageProtectionsReportSettingsPersisting {
    enum Keys {
        static let isViewExpanded = "new-tab-page.protection-report.is-view-expanded"
        static let activeFeed = "new-tab-page.protection-report.active-feed"
    }

    private let keyValueStore: ThrowingKeyValueStoring

    init(
        _ keyValueStore: ThrowingKeyValueStoring,
        getLegacyIsViewExpanded: @autoclosure () -> Bool?,
        getLegacyActiveFeed: @autoclosure () -> NewTabPageDataModel.Feed?
    ) {
        self.keyValueStore = keyValueStore
        migrateFromLegacyIsViewExpandedSetting(using: getLegacyIsViewExpanded)
        migrateFromLegacyActiveFeedSetting(using: getLegacyActiveFeed)
    }

    var isViewExpanded: Bool {
        get { return (try? keyValueStore.object(forKey: Keys.isViewExpanded) as? Bool) ?? true }
        set { try? keyValueStore.set(newValue, forKey: Keys.isViewExpanded) }
    }

    var activeFeed: NewTabPageDataModel.Feed {
        get { return (try? keyValueStore.object(forKey: Keys.activeFeed) as? String).flatMap(NewTabPageDataModel.Feed.init) ?? .privacyStats }
        set { try? keyValueStore.set(newValue.rawValue, forKey: Keys.activeFeed)}
    }

    private func migrateFromLegacyIsViewExpandedSetting(using getLegacyIsViewExpanded: () -> Bool?) {
        guard (try? keyValueStore.object(forKey: Keys.isViewExpanded)) == nil, let legacyIsViewExpanded = getLegacyIsViewExpanded() else {
            return
        }
        isViewExpanded = legacyIsViewExpanded
    }

    private func migrateFromLegacyActiveFeedSetting(using getLegacyActiveFeed: () -> NewTabPageDataModel.Feed?) {
        guard (try? keyValueStore.object(forKey: Keys.activeFeed)) == nil, let legacyActiveFeed = getLegacyActiveFeed() else {
            return
        }
        activeFeed = legacyActiveFeed
    }
}

public final class NewTabPageProtectionsReportModel {

    let privacyStats: PrivacyStatsCollecting
    let statsUpdatePublisher: AnyPublisher<Void, Never>

    @Published var isViewExpanded: Bool {
        didSet {
            settingsPersistor.isViewExpanded = self.isViewExpanded
        }
    }

    @Published var activeFeed: NewTabPageDataModel.Feed {
        didSet {
            settingsPersistor.activeFeed = self.activeFeed
        }
    }

    /**
     * This property is public to provide data for the `.newTabPageShown` pixel.
     */
    @Published public private(set) var visibleFeed: NewTabPageDataModel.Feed?

    private let settingsPersistor: NewTabPageProtectionsReportSettingsPersisting

    private let statsUpdateSubject = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []

    public convenience init(
        privacyStats: PrivacyStatsCollecting,
        keyValueStore: ThrowingKeyValueStoring,
        getLegacyIsViewExpandedSetting: @autoclosure () -> Bool?,
        getLegacyActiveFeedSetting: @autoclosure () -> NewTabPageDataModel.Feed?
    ) {
        let settingsPersistor = UserDefaultsNewTabPageProtectionsReportSettingsPersistor(
            keyValueStore,
            getLegacyIsViewExpanded: getLegacyIsViewExpandedSetting(),
            getLegacyActiveFeed: getLegacyActiveFeedSetting()
        )
        self.init(privacyStats: privacyStats, settingsPersistor: settingsPersistor)
    }

    init(privacyStats: PrivacyStatsCollecting, settingsPersistor: NewTabPageProtectionsReportSettingsPersisting) {
        self.privacyStats = privacyStats
        self.settingsPersistor = settingsPersistor

        isViewExpanded = settingsPersistor.isViewExpanded
        activeFeed = settingsPersistor.activeFeed
        statsUpdatePublisher = statsUpdateSubject.eraseToAnyPublisher()
        visibleFeed = isViewExpanded ? activeFeed : nil

        Publishers.CombineLatest($isViewExpanded, $activeFeed)
            .sink { [weak self] isViewExpanded, activeFeed in
                self?.visibleFeed = isViewExpanded ? activeFeed : nil
            }
            .store(in: &cancellables)

        privacyStats.statsUpdatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statsUpdateSubject.send()
            }
            .store(in: &cancellables)
    }

    func calculateTotalCount() async -> Int64 {
        await privacyStats.fetchPrivacyStatsTotalCount()
    }
}

extension NewTabPageProtectionsReportModel: NewTabPagePrivacyStatsVisibilityProviding {
    public var isPrivacyStatsVisible: Bool {
        visibleFeed == .privacyStats
    }
}

extension NewTabPageProtectionsReportModel: NewTabPageRecentActivityVisibilityProviding {
    public var isRecentActivityVisible: Bool {
        visibleFeed == .activity
    }
}
