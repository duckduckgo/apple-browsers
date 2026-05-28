//
//  NewTabDaxDialogFactory.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import FoundationExtensions

typealias DaxDialogsFlowCoordinator = ContextualOnboardingLogic & SubscriptionPromotionCoordinating

protocol NewTabDaxDialogProviding {
    associatedtype DaxDialog: View

    /// Creates a Dax dialog for a given home screen specification.
    ///
    /// - Parameters:
    ///   - homeDialog: The specific `DaxDialogs.HomeScreenSpec` configuration that determines the dialog's content.
    ///   - onCompletion: A closure that is executed when the dialog is dismissed when the onboarding is completed.
    ///     - `activateSearch`: A Boolean value indicating whether the search should be activated after dismissal (i.e if the omnibar should become the first responder)
    ///   - onManualDismiss: A closure that is executed when the dialog is dismissed manually by the user.
    ///
    /// - Returns: A view conforming to `DaxDialog` that represents the Dax dialog.
    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec, onCompletion: @escaping (_ activateSearch: Bool) -> Void, onManualDismiss: @escaping () -> Void) -> DaxDialog

    /// Creates an experiment completion dialog shown after Duck.ai fire onboarding.
    ///
    /// - Parameters:
    ///   - message: Completion message to display.
    ///   - onDismiss: Closure called when the dialog is dismissed.
    ///
    /// - Returns: Type-erased completion dialog view.
    func createExperimentCompletionDialog(message: String, onDismiss: @escaping () -> Void) -> AnyView
}

final class NewTabDaxDialogFactory: NewTabDaxDialogProviding {
    private var delegate: OnboardingNavigationDelegate?
    private var daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator
    private let onboardingPixelReporter: OnboardingPixelReporting
    private let onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping
    private let onboardingFlowProvider: OnboardingFlowProviding

