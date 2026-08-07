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

import SwiftUI
import UIKit
import Persistence

/// Single presentation point for the onboarding flow from all entry points.
@MainActor
struct SubscriptionOnboardingLauncher {

    /// PIR availability and screen provider, resolved by the caller.
    struct PIRAvailability {
        let isAvailable: Bool
        /// Whether the customer has already saved a profile and started a scan, which is what completes the
        /// PIR step. It happens entirely outside this flow, so the host has to tell us.
        var isActivated: Bool = false
        let makeScreen: () -> AnyView

        /// For PIR-ineligible customers.
        static let unavailable = PIRAvailability(isAvailable: false, makeScreen: { AnyView(EmptyView()) })
    }

    private let keyValueStore: ThrowingKeyValueStoring
    private let pir: PIRAvailability
    private let chatLauncher: SubscriptionOnboardingDuckAIChatLauncher

    /// Defaults resolve in the body, not in the parameter list: default arguments are evaluated in a
    /// nonisolated context, and both of these are main-actor isolated.
    init(keyValueStore: ThrowingKeyValueStoring,
         pir: PIRAvailability? = nil,
         chatLauncher: SubscriptionOnboardingDuckAIChatLauncher? = nil) {
        self.keyValueStore = keyValueStore
        self.pir = pir ?? .unavailable
        self.chatLauncher = chatLauncher ?? SubscriptionOnboardingDuckAIChatLauncher()
    }

    /// Builds the flow; `onFinish` fires when the customer leaves.
    func makeFlow(entryPoint: SubscriptionOnboardingEntryPoint, onFinish: @escaping () -> Void) -> AnyView {
        let prefetcher = SubscriptionOnboardingPrefetcher()

        let flow = SubscriptionOnboardingFlowViewModel(
            entryPoint: entryPoint,
            store: SubscriptionOnboardingProgressStore(keyValueStore: keyValueStore),
            isPIRAvailable: pir.isAvailable,
            isPIRActivated: pir.isActivated,
            onFinish: {
                onFinish()
                Self.dropIntoSubscriptionSettingsIfNeeded(entryPoint: entryPoint)
            },
            onRequestDuckAIChat: { modelID in
                // Deliberately no dismiss here — the chat launcher tears down the whole presented chain.
                chatLauncher.launch(modelID: modelID)
            })

        let factory = SubscriptionOnboardingViewFactory(flow: flow,
                                                        prefetcher: prefetcher,
                                                        pirDestination: pir.makeScreen)

        prefetcher.prefetch(Self.prefetchTargets(for: flow.sequence))

        return AnyView(
            SubscriptionOnboardingFlowView(flow: flow,
                                           factory: factory,
                                           pirDetour: { pirDetour(flow: flow) })
                .graphicLottieRenderer(SubscriptionOnboardingLottieRenderer.shared))
    }

    /// Presents the flow from UIKit.
    func present(from presenting: UIViewController, entryPoint: SubscriptionOnboardingEntryPoint) {
        let root = makeFlow(entryPoint: entryPoint, onFinish: { [weak presenting] in
            presenting?.dismiss(animated: true)
        })
        presenting.present(UIHostingController(rootView: root), animated: true)
    }

    /// Only the sections this run will actually reach are worth fetching for.
    private static func prefetchTargets(for sequence: [SubscriptionOnboardingSection]) -> SubscriptionOnboardingPrefetcher.Targets {
        var targets: SubscriptionOnboardingPrefetcher.Targets = []
        if sequence.contains(.vpnActivation) {
            targets.insert(.connectionInfo)
        }
        if sequence.contains(.duckAI) {
            targets.insert(.aiModels)
        }
        return targets
    }

    /// A post-checkout run ends on Subscription Settings (PRD), reusing the app-wide deep link rather than
    /// reaching into Settings directly. A re-entry run is already there, so it just closes.
    private static func dropIntoSubscriptionSettingsIfNeeded(entryPoint: SubscriptionOnboardingEntryPoint) {
        guard entryPoint == .postCheckout else { return }
        NotificationCenter.default.post(name: .settingsDeepLinkNotification,
                                        object: SettingsViewModel.SettingsDeepLinkSection.subscriptionSettings)
    }

    /// The PIR screen reached from a summary's PIR row. It gets its own navigation container because it is
    /// presented over the flow rather than pushed onto it.
    private func pirDetour(flow: SubscriptionOnboardingFlowViewModel) -> AnyView {
        AnyView(
            SubscriptionOnboardingPIRView(
                title: String(format: UserText.subscriptionOnboardingStepIndicatorFormat,
                              SubscriptionOnboardingSection.indicatorStepCount,
                              SubscriptionOnboardingSection.indicatorStepCount),
                navigationButton: .close { flow.isPresentingPIR = false },
                push: pir.makeScreen())
                .subscriptionOnboardingNavigationContainer())
    }
}
