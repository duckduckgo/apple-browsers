//
//  HistoryViewDateFormatter.swift
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
import Foundation

/**
 * This protocol defines API for date and time formatting in History View.
 */
protocol HistoryViewDateFormatting {
    /**
     * Returns the current date - useful for unit testing.
     */
    func currentDate() -> Date

    /**
     * Returns string representation of a day for a given `date`.
     */
    func dayString(for date: Date) -> String

    /**
     * Returns string representation of time for a given `date`.
     */
    func timeString(for date: Date) -> String
}

struct DefaultHistoryViewDateFormatter: HistoryViewDateFormatting {
    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        formatter.formattingContext = .beginningOfSentence
        return formatter
    }()

    let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    func currentDate() -> Date {
        Date()
    }

    func dayString(for date: Date) -> String {
        let today = currentDate().startOfDay
        switch Calendar.autoupdatingCurrent.numberOfDaysBetween(date.startOfDay, and: today) {
        case 0:
            return UserText.today.localizedCapitalized
        case 1:
            return UserText.yesterday.localizedCapitalized
        default:
            return dateFormatter.string(from: date)
        }
    }

    func timeString(for date: Date) -> String {
        timeFormatter.string(from: date)
    }
}
