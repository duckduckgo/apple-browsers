//
//  FocusedContentDismissFade.swift
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

import SwiftUI

/// Content fades on a mode switch. A leaving logo fades out first and the incoming content appears
/// once it has gone, so the two never overlap.
enum FocusedContentFade {
    static let duration: TimeInterval = 0.15
    static let fadeOut = Animation.easeOut(duration: duration)
    static let fadeIn = Animation.easeInOut(duration: duration)
    /// Shows content at once when the logo has faded out. SwiftUI needs a duration for the delay to hold.
    static let afterLogoFadeOut = Animation.linear(duration: 0.01).delay(duration)
}

/// Fades transient content (logo, suggestion list) out as the host collapses back to the NTP, so it
/// hands off to the NTP content instead of snapping away. Favorites are excluded — they hand off via
/// the embedded-copy reveal, not a fade.
///
/// One-directional: only the fade-*out* (false→true) animates. The reset (true→false, on the next
/// focus) snaps, so the logo reappears instantly instead of replaying a fade-in.
struct FocusedContentDismissFade: ViewModifier {
    let isFadingOut: Bool
    func body(content: Content) -> some View {
        content
            .opacity(isFadingOut ? 0 : 1)
            .animation(isFadingOut ? .easeInOut(duration: 0.2) : nil, value: isFadingOut)
    }
}

/// Content inserted by a mode switch appears once the leaving logo has faded out. Read when the
/// content is inserted, after the switch has resolved, so a focus or a typing change shows it at once.
struct FocusedContentDelayedReveal: ViewModifier {
    @State private var isRevealed: Bool

    init(isDelayed: () -> Bool) {
        // One-time seed: the content is inserted fresh on each switch.
        _isRevealed = State(initialValue: !isDelayed())
    }

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .onAppear {
                guard !isRevealed else { return }
                withAnimation(FocusedContentFade.afterLogoFadeOut) { isRevealed = true }
            }
    }
}
