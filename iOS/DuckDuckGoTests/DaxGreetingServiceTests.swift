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
        var language: String? = "en"
        var context = DaxGreetingContext(isAIChatEnabled: true)
        var draws: [Range<Int>] = []
        var chooseLast = false

        func makeService() -> DaxGreetingService {
            DaxGreetingService(now: { self.date },
                               calendarProvider: { self.calendar },
                               languageProvider: { self.language },
                               contextProvider: { _, _ in self.context },
                               randomIndex: { range in
                self.draws.append(range)
                return self.chooseLast ? range.upperBound - 1 : range.lowerBound
            })
        }

        /// September 2026 starts on a Tuesday: 14 and 21 are Mondays, 18 and 25 Fridays, 20 Sunday.
        func setDate(day: Int = 15, hour: Int, minute: Int = 0, second: Int = 0) {
            date = calendar.date(from: DateComponents(year: 2026, month: 9, day: day,
                                                      hour: hour, minute: minute, second: second))!
        }
    }

    func testWhenAIChatIsDisabledOrUnavailableThenChatGreetingIsExcluded() {
        for language in ["en", "pl"] {
            for enabled: Bool? in [false, nil] {
                let inputs = Inputs()
                inputs.language = language
                inputs.context.isAIChatEnabled = enabled
                let service = inputs.makeService()
                var previous: String?
                for day in 1...30 {
                    inputs.setDate(day: day, hour: 8)
                    let greeting = service.getGreeting()
                    XCTAssertNotEqual(greeting, DaxGreeting.askMe.text)
                    XCTAssertNotEqual(greeting, previous)
                    previous = greeting
                }
            }
        }
    }

    func testWhenAIChatIsDisabledThenCachedChatGreetingIsReplaced() {
        let inputs = Inputs()
        inputs.setDate(hour: 13)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.askMe.text)
        inputs.context.isAIChatEnabled = false
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
    }

    func testWhenLanguageIsNotEnglishThenEnglishOnlyGreetingsAreExcluded() {
        let englishOnly: Set<DaxGreeting> = [.fridayDuck, .sunday, .readyToDiveIn]
        XCTAssertEqual(Set(DaxGreeting.allCases.filter(\.isEnglishOnly)), englishOnly)
        let excludedText = Set(englishOnly.map(\.text))
        for language: String? in ["pl", "fr-CA", nil] {
            let inputs = Inputs()
            inputs.language = language
            inputs.chooseLast = true
            let service = inputs.makeService()
            var history: [String] = []
            for day in 1...30 {
                inputs.setDate(day: day, hour: 8)
                let greeting = service.getGreeting()
                XCTAssertFalse(excludedText.contains(greeting))
                XCTAssertFalse(history.suffix(5).contains(greeting))
                history.append(greeting)
            }
        }
    }

    func testWhenEnglishLanguageChangesThenCachedEnglishOnlyGreetingIsReplaced() {
        for language in ["en", "en-US", "en_GB"] {
            let inputs = Inputs()
            inputs.language = language
            inputs.context.isAIChatEnabled = false
            inputs.setDate(day: 20, hour: 13)
            let service = inputs.makeService()
            XCTAssertEqual(service.getGreeting(), DaxGreeting.sunday.text)
            inputs.language = "pl"
            XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        }
    }

    func testWhenAllRegularGreetingsApplyThenEachHasEqualChance() {
        let inputs = Inputs()
        inputs.setDate(day: 18, hour: 8)
        inputs.context = DaxGreetingContext(isFirstOpenOfDay: true, foregroundOpenCount: 2,
                                           isTrackerOrAdBlockingEnabled: true, isAIChatEnabled: true)
        XCTAssertEqual(inputs.makeService().getGreeting(), DaxGreeting.friday.text)
        XCTAssertEqual(inputs.draws, [0..<18])
    }

    func testWhenContextIsMissingThenOnlyTimeWeekdayAndGenericGreetingsApply() {
        let inputs = Inputs()
        inputs.context = DaxGreetingContext()
        inputs.setDate(hour: 8)
        inputs.chooseLast = true
        XCTAssertEqual(inputs.makeService().getGreeting(), DaxGreeting.readyToDiveIn.text)
        XCTAssertEqual(inputs.draws, [0..<1 + DaxGreeting.generic.count])
    }

    func testWhenWithinLifetimeThenGreetingIsKeptEvenIfOthersBecomeEligible() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(hour: 13)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        inputs.context = DaxGreetingContext(isFirstOpenOfDay: true, foregroundOpenCount: 2,
                                           isTrackerOrAdBlockingEnabled: true, isAIChatEnabled: true)
        for minute in [30, 59] {
            inputs.setDate(hour: 13, minute: minute, second: 59)
            XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        }
        XCTAssertEqual(inputs.draws.count, 1)
        inputs.setDate(hour: 14)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.whereToToday.text)
        XCTAssertEqual(inputs.draws.count, 2)
        inputs.context = DaxGreetingContext(isAIChatEnabled: false)
        inputs.setDate(day: 16, hour: 13)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.niceToSeeYou.text)
    }

    func testWhenGreetingStopsApplyingThenNewOneIsPickedAndKept() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(hour: 11, minute: 30)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.morning.text)
        inputs.setDate(hour: 11, minute: 59, second: 59)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.morning.text)
        inputs.setDate(hour: 12)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        inputs.setDate(hour: 12, minute: 59, second: 59)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        inputs.setDate(hour: 13)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.niceToSeeYou.text)
    }

    func testWhenTimeIsAtWindowBoundaryThenCorrectGreetingIsEligible() {
        let cases: [(Int, Int, DaxGreeting)] = [
            (0, 0, .stillAwake), (2, 59, .stillAwake), (3, 0, .morning), (11, 59, .morning),
            (12, 0, .duckDuckHello), (21, 59, .duckDuckHello), (22, 0, .stillAwake)
        ]
        for (hour, minute, greeting) in cases {
            let inputs = Inputs()
            inputs.context.isAIChatEnabled = false
            inputs.setDate(hour: hour, minute: minute)
            XCTAssertEqual(inputs.makeService().getGreeting(), greeting.text, "\(hour):\(minute)")
        }
    }

    func testWhenLateNightOnConsecutiveDaysThenBothVariantsCanBeSelected() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(day: 15, hour: 23)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.stillAwake.text)
        inputs.setDate(day: 16, hour: 23)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.nightOwl.text)
    }

    func testWhenWeekdayMatchesThenItsGreetingsAreEligible() {
        for (day, expected) in [(14, DaxGreeting.monday), (18, .friday), (20, .sunday)] {
            let inputs = Inputs()
            inputs.context.isAIChatEnabled = false
            inputs.setDate(day: day, hour: 13)
            XCTAssertEqual(inputs.makeService().getGreeting(), expected.text)
        }
        for day in [15, 16, 17, 19] {
            let inputs = Inputs()
            inputs.context.isAIChatEnabled = false
            inputs.setDate(day: day, hour: 13)
            XCTAssertEqual(inputs.makeService().getGreeting(), DaxGreeting.duckDuckHello.text)
        }
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(day: 18, hour: 13)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.friday.text)
        inputs.setDate(day: 25, hour: 13)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.fridayDuck.text)
    }

    func testWhenFirstOpenEndsThenFirstOpenGreetingIsReplaced() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.context.isFirstOpenOfDay = true
        inputs.setDate(hour: 13)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.whereToToday.text)
        inputs.context.isFirstOpenOfDay = false
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
    }

    func testWhenFrequentReturnAppliesThenItReplacesCurrentGreetingUnlessShownRecently() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(day: 15, hour: 13)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        inputs.context.foregroundOpenCount = 3
        XCTAssertEqual(service.getGreeting(), DaxGreeting.youreBack.text)
        inputs.context.foregroundOpenCount = 4
        XCTAssertEqual(service.getGreeting(), DaxGreeting.youreBack.text)
        inputs.context.foregroundOpenCount = 2
        XCTAssertEqual(service.getGreeting(), DaxGreeting.niceToSeeYou.text)
        inputs.context.foregroundOpenCount = 3
        let laterDays: [(Int, DaxGreeting)] = [
            (16, .readyWhenYouAre), (17, .readyToSearchPrivately), (19, .heyThere), (22, .whatsOnYourMind), (23, .youreBack)
        ]
        for (day, expected) in laterDays {
            inputs.setDate(day: day, hour: 13)
            XCTAssertEqual(service.getGreeting(), expected.text, "day \(day)")
        }
    }

    func testWhenAdProtectionIsDisabledThenAdsGreetingIsReplaced() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.context.isTrackerOrAdBlockingEnabled = true
        inputs.setDate(hour: 13)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.goodbyeAds.text)
        inputs.context.isTrackerOrAdBlockingEnabled = false
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
    }

    func testWhenMidnightPassesWithoutEligibilityChangeThenGreetingChanges() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(day: 15, hour: 23, minute: 59, second: 59)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.stillAwake.text)
        inputs.date += 1
        XCTAssertEqual(service.getGreeting(), DaxGreeting.nightOwl.text)
    }

    func testWhenClockMovesBehindSelectionThenGreetingChanges() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(hour: 8)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.morning.text)
        inputs.date -= 1
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
    }

    func testWhenCalendarOrTimeZoneChangesThenGreetingChanges() {
        for changeTimeZone in [true, false] {
            let inputs = Inputs()
            inputs.context.isAIChatEnabled = false
            inputs.setDate(hour: 8)
            let service = inputs.makeService()
            XCTAssertEqual(service.getGreeting(), DaxGreeting.morning.text)
            if changeTimeZone {
                inputs.calendar.timeZone = TimeZone(secondsFromGMT: 3600)!
            } else {
                inputs.calendar = Calendar(identifier: .iso8601)
                inputs.calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            }
            XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        }
    }

    func testWhenTimeZoneChangesTimeWindowThenNewWindowApplies() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(hour: 8)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.morning.text)
        inputs.calendar.timeZone = TimeZone(secondsFromGMT: 15 * 3600)!
        XCTAssertEqual(service.getGreeting(), DaxGreeting.stillAwake.text)
    }

    func testWhenSelectingOnLaterDaysThenLastFiveAreExcludedAndOldestIsEvicted() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        let service = inputs.makeService()
        let daysWithoutWeekdayGreeting = [15, 16, 17, 19, 22, 23, 24, 26]
        let expected: [DaxGreeting] = [
            .duckDuckHello, .niceToSeeYou, .readyWhenYouAre, .readyToSearchPrivately, .heyThere, .whatsOnYourMind,
            .duckDuckHello, .niceToSeeYou
        ]
        for (day, greeting) in zip(daysWithoutWeekdayGreeting, expected) {
            inputs.setDate(day: day, hour: 13)
            XCTAssertEqual(service.getGreeting(), greeting.text, "day \(day)")
        }
        XCTAssertEqual(inputs.makeService().getGreeting(), DaxGreeting.duckDuckHello.text)
    }
}
