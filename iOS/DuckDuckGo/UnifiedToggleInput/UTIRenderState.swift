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

func unifiedToggleInputDebug(_ message: @autoclosure () -> String) {
    print("[UTI_DEBUG] \(message())")
}

struct UTIRenderState: Equatable {
    var isInputVisible: Bool
    var isContentVisible: Bool
    var isExpanded: Bool
    var cardPosition: UnifiedToggleInputCardPosition
    var usesOmnibarMargins: Bool
    var showsDismissButton: Bool
    var isToolbarSubmitHidden: Bool
    var inactiveAppearance: Bool
    var isFloatingSubmitVisible: Bool
    var headerDisplayMode: UnifiedInputContentContainerViewController.HeaderDisplayMode
    var contentInputMode: TextEntryMode
    var inputMode: TextEntryMode

    var viewConfig: UTIViewConfig {
        UTIViewConfig(
            isExpanded: isExpanded,
            cardPosition: cardPosition,
            usesOmnibarMargins: usesOmnibarMargins,
            showsDismissButton: showsDismissButton,
            isToolbarSubmitHidden: isToolbarSubmitHidden,
            inactiveAppearance: inactiveAppearance,
            inputMode: inputMode,
            isTopBarPosition: usesOmnibarMargins
        )
    }

    var utiDebugDescription: String {
        "inputVisible=\(isInputVisible) contentVisible=\(isContentVisible) expanded=\(isExpanded) cardPosition=\(String(describing: cardPosition)) usesMargins=\(usesOmnibarMargins) dismiss=\(showsDismissButton) toolbarHidden=\(isToolbarSubmitHidden) inactive=\(inactiveAppearance) floatingSubmit=\(isFloatingSubmitVisible) header=\(String(describing: headerDisplayMode)) contentMode=\(contentInputMode.rawValue) inputMode=\(inputMode.rawValue)"
    }
}
