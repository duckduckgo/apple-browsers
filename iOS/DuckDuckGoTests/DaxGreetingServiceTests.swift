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
    private enum Weekday: Int, CaseIterable {
        case monday = 14, tuesday, wednesday, thursday, friday, saturday, sunday
    }

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

        func setDate(_ weekday: Weekday = .tuesday, week: Int = 0, hour: Int, minute: Int = 0, second: Int = 0) {
            date = calendar.date(from: DateComponents(year: 2026, month: 9, day: weekday.rawValue + 7 * week,
                                                      hour: hour, minute: minute, second: second))!
        }
    }

    func testWhenAIChatIsDisabledThenChatGreetingIsReplaced() {
        let inputs = Inputs()
        inputs.setDate(hour: 13)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.askMe.text)
        inputs.context.isAIChatEnabled = false
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
    }

    func testWhenLanguageIsNotEnglishThenEnglishOnlyGreetingsAreExcluded() {
        let excludedText = Set(DaxGreeting.allCases.filter(\.isEnglishOnly).map(\.text))
        for language: String? in ["pl", nil] {
            let inputs = Inputs()
            inputs.language = language
            inputs.chooseLast = true
            let service = inputs.makeService()
            for week in 0..<2 {
                for weekday in Weekday.allCases {
                    inputs.setDate(weekday, week: week, hour: 8)
                    XCTAssertFalse(excludedText.contains(service.getGreeting()))
                }
            }
        }
    }

    func testWhenAllRegularGreetingsApplyThenEachHasEqualChance() {
        let inputs = Inputs()
        inputs.setDate(.friday, hour: 8)
        inputs.context = DaxGreetingContext(isFirstOpenOfDay: true, foregroundOpenCount: 2,
                                           isTrackerOrAdBlockingEnabled: true, isAIChatEnabled: true)
        XCTAssertEqual(inputs.makeService().getGreeting(), DaxGreeting.friday.text)
        XCTAssertEqual(inputs.draws, [0..<18])
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

    func testWhenWeekdayMatchesThenItsGreetingIsEligible() {
        let cases: [(Weekday, DaxGreeting)] = [
            (.monday, .monday), (.tuesday, .duckDuckHello), (.friday, .friday), (.saturday, .duckDuckHello), (.sunday, .sunday)
        ]
        for (weekday, expected) in cases {
            let inputs = Inputs()
            inputs.context.isAIChatEnabled = false
            inputs.setDate(weekday, hour: 13)
            XCTAssertEqual(inputs.makeService().getGreeting(), expected.text, "\(weekday)")
        }
    }

    func testWhenWithinLifetimeThenGreetingIsKeptEvenIfOthersBecomeEligible() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(hour: 13)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        inputs.context = DaxGreetingContext(isFirstOpenOfDay: true, foregroundOpenCount: 2,
                                           isTrackerOrAdBlockingEnabled: true, isAIChatEnabled: true)
        inputs.setDate(hour: 13, minute: 59, second: 59)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        inputs.setDate(hour: 14)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.whereToToday.text)
    }

    func testWhenGreetingStopsApplyingThenNewOneIsPicked() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(hour: 11, minute: 30)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.morning.text)
        inputs.setDate(hour: 12)
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
    }

    func testWhenMidnightPassesThenGreetingChanges() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(hour: 23, minute: 59, second: 59)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.stillAwake.text)
        inputs.date += 1
        XCTAssertEqual(service.getGreeting(), DaxGreeting.nightOwl.text)
    }

    func testWhenFrequentReturnAppliesThenItReplacesCurrentGreetingUnlessShownRecently() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        inputs.setDate(hour: 13)
        let service = inputs.makeService()
        XCTAssertEqual(service.getGreeting(), DaxGreeting.duckDuckHello.text)
        inputs.context.foregroundOpenCount = 3
        XCTAssertEqual(service.getGreeting(), DaxGreeting.youreBack.text)
        inputs.context.foregroundOpenCount = 2
        XCTAssertEqual(service.getGreeting(), DaxGreeting.niceToSeeYou.text)
        inputs.context.foregroundOpenCount = 3
        let laterDays: [(Weekday, Int, DaxGreeting)] = [
            (.wednesday, 0, .readyWhenYouAre), (.thursday, 0, .readyToSearchPrivately), (.saturday, 0, .heyThere),
            (.tuesday, 1, .whatsOnYourMind), (.wednesday, 1, .youreBack)
        ]
        for (weekday, week, expected) in laterDays {
            inputs.setDate(weekday, week: week, hour: 13)
            XCTAssertEqual(service.getGreeting(), expected.text, "\(weekday) week \(week)")
        }
    }

    func testWhenSelectingOnLaterDaysThenLastFiveAreExcludedAndOldestIsEvicted() {
        let inputs = Inputs()
        inputs.context.isAIChatEnabled = false
        let service = inputs.makeService()
        let weekdaysWithoutWeekdayGreeting: [Weekday] = [.tuesday, .wednesday, .thursday, .saturday]
        let days = [0, 1].flatMap { week in weekdaysWithoutWeekdayGreeting.map { ($0, week) } }
        let expected: [DaxGreeting] = [
            .duckDuckHello, .niceToSeeYou, .readyWhenYouAre, .readyToSearchPrivately, .heyThere, .whatsOnYourMind,
            .duckDuckHello, .niceToSeeYou
        ]
        for ((weekday, week), greeting) in zip(days, expected) {
            inputs.setDate(weekday, week: week, hour: 13)
            XCTAssertEqual(service.getGreeting(), greeting.text, "\(weekday) week \(week)")
        }
    }
}
