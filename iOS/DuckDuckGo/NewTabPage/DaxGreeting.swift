//
//  DaxGreeting.swift
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

/// Stable identities are independent of translated copy.
enum DaxGreeting: String, CaseIterable {
    case monday
    case wednesday
    case fridaySearch
    case fridayDuck
    case early
    case afternoon
    case evening
    case late
    case dark
    case light
    case firstOpen
    case frequentHabit
    case frequentSearch
    case trackersQuiet
    case cookies
    case ads
    case scams
    case trackersSearch
    case trackersAsk
    case cookieBreakfast
    case cookieLunch
    case cookieDinner
    case wingIt
    case duckIt
    case ready
    case feelingDucky
    case diveIn
    case chatPrivately
    case nobodyWatching
    case justUs
    case question
    case searchOrChat
    case duckDuckHello

    var text: String {
        switch self {
        case .monday: return UserText.daxGreetingMonday
        case .wednesday: return UserText.daxGreetingWednesday
        case .fridaySearch: return UserText.daxGreetingFridaySearch
        case .fridayDuck: return UserText.daxGreetingFridayDuck
        case .early: return UserText.daxGreetingEarly
        case .afternoon: return UserText.daxGreetingAfternoon
        case .evening: return UserText.daxGreetingEvening
        case .late: return UserText.daxGreetingLate
        case .dark: return UserText.daxGreetingDark
        case .light: return UserText.daxGreetingLight
        case .firstOpen: return UserText.daxGreetingFirstOpen
        case .frequentHabit: return UserText.daxGreetingFrequentHabit
        case .frequentSearch: return UserText.daxGreetingFrequentSearch
        case .trackersQuiet: return UserText.daxGreetingTrackersQuiet
        case .cookies: return UserText.daxGreetingCookies
        case .ads: return UserText.daxGreetingAds
        case .scams: return UserText.daxGreetingScams
        case .trackersSearch: return UserText.daxGreetingTrackersSearch
        case .trackersAsk: return UserText.daxGreetingTrackersAsk
        case .cookieBreakfast: return UserText.daxGreetingCookieBreakfast
        case .cookieLunch: return UserText.daxGreetingCookieLunch
        case .cookieDinner: return UserText.daxGreetingCookieDinner
        case .wingIt: return UserText.daxGreetingWingIt
        case .duckIt: return UserText.daxGreetingDuckIt
        case .ready: return UserText.daxGreetingReady
        case .feelingDucky: return UserText.daxGreetingFeelingDucky
        case .diveIn: return UserText.daxGreetingDiveIn
        case .chatPrivately: return UserText.daxGreetingChatPrivately
        case .nobodyWatching: return UserText.daxGreetingNobodyWatching
        case .justUs: return UserText.daxGreetingJustUs
        case .question: return UserText.daxGreetingQuestion
        case .searchOrChat: return UserText.daxGreetingSearchOrChat
        case .duckDuckHello: return UserText.daxGreetingDuckDuckHello
        }
    }

    static let generic: [DaxGreeting] = [
        .wingIt, .duckIt, .ready, .feelingDucky, .diveIn,
        .chatPrivately, .nobodyWatching, .justUs, .question, .searchOrChat, .duckDuckHello
    ]
}
