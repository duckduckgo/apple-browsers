//
//  SubscriptionOnboardingInstrumentation.swift
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
import PixelKit
import AIChat

/// Reports the onboarding funnel.
protocol SubscriptionOnboardingInstrumenting {
    /// The funnel's denominator, and the only place the Duck.ai-disabled cohort is counted.
    func flowStarted()
    func stepShown(_ section: SubscriptionOnboardingSection)
    func stepCompleted(_ section: SubscriptionOnboardingSection)
    func stepSkipped(_ section: SubscriptionOnboardingSection)
}

// MARK: - Pixel vocabulary

/// Step names are their own vocabulary rather than the section case names, so renaming a case cannot
/// rename a pixel.
extension SubscriptionOnboardingSection {
    var pixelStepName: String {
        switch self {
        case .orderConfirmation: "intro"
        case .welcome: "features_summary"
        case .vpnActivation: "vpn"
        case .vpnWidget, .vpnTips: "vpn_widget"
        case .idtr: "idtr"
        case .duckAI: "duck_ai"
        case .progress: "completion"
        case .pir: "pir"
        }
    }
}

extension SubscriptionOnboardingEntryPoint {
    var pixelValue: String {
        switch self {
        case .postCheckout: "post_checkout"
        case .subscriptionSettings: "subscription_settings"
        }
    }
}

// MARK: - Implementation

@MainActor
struct SubscriptionOnboardingInstrumentation: SubscriptionOnboardingInstrumenting {

    private let entryPoint: SubscriptionOnboardingEntryPoint
    private let isDuckAIEnabled: () -> Bool
    private let pixelFiring: PixelFiring?

    init(entryPoint: SubscriptionOnboardingEntryPoint,
         isDuckAIEnabled: (() -> Bool)? = nil,
         pixelFiring: PixelFiring? = PixelKit.shared) {
        self.entryPoint = entryPoint
        if let isDuckAIEnabled {
            self.isDuckAIEnabled = isDuckAIEnabled
        } else {
            let aiChatSettings = AIChatSettings()
            self.isDuckAIEnabled = { aiChatSettings.isAIChatEnabled }
        }
        self.pixelFiring = pixelFiring
    }

    func flowStarted() {
        fire(.subscriptionOnboardingFlowStarted(entryPoint: entryPoint.pixelValue,
                                                isDuckAIEnabled: isDuckAIEnabled()))
    }

    func stepShown(_ section: SubscriptionOnboardingSection) {
        fire(.subscriptionOnboardingStepShown(step: section.pixelStepName, entryPoint: entryPoint.pixelValue))
    }

    func stepCompleted(_ section: SubscriptionOnboardingSection) {
        fire(.subscriptionOnboardingStepCompleted(step: section.pixelStepName, entryPoint: entryPoint.pixelValue))
    }

    func stepSkipped(_ section: SubscriptionOnboardingSection) {
        fire(.subscriptionOnboardingStepSkipped(step: section.pixelStepName, entryPoint: entryPoint.pixelValue))
    }

    private func fire(_ pixel: SubscriptionPixel) {
        pixelFiring?.fire(pixel)
    }
}

/// Reports nothing, for previews and tests.
struct NullSubscriptionOnboardingInstrumentation: SubscriptionOnboardingInstrumenting {
    func flowStarted() {}
    func stepShown(_ section: SubscriptionOnboardingSection) {}
    func stepCompleted(_ section: SubscriptionOnboardingSection) {}
    func stepSkipped(_ section: SubscriptionOnboardingSection) {}
}
