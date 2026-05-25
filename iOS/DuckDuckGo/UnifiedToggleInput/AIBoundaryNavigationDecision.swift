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

/// Pure decision of whether a navigation that crosses (or doesn't cross) the
/// Duck.ai ↔ web boundary should open in a new tab or load into the current one.
///
/// Extracted so the boundary rules can be exercised by unit tests without dragging
/// in `MainViewController` / `TabViewController`'s full dependency surface.
enum AIBoundaryNavigationDecision: Equatable {
    case loadInPlace
    case openInNewTab

    /// Programmatic loads (favorites, bookmarks, suggestions, query submits).
    ///
    /// Rule: when unified input is on and the current tab has content, any cross of the
    /// Duck.ai ↔ web boundary opens in a new tab so the origin tab survives. NTP/empty
    /// tabs always load in place; legacy mode (feature off) keeps the pre-existing
    /// in-place behavior.
    static func forProgrammaticNavigation(currentIsAI: Bool,
                                          currentHasContent: Bool,
                                          targetIsAI: Bool,
                                          unifiedToggleInputAvailable: Bool) -> AIBoundaryNavigationDecision {
        guard unifiedToggleInputAvailable, currentHasContent, currentIsAI != targetIsAI else {
            return .loadInPlace
        }
        return .openInNewTab
    }

    /// Same-frame in-page link taps (i.e. `<a href="...">` without `target="_blank"`).
    ///
    /// Rule: chat→web link taps always intercept (Duck.ai tabs are preserved across
    /// outbound links). Web→chat link taps intercept only when unified input is on.
    /// Same-side taps (web→web, chat→chat) load in place.
    static func forSameFrameLinkTap(currentIsAI: Bool,
                                    targetIsAI: Bool,
                                    unifiedToggleInputAvailable: Bool) -> AIBoundaryNavigationDecision {
        guard currentIsAI != targetIsAI, currentIsAI || unifiedToggleInputAvailable else {
            return .loadInPlace
        }
        return .openInNewTab
    }
}
