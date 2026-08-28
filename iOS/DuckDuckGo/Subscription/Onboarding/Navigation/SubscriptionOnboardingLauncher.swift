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
import PixelKit
import UIKit
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
                .graphicLottieRenderer(.app)
                .interactiveDismissDisabled(true)
                .onAppear { lockToPortrait() }
                .onDisappear { unlockOrientation() })
    }
}

// MARK: - Orientation lock

private extension SubscriptionOnboardingLauncher {

    static func lockToPortrait() {
        setOrientationLock(.portrait, snapTo: .portrait)
    }

    /// Re-triggers a query, or the relaxed mask goes unnoticed and the screen stays portrait-locked.
    static func unlockOrientation() {
        setOrientationLock(AppDelegate.defaultOrientationMask)
    }

    /// Forces an immediate snap — the mask alone only constrains future rotation attempts.
    static func setOrientationLock(_ mask: UIInterfaceOrientationMask, snapTo orientation: UIInterfaceOrientation? = nil) {
        AppDelegate.orientationLock = mask
        guard let windowScene = UIApplication.shared.foregroundWindowScene else { return }
        if #available(iOS 16.0, *) {
            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            windowScene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            if let orientation {
                UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
            }
            UIViewController.attemptRotationToDeviceOrientation()
        }
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
        let progress = await makeProgress(persistor: persistor,
                                          isPIRAvailable: isPIRAvailable,
                                          subscriptionManager: subscriptionManager,
                                          vpnController: vpnController,
                                          profileStateManager: profileStateManager,
                                          freemiumDBPUserStateManager: freemiumDBPUserStateManager)
        return makeFlow(entryPoint: .postCheckout,
                        progress: progress,
                        onFinish: onFinish,
                        onRequestDuckAIChat: onRequestDuckAIChat,
                        pirScreen: pirScreen)
    }

    /// Resumes at the first unfinished section, and closes on the summary. Backfills the same as `postCheckout`.
    static func subscriptionSettings<PIRScreen: View>(persistor: SubscriptionOnboardingProgressPersisting,
                                                      isPIRAvailable: Bool,
                                                      subscriptionManager: any SubscriptionManager,
                                                      onFinish: @escaping () -> Void,
                                                      onRequestDuckAIChat: ((String?) -> Bool)? = nil,
                                                      vpnController: SubscriptionOnboardingVPNControlling = DefaultSubscriptionOnboardingVPNController(),
                                                      profileStateManager: DBPProfileStateManaging = DefaultDBPProfileStateManager(keyValueStore: UserDefaults.dbp),
                                                      freemiumDBPUserStateManager: FreemiumDBPUserStateManaging = DefaultFreemiumDBPUserStateManager(userDefaults: .dbp, isUserAuthenticated: { false }, isFreemiumEnabled: { false }),
                                                      @ViewBuilder pirScreen: @escaping () -> PIRScreen) async
    -> SubscriptionOnboardingFlowViewModel? {
        let progress = await makeProgress(persistor: persistor,
                                          isPIRAvailable: isPIRAvailable,
                                          subscriptionManager: subscriptionManager,
                                          vpnController: vpnController,
                                          profileStateManager: profileStateManager,
                                          freemiumDBPUserStateManager: freemiumDBPUserStateManager)
        return makeFlow(entryPoint: .subscriptionSettings,
                        progress: progress,
                        onFinish: onFinish,
                        onRequestDuckAIChat: onRequestDuckAIChat,
                        pirScreen: pirScreen)
    }

    /// Awaits the real entitlement, live-checks VPN/PIR and backfills either into `persistor` first — the
    /// shared body of both entry points above.
    private static func makeProgress(persistor: SubscriptionOnboardingProgressPersisting,
                                     isPIRAvailable: Bool,
                                     subscriptionManager: any SubscriptionManager,
                                     vpnController: SubscriptionOnboardingVPNControlling,
                                     profileStateManager: DBPProfileStateManaging,
                                     freemiumDBPUserStateManager: FreemiumDBPUserStateManaging) async -> SubscriptionOnboardingProgress {
        async let entitlement = subscriptionManager.getAllEntitlementStatus()
        let persistor = await backfilledPersistor(persistor,
                                                   vpnController: vpnController,
                                                   profileStateManager: profileStateManager,
                                                   freemiumDBPUserStateManager: freemiumDBPUserStateManager)
        return SubscriptionOnboardingProgress(persistor: persistor, isPIRAvailable: isPIRAvailable, entitlement: await entitlement)
    }

    /// Live-checks VPN and PIR activation and marks either complete on `persistor`, skipping the check
    /// entirely for whichever is already marked.
    private static func backfilledPersistor(_ persistor: SubscriptionOnboardingProgressPersisting,
                                            vpnController: SubscriptionOnboardingVPNControlling,
                                            profileStateManager: DBPProfileStateManaging,
                                            freemiumDBPUserStateManager: FreemiumDBPUserStateManaging) async -> SubscriptionOnboardingProgressPersisting {
        var persistor = persistor
        let completedItems = persistor.completedItems

        if !completedItems.contains(.vpn), await vpnController.isVPNConfigured() {
            persistor.markComplete(.vpn)
        }
        if !completedItems.contains(.pir),
           PIRActivation.isActivated(profileStateManager: profileStateManager,
                                     freemiumDBPUserStateManager: freemiumDBPUserStateManager) {
            persistor.markComplete(.pir)
        }
        return persistor
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
            // Only the post-checkout entry point represents a purchase that should have gotten onboarding;
            // Settings re-entry is a customer manually retrying
            if case .postCheckout = entryPoint {
                PixelKit.fire(SubscriptionPixel.subscriptionOnboardingLaunchFailure(.emptyChecklist), frequency: .dailyAndCount)
            }
            return nil
        }
        return SubscriptionOnboardingFlowViewModel(entryPoint: entryPoint,
                                                   progress: progress,
                                                   onFinish: onFinish,
                                                   onRequestDuckAIChat: onRequestDuckAIChat,
                                                   pirScreen: pirScreen)
    }
}
