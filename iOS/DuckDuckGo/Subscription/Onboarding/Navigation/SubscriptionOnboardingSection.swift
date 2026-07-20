//
//  SubscriptionOnboardingSection.swift
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

/// A section of the post-subscription onboarding flow. A section can span several screens internally —
/// e.g. `.vpn` walks through its activation, post-activation, home-screen-widget and VPN-tips screens —
/// but each is a single unit the flow navigates between. The flow view model (next PR) builds a section's
/// view via ``SubscriptionOnboardingViewFactory`` and reacts to its completion via
/// ``SubscriptionOnboardingSectionDelegate``.
enum SubscriptionOnboardingSection: CaseIterable {
    case vpn
    case duckAI

    /// How a section counts toward the flow's progress. Consumed by the flow view model (Stage 3); the
    /// mapping itself is a pure model label and lives here.
    enum Kind: Equatable {
        /// Activates a specific premium protection; contributes to the completion percentage.
        case activation(SubscriptionOnboardingChecklistItem)
    }

    var kind: Kind {
        switch self {
        case .vpn: .activation(.vpn)
        case .duckAI: .activation(.duckAI)
        }
    }
}
