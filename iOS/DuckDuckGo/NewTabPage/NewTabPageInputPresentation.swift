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
                        isDismissing: Bool = false) -> Self {
        guard hasInlineInput else { return .browser }
        let isEditing = isLegacyInputEditing || isUnifiedInputEditing || isHandingOff || isDismissing
        return isEditing ? .editing(usesUnifiedInput: usesUnifiedInput) : .resting(usesUnifiedInput: usesUnifiedInput)
    }

    var usesFocusedContentContainer: Bool {
        self == .editing(usesUnifiedInput: true)
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
