//
//  DaxGreetingService.swift
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

@MainActor
protocol DaxGreetingProviding {
    func getGreeting() -> String
    func getNewGreeting() -> String
}

/// Nil values make the corresponding greeting rules ineligible.
struct DaxGreetingContext {
    enum Appearance: Equatable {
        case light, dark
    }

    var appearance: Appearance?
    var isFirstOpenOfDay: Bool?
    var foregroundOpenCount: Int?
    var isTrackerProtectionEnabled: Bool?
    var isCookiePopupProtectionEnabled: Bool?
    var isAdBlockingEnabled: Bool?
    var isScamProtectionEnabled: Bool?
}

@MainActor
final class DaxGreetingService {
    private struct Conditions: Equatable {
        let eligible: Set<DaxGreeting>
        let day: Date
        let calendar: Calendar
        let appearance: DaxGreetingContext.Appearance?
    }

    private struct Selection {
        let greeting: DaxGreeting
        let date: Date
        let conditions: Conditions
    }

    private let now: () -> Date
    private let calendarProvider: () -> Calendar
    private let contextProvider: (Date, Calendar) -> DaxGreetingContext
    private let randomIndex: (Range<Int>) -> Int
    private var selection: Selection?
    private var recentGreetings: [DaxGreeting] = []

    init(now: @escaping () -> Date = Date.init,
         calendarProvider: @escaping () -> Calendar = { Calendar.current },
         contextProvider: @escaping (Date, Calendar) -> DaxGreetingContext = { _, _ in DaxGreetingContext() },
         randomIndex: @escaping (Range<Int>) -> Int = { Int.random(in: $0) }) {
        self.now = now
        self.calendarProvider = calendarProvider
        self.contextProvider = contextProvider
        self.randomIndex = randomIndex
    }

    private func eligibleGroups(date: Date, calendar: Calendar, context: DaxGreetingContext) -> [[DaxGreeting]] {
        var weekday: [DaxGreeting] = []
        switch calendar.component(.weekday, from: date) {
        case 2: weekday = [.monday]
        case 4: weekday = [.wednesday]
        case 6: weekday = [.fridaySearch, .fridayDuck]
        default: break
        }

        let time: DaxGreeting
        let meal: [DaxGreeting]
        switch calendar.component(.hour, from: date) {
        case 3..<12:
            time = .early
            meal = [.cookieBreakfast]
        case 12..<18:
            time = .afternoon
            meal = [.cookieLunch]
        case 18..<22:
            time = .evening
            meal = [.cookieDinner]
        default:
            time = .late
            meal = []
        }

        let appearance: [DaxGreeting]
        switch context.appearance {
        case .dark: appearance = [.dark]
        case .light: appearance = [.light]
        case nil: appearance = []
        }

        var features: [DaxGreeting] = []
        if context.isTrackerProtectionEnabled == true {
            features += [.trackersQuiet, .trackersSearch, .trackersAsk]
        }
        if context.isCookiePopupProtectionEnabled == true { features.append(.cookies) }
        if context.isAdBlockingEnabled == true { features.append(.ads) }
        if context.isScamProtectionEnabled == true { features.append(.scams) }

        return [
            weekday,
            [time],
            appearance,
            context.isFirstOpenOfDay == true ? [.firstOpen] : [],
            (context.foregroundOpenCount ?? 0) >= 3 ? [.frequentHabit, .frequentSearch] : [],
            features,
            context.isCookiePopupProtectionEnabled == true ? meal : []
        ]
    }
}

extension DaxGreetingService: DaxGreetingProviding {
    func getGreeting() -> String {
        selectGreeting(forceRefresh: false)
    }

    func getNewGreeting() -> String {
        selectGreeting(forceRefresh: true)
    }

    private func selectGreeting(forceRefresh: Bool) -> String {
        let date = now()
        let calendar = calendarProvider()
        let context = contextProvider(date, calendar)
        let groups = eligibleGroups(date: date, calendar: calendar, context: context)
        let conditions = Conditions(eligible: Set(groups.flatMap { $0 }),
                                    day: calendar.startOfDay(for: date),
                                    calendar: calendar,
                                    appearance: context.appearance)
        if !forceRefresh, let selection,
           date >= selection.date,
           conditions == selection.conditions {
            return selection.greeting.text
        }

        let availableGroups = groups.map { group in
            group.filter { !recentGreetings.contains($0) }
        }.filter { !$0.isEmpty }
        let candidates: [DaxGreeting]
        if availableGroups.isEmpty {
            candidates = DaxGreeting.generic.filter { !recentGreetings.contains($0) }
        } else {
            candidates = availableGroups[randomIndex(availableGroups.indices)]
        }
        let greeting = candidates[randomIndex(candidates.indices)]
        selection = Selection(greeting: greeting, date: date, conditions: conditions)
        recentGreetings.append(greeting)
        recentGreetings = Array(recentGreetings.suffix(5))
        return greeting.text
    }
}
