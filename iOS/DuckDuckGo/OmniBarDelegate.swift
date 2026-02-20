//
//  OmniBarDelegate.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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
import Suggestions
import Bookmarks
import AIChat

enum OmniBarEditingEndResult {
    case suspended
    case dismissed
}

protocol OmniBarDelegate: AnyObject {

    func onOmniQueryUpdated(_ query: String)
    
    func onOmniQuerySubmitted(_ query: String)

    func onOmniSuggestionSelected(_ suggestion: Suggestion)
    
    func onEditingEnd() -> OmniBarEditingEndResult

    func onPrivacyIconPressed(isHighlighted: Bool)
    
    func onMenuPressed()

    func onBookmarksPressed()
    
    func onSettingsPressed()

    func onMenuLongPressed()

    func onClearTextPressed()

    func onAbortPressed()

    func onCancelPressed()
    
    func onEnterPressed()

    func onRefreshPressed()

    func onCustomizableButtonPressed()

    func onBackPressed()
    
    func onForwardPressed()
    
    func onAIChatPressed()

    /// Called when the AI Chat left button is tapped
    func onAIChatLeftButtonPressed()

    /// Called when the AI Chat full mode omnibar branding area is tapped.
    func onAIChatBrandingPressed()

    func onTextFieldWillBeginEditing(_ omniBar: OmniBarView, tapped: Bool)

    // Returns whether field should select the text or not
    func onTextFieldDidBeginEditing(_ omniBar: OmniBarView) -> Bool

    func selectedSuggestion() -> Suggestion?
    
    func onVoiceSearchPressed()
    
    func onVoiceSearchPressed(preferredTarget: VoiceSearchTarget)

    func onDidBeginEditing()

    func onDidEndEditing()

    /// SwitchBar
    func onPromptSubmitted(_ query: String, tools: [AIChatRAGTool]?)

    func onSelectFavorite(_ favorite: BookmarkEntity)
    func onEditFavorite(_ favorite: BookmarkEntity)

    func didRequestCurrentURL() -> URL?

    func isSuggestionTrayVisible() -> Bool

    func onDaxLogoTapped(logoURL: URL?, image: UIImage?, sourceFrame: CGRect)

    /// Called when user selects a chat from the AI Chat history list
    func onChatHistorySelected(url: URL)

    // MARK: - Experimental Address Bar
    func onExperimentalAddressBarTapped()
    func onExperimentalAddressBarClearPressed()
    func onExperimentalAddressBarCancelPressed()
    func dismissContextualSheetIfNeeded(completion: @escaping () -> Void)
}

extension OmniBarDelegate {
    
    func onOmniQueryUpdated(_ query: String) {
        
    }
    
    func onOmniQuerySubmitted(_ query: String) {
        
    }
    
    func onPrivacyIconPressed(isHighlighted: Bool) {

    }
    
    func onMenuPressed() {
        
    }

    func onBookmarksPressed() {
        
    }
    
    func onSettingsPressed() {
        
    }

    func onMenuLongPressed() {

    }

    func onCancelPressed() {
        
    }
    
    func onRefreshPressed() {
    
    }

    func onAIChatPressed() {
    }

    func onAIChatLeftButtonPressed() {
    }

    func onAIChatBrandingPressed() {
    }

    func onBackPressed() {
    }
    
    func onForwardPressed() {
    }
    
    func onVoiceSearchPressed(preferredTarget: VoiceSearchTarget) {
        onVoiceSearchPressed()
    }

    func onDaxLogoTapped(logoURL: URL?, image: UIImage?, sourceFrame: CGRect) {
    }

    func onChatHistorySelected(url: URL) {
    }

    // Default no-op implementations for experimental address bar pixel hooks
    func onExperimentalAddressBarTapped() {}
    func onExperimentalAddressBarClearPressed() {}
    func onExperimentalAddressBarCancelPressed() {}

    func dismissContextualSheetIfNeeded(completion: @escaping () -> Void) {
        completion()
    }
}
