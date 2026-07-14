//
//  ToolbarVisibilityDecision.swift
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

import CoreGraphics

enum ToolbarVisibility: Equatable {
    case hidden
    /// `healsClampConstant` snaps a stale off-screen toolbar constraint back on-screen. See
    /// `MainViewController.reconcileToolbarVisibilityForCurrentTab`.
    case visible(healsClampConstant: Bool)
}

/// Pure decision for the browser toolbar's visibility on the current tab.
struct ToolbarVisibilityDecision: Equatable {
    let visibility: ToolbarVisibility
    /// True when the toolbar's hidden-state flips, so the bars layout must be recomputed.
    let recomputesBars: Bool

    /// Value-only inputs, so the decision is pure and its tests need no mocks.
    struct Inputs: Equatable {
        let isCurrentTabUsingUnifiedInputAIChrome: Bool
        let isFocusedOmnibarSession: Bool
        let isLargeWidth: Bool
        let isInMinimalChromeLayout: Bool
        let currentToolbarIsHidden: Bool
        let toolbarAlpha: CGFloat
        let toolbarBottomConstant: CGFloat
    }

    static func resolve(_ inputs: Inputs) -> ToolbarVisibilityDecision {
        let visibility = resolveVisibility(inputs)
        let willHide = (visibility == .hidden)
        return ToolbarVisibilityDecision(
            visibility: visibility,
            recomputesBars: inputs.currentToolbarIsHidden != willHide
        )
    }

    private static func resolveVisibility(_ inputs: Inputs) -> ToolbarVisibility {
        if inputs.isCurrentTabUsingUnifiedInputAIChrome && !inputs.isFocusedOmnibarSession {
            return .hidden
        }
        if inputs.isLargeWidth || inputs.isInMinimalChromeLayout {
            return .hidden
        }
        // alpha == 1 excludes mid-scroll partial hides; a non-zero constant with full alpha is a
        // stale clamp left by a transient AI-tab phase.
        let healsClampConstant = inputs.toolbarAlpha == 1.0 && inputs.toolbarBottomConstant != 0
        return .visible(healsClampConstant: healsClampConstant)
    }
}
