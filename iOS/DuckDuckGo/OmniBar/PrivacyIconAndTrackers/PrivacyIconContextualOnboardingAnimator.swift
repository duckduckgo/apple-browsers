//
//  PrivacyIconContextualOnboardingAnimator.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import UIKit

final class PrivacyIconContextualOnboardingAnimator {

    func showPrivacyIconAnimation(in omniBar: any OmniBarView) {
        guard let window = omniBar.window else { return }
        // Center on the actual shield animation view (47x47), not the container (28x28)
        // This accounts for the larger animation that overflows the privacy icon container
        let targetView: UIView = omniBar.privacyInfoContainer.privacyIcon.shieldAnimationView ?? omniBar.privacyInfoContainer.privacyIcon
        ViewHighlighter.showIn(window, focussedOnView: targetView, scale: .custom(3))
    }

    func dismissPrivacyIconAnimation(_ view: PrivacyIconView) {
        if isPrivacyIconHighlighted(view) {
            ViewHighlighter.hideAll()
        }
    }

    /// Force-dismiss the privacy-icon pulse regardless of the `isPrivacyIconHighlighted` gate.
    /// `dismissPrivacyIconAnimation(_:)` only checks for a highlight whose anchor view is exactly
    /// the outer `PrivacyIconView`, but `showPrivacyIconAnimation(in:)` actually anchors the
    /// highlight to the inner `shieldAnimationView` whenever it's available — so the gated
    /// path silently misses the highlight in practice. This variant removes both anchors via
    /// the per-view `ViewHighlighter.hide(focussedOnView:)`, leaving any other concurrent
    /// highlight (e.g. the fire-button pulse) intact. It's intended for explicit user actions
    /// — taps that should make the pulse go away regardless of state — and is *not* called
    /// from `cancelAllAnimations`, so the existing show timing is preserved.
    func forceDismissPrivacyIconAnimation(_ view: PrivacyIconView) {
        ViewHighlighter.hide(focussedOnView: view)
        if let shieldAnimationView = view.shieldAnimationView {
            ViewHighlighter.hide(focussedOnView: shieldAnimationView)
        }
    }

    func isPrivacyIconHighlighted(_ view: PrivacyIconView) -> Bool {
        ViewHighlighter.highlightedViews.contains(where: { $0.view == view })
    }
}