    init(
        delegate: OnboardingNavigationDelegate?,
        daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator,
        onboardingPixelReporter: OnboardingPixelReporting,
        onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping = OnboardingSubscriptionPromotionHelper(),
        onboardingFlowProvider: OnboardingFlowProviding = OnboardingManager()

    ) {
        self.delegate = delegate
        self.daxDialogsFlowCoordinator = daxDialogsFlowCoordinator
        self.onboardingPixelReporter = onboardingPixelReporter
        self.onboardingSubscriptionPromotionHelper = onboardingSubscriptionPromotionHelper
        self.onboardingFlowProvider = onboardingFlowProvider
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

    private func createInitialDialog(onManualDismiss: @escaping () -> Void) -> some View {
        let viewModel = OnboardingSearchSuggestionsViewModel(
            suggestedSearchesProvider: OnboardingSuggestedSearchesProvider(),
            delegate: delegate,
            onSuggestionPressed: { [weak self] in
                self?.onboardingPixelReporter.measureTrySearchDialogSuggestedSearchTapped()
            }
        )
        let message = UserText.Onboarding.ContextualOnboarding.onboardingTryASearchMessage

        let manualDismissAction = { [weak self] in
            self?.onboardingPixelReporter.measureTrySearchDialogNewTabDismissButtonTapped()
            onManualDismiss()
        }

        return FadeInView {
            OnboardingTrySearchDialog(message: message, viewModel: viewModel, onManualDismiss: manualDismissAction)
                .onboardingDaxDialogStyle()
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
        .onFirstAppear { [weak self] in
            self?.daxDialogsFlowCoordinator.setTryAnonymousSearchMessageSeen()
            self?.onboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTrySearchUnique)
            self?.onboardingPixelReporter.measureScreenImpression(.search(.shown))
        }
    }

    private func createSubsequentDialog(onManualDismiss: @escaping () -> Void) -> some View {
        let isChatPath = daxDialogsFlowCoordinator.chatPathPhase == .visitSite

        let viewModel = OnboardingSiteSuggestionsViewModel(
            title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteNTPTitle,
            suggestedSitesProvider: OnboardingSuggestedSitesProvider(surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle),
            delegate: delegate,
            onSuggestionPressed: { [weak self] in
                self?.onboardingPixelReporter.measureTryVisitSiteDialogSuggestedSiteTapped()
            }
        )

        let manualDismissAction = { [weak self] in
            self?.onboardingPixelReporter.measureTryVisitSiteDialogNewTabDismissButtonTapped()
            onManualDismiss()
        }

        return FadeInView {
            OnboardingTryVisitingSiteDialog(logoPosition: .top, viewModel: viewModel, onManualDismiss: manualDismissAction)
                .onboardingDaxDialogStyle()
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
        .onFirstAppear { [weak self] in
            if isChatPath {
                self?.daxDialogsFlowCoordinator.setChatPathVisitSiteSeen()
                self?.onboardingPixelReporter.measureScreenImpression(event: .onboardingChatPathTryVisitSiteUnique)
            } else {
                self?.daxDialogsFlowCoordinator.setTryVisitSiteMessageSeen()
                self?.onboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTryVisitSiteUnique)
            }
            self?.onboardingPixelReporter.measureScreenImpression(.visitSite(.shown))
        }
    }

    private func createAddFavoriteDialog(message: String) -> some View {
        FadeInView {
            ScrollView(.vertical) {
                DaxDialogView(logoPosition: .top) {
                    ContextualDaxDialogContent(message: NSAttributedString(string: message), messageFont: Font.system(size: 16))
                }
                .padding()
            }
            .onboardingDaxDialogStyle()
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
    }

    private func createFinalDialog(onCompletion: @escaping (_ activateSearch: Bool) -> Void, onManualDismiss: @escaping () -> Void) -> some View {
        return FadeInView {
            OnboardingFinalDialog(
                logoPosition: .top,
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
            .onboardingDaxDialogStyle()
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
        .onFirstAppear { [weak self] in
            self?.daxDialogsFlowCoordinator.setFinalOnboardingDialogSeen()
            self?.onboardingPixelReporter.measureScreenImpression(event: .daxDialogsEndOfJourneyNewTabUnique)
            self?.onboardingPixelReporter.measureScreenImpression(.end(.shown))
        }
    }

    func createExperimentCompletionDialog(message: String, onDismiss: @escaping () -> Void) -> AnyView {
        let onDismiss = { [weak self] in
            self?.onboardingPixelReporter.measureDuckAIExperimentFinalDialogCTAAction()
            onDismiss()
        }

        return AnyView(
            OnboardingFinalDialog(
                logoPosition: .top,
                message: message,
                cta: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenButton,
                dismissAction: onDismiss
            )
            .onboardingDaxDialogStyle()
            .onboardingContextualBackgroundStyle(background: .illustratedGradient)
            .onFirstAppear { [weak self] in
                self?.daxDialogsFlowCoordinator.setFinalOnboardingDialogSeen()
                self?.onboardingPixelReporter.measureDuckAIExperimentFinalDialogImpression()
            }
        )
    }
}

private extension NewTabDaxDialogFactory {
    private func createSubscriptionPromoDialog(proceedButtonText: String, onDismiss: @escaping (_ activateSearch: Bool) -> Void) -> some View {
        return FadeInView {
            SubscriptionPromotionView(
                title: UserText.SubscriptionPromotionOnboarding.Promo.title,
                // This is temporary and will be removed after rebranding is launched
                message: AppDependencyProvider.shared.featureFlagger.isFeatureOn(.paidAIChat) ?  UserText.SubscriptionPromotionOnboarding.Promo.message() : UserText.SubscriptionPromotionOnboarding.Promo.messageDeprecated(),
                proceedText: proceedButtonText,
                dismissText: UserText.SubscriptionPromotionOnboarding.Buttons.skip,
                proceedAction: { [weak self] in
                    self?.onboardingPixelReporter.measureSubscriptionPromoEngageCTAAction()
                    self?.onboardingSubscriptionPromotionHelper.fireTapPixel()
                    let featurePage: OnboardingSubscriptionPromotionPage? = self?.onboardingFlowProvider.currentOnboardingFlow == .duckAI ? .duckAI : nil
                    let urlComponents = self?.onboardingSubscriptionPromotionHelper.redirectURLComponents(featurePage: featurePage)
                    NotificationCenter.default.post(
                        name: .settingsDeepLinkNotification,
                        object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(redirectURLComponents: urlComponents),
                        userInfo: nil
                    )
                    onDismiss(false)
                },
                onManualDismiss: { [weak self] in
                    self?.onboardingSubscriptionPromotionHelper.fireDismissPixel()
                    self?.onboardingPixelReporter.measureSubscriptionDialogNewTabDismissButtonTapped()
                    onDismiss(true)
                }
            )
            .onboardingDaxDialogStyle()
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
        .onFirstAppear { [weak self] in
            self?.onboardingSubscriptionPromotionHelper.fireImpressionPixel()
            self?.onboardingPixelReporter.measureSubscriptionPromoDialogShown()
            self?.daxDialogsFlowCoordinator.subscriptionPromotionDialogSeen = true
        }
    }
}
