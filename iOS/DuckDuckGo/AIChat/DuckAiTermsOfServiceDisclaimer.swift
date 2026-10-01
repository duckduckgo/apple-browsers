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

import Foundation

/// The UTI footer's Terms of Service rules, for the iPad inputs that have no UTI: required until the
/// user accepts on either side, and sending with it on screen is the acceptance.
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
    var message: UTIFooterMessage? {
        guard feature.isAvailable, !store.hasAccepted else { return nil }
        return mapper.termsOfServiceMessage()
    }

    /// `visibleMessage` is what the input's card shows right now; a send made without seeing the
    /// disclaimer accepts nothing, and the web app shows its own card for that prompt instead.
    @discardableResult
    func acceptIfShown(_ visibleMessage: UTIFooterMessage?) -> Bool {
        guard let visibleMessage, visibleMessage == message else { return false }
        store.recordAcceptedInNativeInput()
        return true
    }
}
