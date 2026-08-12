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

/// A section of the post-subscription onboarding flow; a section may span several screens internally.
enum SubscriptionOnboardingSection: CaseIterable {
    case orderConfirmation
    case welcome
    case vpnActivation
    case vpnWidget
    case idtr
    case duckAI
    case progress
    case pir

    enum Kind: Equatable {
        case activation(SubscriptionOnboardingChecklistItem)
        case overview
        case progressTracker
    }

    var kind: Kind {
        switch self {
        case .orderConfirmation, .welcome: .overview
        case .vpnActivation: .activation(.vpn)
        case .vpnWidget: .activation(.widget)
        case .idtr: .activation(.idtr)
        case .duckAI: .activation(.duckAI)
        case .progress: .progressTracker
        case .pir: .activation(.pir)
        }
    }

    /// In-flow sections (excludes .pir, overview, and progress).
    static let activationSections: [SubscriptionOnboardingSection] = [.vpnActivation, .vpnWidget, .idtr, .duckAI]
}
