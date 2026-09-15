//
//  MockOnboardingPersonalizationManager.swift
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
import Onboarding

final class MockOnboardingPersonalizationManager: OnboardingPersonalizationManaging {
    var isRecentlyVisitedSitesEnabled = false
    var isSafeSearchEnabled = false
    var doesNewTabOpenWithAIChat = false
    var isSearchAssistEnabled = false
    var areAIGeneratedImagesHidden = false
    var isDuckAIEnabled = false
    var isYouTubeAdBlockingEnabled = false
    var isCookiePopUpProtectionEnabled = false
    var isPopUpsWithoutOptOutsEnabled = false

    private(set) var applyDefaultsCallCount = 0
    private(set) var capturedApplyDefaultsReason: OnboardingDownloadReason?

    var selectedAIChatModelID: String?

    func setRecentlyVisitedSites(_ enabled: Bool) { isRecentlyVisitedSitesEnabled = enabled }
    func setSafeSearch(_ enabled: Bool) { isSafeSearchEnabled = enabled }
    func setAIChatModel(_ model: OnboardingAIModel) { selectedAIChatModelID = model.id }
    func setNewTabOpensWithAIChat(_ opensWithAIChat: Bool) { doesNewTabOpenWithAIChat = opensWithAIChat }
    func setSearchAssist(_ enabled: Bool) { isSearchAssistEnabled = enabled }
    func setAIGeneratedImagesHidden(_ hidden: Bool) { areAIGeneratedImagesHidden = hidden }
    func setDuckAIEnabled(_ enabled: Bool) { isDuckAIEnabled = enabled }
    func setYouTubeAdBlocking(_ enabled: Bool) { isYouTubeAdBlockingEnabled = enabled }
    func setCookiePopUpProtection(_ enabled: Bool) { isCookiePopUpProtectionEnabled = enabled }
    func setPopUpsWithoutOptOuts(_ enabled: Bool) { isPopUpsWithoutOptOutsEnabled = enabled }
    func applyDefaults(for reason: OnboardingDownloadReason) {
        applyDefaultsCallCount += 1
        capturedApplyDefaultsReason = reason
    }
}
