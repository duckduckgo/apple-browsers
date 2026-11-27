//
//  DuckAIOnboardingPathPixel.swift
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

import PixelKit

/// The contextual onboarding Duck.ai path's own moments, which the shared onboarding pixels don't cover.
enum DuckAIOnboardingPathPixel: PixelKit.Event {
    var namePrefix: PixelKitNamePrefix { .none }

    enum Trigger: String {
        /// Duck.ai's first answer arrived.
        case answer
        /// The answer didn't arrive in time.
        case timeout
    }

    /// The wait for Duck.ai's first answer ended, so "That's Duck.ai!" can show.
    case thatsDuckAITriggered(Trigger)
    /// The app reopened the onboarding chat in a window opened while the path waits for Fire.
    case chatReopened
    /// The path moved to the search path because Duck.ai or the prompt was no longer available.
    case searchFallback

    var name: String {
        switch self {
        case .thatsDuckAITriggered: return "onboarding_thats-duckai_trigger_macos"
        case .chatReopened: return "onboarding_duckai-chat_reopened_macos"
        case .searchFallback: return "onboarding_duckai-path_search-fallback_macos"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .thatsDuckAITriggered(let trigger): return ["trigger": trigger.rawValue]
        case .chatReopened, .searchFallback: return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        [.pixelSource]
    }
}
