//
//  UTIRenderState.swift
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

struct UTIRenderState: Equatable {
    var isInputVisible: Bool
    var isContentVisible: Bool
    var isExpanded: Bool
    var cardPosition: UnifiedToggleInputCardPosition
    var usesOmnibarMargins: Bool
    var isToolbarSubmitHidden: Bool
    var inactiveAppearance: Bool
    var isFloatingSubmitVisible: Bool
    var isToggleEnabled: Bool
    var contentInputMode: TextEntryMode
    var inputMode: TextEntryMode

    var viewConfig: UTIViewConfig {
        UTIViewConfig(
            isExpanded: isExpanded,
            cardPosition: cardPosition,
            usesOmnibarMargins: usesOmnibarMargins,
            isToolbarSubmitHidden: isToolbarSubmitHidden,
            inactiveAppearance: inactiveAppearance,
            inputMode: inputMode,
            isTopBarPosition: usesOmnibarMargins
        )
    }

    /// The inline dismiss (X inside the card's top row) takes over when the expanded card is
    /// anchored at the top with the Search/Duck.ai toggle enabled. When the toggle setting is
    /// disabled, the card has no top row to host the X, so the floating dismiss in the content
    /// container is used instead.
    var isInlineDismissActive: Bool {
        cardPosition == .top && isExpanded && isToggleEnabled
    }

    var isFloatingDismissVisible: Bool {
        isContentVisible && !isInlineDismissActive
    }

}
