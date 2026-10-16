//
//  UTIFooterMultiTabPromotionSource.swift
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

@MainActor
final class UTIFooterMultiTabPromotionSource {
    private let feature: () -> AIChatContextualAttachMoreTabsFeatureProviding?
    private let isEligible: () -> Bool
    private var isPresentationActive = false
    private var hasDisplayedInCurrentOpening = false
    private var hasSubmittedPrompt = false

    init(feature: @escaping () -> AIChatContextualAttachMoreTabsFeatureProviding?,
         isEligible: @escaping () -> Bool) {
        self.feature = feature
        self.isEligible = isEligible
    }

    var isPresented: Bool {
        isPresentationActive && !hasSubmittedPrompt && isEligible()
            && feature()?.isDrawerPromoAvailable(isCurrentDisplay: hasDisplayedInCurrentOpening) == true
    }

    func beginPresentation() {
        guard !isPresentationActive else { return }
        isPresentationActive = true
        hasDisplayedInCurrentOpening = false
        hasSubmittedPrompt = false
    }

    func endPresentation() {
        isPresentationActive = false
        hasDisplayedInCurrentOpening = false
    }

    func recordDisplay() {
        guard isPresented, !hasDisplayedInCurrentOpening else { return }
        hasDisplayedInCurrentOpening = true
        feature()?.recordDrawerPromoDisplay()
    }

    func recordPromptSubmitted() {
        hasSubmittedPrompt = true
    }

    func startNewChat() {
        hasSubmittedPrompt = false
    }

    func dismiss() {
        feature()?.dismissDrawerPromo()
    }
}
