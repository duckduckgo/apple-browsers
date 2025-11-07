//
//  AutoconsentDailyStatsTest.swift
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

import Common
import FeatureFlags
import Foundation
import PersistenceTestingUtils
import PixelKit
import Testing

@testable import DuckDuckGo_Privacy_Browser

@Suite("CPM - Daily Stats")
class AutoconsentDailyStatsTest {

    let today = Date()
    let startOfToday = Calendar.current.startOfDay(for: Date())
    let mockStore: MockKeyValueFileStore
    let calendar = Calendar.current
    var currentDate = Date()
    let featureFlagger: MockFeatureFlagger
    var firedPixel: AutoconsentPixel?
    var firedFrequency: PixelKit.Frequency?

    init() throws {
        mockStore = try MockKeyValueFileStore()
        featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFeatureFlags = [.cpmCountPixel]
    }

    private func startOfDay(for date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }

    func makeStat(firePixel: @escaping (AutoconsentPixel, PixelKit.Frequency) -> Void = { _, _ in }) -> AutoconsentDailyStats {
        return AutoconsentDailyStats(
            keyValueStore: mockStore,
            featureFlagger: featureFlagger,
            currentDateProvider: { self.currentDate },
            queue: DispatchQueue.main,
            firePixel: { pixel, frequency in
                self.firedPixel = pixel
                self.firedFrequency = frequency
            }
        )
    }

    private struct Stats: Codable {
        var counts: [Date: Int]
    }

    @Test("Check Increment Popup Count once when no data")
    func testIncrementPopupCountWhenNoDataSaved() throws {
        // Given
        let stats = makeStat()
        currentDate = today

        // When
        stats.incrementPopupCount()
        DispatchQueue.main.sync {}

        // Then
        let data = mockStore.underlyingDict["autoconsent_daily_stats"] as! Data
        let storedStats = try JSONDecoder().decode(Stats.self, from: data)
        #expect(storedStats.counts.count == 1)

        let todayStart = startOfDay(for: today)
        #expect(storedStats.counts[todayStart] == 1)
    }

    @Test("Check Multiple Increments")
    func testMultipleIncrements() throws {
        // Given
        let stats = makeStat()
        currentDate = today

        // When
        stats.incrementPopupCount()
        stats.incrementPopupCount()
        stats.incrementPopupCount()
        DispatchQueue.main.sync {}

        // Then
        let data = mockStore.underlyingDict["autoconsent_daily_stats"] as! Data
        let storedStats = try JSONDecoder().decode(Stats.self, from: data)
        let todayStart = startOfDay(for: today)
        #expect(storedStats.counts[todayStart] == 3)
    }

    @Test("Check Increments Across Multiple Days")
    func testIncrementsAcrossDays() throws {
        // Given
        let stats = makeStat()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        currentDate = yesterday

        stats.incrementPopupCount()
        stats.incrementPopupCount()
        DispatchQueue.main.sync {}

        // When
        currentDate = today
        stats.incrementPopupCount()
        DispatchQueue.main.sync {}

        // Then
        let data = mockStore.underlyingDict["autoconsent_daily_stats"] as! Data
        let storedStats = try JSONDecoder().decode(Stats.self, from: data)
        #expect(storedStats.counts.count == 2)

        let todayStart = startOfDay(for: today)
        let yesterdayStart = startOfDay(for: yesterday)

        #expect(storedStats.counts[todayStart] == 1, "Today should have 1 popup")
        #expect(storedStats.counts[yesterdayStart] == 2, "Yesterday should have 2 popups")
    }

    @Test("Check Send Daily Pixel")
    func testSendDailyPixelAndCleanOldStats() throws {
        // Given
        let stats = makeStat()

        // Create stats for days
        let initialStats = addStatsForDays(12)

        let initialData = try JSONEncoder().encode(Stats(counts: initialStats))
        mockStore.underlyingDict["autoconsent_daily_stats"] = initialData

        // When
        stats.sendDailyPixelIfNeeded()
        DispatchQueue.main.sync {}

        // Then
        #expect(firedFrequency == .daily)
        switch firedPixel {
        case .popupManagedCount(let firedParams):
            #expect(firedParams["d1"] == "1", "Wrong count for d1")
            #expect(firedParams["d2"] == "3", "Wrong count for d2")
            #expect(firedParams["d5"] == "15", "Wrong count for d5")
            #expect(firedParams["d10"] == "55", "Wrong count for d10")
        case let other:
            #expect(true == false, "Wrong pixel type: expected popupManagedCount but got \(String(describing: other))")
        }
    }

    @Test("Check Clean Old Stats")
    func testCleanOldStats() throws {
        // Given
        let stats = makeStat()
        currentDate = today

        // Add stats for last 3 days more than our day limit
        let initialStats = addStatsForDays(12)
        print(initialStats)
        let initialData = try JSONEncoder().encode(Stats(counts: initialStats))
        mockStore.underlyingDict["autoconsent_daily_stats"] = initialData

        stats.sendDailyPixelIfNeeded()
        DispatchQueue.main.sync {}

        // Then
        // Check old stats were cleaned up
        let finalData = mockStore.underlyingDict["autoconsent_daily_stats"] as! Data
        let finalStats = try JSONDecoder().decode(Stats.self, from: finalData)
        #expect(finalStats.counts.count == AutoconsentDailyStats.Constants.maxDaysToKeep + 1, "Should only keep last \(AutoconsentDailyStats.Constants.maxDaysToKeep) days of stats")

        // Verify we kept the most recent stats
        for i in 0..<AutoconsentDailyStats.Constants.maxDaysToKeep {
            guard let date = calendar.date(byAdding: .day, value: -i, to: startOfToday) else { continue }
            let dateStart = startOfDay(for: date)
            #expect(finalStats.counts[dateStart] == i, "Missing or incorrect value for day -\(i + 1)")
        }
    }

    private func addStatsForDays(_ days: Int) -> [Date: Int] {
        var stats: [Date: Int] = [:]
        for daysAgo in 0...days {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let dateStart = startOfDay(for: date)
            stats[dateStart] = daysAgo  // Value matches days ago
        }
        return stats
    }
}
