//
//  CalendarExtension.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

extension Calendar {
	public func numberOfDaysBetween(_ from: Date, and to: Date) -> Int? {
		let numberOfDays = dateComponents([.day], from: from, to: to)
		return numberOfDays.day
	}

    /**
     * This function calculates the date of the most recent weekday before `referenceDate`.
     *
     * > `weekday` must be between 1 and 7 inclusive (Sunday through Saturday) following possible values of `DateComponents.weekday`.
     *
     * When `weekday` matches the weekday of `referenceDate`, a date 1 week ago is returned.
     * The time of the day in a returned date matches the time of `referenceDate`.
     *
     * - Seealso: `DateComponents.weekday`.
     */
    public func firstWeekday(_ weekday: Int, before referenceDate: Date) -> Date {
        assert((1...7).contains(weekday), "Weekday must be between 1 and 7 (as per DateComponents API)")

        // ensure weekday is between 1 and 7
        let adjustedWeekday: Int = min(max(weekday, 1), 7)

        let referenceWeekday = component(.weekday, from: referenceDate)
        var daysDiff = referenceWeekday - adjustedWeekday
        if daysDiff <= 0 { // same weekday
            daysDiff += 7
        }
        return referenceDate.daysAgo(daysDiff)
    }
}
