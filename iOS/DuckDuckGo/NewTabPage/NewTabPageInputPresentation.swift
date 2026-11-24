//
//  NewTabPageInputPresentation.swift
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

/// The page a redesigned focused state sits over.
enum RedesignedFocusedSurface: Equatable {
    /// Favorites, messages and the escape hatch, as on the new tab page.
    case newTabPage
    /// Only the favorites grid.
    case webPage

    /// Whether a Search and Duck.ai switch swaps the empty-state logo at once, instead of keeping it in place.
    var swapsLogoOnModeChange: Bool {
        self == .newTabPage
    }
}

enum NewTabPageInputPresentation: Equatable {
    case browser
    case resting(usesUnifiedInput: Bool)
    case editing(usesUnifiedInput: Bool)

    enum Transition {
        case omnibar
        case inlineInput
    }

    static func resolve(hasInlineInput: Bool,
                        usesUnifiedInput: Bool,
                        isLegacyInputEditing: Bool,
                        isUnifiedInputEditing: Bool,
                        isHandingOff: Bool,
                        isDismissing: Bool = false,
                        isPresentingOnboardingDialog: Bool = false) -> Self {
        guard hasInlineInput, !isPresentingOnboardingDialog else { return .browser }
        let isEditing = isLegacyInputEditing || isUnifiedInputEditing || isHandingOff || isDismissing
        return isEditing ? .editing(usesUnifiedInput: usesUnifiedInput) : .resting(usesUnifiedInput: usesUnifiedInput)
    }

    /// Only an inline NTP editing session can select the redesigned focused presentation.
    func usesRedesignedFocusedLayout(isOnAITab: Bool) -> Bool {
        !isOnAITab && self == .editing(usesUnifiedInput: true)
    }

    /// The redesigned focused surface this presentation selects, or nil for the legacy one.
    /// A web page keeps the browser presentation, but its focused state shows the redesigned favorites.
    func redesignedFocusedSurface(isOnAITab: Bool, isOnWebPage: Bool) -> RedesignedFocusedSurface? {
        if usesRedesignedFocusedLayout(isOnAITab: isOnAITab) { return .newTabPage }
        if !isOnAITab, isOnWebPage, self == .browser { return .webPage }
        return nil
    }

    var hidesNavigationContainer: Bool {
        if case .resting = self { return true }
        return false
    }

    var hidesRestingOmnibar: Bool {
        switch self {
        case .browser: return false
        case .resting(let usesUnifiedInput), .editing(let usesUnifiedInput): return usesUnifiedInput
        }
    }

    var reservesAddressBarSpace: Bool {
        !hidesNavigationContainer && !hidesRestingOmnibar
    }

    var transition: Transition {
        hidesRestingOmnibar ? .inlineInput : .omnibar
    }
}
