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
    /// treats the region covered by the glass chrome as obscured. This lays out page `position: fixed`
    /// elements below the top omnibar / above the bottom toolbar (matching Safari) and offsets
    /// scrollable content to match.
    ///
    /// The inset is held constant regardless of chrome visibility: when the bars hide on scroll their
    /// space is retained and the floating domain capsule occupies it (matching Safari), so page content
    /// stays put instead of jumping. Keeping it constant also avoids re-laying-out fixed elements on
    /// every scroll frame. Returns `.zero` while the unified toggle input owns the layout, since the
    /// content is anchored to the chrome there.
    static func webViewAdditionalSafeAreaInsets(addressBarPosition: AddressBarPosition,
                                                isUnifiedToggleInputAffectingLayout: Bool,
                                                omniBarHeight: CGFloat,
                                                toolbarHeight: CGFloat) -> UIEdgeInsets {
        guard !isUnifiedToggleInputAffectingLayout else { return .zero }
        switch addressBarPosition {
        case .top:
            return UIEdgeInsets(top: omniBarHeight, left: 0, bottom: 0, right: 0)
        case .bottom:
            return UIEdgeInsets(top: 0, left: 0, bottom: toolbarHeight, right: 0)
        }
    }

    static func shouldHostOmnibarInFloatingToolbar(isFloatingUIEnabled: Bool,
                                                   addressBarPosition: AddressBarPosition,
                                                   isUnifiedToggleInputVisible: Bool) -> Bool {
        isFloatingUIEnabled && addressBarPosition.isBottom && !isUnifiedToggleInputVisible
    }

    static func shouldShowFloatingDomainCapsule(isFloatingUIEnabled: Bool,
                                                isUnifiedToggleInputActive: Bool,
                                                isAITab: Bool,
                                                isMinimalChromeLayout: Bool) -> Bool {
        isFloatingUIEnabled && !isUnifiedToggleInputActive && !isAITab && !isMinimalChromeLayout
    }
}
