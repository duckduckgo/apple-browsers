//
//  UpdatePromptAttribution.swift
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

/// The update entry points a user can click, reported as `promptSurface` so pixels identify the stage and entry point.
///
/// `menuItem` is the regular update item, which carries the menu dot at `.firstPrompt` and is the only entry point
/// while the progressive prompts are off. The other surfaces each appear at a single stage:
/// - `menuRow` at `.secondPrompt`
/// - `menuCard` and `toolbarButton` at `.thirdPrompt`.
/// Critical updates go straight to `.thirdPrompt`.
public enum UpdatePromptSurface: String, CaseIterable, Sendable {
    case menuItem = "menu-item"
    case menuRow = "menu-row"
    case menuCard = "menu-card"
    case toolbarButton = "toolbar-button"
}

/// Remembers the last update entry point the user clicked, so the update success pixel can name it after the restart.
public struct UpdatePromptAttribution {

    /// Value reported when no entry point was clicked within `window` before the update.
    public static let noSurface = "none"
    public static let window: TimeInterval = 7 * 24 * 60 * 60

    private let settings: any ThrowingKeyedStoring<UpdateControllerSettings>
    private let now: () -> Date

    public init(settings: any ThrowingKeyedStoring<UpdateControllerSettings>, now: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.now = now
    }

    public func recordClick(on surface: UpdatePromptSurface) {
        try? settings.set(surface.rawValue, for: \.updatePromptClickedSurface)
        try? settings.set(now(), for: \.updatePromptClickedDate)
    }

    /// Returns the clicked surface's value, or `noSurface` when there's none within `window`, and forgets the click.
    public func consumePromptSurface() -> String {
        defer {
            try? settings.set(nil, for: \.updatePromptClickedSurface)
            try? settings.set(nil, for: \.updatePromptClickedDate)
        }

        guard let surface = try? settings.updatePromptClickedSurface,
              let date = try? settings.updatePromptClickedDate,
              now().timeIntervalSince(date) <= Self.window else {
            return Self.noSurface
        }
        return surface
    }
}
