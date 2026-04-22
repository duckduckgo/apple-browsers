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
    var isInlineDismissActive: Bool
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

    /// The floating dismiss control (owned by the content container) is shown whenever content
    /// is visible but the inline dismiss button in the card is not currently taking over. At
    /// `.bottom` the inline dismiss never applies, and at `.top` the inline dismiss only takes
    /// over once the Search/Duck.ai toggle is in place (i.e. not during keyboard-presentation
    /// transients and not when the toggle setting is disabled).
    var isFloatingDismissVisible: Bool {
        isContentVisible && !isInlineDismissActive
    }

}
