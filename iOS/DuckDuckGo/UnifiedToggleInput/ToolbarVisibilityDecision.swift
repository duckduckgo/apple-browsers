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

/// Pure decision for the browser toolbar's visibility on the current tab.
struct ToolbarVisibilityDecision: Equatable {
    let isHidden: Bool

    /// Value-only inputs, so the decision is pure and its tests need no mocks.
    struct Inputs: Equatable {
        let isCurrentTabUsingUnifiedInputAIChrome: Bool
        let isLargeWidth: Bool
        let isInMinimalChromeLayout: Bool
    }

    static func resolve(_ inputs: Inputs) -> ToolbarVisibilityDecision {
        ToolbarVisibilityDecision(isHidden: shouldHide(inputs))
    }

    private static func shouldHide(_ inputs: Inputs) -> Bool {
        // A Duck.ai tab has no bottom toolbar, and neither do iPad / minimal-chrome layouts.
        inputs.isCurrentTabUsingUnifiedInputAIChrome
            || inputs.isLargeWidth
            || inputs.isInMinimalChromeLayout
    }
}
