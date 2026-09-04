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

    /// Keep focused Favorites clear of the standalone floating toolbar, using the NTP's regular spacing.
    static func focusedFavoritesBottomSpacing(isFloatingUIEnabled: Bool,
                                              isAddressBarAtBottom: Bool,
                                              isLandscape: Bool,
                                              isShowingFavorites: Bool) -> CGFloat {
        isFloatingUIEnabled && !isAddressBarAtBottom && !isLandscape && isShowingFavorites ? 24 : 0
    }

    /// Additional NTP clearance beyond the system safe area. Floating bottom chrome contains both
    /// the address field and buttons; detached input and minimal chrome keep the field-only inset.
    static func newTabPageBottomInset(isFloatingUIEnabled: Bool,
                                      isOmnibarInToolbar: Bool,
                                      omnibarHeight: CGFloat,
                                      toolbarHeight: CGFloat) -> CGFloat {
        isFloatingUIEnabled && isOmnibarInToolbar ? toolbarHeight : omnibarHeight
    }

    static func shouldApplyFloatingTopContentInset(isFloatingUIEnabled: Bool,
                                                   addressBarPosition: AddressBarPosition,
                                                   isUnifiedToggleInputAffectingLayout: Bool) -> Bool {
        isFloatingUIEnabled && addressBarPosition == .top && !isUnifiedToggleInputAffectingLayout
    }

    /// Fraction of a bar's slide travel that is still on screen while the domain capsule morph owns the
    /// transition. The pill morphs out of the bar's *resting* frame, so the bar has to hold that frame
    /// until the cross-fade has finished — sliding during the fade separates the two and the bar
    /// visibly creeps away before it disappears. It slides out over `[0, handoffStart]` instead, by
    /// which point it is no longer drawn.
    static func chromeOnScreenFraction(barsVisibilityPercent: CGFloat, handoffStart: CGFloat) -> CGFloat {
        guard handoffStart > 0 else { return barsVisibilityPercent > 0 ? 1 : 0 }
        let clampedPercent = max(0, min(1, barsVisibilityPercent))
        return min(1, clampedPercent / handoffStart)
    }

    /// Height obscured by the visible bottom chrome, measured from the web view container's bottom edge
    /// (the screen bottom). The floating web view is resized up by this amount so a page `position: fixed`
    /// footer pins to the top of whatever is on screen at the bottom:
    /// - toolbar shown -> `toolbarSlotHeight` (footer above the toolbar),
    /// - toolbar still on screen during the morph -> `visibleToolbarHeight` (footer above the live bar),
    /// - toolbar hidden + bottom capsule -> `bottomCapsuleObscuredHeight` (footer above the capsule),
    /// - neither -> `safeAreaBottom` (footer at the safe area).
    ///
    /// `max` gives a smooth crossover: the shrinking toolbar term and the on-screen floor dominate while
    /// the bars are visible, then the (stable) capsule / safe-area term takes over once the bars have hidden.
    static func webViewBottomObscuredHeight(barsVisibilityPercent: CGFloat,
                                            toolbarSlotHeight: CGFloat,
                                            visibleToolbarHeight: CGFloat = 0,
                                            bottomCapsuleObscuredHeight: CGFloat,
                                            safeAreaBottom: CGFloat) -> CGFloat {
        let clampedPercent = max(0, min(1, barsVisibilityPercent))
        return max(toolbarSlotHeight * clampedPercent, visibleToolbarHeight, bottomCapsuleObscuredHeight, safeAreaBottom)
    }

    /// Top counterpart of `webViewBottomObscuredHeight`. `visibleChromeHeight` is the on-screen floor
    /// while the top bar is pinned through the capsule hand-off, so a page `position: fixed` header
    /// stays below the bar the user can still see instead of sliding under it.
    static func webViewTopObscuredHeight(barsVisibilityPercent: CGFloat,
                                         expandedChromeHeight: CGFloat,
                                         visibleChromeHeight: CGFloat = 0,
                                         topCapsuleObscuredHeight: CGFloat,
                                         safeAreaTop: CGFloat) -> CGFloat {
        let clampedPercent = max(0, min(1, barsVisibilityPercent))
        return max(expandedChromeHeight * clampedPercent, visibleChromeHeight, topCapsuleObscuredHeight, safeAreaTop)
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
