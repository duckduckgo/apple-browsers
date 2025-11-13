//
//  WinBackOfferCoordinator.swift
//  DuckDuckGo
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

import Foundation
import BrowserServicesKit
import Core
import Subscription

/// Coordinator for the Win-back offer.
/// 
/// Responsible for coordinating the Win-back offer.
protocol WinBackOfferCoordinating: AnyObject {
    /// The URL handler for the coordinator.
    /// 
    /// Used to open the purchase flow.
    var urlHandler: URLHandling? { get set }
    /// Checks if the launch prompt should be shown.
    /// 
    /// Eligibility is decided by WinBackOfferVisibilityManager.
    func shouldPresentLaunchPrompt() -> Bool
    /// Marks the launch prompt as presented.
    /// 
    /// Used to prevent the launch prompt from being shown again.
    func markLaunchPromptPresented()
    /// Handles the CTA action.
    /// 
    /// Opens the purchase flow.
    func handleCTAAction()
    /// Handles the dismiss action.
    func handleDismissAction()
}

final class WinBackOfferCoordinator {
    private let visibilityManager: WinBackOfferVisibilityManaging
    private let pixelHandler: (Pixel.Event) -> Void
    private let isOnboardingCompleted: () -> Bool
    
    weak var urlHandler: URLHandling?

    init(
        visibilityManager: WinBackOfferVisibilityManaging,
        pixelHandler: @escaping (Pixel.Event) -> Void = { Pixel.fire(pixel: $0) },
        isOnboardingCompleted: @escaping () -> Bool
    ) {
        self.visibilityManager = visibilityManager
        self.isOnboardingCompleted = isOnboardingCompleted
        self.pixelHandler = pixelHandler
    }
}

// MARK: - WinBackOfferCoordinating

extension WinBackOfferCoordinator: WinBackOfferCoordinating {

    func shouldPresentLaunchPrompt() -> Bool {
        // Don't show if onboarding not completed
        guard isOnboardingCompleted() else {
            Logger.subscription.debug("[Win-Back Offer] Onboarding not completed, not showing prompt.")
            return false
        }

        // Check if the launch message should be shown
        let shouldShow = visibilityManager.shouldShowLaunchMessage
        if shouldShow {
            Logger.subscription.debug("[Win-Back Offer] Launch message should be shown.")
        } else {
            Logger.subscription.debug("[Win-Back Offer] Launch message should not be shown.")
        }

        return shouldShow
    }

    func markLaunchPromptPresented() {
        visibilityManager.setLaunchMessagePresented(true)
        Logger.subscription.debug("[Win-Back Offer] Launch message marked as presented.")
        pixelHandler(.subscriptionWinBackOfferLaunchPromptShown)
    }

    func handleCTAAction() {
        Logger.subscription.debug("[Win-Back Offer] CTA action triggered.")
        pixelHandler(.subscriptionWinBackOfferLaunchPromptCTAClicked)

        let comps = SubscriptionURL.purchaseURLComponentsWithOriginAndFeaturePage(
            origin: SubscriptionFunnelOrigin.winBackLaunch.rawValue,
            featurePage: SubscriptionURL.FeaturePage.winback
        )
        let deepLink = SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(redirectURLComponents: comps)
        NotificationCenter.default.post(name: .settingsDeepLinkNotification, object: deepLink)
    }

    func handleDismissAction() {
        Logger.subscription.debug("[Win-Back Offer] Dismiss action triggered.")
        pixelHandler(.subscriptionWinBackOfferLaunchPromptDismissed)
    }
}
