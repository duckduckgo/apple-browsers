//
//  AIBoundaryNavigationDecision.swift
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

/// Pure decision for whether a Duck.ai ↔ web boundary crossing should open a new tab or load in place. Extracted for unit-test isolation from `MainViewController`/`TabViewController`.
enum AIBoundaryNavigationDecision: Equatable {
    case loadInPlace
    case openInNewTab

    /// Programmatic loads (favorites, bookmarks, suggestions, query submits).
    /// Rule: with UTI on and the current tab having content, a boundary cross spawns a new tab. NTP/empty stays in-place; legacy mode (feature off) stays in-place.
    static func forProgrammaticNavigation(currentIsAI: Bool,
                                          currentHasContent: Bool,
                                          targetIsAI: Bool,
                                          unifiedToggleInputAvailable: Bool) -> AIBoundaryNavigationDecision {
        guard unifiedToggleInputAvailable, currentHasContent, currentIsAI != targetIsAI else {
            return .loadInPlace
        }
        return .openInNewTab
    }

    /// Same-frame link taps (no `target="_blank"`).
    /// Rule: chat→web always intercepts (preserve chat); web→chat intercepts only with UTI on; same-side stays in-place.
    static func forSameFrameLinkTap(currentIsAI: Bool,
                                    targetIsAI: Bool,
                                    unifiedToggleInputAvailable: Bool) -> AIBoundaryNavigationDecision {
        guard currentIsAI != targetIsAI, currentIsAI || unifiedToggleInputAvailable else {
            return .loadInPlace
        }
        return .openInNewTab
    }
}
