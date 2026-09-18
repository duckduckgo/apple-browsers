//
//  DaxGreetingServiceTests.swift
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class DaxGreetingServiceTests: XCTestCase {
    @MainActor
    private final class Inputs {
        var date = Date(timeIntervalSince1970: 0)
        var calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar
        }()
        var context = DaxGreetingContext()
        var draws: [Range<Int>] = []
        var chooseLast = false

        func makeService() -> DaxGreetingService {
            DaxGreetingService(now: { self.date },
                               calendarProvider: { self.calendar },
                               contextProvider: { _, _ in self.context },
                               randomIndex: { range in
                self.draws.append(range)
                return self.chooseLast ? range.upperBound - 1 : range.lowerBound
            })
        }

        func setDate(day: Int = 15, hour: Int, minute: Int = 0, second: Int = 0) {
            date = calendar.date(from: DateComponents(year: 2026, month: 9, day: day,
                                                      hour: hour, minute: minute, second: second))!
        }
    }

    func testWhenTimePassesWithoutConditionChangesThenGreetingRemainsCached() {
        let inputs = Inputs()
        inputs.setDate(hour: 8)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.early.text)
        for interval in [0.0, 1, 1799, 1800, 3600] {
            inputs.setDate(hour: 8)
            inputs.date += interval
            XCTAssertEqual(service.getGreeting(), DaxGreeting.early.text)
        }
        XCTAssertEqual(inputs.draws.count, 2)
        XCTAssertEqual(service.getNewGreeting(), DaxGreeting.wingIt.text)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.wingIt.text)
        XCTAssertEqual(service.getNewGreeting(), DaxGreeting.duckIt.text)
        XCTAssertEqual(inputs.draws.count, 4)
    }

    func testWhenNewGreetingIsRequestedImmediatelyThenCacheIsBypassed() {
        let inputs = Inputs()
        inputs.setDate(hour: 8)
        let service = inputs.makeService()
        XCTAssertEqual(service.getNewGreeting(), DaxGreeting.early.text)
        XCTAssertEqual(service.getNewGreeting(), DaxGreeting.wingIt.text)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.wingIt.text)
    }

    func testWhenTimeIsAtWindowBoundaryThenCorrectGreetingIsEligible() {
        let cases: [(Int, Int, DaxGreeting)] = [
            (0, 0, .late), (2, 59, .late), (3, 0, .early), (11, 59, .early),
            (12, 0, .afternoon), (17, 59, .afternoon), (18, 0, .evening), (21, 59, .evening), (22, 0, .late)
        ]
        for (hour, minute, greeting) in cases {
            let inputs = Inputs()
            inputs.setDate(hour: hour, minute: minute)
            XCTAssertEqual(inputs.makeService().getGreeting(), greeting.text, "\(hour):\(minute)")
        }
    }

    func testWhenCrossingTimeBoundaryThenCacheIsInvalidated() {
        for (hour, next) in [(3, DaxGreeting.early), (12, .afternoon), (18, .evening), (22, .late)] {
            let inputs = Inputs()
            inputs.setDate(hour: hour - 1, minute: 59, second: 59)
            let service = inputs.makeService()
            let previous = service.getGreeting()
            inputs.date += 1
            XCTAssertEqual(service.getGreeting(), next.text)
            XCTAssertNotEqual(previous, next.text)
        }
    }

    func testWhenWeekdayMatchesThenOnlyItsVariantsAreEligible() {
        for (day, expected) in [(14, DaxGreeting.monday), (16, .wednesday), (18, .fridaySearch)] {
            let inputs = Inputs()
            inputs.setDate(day: day, hour: 8)
            XCTAssertEqual(inputs.makeService().getGreeting(), expected.text)
        }
        for day in [15, 17, 19, 20] {
            let inputs = Inputs()
            inputs.setDate(day: day, hour: 8)
            XCTAssertEqual(inputs.makeService().getGreeting(), DaxGreeting.early.text)
        }
        let inputs = Inputs()
        inputs.setDate(day: 18, hour: 8)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.fridaySearch.text)
        XCTAssertEqual(service.getNewGreeting(), DaxGreeting.fridayDuck.text)
    }

    func testWhenAppearanceChangesOrBecomesUnavailableThenCacheRefreshes() {
        let inputs = Inputs()
        inputs.setDate(hour: 8)
        inputs.chooseLast = true
        inputs.context.appearance = .dark
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.dark.text)
        inputs.context.appearance = .light
        XCTAssertEqual(service.getGreeting(), DaxGreeting.light.text)
        inputs.context.appearance = nil
        XCTAssertEqual(service.getGreeting(), DaxGreeting.early.text)
    }

    func testWhenFirstOpenChangesThenCacheRefreshes() {
        let inputs = Inputs()
        inputs.setDate(hour: 8)
        inputs.chooseLast = true
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.early.text)
        inputs.context.isFirstOpenOfDay = true
        XCTAssertEqual(service.getGreeting(), DaxGreeting.firstOpen.text)
        inputs.context.isFirstOpenOfDay = false
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
    }

    func testWhenOpenCountCrossesThresholdThenEligibilityChangesButFurtherOpensKeepCache() {
        let inputs = Inputs()
        inputs.setDate(hour: 8)
        inputs.chooseLast = true
        inputs.context.foregroundOpenCount = 2
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.early.text)
        inputs.context.foregroundOpenCount = 3
        XCTAssertEqual(service.getGreeting(), DaxGreeting.frequentSearch.text)
        inputs.context.foregroundOpenCount = 4
        XCTAssertEqual(service.getGreeting(), DaxGreeting.frequentSearch.text)
        inputs.context.foregroundOpenCount = 2
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        XCTAssertEqual(inputs.context.foregroundOpenCount, 2)
    }

    func testWhenProtectionIsEnabledThenItsGreetingBecomesEligibleAndDisablingRefreshesCache() {
        let cases: [(WritableKeyPath<DaxGreetingContext, Bool?>, DaxGreeting)] = [
            (\.isTrackerProtectionEnabled, .trackersAsk), (\.isCookiePopupProtectionEnabled, .cookies),
            (\.isAdBlockingEnabled, .ads), (\.isScamProtectionEnabled, .scams)
        ]
        for (key, greeting) in cases {
            let inputs = Inputs()
            inputs.setDate(hour: 23)
            inputs.chooseLast = true
            let service = inputs.makeService()
            XCTAssertEqual(service.getGreeting(), DaxGreeting.late.text)
            inputs.context[keyPath: key] = true
            XCTAssertEqual(service.getGreeting(), greeting.text)
            XCTAssertEqual(service.getGreeting(), greeting.text)
            inputs.context[keyPath: key] = false
            XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        }
    }

    func testWhenCookieProtectionIsEnabledThenMealGreetingRequiresMatchingTimeWindow() {
        for (hour, expected) in [(3, DaxGreeting.cookieBreakfast), (12, .cookieLunch), (18, .cookieDinner), (22, .cookies)] {
            let inputs = Inputs()
            inputs.setDate(hour: hour)
            inputs.chooseLast = true
            inputs.context.isCookiePopupProtectionEnabled = true
            XCTAssertEqual(inputs.makeService().getGreeting(), expected.text)
            inputs.context.isCookiePopupProtectionEnabled = false
            XCTAssertNotEqual(inputs.makeService().getGreeting(), expected.text)
        }
    }

    func testWhenContextIsMissingThenOnlyTimeAndWeekdayRulesApply() {
        let inputs = Inputs()
        inputs.setDate(hour: 8)
        XCTAssertEqual(inputs.makeService().getGreeting(), DaxGreeting.early.text)
        XCTAssertEqual(inputs.draws, [0..<1, 0..<1])
    }

    func testWhenAllGroupsAreEligibleThenEachCategoryGetsOneSlot() {
        let inputs = Inputs()
        inputs.setDate(day: 18, hour: 8)
        inputs.context = DaxGreetingContext(appearance: .dark, isFirstOpenOfDay: true, foregroundOpenCount: 3,
                                           isTrackerProtectionEnabled: true, isCookiePopupProtectionEnabled: true,
                                           isAdBlockingEnabled: true, isScamProtectionEnabled: true)
        XCTAssertEqual(inputs.makeService().getGreeting(), DaxGreeting.fridaySearch.text)
        XCTAssertEqual(inputs.draws, [0..<7, 0..<2])
    }

    func testWhenSelectingFeatureVariantsThenAllSixShareOneCategory() {
        let expected: [DaxGreeting] = [.trackersQuiet, .trackersSearch, .trackersAsk, .cookies, .ads, .scams]
        for (index, greeting) in expected.enumerated() {
            let inputs = Inputs()
            inputs.setDate(hour: 23)
            inputs.context = DaxGreetingContext(isTrackerProtectionEnabled: true, isCookiePopupProtectionEnabled: true,
                                               isAdBlockingEnabled: true, isScamProtectionEnabled: true)
            var draws = 0
            let service = DaxGreetingService(now: { inputs.date },
                                             calendarProvider: { inputs.calendar },
                                             contextProvider: { _, _ in inputs.context },
                                             randomIndex: { range in
                draws += 1
                XCTAssertEqual(range, draws == 1 ? 0..<2 : 0..<6)
                return draws == 1 ? 1 : index
            })
            XCTAssertEqual(service.getGreeting(), greeting.text)
        }
    }

    func testWhenFrequentUsePersistsThenBothVariantsCanBeSelected() {
        let inputs = Inputs()
        inputs.setDate(hour: 8)
        inputs.chooseLast = true
        inputs.context.foregroundOpenCount = 3
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.frequentSearch.text)
        XCTAssertEqual(service.getNewGreeting(), DaxGreeting.frequentHabit.text)
    }

    func testWhenMidnightPassesWithoutEligibilityChangeThenCacheRefreshes() {
        let inputs = Inputs()
        inputs.setDate(day: 19, hour: 23, minute: 59, second: 59)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.late.text)
        inputs.date += 1
        XCTAssertEqual(service.getGreeting(), DaxGreeting.wingIt.text)
    }

    func testWhenClockMovesBehindSelectionThenCacheRefreshes() {
        let inputs = Inputs()
        inputs.setDate(hour: 8)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.early.text)
        inputs.date -= 1
        XCTAssertEqual(service.getGreeting(), DaxGreeting.wingIt.text)
    }

    func testWhenCalendarOrTimeZoneChangesThenCacheRefreshes() {
        for changeTimeZone in [true, false] {
            let inputs = Inputs()
            inputs.setDate(hour: 8)
            let service = inputs.makeService()
            XCTAssertEqual(service.getGreeting(), DaxGreeting.early.text)
            if changeTimeZone {
                inputs.calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
            } else {
                inputs.calendar = Calendar(identifier: .iso8601)
                inputs.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            }
            XCTAssertEqual(service.getGreeting(), DaxGreeting.wingIt.text)
        }
    }

    func testWhenTimeZoneChangesTimeWindowThenNewWindowApplies() {
        let inputs = Inputs()
        inputs.setDate(hour: 8)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.early.text)
        inputs.calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        XCTAssertEqual(service.getGreeting(), DaxGreeting.afternoon.text)
    }

    func testWhenSelectingThenLastFiveAreExcludedAndOldestIsEvicted() {
        let inputs = Inputs()
        inputs.setDate(hour: 3)
        let service = inputs.makeService()
        let expected: [DaxGreeting] = [.early, .wingIt, .duckIt, .ready, .feelingDucky, .diveIn, .early, .wingIt]
        for greeting in expected {
            XCTAssertEqual(service.getNewGreeting(), greeting.text)
        }
        XCTAssertEqual(inputs.makeService().getGreeting(), DaxGreeting.early.text)
    }

    func testWhenLoadingEnglishResourcesThenAll33GreetingsPreserveExactCopy() throws {
        let path = try XCTUnwrap(Bundle(for: DaxGreetingService.self).path(forResource: "en", ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        let expected: [DaxGreeting: String] = [
            .monday: "Let's ease into Monday together.",
            .wednesday: "Halfway through the week. You're doing great!",
            .fridaySearch: "Friday! One more search before the weekend?",
            .fridayDuck: "Thank duck it's Friday!!",
            .early: "Quack of dawn, glad you're up.",
            .afternoon: "Afternoon slump? A quick search might help.",
            .evening: "Evening. Got a burning question for me?",
            .late: "Up late, huh? I never sleep, so ask away.",
            .dark: "Dark and cozy in here. Perfect time to search.",
            .light: "Bright out here. Should have worn my DDG glasses!",
            .firstOpen: "There you are. Great to see you!",
            .frequentHabit: "This is becoming a habit. A good one.",
            .frequentSearch: "We've searched a lot together. What's next?",
            .trackersQuiet: "I've been blocking trackers quietly. ",
            .cookies: "Cleared a few cookie pop-ups for you.",
            .ads: "Caught a few ads trying to sneak in today.",
            .scams: "Just like water, scams roll right off my back!",
            .trackersSearch: "Trackers blocked. What should we look for today?",
            .trackersAsk: "Trackers blocked already. Ask me anything.",
            .cookieBreakfast: "Yum! Cookie pop-ups \nare my favorite breakfast.",
            .cookieLunch: "Yum! Cookie pop-ups \nfor lunch.",
            .cookieDinner: "I eat cookie pop-ups \nfor dinner.",
            .wingIt: "Let's wing it together. Privately.",
            .duckIt: "Duck it! No one's watching.",
            .ready: "Hey, I'm ready whenever you are.",
            .feelingDucky: "Feeling ducky? Let's dive in.",
            .diveIn: "Let's dive into the internet!",
            .chatPrivately: "Hey there, let's chat privately.",
            .nobodyWatching: "Search like nobody's watching. Because they're not.",
            .justUs: "Just us here. Ask me anything privately.",
            .question: "Hi there! Got a question for me?",
            .searchOrChat: "Search or chat? I'm here for both.",
            .duckDuckHello: "DuckDuckHello!"
        ]
        XCTAssertEqual(expected.count, 33)
        XCTAssertEqual(Set(expected.keys), Set(DaxGreeting.allCases))
        for (greeting, text) in expected {
            let key = "new-tab-page.dax-greeting." + greeting.rawValue
            XCTAssertEqual(bundle.localizedString(forKey: key, value: nil, table: nil), text, key)
        }
    }
}
