//
//  DuckAISwipeNewChatUsageTests.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Testing
@testable import DuckDuckGo
@_spi(Testing) import Persistence
@_spi(Testing) import PixelKit

@Suite("Duck.ai swipe for a new chat: 3-day milestone")
struct DuckAISwipeNewChatUsageTests {

    private final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func makeUsage(store: MockKeyValueStore, pixelFiring: PixelKitMock, clock: Clock) -> DuckAISwipeNewChatUsage {
        DuckAISwipeNewChatUsage(storage: store, pixelFiring: pixelFiring, calendar: calendar, now: { clock.now })
    }

    private func milestoneFires(_ pixelFiring: PixelKitMock) -> [ExpectedFireCall] {
        pixelFiring.actualFireCalls.filter { $0.pixel.name == "aichat_swipe_new_chat_used_3_days_u" }
    }

    @available(iOS 16, *)
    @Test("Fires once, unique per install, on the third distinct day", .timeLimit(.minutes(1)))
    func firesOnThirdDistinctDay() {
        let store = MockKeyValueStore()
        let pixelFiring = PixelKitMock()
        let clock = Clock(date(day: 1, hour: 9))
        let usage = makeUsage(store: store, pixelFiring: pixelFiring, clock: clock)

        usage.recordSwipe()
        clock.now = date(day: 1, hour: 23)
        usage.recordSwipe()
        clock.now = date(day: 2, hour: 0)
        usage.recordSwipe()
        #expect(milestoneFires(pixelFiring).isEmpty)

        clock.now = date(day: 5, hour: 12)
        usage.recordSwipe()
        #expect(milestoneFires(pixelFiring).count == 1)
        #expect(milestoneFires(pixelFiring).first?.frequency == .uniqueByName)

        clock.now = date(day: 6, hour: 12)
        usage.recordSwipe()
        #expect(milestoneFires(pixelFiring).count == 1)
    }

    @available(iOS 16, *)
    @Test("Many swipes on one day count as one day", .timeLimit(.minutes(1)))
    func sameDaySwipesCountOnce() {
        let store = MockKeyValueStore()
        let pixelFiring = PixelKitMock()
        let clock = Clock(date(day: 1, hour: 8))
        let usage = makeUsage(store: store, pixelFiring: pixelFiring, clock: clock)

        for hour in 8..<20 {
            clock.now = date(day: 1, hour: hour)
            usage.recordSwipe()
        }

        #expect(store.object(forKey: DuckAISwipeNewChatUsage.Key.dayCount) as? Int == 1)
        #expect(milestoneFires(pixelFiring).isEmpty)
    }

    @available(iOS 16, *)
    @Test("The count survives a relaunch", .timeLimit(.minutes(1)))
    func countPersistsAcrossInstances() {
        let store = MockKeyValueStore()
        let pixelFiring = PixelKitMock()
        let clock = Clock(date(day: 1, hour: 9))

        for day in 1...3 {
            clock.now = date(day: day, hour: 9)
            makeUsage(store: store, pixelFiring: pixelFiring, clock: clock).recordSwipe()
        }

        #expect(milestoneFires(pixelFiring).count == 1)
    }
}
