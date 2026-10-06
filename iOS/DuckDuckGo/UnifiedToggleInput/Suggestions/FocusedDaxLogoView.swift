//
//  FocusedDaxLogoView.swift
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

import Lottie
import SwiftUI
import DesignResourcesKitIcons

/// The focused-omnibar empty-state logo, morphing Dax ↔ Duck.ai via a bound `progress`
/// (0 = Dax/search, 1 = Duck.ai). Renders through the same Lottie asset as `NewTabPageDaxLogoView`
/// so the focused and NTP logos stay pixel-identical. No positioning or visibility logic — the host owns that.
struct FocusedDaxLogoView: View {
    @Environment(\.colorScheme) private var colorScheme

    /// 0 = Dax (search), 1 = Duck.ai.
    let progress: CGFloat
    /// When true, animate the morph from the current frame to `progress`; when false, jump straight to
    /// it (used when the logo is crossfading in/out against favorites/lists, where a morph isn't wanted).
    var morph: Bool = true
    /// Playback rate for the morph. >1 finishes faster — used so a dismiss morph fits inside the
    /// (shorter) bar collapse instead of being cut off.
    var animationSpeed: Double = 1

    private var animationName: String {
        let isDark = colorScheme == .dark
        if AppRebrand.isAppRebranded() {
            return isDark ? Constant.darkAnimationName : Constant.animationName
        } else {
            return isDark ? Constant.darkAnimationNameLegacy : Constant.animationNameLegacy
        }
    }

    private var playbackMode: LottiePlaybackMode {
        morph ? .playing(.toProgress(progress, loopMode: .playOnce)) : .paused(at: .progress(progress))
    }

    var body: some View {
        Lottie.LottieView(animation: LottieAnimation.named(animationName))
            .playbackMode(playbackMode)
            .animationSpeed(animationSpeed)
            .frame(height: Constant.logoHeight)
            .id(animationName)
    }

    private enum Constant {
        static let animationName = "duckduckgo-ai-transition.json"
        static let darkAnimationName = "duckduckgo-ai-transition-dark.json"
        static let animationNameLegacy = "duckduckgo-ai-transition-legacy.json"
        static let darkAnimationNameLegacy = "duckduckgo-ai-transition-dark-legacy.json"
        static let logoHeight: CGFloat = 162
    }
}
