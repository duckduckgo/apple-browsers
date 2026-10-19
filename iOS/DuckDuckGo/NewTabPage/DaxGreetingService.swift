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
}

/// Nil values make the corresponding greeting rules ineligible.
struct DaxGreetingContext {
    var isFirstOpenOfDay: Bool?
    var foregroundOpenCount: Int?
    var isTrackerOrAdBlockingEnabled: Bool?
    var isAIChatEnabled: Bool?
}

@MainActor
final class DaxGreetingService {
    private static let greetingLifetime: TimeInterval = 60 * 60

    private struct Selection {
        let greeting: DaxGreeting
        let date: Date
        let day: Date
        let calendar: Calendar
    }

    private let now: () -> Date
    private let calendarProvider: () -> Calendar
    private let languageProvider: () -> String?
    private let contextProvider: (Date, Calendar) -> DaxGreetingContext
    private let randomIndex: (Range<Int>) -> Int
    private var selection: Selection?
    private var recentGreetings: [DaxGreeting] = []

    init(now: @escaping () -> Date = Date.init,
         calendarProvider: @escaping () -> Calendar = { Calendar.current },
         languageProvider: @escaping () -> String? = { Bundle.main.preferredLocalizations.first },
         contextProvider: @escaping (Date, Calendar) -> DaxGreetingContext = { _, _ in DaxGreetingContext() },
         randomIndex: @escaping (Range<Int>) -> Int = { Int.random(in: $0) }) {
        self.now = now
        self.calendarProvider = calendarProvider
        self.languageProvider = languageProvider
        self.contextProvider = contextProvider
        self.randomIndex = randomIndex
    }

    private func priorityGreetings(context: DaxGreetingContext) -> [DaxGreeting] {
        (context.foregroundOpenCount ?? 0) >= 3 ? [.youreBack] : []
    }

    private func regularGreetings(date: Date, calendar: Calendar, context: DaxGreetingContext) -> [DaxGreeting] {
        let weekday: [DaxGreeting]
        switch calendar.component(.weekday, from: date) {
        case 1: weekday = [.sunday]
        case 2: weekday = [.monday]
        case 6: weekday = [.friday, .fridayDuck]
        default: weekday = []
        }

        let time: [DaxGreeting]
        switch calendar.component(.hour, from: date) {
        case 3..<12: time = [.morning]
        case 12..<22: time = []
        default: time = [.stillAwake, .nightOwl]
        }

        let features: [DaxGreeting] = (context.isTrackerOrAdBlockingEnabled == true ? [.goodbyeAds] : []) + [.askMe]

        let firstOpen: [DaxGreeting] = context.isFirstOpenOfDay == true
            ? [.whereToToday, .newDayNewTabs, .whereShouldWeStart]
            : []

        return weekday + time + firstOpen + features + DaxGreeting.generic
    }

    private func shouldKeep(_ selection: Selection, date: Date, day: Date, calendar: Calendar,
                            eligible: [DaxGreeting], unshownPriority: [DaxGreeting]) -> Bool {
        let isWithinLifetime = date >= selection.date && date < selection.date + Self.greetingLifetime
        let isSameDay = day == selection.day && calendar == selection.calendar
        let isStillEligible = eligible.contains(selection.greeting)
        let isNotReplacedByPriority = unshownPriority.isEmpty || unshownPriority.contains(selection.greeting)
        return isWithinLifetime && isSameDay && isStillEligible && isNotReplacedByPriority
    }

    private func leastRecentlyShown(_ pool: [DaxGreeting]) -> [DaxGreeting] {
        var history = recentGreetings
        var candidates = pool.filter { !history.contains($0) }
        while candidates.isEmpty && !history.isEmpty {
            history.removeFirst()
            candidates = pool.filter { !history.contains($0) }
        }
        return candidates
    }
}

extension DaxGreetingService: DaxGreetingProviding {
    func getGreeting() -> String {
        let date = now()
        let calendar = calendarProvider()
        let context = contextProvider(date, calendar)
        let isEnglish = languageProvider().map { Locale(identifier: $0).languageCode == "en" } ?? false
        func isEligible(_ greeting: DaxGreeting) -> Bool {
            (isEnglish || !greeting.isEnglishOnly) && (context.isAIChatEnabled == true || !greeting.requiresAIChat)
        }
        let priority = priorityGreetings(context: context).filter(isEligible)
        let regular = regularGreetings(date: date, calendar: calendar, context: context).filter(isEligible)
        let unshownPriority = priority.filter { !recentGreetings.contains($0) }
        let day = calendar.startOfDay(for: date)
        if let selection, shouldKeep(selection, date: date, day: day, calendar: calendar,
                                     eligible: priority + regular, unshownPriority: unshownPriority) {
            return selection.greeting.text
        }

        let candidates = unshownPriority.isEmpty ? leastRecentlyShown(regular) : unshownPriority
        let greeting = candidates[randomIndex(candidates.indices)]
        selection = Selection(greeting: greeting, date: date, day: day, calendar: calendar)
        recentGreetings.append(greeting)
        recentGreetings = Array(recentGreetings.suffix(5))
        return greeting.text
    }
}
