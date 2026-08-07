//
//  FocusedLogoModel.swift
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

/// The focused empty-state logo's presentation: which mark it shows (`progress`), whether it morphs
/// to reach it, and how fast. A pure value type — every transition is a deterministic function of the
/// resolver output and the dismiss lifecycle, so the morph rules are unit-testable in isolation.
struct FocusedLogoModel: Equatable {

    /// The Dax↔Duck.ai morph asset's natural duration (16 frames @ 30fps); used to derive a morph
    /// speed that fits a dismiss collapse. Keep in sync with the asset.
    static let transitionDuration: TimeInterval = 16.0 / 30.0

    /// 0 = Dax/search, 1 = Duck.ai.
    private(set) var progress: CGFloat = 0
    /// Animate the morph to `progress` (vs. snap straight to it).
    private(set) var morphs = false
    /// Playback rate for the morph; >1 to fit a dismiss collapse.
    private(set) var morphSpeed: Double = 1

    /// React to a resolved content state during a session:
    /// - Morph only for an *in-session* logo→logo change; the first resolve after a focus snaps (the
    ///   logo was hidden in between), so a refocus never replays a stale Duck.ai→search morph.
    /// - Retarget the mark only while the logo is (becoming) visible; otherwise keep the current mark
    ///   so it fades out as-is instead of snapping to the other mode's mark first.
    mutating func update(wasLogo: Bool, isLogo: Bool, isDuckAI: Bool, isFirstSinceActivation: Bool) {
        morphs = wasLogo && isLogo && !isFirstSinceActivation
        if isLogo {
            progress = isDuckAI ? 1 : 0
        }
        morphSpeed = 1
    }

    /// Morph back to the Dax mark and keep showing (a logo→logo dismiss), sped up so the morph
    /// finishes within the bar's `collapseDuration` instead of being cut off.
    mutating func morphToDax(matching collapseDuration: TimeInterval) {
        progress = 0
        morphs = true
        morphSpeed = max(1, Self.transitionDuration / collapseDuration)
    }
}
