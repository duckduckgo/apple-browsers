//
//  DuckAiTermsOfServiceDisclaimer.swift
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

import AIChat
import FeatureFlags_macOS
import Foundation
import os.log
import PrivacyConfig

/// The native Duck.ai input's Terms of Service rules: required until the user accepts on either side,
/// and clicking Ask with the disclaimer on screen is the acceptance.
struct DuckAiTermsOfServiceDisclaimer {

    private let featureFlagger: FeatureFlagger
    private let store: DuckAiTermsOfServiceStore

    init(featureFlagger: FeatureFlagger, store: DuckAiTermsOfServiceStore = DuckAiTermsOfServiceStore()) {
        self.featureFlagger = featureFlagger
        self.store = store
    }

    /// Read on every call, so an acceptance made on the web or in another window retires it.
    var isRequired: Bool {
        featureFlagger.isFeatureOn(.aiChatNativeTermsOfService) && !store.hasAccepted
    }

    /// Call only for an Ask click. `isShown` is whether the input's card shows the disclaimer right now; a send
    /// made without seeing it accepts nothing, and the web app shows its own card for that prompt instead.
    @discardableResult
    func acceptIfShown(_ isShown: Bool) -> Bool {
        guard isShown, isRequired else { return false }
        store.recordAcceptedInNativeInput()
        Logger.aiChat.debug("[TermsOfService] Ask clicked with the disclaimer on screen: acceptance recorded")
        return true
    }
}

/// The send button the disclaimer names, as on the web: "Create" while Create Image is selected, "Ask" otherwise.
enum DuckAiTermsOfServiceSendButton: CaseIterable {
    case ask
    case create

    init(isImageGenerationMode: Bool) {
        self = isImageGenerationMode ? .create : .ask
    }

    var title: String {
        switch self {
        case .ask: return UserText.aiChatAskButtonTitle
        case .create: return UserText.aiChatCreateButtonTitle
        }
    }

    var disclaimerFormat: String {
        switch self {
        case .ask: return UserText.aiChatTermsOfServiceDisclaimer
        case .create: return UserText.aiChatTermsOfServiceCreateDisclaimer
        }
    }
}
