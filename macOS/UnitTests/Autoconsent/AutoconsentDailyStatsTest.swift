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

import Testing
import Common
import PixelKit
import PersistenceTestingUtils
@testable import DuckDuckGo_Privacy_Browser

@Suite("CPM - Daily Stats")
class AutoconsentDailyStatsTest {

    let today = Date()
    let startOfToday = Calendar.current.startOfDay(for: Date())
    let mockStore: MockKeyValueFileStore
    let calendar = Calendar.current
    var currentDate = Date()

    init() throws {
        mockStore = try MockKeyValueFileStore()
    }

    private func startOfDay(for date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }

    func makeStat(firePixel: @escaping (AutoconsentPixel, PixelKit.Frequency) -> Void = { _, _ in }) -> AutoconsentDailyStats {
        return AutoconsentDailyStats(
            keyValueStore: mockStore,
            currentDateProvider: { self.currentDate },
            queue: DispatchQueue.main,
            firePixel: firePixel
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
        var firedPixel: AutoconsentPixel?
        var firedFrequency: PixelKit.Frequency?
        let stats = makeStat { pixel, frequency in
            firedPixel = pixel
            firedFrequency = frequency
        }
        currentDate = today

        // Create stats for days -1 through -7 (yesterday through 7 days ago)
        var initialStats: [Date: Int] = [:]
        for daysAgo in 1...7 {
            guard let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let dateStart = startOfDay(for: date)
            initialStats[dateStart] = daysAgo  // Value matches days ago
        }

        let initialData = try JSONEncoder().encode(Stats(counts: initialStats))
        mockStore.underlyingDict["autoconsent_daily_stats"] = initialData

        // When
        stats.sendDailyPixelIfNeeded()
        DispatchQueue.main.sync {}

        // Then
        #expect(firedFrequency == .daily)
        switch firedPixel {
        case .popupManagedCount(let firedParams):
            // Check that params contain d0 through d6 with correct values
            // d0 is yesterday's count (1), d1 is 2 days ago (2), etc.
            for i in 0...6 {
                #expect(firedParams["d\(i)"] == "\(i + 1)", "Wrong count for d\(i)")
            }
        case let other:
            #expect(true == false, "Wrong pixel type: expected popupManagedCount but got \(String(describing: other))")
        }
    }

    @Test("Check Clean Old Stats")
    func testCleanOldStats() throws {
        // Given
        let stats = makeStat()
        currentDate = today

        var initialStats: [Date: Int] = [:]
        // Add stats for last 10 days (more than our 7 day limit)
        for i in 0...10 {
            guard let date = calendar.date(byAdding: .day, value: -(i + 1), to: startOfToday) else { continue }
            let dateStart = startOfDay(for: date)
            initialStats[dateStart] = i + 1
        }
        let initialData = try JSONEncoder().encode(Stats(counts: initialStats))
        mockStore.underlyingDict["autoconsent_daily_stats"] = initialData

        stats.sendDailyPixelIfNeeded()
        DispatchQueue.main.sync {}

        // Then
        // Check old stats were cleaned up
        let finalData = mockStore.underlyingDict["autoconsent_daily_stats"] as! Data
        let finalStats = try JSONDecoder().decode(Stats.self, from: finalData)
        #expect(finalStats.counts.count == 8, "Should only keep last 8 days of stats")

        // Verify we kept the most recent stats
        for i in 0...7 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: startOfToday) else { continue }
            let dateStart = startOfDay(for: date)
            #expect(finalStats.counts[dateStart] == i, "Missing or incorrect value for day -\(i + 1)")
        }
    }
}
