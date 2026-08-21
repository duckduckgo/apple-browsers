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
import os.log

enum SubscriptionOnboardingEntryPoint {
    /// Presented over the post-checkout page once a purchase completes.
    case postCheckout
    /// The "Continue Setup" card on Subscription Settings.
    case subscriptionSettings
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
    static func postCheckout<PIRScreen: View>(persistor: SubscriptionOnboardingProgressPersisting,
                                              isPIRAvailable: Bool,
                                              subscriptionManager: any SubscriptionManager,
                                              onFinish: @escaping () -> Void,
                                              @ViewBuilder pirScreen: @escaping () -> PIRScreen) async
    -> SubscriptionOnboardingFlowViewModel? {
        await makeFlow(entryPoint: .postCheckout,
                       persistor: persistor,
                       isPIRAvailable: isPIRAvailable,
                       subscriptionManager: subscriptionManager,
                       onFinish: onFinish,
                       pirScreen: pirScreen)
    }

    /// Resumes at the first unfinished section, and closes on the summary.
    static func subscriptionSettings<PIRScreen: View>(persistor: SubscriptionOnboardingProgressPersisting,
                                                      isPIRAvailable: Bool,
                                                      subscriptionManager: any SubscriptionManager,
                                                      onFinish: @escaping () -> Void,
                                                      @ViewBuilder pirScreen: @escaping () -> PIRScreen) async
    -> SubscriptionOnboardingFlowViewModel? {
        await makeFlow(entryPoint: .subscriptionSettings,
                       persistor: persistor,
                       isPIRAvailable: isPIRAvailable,
                       subscriptionManager: subscriptionManager,
                       onFinish: onFinish,
                       pirScreen: pirScreen)
    }

    /// A checklist that comes back empty means
    /// something is wrong with the entitlement read, not that this customer legitimately has nothing
    /// there's nothing to show, so the flow doesn't launch
    private static func makeFlow<PIRScreen: View>(entryPoint: SubscriptionOnboardingEntryPoint,
                                                  persistor: SubscriptionOnboardingProgressPersisting,
                                                  isPIRAvailable: Bool,
                                                  subscriptionManager: any SubscriptionManager,
                                                  onFinish: @escaping () -> Void,
                                                  @ViewBuilder pirScreen: @escaping () -> PIRScreen) async
    -> SubscriptionOnboardingFlowViewModel? {
        let progress = await SubscriptionOnboardingProgress.make(persistor: persistor,
                                                                  isPIRAvailable: isPIRAvailable,
                                                                  subscriptionManager: subscriptionManager)
        guard !progress.checklist.isEmpty else {
            Logger.subscription.error("Onboarding checklist is empty at launch — refusing to present the flow")
            return nil
        }
        return SubscriptionOnboardingFlowViewModel(entryPoint: entryPoint,
                                                   progress: progress,
                                                   onFinish: onFinish,
                                                   pirScreen: pirScreen)
    }
}
