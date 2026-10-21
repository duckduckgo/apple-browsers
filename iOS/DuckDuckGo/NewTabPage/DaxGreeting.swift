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

enum DaxGreeting: String, CaseIterable {
    case monday
    case friday
    case fridayDuck
    case sunday
    case whereToToday
    case newDayNewTabs
    case whereShouldWeStart
    case morning
    case stillAwake
    case nightOwl
    case youreBack
    case goodbyeAds
    case askMe
    case duckDuckHello
    case niceToSeeYou
    case readyWhenYouAre
    case readyToSearchPrivately
    case heyThere
    case whatsOnYourMind
    case howCanIHelp
    case letsExplore
    case letsDoThis
    case readyToDiveIn

    var isEnglishOnly: Bool {
        switch self {
        case .fridayDuck, .sunday, .readyToDiveIn:
            return true
        default:
            return false
        }
    }

    var requiresAIChat: Bool {
        self == .askMe
    }

    var text: String {
        switch self {
        case .monday: return UserText.daxGreetingMonday
        case .friday: return UserText.daxGreetingFriday
        case .fridayDuck: return UserText.daxGreetingFridayDuck
        case .sunday: return UserText.daxGreetingSunday
        case .whereToToday: return UserText.daxGreetingWhereToToday
        case .newDayNewTabs: return UserText.daxGreetingNewDayNewTabs
        case .whereShouldWeStart: return UserText.daxGreetingWhereShouldWeStart
        case .morning: return UserText.daxGreetingMorning
        case .stillAwake: return UserText.daxGreetingStillAwake
        case .nightOwl: return UserText.daxGreetingNightOwl
        case .youreBack: return UserText.daxGreetingYoureBack
        case .goodbyeAds: return UserText.daxGreetingGoodbyeAds
        case .askMe: return UserText.daxGreetingAskMe
        case .duckDuckHello: return UserText.daxGreetingDuckDuckHello
        case .niceToSeeYou: return UserText.daxGreetingNiceToSeeYou
        case .readyWhenYouAre: return UserText.daxGreetingReadyWhenYouAre
        case .readyToSearchPrivately: return UserText.daxGreetingReadyToSearchPrivately
        case .heyThere: return UserText.daxGreetingHeyThere
        case .whatsOnYourMind: return UserText.daxGreetingWhatsOnYourMind
        case .howCanIHelp: return UserText.daxGreetingHowCanIHelp
        case .letsExplore: return UserText.daxGreetingLetsExplore
        case .letsDoThis: return UserText.daxGreetingLetsDoThis
        case .readyToDiveIn: return UserText.daxGreetingReadyToDiveIn
        }
    }

    static let generic: [DaxGreeting] = [
        .duckDuckHello, .niceToSeeYou, .readyWhenYouAre, .readyToSearchPrivately, .heyThere,
        .whatsOnYourMind, .howCanIHelp, .letsExplore, .letsDoThis, .readyToDiveIn
    ]
}
