//
//  RebrandedNewTabDaxDialogFactory.swift
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
import SwiftUI
import Onboarding
import Subscription
import Common

final class RebrandedNewTabDaxDialogFactory: NewTabDaxDialogProviding {
    private var delegate: OnboardingNavigationDelegate?
    private var daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator
    private let onboardingPixelReporter: OnboardingPixelReporting
    private let onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping

    init(
        delegate: OnboardingNavigationDelegate?,
        daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator,
        onboardingPixelReporter: OnboardingPixelReporting,
        onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping = OnboardingSubscriptionPromotionHelper()
    ) {
        self.delegate = delegate
        self.daxDialogsFlowCoordinator = daxDialogsFlowCoordinator
        self.onboardingPixelReporter = onboardingPixelReporter
        self.onboardingSubscriptionPromotionHelper = onboardingSubscriptionPromotionHelper
    }

    @ViewBuilder
    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec, onCompletion: @escaping (_ activateSearch: Bool) -> Void, onManualDismiss: @escaping () -> Void) -> some View {
        switch homeDialog {
        case .initial:
            createInitialDialog(onManualDismiss: onManualDismiss)
        case .addFavorite:
            createAddFavoriteDialog(message: UserText.Onboarding.ContextualOnboarding.daxDialogHomeAddFavorite)
        case .subsequent:
            createSubsequentDialog(onManualDismiss: onManualDismiss)
        case .final:
            createFinalDialog(onCompletion: onCompletion, onManualDismiss: onManualDismiss)
        case .subscriptionPromotion:
            // Re-use same dismiss closure as dismissing the final dialog will set onboarding completed true
            createSubscriptionPromoDialog(proceedButtonText: onboardingSubscriptionPromotionHelper.proceedButtonText, onDismiss: onCompletion)
        }
    }
}

// MARK: - Initial Dialog (Try A Search!)

private extension RebrandedNewTabDaxDialogFactory {

    func createInitialDialog(onManualDismiss: @escaping () -> Void) -> some View {
        let viewModel = OnboardingSearchSuggestionsViewModel(
            suggestedSearchesProvider: OnboardingSuggestedSearchesProvider(),
            delegate: delegate
        )

        let manualDismissAction = { [weak self] in
            self?.onboardingPixelReporter.measureTrySearchDialogNewTabDismissButtonTapped()
            onManualDismiss()
        }

        return FadeInView {
            OnboardingRebranding.OnboardingTrySearchDialog(viewModel: viewModel, onManualDismiss: manualDismissAction)
        }
        .applyNewTabOnboardingBackground(backgroundType: .tryASearch)
        .onFirstAppear { [weak self] in
            self?.daxDialogsFlowCoordinator.setTryAnonymousSearchMessageSeen()
            self?.onboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTrySearchUnique)
        }
    }

}

// MARK: - Subsequent Dialog (Try Visiting A Site!)

private extension RebrandedNewTabDaxDialogFactory {

    private func createSubsequentDialog(onManualDismiss: @escaping () -> Void) -> some View {
        let viewModel = OnboardingSiteSuggestionsViewModel(
            title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteNTPTitle,
            suggestedSitesProvider: OnboardingSuggestedSitesProvider(surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle),
            delegate: delegate
        )

        let manualDismissAction = { [weak self] in
            self?.onboardingPixelReporter.measureTryVisitSiteDialogNewTabDismissButtonTapped()
            onManualDismiss()
        }

        return FadeInView {
            OnboardingRebranding.OnboardingTrySiteDialog(viewModel: viewModel, onManualDismiss: manualDismissAction)
        }
        .applyNewTabOnboardingBackground(backgroundType: .tryVisitingASiteNTP)
        .onFirstAppear { [weak self] in
            self?.daxDialogsFlowCoordinator.setTryVisitSiteMessageSeen()
            self?.onboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTryVisitSiteUnique)
        }
    }

}

// MARK: - Add Favourite

private extension RebrandedNewTabDaxDialogFactory {

    func createAddFavoriteDialog(message: String) -> some View {
        FadeInView {
            OnboardingRebranding.OnboardingAddFavorite(message: message)
        }
        .applyNewTabOnboardingBackground(backgroundType: .tryVisitingASiteNTP)
    }

}

