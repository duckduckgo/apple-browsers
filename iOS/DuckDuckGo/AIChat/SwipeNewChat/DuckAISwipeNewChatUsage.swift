//
//  DuckAISwipeNewChatUsage.swift
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
import Persistence
import PixelKit

enum DuckAISwipeNewChatPixel: PixelKit.Event {
    case usedOnThreeDays

    var name: String { "aichat_swipe_new_chat_used_3_days_u" }
    var parameters: [String: String]? { nil }
    var standardParameters: [PixelKitStandardParameter]? { nil }
}

/// Counts the distinct local days the user swipes for a new chat, and reports the third one once per install.
struct DuckAISwipeNewChatUsage {

    static let milestoneDays = 3

    enum Key {
        static let lastDay = "duckAISwipeNewChat.lastDay"
        static let dayCount = "duckAISwipeNewChat.dayCount"
    }

    private let storage: KeyValueStoring
    private let pixelFiring: PixelFiring?
    private let calendar: Calendar
    private let now: () -> Date

    init(storage: KeyValueStoring = UserDefaults.standard,
         pixelFiring: PixelFiring? = PixelKit.shared,
         calendar: Calendar = .current,
         now: @escaping () -> Date = Date.init) {
        self.storage = storage
        self.pixelFiring = pixelFiring
        self.calendar = calendar
        self.now = now
    }

    func recordSwipe() {
        let count = storage.object(forKey: Key.dayCount) as? Int ?? 0
        guard count < Self.milestoneDays else { return }
        let today = now()
        if let lastDay = storage.object(forKey: Key.lastDay) as? Date, calendar.isDate(lastDay, inSameDayAs: today) { return }
        storage.set(today, forKey: Key.lastDay)
        storage.set(count + 1, forKey: Key.dayCount)
        if count + 1 == Self.milestoneDays {
            pixelFiring?.fire(DuckAISwipeNewChatPixel.usedOnThreeDays, frequency: .uniqueByName)
        }
    }
}
