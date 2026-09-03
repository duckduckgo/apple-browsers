//
//  SubscriptionOnboardingLauncher.swift
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

import Subscription
import SwiftUI
import DataBrokerProtection_iOS
import os.log

enum SubscriptionOnboardingEntryPoint {
    /// Presented over the post-checkout page once a purchase completes.
    case postCheckout
    /// The "Continue Setup" card on Subscription Settings.
    case subscriptionSettings
}

/// Atomic sheet payload to avoid SwiftUI staleness when both flag and content come from one tap.
struct OnboardingFlowPayload: Identifiable {
    let id = UUID()
    let flow: SubscriptionOnboardingFlowViewModel
}

@MainActor
enum SubscriptionOnboardingLauncher {

    static func launch(flow: SubscriptionOnboardingFlowViewModel) -> AnyView {
        launch(flow: flow, forcedTrialLengthDays: nil)
    }

    private static func launch(flow: SubscriptionOnboardingFlowViewModel, forcedTrialLengthDays: Int?) -> AnyView {
        AnyView(
            SubscriptionOnboardingFlowView(flow: flow,
                                           factory: SubscriptionOnboardingViewFactory(flow: flow,
                                                                                       forcedTrialLengthDays: forcedTrialLengthDays))
                .graphicLottieRenderer(.app))
    }
}

// MARK: - Debug Menu

extension SubscriptionOnboardingLauncher {
    /// Debug-menu only: forces `.orderConfirmation`'s free-trial card to `forcedTrialLengthDays` instead of
    /// the real subscription's.
    static func launchForDebug(flow: SubscriptionOnboardingFlowViewModel, forcedTrialLengthDays: Int?) -> AnyView {
        launch(flow: flow, forcedTrialLengthDays: forcedTrialLengthDays)
    }
}

// MARK: - Flows to launch

extension SubscriptionOnboardingFlowViewModel {

    /// Walks the whole flow from the order confirmation.
    ///  A VPN configuration already installed marks `.vpn` complete;
    ///  an existing PIR profile marks `.pir` complete.
    static func postCheckout<PIRScreen: View>(persistor: SubscriptionOnboardingProgressPersisting,
                                              isPIRAvailable: Bool,
                                              subscriptionManager: any SubscriptionManager,
                                              onFinish: @escaping () -> Void,
                                              onRequestDuckAIChat: ((String?) -> Bool)? = nil,
                                              vpnController: SubscriptionOnboardingVPNControlling = DefaultSubscriptionOnboardingVPNController(),
                                              profileStateManager: DBPProfileStateManaging = DefaultDBPProfileStateManager(keyValueStore: UserDefaults.dbp),
                                              freemiumDBPUserStateManager: FreemiumDBPUserStateManaging = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp, isUserAuthenticated: { false }, isFreemiumEnabled: { false }),
                                              @ViewBuilder pirScreen: @escaping () -> PIRScreen) async
    -> SubscriptionOnboardingFlowViewModel? {
        async let vpnConfigured = vpnController.isVPNConfigured()
        async let entitlement = subscriptionManager.getAllEntitlementStatus()

        var persistor = persistor
        if await vpnConfigured {
            persistor.markComplete(.vpn)
        }
        if PIRActivation.isActivated(profileStateManager: profileStateManager,
                                     freemiumDBPUserStateManager: freemiumDBPUserStateManager) {
            persistor.markComplete(.pir)
        }
        let progress = SubscriptionOnboardingProgress(persistor: persistor, isPIRAvailable: isPIRAvailable, entitlement: await entitlement)
        return makeFlow(entryPoint: .postCheckout,
                        progress: progress,
                        onFinish: onFinish,
                        onRequestDuckAIChat: onRequestDuckAIChat,
                        pirScreen: pirScreen)
    }

    /// Resumes at the first unfinished section, and closes on the summary.
    static func subscriptionSettings<PIRScreen: View>(persistor: SubscriptionOnboardingProgressPersisting,
                                                      isPIRAvailable: Bool,
                                                      subscriptionManager: any SubscriptionManager,
                                                      onFinish: @escaping () -> Void,
                                                      onRequestDuckAIChat: ((String?) -> Bool)? = nil,
                                                      @ViewBuilder pirScreen: @escaping () -> PIRScreen) async
    -> SubscriptionOnboardingFlowViewModel? {
        let progress = await SubscriptionOnboardingProgress.make(persistor: persistor,
                                                                  isPIRAvailable: isPIRAvailable,
                                                                  subscriptionManager: subscriptionManager)
        return makeFlow(entryPoint: .subscriptionSettings,
                        progress: progress,
                        onFinish: onFinish,
                        onRequestDuckAIChat: onRequestDuckAIChat,
                        pirScreen: pirScreen)
    }

    /// A checklist that comes back empty means
    /// something is wrong with the entitlement read, not that this customer legitimately has nothing
    /// there's nothing to show, so the flow doesn't launch
    private static func makeFlow<PIRScreen: View>(entryPoint: SubscriptionOnboardingEntryPoint,
                                                  progress: SubscriptionOnboardingProgress,
                                                  onFinish: @escaping () -> Void,
                                                  onRequestDuckAIChat: ((String?) -> Bool)?,
                                                  @ViewBuilder pirScreen: @escaping () -> PIRScreen)
    -> SubscriptionOnboardingFlowViewModel? {
        guard !progress.checklist.isEmpty else {
            Logger.subscription.error("Onboarding checklist is empty at launch — refusing to present the flow")
            return nil
        }
        return SubscriptionOnboardingFlowViewModel(entryPoint: entryPoint,
                                                   progress: progress,
                                                   onFinish: onFinish,
                                                   onRequestDuckAIChat: onRequestDuckAIChat,
                                                   pirScreen: pirScreen)
    }
}