// MARK: - Final Dialog (You've Got This!)

private extension RebrandedNewTabDaxDialogFactory {
    
    func createFinalDialog(onCompletion: @escaping (_ activateSearch: Bool) -> Void, onManualDismiss: @escaping () -> Void) -> some View {
        return FadeInView {
            ScrollView(.vertical, showsIndicators: false) {
                OnboardingRebranding.OnboardingEndOfJourneyDialog(
                    message: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenMessage,
                    cta: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenButton,
                    dismissAction: { [weak self] in
                        self?.onboardingPixelReporter.measureEndOfJourneyDialogCTAAction()
                        onCompletion(true)
                    },
                    onManualDismiss: { [weak self] in
                        self?.onboardingPixelReporter.measureEndOfJourneyDialogNewTabDismissButtonTapped()
                        onManualDismiss()
                    }
                )
            }
            .scrollIfNeeded()
        }
        .applyNewTabOnboardingBackground(backgroundType: .endOfJourneyNTP)
        .onFirstAppear { [weak self] in
            self?.daxDialogsFlowCoordinator.setFinalOnboardingDialogSeen()
            self?.onboardingPixelReporter.measureScreenImpression(event: .daxDialogsEndOfJourneyNewTabUnique)
        }
    }
    
}

// MARK: - Subscription Promotion (Oh before I forget...)

private extension RebrandedNewTabDaxDialogFactory {

    func createSubscriptionPromoDialog(proceedButtonText: String, onDismiss: @escaping (_ activateSearch: Bool) -> Void) -> some View {
        func createSubscriptionPromoMessage() -> AttributedString {
            let fullText = String(
                format: UserText.SubscriptionPromotionOnboarding.Promo.messageFormat,
                UserText.SubscriptionPromotionOnboarding.Promo.optionalSubscriptionBold,
                UserText.SubscriptionPromotionOnboarding.Promo.vpnBold,
                UserText.SubscriptionPromotionOnboarding.Promo.privateAIBold
            )

            return AttributedString(fullText)
        }

        func createSubscriptionPromoMessageDeprecated() -> AttributedString {
            let fullText = String(
                format: UserText.SubscriptionPromotionOnboarding.Promo.messageFormatDeprecated,
                UserText.SubscriptionPromotionOnboarding.Promo.vpnAndTwoMoreBold,
                UserText.SubscriptionPromotionOnboarding.Promo.optionalSubscriptionBoldDeprecated
            )

            return AttributedString(fullText)
        }

        let title = UserText.SubscriptionPromotionOnboarding.Promo.title
        let message = AppDependencyProvider.shared.featureFlagger.isFeatureOn(.paidAIChat) ? createSubscriptionPromoMessage() : createSubscriptionPromoMessageDeprecated()
        let dismissText = UserText.SubscriptionPromotionOnboarding.Buttons.Rebranding.skip

        return FadeInView {
            OnboardingRebranding.OnboardingSubscriptionPromoDialog(
                title: title,
                message: message,
                proceedText: proceedButtonText,
                dismissText: dismissText,
                proceedAction: { [weak self] in
                    self?.onboardingSubscriptionPromotionHelper.fireTapPixel()
                    let urlComponents = self?.onboardingSubscriptionPromotionHelper.redirectURLComponents()
                    NotificationCenter.default.post(
                        name: .settingsDeepLinkNotification,
                        object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(redirectURLComponents: urlComponents),
                        userInfo: nil
                    )
                    onDismiss(false)
                },
                dismissAction: {
                    onDismiss(true)
                },
                onManualDismiss: { [weak self] in
                    self?.onboardingSubscriptionPromotionHelper.fireDismissPixel()
                    self?.onboardingPixelReporter.measureSubscriptionDialogNewTabDismissButtonTapped()
                    onDismiss(true)
                }
            )
        }
        .applyNewTabOnboardingBackground(backgroundType: .privacyProTrial)
        .onFirstAppear { [weak self] in
            self?.onboardingSubscriptionPromotionHelper.fireImpressionPixel()
            self?.daxDialogsFlowCoordinator.subscriptionPromotionDialogSeen = true
        }
    }

}
