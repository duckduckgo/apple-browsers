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

    /// Additional safe-area insets applied to the web view's controller in floating UI mode so WebKit
    /// treats the region covered by the top glass chrome as obscured, laying out page `position: fixed`
    /// top elements below the omnibar and offsetting scrollable content to match.
    ///
    /// Only the top is applied here: the bottom obscured region is handled by physically resizing the
    /// web view (see `webViewBottomObscuredHeight`), which pins bottom `position: fixed` elements
    /// reliably on load without depending on a WebKit inset relayout. Returns `.zero` while the unified
    /// toggle input owns the layout, since the content is anchored to the chrome there.
    static func webViewAdditionalSafeAreaInsets(addressBarPosition: AddressBarPosition,
                                                isUnifiedToggleInputAffectingLayout: Bool,
                                                omniBarHeight: CGFloat) -> UIEdgeInsets {
        guard !isUnifiedToggleInputAffectingLayout else { return .zero }
        switch addressBarPosition {
        case .top:
            return UIEdgeInsets(top: omniBarHeight, left: 0, bottom: 0, right: 0)
        case .bottom:
            return .zero
        }
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
