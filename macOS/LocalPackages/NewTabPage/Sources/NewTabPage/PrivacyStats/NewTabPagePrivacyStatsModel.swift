//
//  NewTabPagePrivacyStatsModel.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

public enum NewTabPagePrivacyStatsEvent: Equatable {
    case showLess, showMore
}

/**
 * This protocol describes objects that can return Privacy Stats widget visibility.
 *
 * It's implemented by `NewTabPageProtectionsReportModel` and it's used to limit unnecessary
 * data processing when the widget is not present on New Tab Page.
 */
public protocol NewTabPagePrivacyStatsVisibilityProviding {
    /**
     * This property should return `true` if Privacy Stats widget is visible on the New Tab Page.
     */
    var isPrivacyStatsVisible: Bool { get }
}

public final class NewTabPagePrivacyStatsModel {

    let privacyStats: PrivacyStatsCollecting
    let statsUpdatePublisher: AnyPublisher<Void, Never>

    private var topCompanies: Set<String> = []
    private let trackerDataProvider: PrivacyStatsTrackerDataProviding
    private let visibilityProvider: NewTabPagePrivacyStatsVisibilityProviding
    private let eventMapping: EventMapping<NewTabPagePrivacyStatsEvent>?

    private let statsUpdateSubject = PassthroughSubject<Void, Never>()
    private var cancellables: Set<AnyCancellable> = []

    public init(
        visibilityProvider: NewTabPagePrivacyStatsVisibilityProviding,
        privacyStats: PrivacyStatsCollecting,
        trackerDataProvider: PrivacyStatsTrackerDataProviding,
        eventMapping: EventMapping<NewTabPagePrivacyStatsEvent>? = nil
    ) {
        self.visibilityProvider = visibilityProvider
        self.privacyStats = privacyStats
        self.trackerDataProvider = trackerDataProvider
        self.eventMapping = eventMapping

        statsUpdatePublisher = statsUpdateSubject.eraseToAnyPublisher()

        privacyStats.statsUpdatePublisher
            .filter { [weak self] in
                self?.visibilityProvider.isPrivacyStatsVisible == true
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.statsUpdateSubject.send()
            }
            .store(in: &cancellables)

        trackerDataProvider.trackerDataUpdatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.refreshTopCompanies()
            }
            .store(in: &cancellables)

        refreshTopCompanies()
    }

    func showLess() {
        eventMapping?.fire(.showLess)
    }

    func showMore() {
        eventMapping?.fire(.showMore)
    }

    func calculateTotalCount() async -> Int64 {
        await privacyStats.fetchPrivacyStatsTotalCount()
    }

    func calculatePrivacyStats() async -> NewTabPageDataModel.PrivacyStatsData {
        let stats = await privacyStats.fetchPrivacyStats()

        var otherCount: Int64 = 0

        var companiesStats: [NewTabPageDataModel.TrackerCompany] = stats.compactMap { key, value in
            guard topCompanies.contains(key) else {
                otherCount += value
                return nil
            }
            return NewTabPageDataModel.TrackerCompany(count: value, displayName: key)
        }

        if otherCount > 0 {
            companiesStats.append(.otherCompanies(count: otherCount))
        }
        return NewTabPageDataModel.PrivacyStatsData(trackerCompanies: companiesStats)
    }

    private func refreshTopCompanies() {
        struct TrackerWithPrevalence {
            let name: String
            let prevalence: Double
        }

        let trackers: [TrackerWithPrevalence] = trackerDataProvider.trackerData.entities.values.compactMap { entity in
            guard let displayName = entity.displayName, let prevalence = entity.prevalence else {
                return nil
            }
            return TrackerWithPrevalence(name: displayName, prevalence: prevalence)
        }

        let topTrackersArray = trackers.sorted(by: { $0.prevalence > $1.prevalence }).prefix(Const.maxTopCompaniesCount).map(\.name)
        Logger.privacyStats.debug("top tracker companies: \(topTrackersArray)")
        topCompanies = Set(topTrackersArray)
    }

    private enum Const {
        /**
         * This number is arbitrary, we decided to only show up to 100 most popular companies
         * while putting all others into "Other companies" bucket. FWIW, at the time of writing
         * this there are 831 companies in total in the Tracker Data Set.
         */
        static let maxTopCompaniesCount: Int = 100
    }
}
