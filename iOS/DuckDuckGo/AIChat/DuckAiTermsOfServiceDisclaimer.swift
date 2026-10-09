//
//  DuckAiTermsOfServiceDisclaimer.swift
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

import AIChat
import Foundation
import os.log

/// The UTI footer's Terms of Service rules, for the iPad inputs that have no UTI: required until the
/// user accepts on either side, and tapping Ask with it on screen is the acceptance.
struct DuckAiTermsOfServiceDisclaimer {

    private let feature: DuckAiNativeTermsOfServiceFeatureProviding
    private let store: DuckAiTermsOfServiceStore
    private let mapper: UTIFooterMessageMapper

    init(feature: DuckAiNativeTermsOfServiceFeatureProviding = DuckAiNativeTermsOfServiceFeature(),
         store: DuckAiTermsOfServiceStore = DuckAiTermsOfServiceStore(),
         mapper: UTIFooterMessageMapper = UTIFooterMessageMapper()) {
        self.feature = feature
        self.store = store
        self.mapper = mapper
    }

    /// Read on every call, so an acceptance made on the web or in another input retires it.
    func message(sendButton: DuckAiTermsOfServiceSendButton) -> UTIFooterMessage? {
        guard feature.isAvailable, !store.hasAccepted else { return nil }
        return mapper.termsOfServiceMessage(sendButton: sendButton)
    }

    /// Whether `visibleMessage` is the disclaimer, whichever send button it names.
    func isDisclaimer(_ visibleMessage: UTIFooterMessage?) -> Bool {
        guard let visibleMessage else { return false }
        return DuckAiTermsOfServiceSendButton.allCases.contains { message(sendButton: $0) == visibleMessage }
    }

    /// Off with the flag, so no prompt claims an acceptance made while native Terms of Service was on.
    var hasAccepted: Bool { feature.isAvailable && store.hasAccepted }

    /// These inputs have no usage-limit block, so nothing keeps a session out of the `not_shown` group.
    func startMeasurementSession(_ measurement: DuckAiTermsOfServiceMeasurement, isDisclaimerShown: Bool) {
        measurement.inputSessionStarted(hasAccepted: store.hasAcceptedOrExistingChats,
                                        isDisclaimerEnabled: feature.isAvailable,
                                        isInputBlocked: false)
        if isDisclaimerShown { measurement.disclaimerBecameVisible() }
    }

    /// Call only for an Ask tap. `visibleMessage` is what the input's card shows right now; a send made
    /// without seeing the disclaimer accepts nothing, and the web app shows its own card for that prompt instead.
    /// Returns whether this tap is the acceptance.
    @discardableResult
    func acceptIfShown(_ visibleMessage: UTIFooterMessage?) -> Bool {
        guard isDisclaimer(visibleMessage) else { return false }
        store.recordAcceptedInNativeInput()
        Logger.aiChat.debug("[TermsOfService] Ask tapped with the disclaimer on screen: acceptance recorded")
        return true
    }
}

/// The send button the disclaimer names, as on the web: "Create" while Create Image is selected, "Ask" otherwise.
enum DuckAiTermsOfServiceSendButton: CaseIterable {
    case ask
    case create

    init(selectedTool: AIChatRAGTool?) {
        self = selectedTool == .imageGeneration ? .create : .ask
    }

    var title: String {
        switch self {
        case .ask: return UserText.duckAIAskButtonTitle
        case .create: return UserText.duckAICreateButtonTitle
        }
    }

    var disclaimerFormat: String {
        switch self {
        case .ask: return UserText.duckAITermsOfServiceDisclaimer
        case .create: return UserText.duckAITermsOfServiceCreateDisclaimer
        }
    }
}
