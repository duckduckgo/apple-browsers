//
//  FloatingUILayoutPolicy.swift
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

import Core
import UIKit

enum FloatingUILayoutPolicy {

    static func shouldApplyFloatingTopContentInset(isFloatingUIEnabled: Bool,
                                                   addressBarPosition: AddressBarPosition,
                                                   isUnifiedToggleInputAffectingLayout: Bool) -> Bool {
        isFloatingUIEnabled && addressBarPosition == .top && !isUnifiedToggleInputAffectingLayout
    }

    /// Height obscured by the visible bottom chrome, measured from the web view container's bottom edge
    /// (the screen bottom). The floating web view is resized up by this amount so a page `position: fixed`
    /// footer pins to the top of whatever is on screen at the bottom:
    /// - toolbar shown -> `toolbarSlotHeight` (footer above the toolbar),
    /// - toolbar hidden + bottom capsule -> `bottomCapsuleObscuredHeight` (footer above the capsule),
    /// - neither -> `safeAreaBottom` (footer at the safe area).
    ///
    /// `max` gives a smooth crossover: the shrinking toolbar term dominates while the bars are visible,
    /// then the (stable) capsule / safe-area term takes over once the bars have hidden.
    static func webViewBottomObscuredHeight(barsVisibilityPercent: CGFloat,
                                            toolbarSlotHeight: CGFloat,
                                            bottomCapsuleObscuredHeight: CGFloat,
                                            safeAreaBottom: CGFloat) -> CGFloat {
        let clampedPercent = max(0, min(1, barsVisibilityPercent))
        return max(toolbarSlotHeight * clampedPercent, bottomCapsuleObscuredHeight, safeAreaBottom)
    }

    static func webViewTopObscuredHeight(barsVisibilityPercent: CGFloat,
                                         expandedChromeHeight: CGFloat,
                                         topCapsuleObscuredHeight: CGFloat,
                                         safeAreaTop: CGFloat) -> CGFloat {
        let clampedPercent = max(0, min(1, barsVisibilityPercent))
        return max(expandedChromeHeight * clampedPercent, topCapsuleObscuredHeight, safeAreaTop)
    }

    /// Top offset for the contextual onboarding dialog in the tab's content stack. Only the web view
    /// can underflow the chrome (via `obscuredContentInsets`); the dialog is a plain UIKit sibling, so
    /// it needs the obscured region as an offset or it renders behind the chrome.
    static func contextualOnboardingTopInset(isFloatingUIEnabled: Bool,
                                             isContextualOnboardingVisible: Bool,
                                             topObscuredHeight: CGFloat) -> CGFloat {
        guard isFloatingUIEnabled, isContextualOnboardingVisible else { return 0 }
        return max(0, topObscuredHeight)
    }

    /// Height obscured at the top of the new tab page by the focused unified toggle input card. Only
    /// floating UI floats the card over the page; the classic layout puts it above.
    ///
    /// `cardBottomEdge` must come from the card's applied constraints, not its measured height — those
    /// diverge under the landscape cap and while the chrome is hidden.
    static func newTabPageUnifiedInputTopObscuredHeight(isFloatingUIEnabled: Bool,
                                                        isUnifiedToggleInputActive: Bool,
                                                        addressBarPosition: AddressBarPosition,
                                                        cardBottomEdge: CGFloat) -> CGFloat {
        // A bottom-position card obscures nothing at the top.
        guard isFloatingUIEnabled, isUnifiedToggleInputActive, addressBarPosition == .top else { return 0 }
        return max(0, cardBottomEdge)
    }

    static func shouldHostOmnibarInFloatingToolbar(isFloatingUIEnabled: Bool,
                                                   addressBarPosition: AddressBarPosition,
                                                   isUnifiedToggleInputVisible: Bool,
                                                   isMinimalChromeLayout: Bool) -> Bool {
        // Excludes minimal chrome, where the toolbar is hidden and would take the omnibar with it.
        isFloatingUIEnabled && addressBarPosition.isBottom && !isUnifiedToggleInputVisible && !isMinimalChromeLayout
    }

    static func shouldShowFloatingDomainCapsule(isFloatingUIEnabled: Bool,
                                                isUnifiedToggleInputActive: Bool,
                                                isAITab: Bool,
                                                isMinimalChromeLayout: Bool) -> Bool {
        isFloatingUIEnabled && !isUnifiedToggleInputActive && !isAITab && !isMinimalChromeLayout
    }
}
