//
//  SubscriptionOnboardingChecklistItem.swift
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

/// Steps the completion checklist tracks. `widget` is a checklist step but not a subscription feature—it has no "Learn More" content and doesn't appear in the welcome list.
///
/// Raw values are persisted by `SubscriptionOnboardingProgressStore`, so renaming a case resets progress
/// for anyone mid-flow.
enum SubscriptionOnboardingChecklistItem: String, CaseIterable, Identifiable {
    case vpn
    case widget
    case idtr
    case duckAI
    case pir

    static let features: [SubscriptionOnboardingChecklistItem] = [.vpn, .idtr, .duckAI, .pir]

    /// Customer's checklist (4 items if PIR unavailable, to keep ceiling at 100%).
    static func checklist(isPIRAvailable: Bool) -> [SubscriptionOnboardingChecklistItem] {
        isPIRAvailable ? allCases : allCases.filter { $0 != .pir }
    }

    /// Completion percentage over `checklist`, clamped to `0...100`.
    static func completionPercentage(completed: Set<SubscriptionOnboardingChecklistItem>,
                                     checklist: [SubscriptionOnboardingChecklistItem]) -> Int {
        guard !checklist.isEmpty else { return 0 }
        return completed.intersection(checklist).count * 100 / checklist.count
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .vpn: return UserText.subscriptionOnboardingChecklistVPNTitle
        case .widget: return UserText.subscriptionOnboardingChecklistWidgetTitle
        case .idtr: return UserText.subscriptionOnboardingChecklistIDTRTitle
        case .duckAI: return UserText.subscriptionOnboardingChecklistDuckAITitle
        case .pir: return UserText.subscriptionOnboardingChecklistPIRTitle
        }
    }
}
