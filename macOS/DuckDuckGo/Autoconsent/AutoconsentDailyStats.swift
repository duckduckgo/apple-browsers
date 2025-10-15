//
//  AutoconsentDailyStats.swift
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
import PixelKit
import OSLog
import BrowserServicesKit
import FeatureFlags

protocol AutoconsentDailyStatsManaging {
    func incrementPopupCount()
    func sendDailyPixelIfNeeded()
}

final class AutoconsentDailyStats: AutoconsentDailyStatsManaging {

    private struct Constants {
        static let maxDaysToKeep = 7
        static let statsKey = "autoconsent_daily_stats"
    }

    private struct Stats: Codable {
        var counts: [Date: Int]
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let featureFlagger: FeatureFlagger
    private let currentDateProvider: () -> Date
    private let queue: DispatchQueue
    private let firePixel: (AutoconsentPixel, PixelKit.Frequency) -> Void

    init(keyValueStore: ThrowingKeyValueStoring,
         featureFlagger: FeatureFlagger,
         currentDateProvider: @escaping () -> Date = { Date() },
         queue: DispatchQueue = DispatchQueue(label: "com.duckduckgo.autoconsent.stats"),
         firePixel: @escaping (AutoconsentPixel, PixelKit.Frequency) -> Void = { PixelKit.fire($0, frequency: $1) }
    ) {
        self.keyValueStore = keyValueStore
        self.featureFlagger = featureFlagger
        self.currentDateProvider = currentDateProvider
        self.queue = queue
        self.firePixel = firePixel
    }

    private var dailyStats: [Date: Int] {
        get {
            do {
                guard let data = try keyValueStore.object(forKey: Constants.statsKey) as? Data,
                      let stats = try? JSONDecoder().decode(Stats.self, from: data) else {
                    return [:]
                }
                return stats.counts
            } catch {
                Logger.autoconsent.error("Failed to read daily stats: \(error.localizedDescription)")
                return [:]
            }
        }
        set {
            do {
                let stats = Stats(counts: newValue)
                let data = try JSONEncoder().encode(stats)
                try keyValueStore.set(data, forKey: Constants.statsKey)
            } catch {
                Logger.autoconsent.error("Failed to save daily stats: \(error.localizedDescription)")
            }
        }
    }

    func incrementPopupCount() {
        guard featureFlagger.isFeatureOn(.cpmCountPixel) else { return }
        queue.async {
            let today = self.startOfDay(for: self.currentDateProvider())
            self.dailyStats[today, default: 0] += 1
        }
    }

    private func cleanOldStats() {
        let today = self.startOfDay(for: self.currentDateProvider())

        var stats = self.dailyStats
        stats = stats.filter { date, _ in
            let days = Calendar.current.dateComponents([.day], from: date, to: today).day ?? 0
            return days <= Constants.maxDaysToKeep
        }
        self.dailyStats = stats
    }

    func sendDailyPixelIfNeeded() {
        guard featureFlagger.isFeatureOn(.cpmCountPixel) else { return }
        queue.async {
            let today = self.startOfDay(for: self.currentDateProvider())

            if self.dailyStats[today] == nil {
                self.dailyStats[today] = 0
            }

            // Get stats for last 7 days
            var params: [String: String] = [:]
            for daysAgo in 0..<Constants.maxDaysToKeep {
                if let date = Calendar.current.date(byAdding: .day, value: -(daysAgo + 1), to: today) {
                    let count = self.dailyStats[date] ?? -1
                    params["d\(daysAgo)"] = String(count)
                }
            }

            // Send pixel
            self.firePixel(AutoconsentPixel.popupManagedCount(params: params), .daily)

            // Remove old dates
            self.cleanOldStats()
        }
    }

    private func startOfDay(for date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }
}
