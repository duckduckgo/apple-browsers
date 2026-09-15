//
//  AIChatPickerSectionCopy.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Copy shared by the address-bar pickers and the NTP omnibar payload, so the two can't drift.
/// Lives in the app module rather than `SharedPackages/AIChat` because it reads `UserText`.
enum AIChatPickerSectionCopy {

    static func subtitle(for label: AIChatModelLabel?) -> String? {
        switch label {
        case .everydayUse: return UserText.aiChatModelPickerLabelEverydayUse
        case .usesLimitsFaster: return UserText.aiChatModelPickerLabelUsesLimitsFaster
        case .unknown, .none: return nil
        }
    }

    /// Free trial first; once it's spent, a non-subscriber's gated models span both paid plans,
    /// while a Plus subscriber's remaining ones are Pro-only.
    static func gatedModelsHeader(userTier: AIChatUserTier, isEligibleForFreeTrial: Bool) -> String {
        if isEligibleForFreeTrial { return UserText.aiChatModelPickerTryFreeSectionHeader }
        return userTier == .free ? UserText.aiChatModelPickerAvailableWithPaidPlansSectionHeader
                                 : UserText.aiChatModelPickerAvailableWithProSectionHeader
    }

    /// Same heading as the models section — what unlocks a gated row depends on the plan the user
    /// has, not on the row's own tier. Keying off `requiredTier` alone told a trial-spent free user
    /// their gated effort was "Pro Plan Exclusive" when Plus would have unlocked it too.
    static func gatedEffortsHeader(requiredTier: AIChatModelPublicAccessTier?, userTier: AIChatUserTier, isEligibleForFreeTrial: Bool) -> String? {
        switch requiredTier {
        case .plus, .pro: return gatedModelsHeader(userTier: userTier, isEligibleForFreeTrial: isEligibleForFreeTrial)
        case .free, .none: return nil
        }
    }
}
