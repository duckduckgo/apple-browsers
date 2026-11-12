//
//  NewTabKeyboardDeparture.swift
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

/// How a new tab without its own keyboard waits for one still on screen, so the two never move at once.
enum NewTabKeyboardDeparture: Equatable {
    case openNow
    /// The keyboard is already sliding away.
    case waitForHide
    /// A focused field holds the keyboard up, and resigning it sends the keyboard away.
    case resignThenWaitForHide

    /// Waits only when keyboardDidHide is sure to follow, so a stale `keyboardShowing` alone never holds a tab back.
    static func plan(keyboardShowing: Bool, isHiding: Bool, hasFocusedField: Bool) -> Self {
        if isHiding { return .waitForHide }
        if keyboardShowing && hasFocusedField { return .resignThenWaitForHide }
        return .openNow
    }
}
