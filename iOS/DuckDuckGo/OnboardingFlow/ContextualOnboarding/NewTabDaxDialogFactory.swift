//
//  NewTabDaxDialogFactory.swift
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
import FoundationExtensions
import PrivacyConfig

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

    /// Creates a completion dialog shown after Duck.ai fire onboarding.
    ///
    /// - Parameters:
    ///   - message: Completion message to display.
    ///   - onDismiss: Closure called when the dialog is dismissed.
    ///
    /// - Returns: Type-erased completion dialog view.
    func createDuckAIFireOnboardingCompletionDialog(message: String, onDismiss: @escaping () -> Void) -> AnyView
}

final class NewTabDaxDialogFactory: NewTabDaxDialogProviding {
    private var delegate: OnboardingNavigationDelegate?
    private var daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator
    private let onboardingPixelReporter: OnboardingPixelReporting
    private let onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping
    private let onboardingFlowProvider: OnboardingFlowProviding
    private let featureFlagger: FeatureFlagger

    init(
        delegate: OnboardingNavigationDelegate?,
        daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator,
        onboardingPixelReporter: OnboardingPixelReporting,
        onboardingSubscriptionPromotionHelper: OnboardingSubscriptionPromotionHelping = OnboardingSubscriptionPromotionHelper(),
        onboardingFlowProvider: OnboardingFlowProviding = OnboardingManager(),
        featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger
    ) {
        self.delegate = delegate
        self.daxDialogsFlowCoordinator = daxDialogsFlowCoordinator
        self.onboardingPixelReporter = onboardingPixelReporter
        self.onboardingSubscriptionPromotionHelper = onboardingSubscriptionPromotionHelper
        self.onboardingFlowProvider = onboardingFlowProvider
        self.featureFlagger = featureFlagger
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

private extension NewTabDaxDialogFactory {

    func createInitialDialog(onManualDismiss: @escaping () -> Void) -> some View {
        let viewModel = OnboardingSearchSuggestionsViewModel(
            suggestedSearchesProvider: OnboardingSuggestedSearchesProvider(),
            delegate: delegate,
            onSuggestionPressed: { [weak self] in
                self?.onboardingPixelReporter.measureTrySearchDialogSuggestedSearchTapped()
            }
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
            self?.onboardingPixelReporter.measureScreenImpression(.search(.shown))
        }
    }

}

extension NewTabDaxDialogFactory {

    func createDuckAIFireOnboardingCompletionDialog(message: String, onDismiss: @escaping () -> Void) -> AnyView {
        let onDismiss = { [weak self] in
            self?.onboardingPixelReporter.measureDuckAIFinalDialogCTAAction()
            onDismiss()
        }

        return AnyView(
            FadeInView {
                ScrollView(.vertical, showsIndicators: false) {
                    // The Duck.ai fire onboarding completion dialog reuses `OnboardingEndOfJourneyDialog`
                    // but is presented over the active address bar with the keyboard up — no room
                    // for the screen-bottom Dax animation, so suppress it explicitly here.
                    OnboardingRebranding.OnboardingEndOfJourneyDialog(
                        message: message,
                        cta: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenButton,
                        showsDaxAnimation: false,
                        dismissAction: onDismiss
                    )
                }
                .scrollIfNeeded()
            }
            .applyNewTabOnboardingBackground(backgroundType: .endOfJourneyNTPChat)
            .onFirstAppear { [weak self] in
                self?.daxDialogsFlowCoordinator.setFinalOnboardingDialogSeen()
                self?.onboardingPixelReporter.measureDuckAIFinalDialogImpression()
                self?.onboardingPixelReporter.measureScreenImpression(.end(.shown))
            }
        )
    }

}

// MARK: - Subsequent Dialog (Try Visiting A Site!)

private extension NewTabDaxDialogFactory {

    private func createSubsequentDialog(onManualDismiss: @escaping () -> Void) -> some View {
        let isChatPath = daxDialogsFlowCoordinator.chatPathPhase == .visitSite

        let viewModel = OnboardingSiteSuggestionsViewModel(
            title: isChatPath
                ? UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle
                : UserText.Onboarding.ContextualOnboarding.onboardingTryASiteNTPTitle,
            suggestedSitesProvider: OnboardingSuggestedSitesProvider(surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle),
            delegate: delegate,
            onSuggestionPressed: { [weak self] in
                self?.onboardingPixelReporter.measureTryVisitSiteDialogSuggestedSiteTapped()
            }
        )

        let manualDismissAction: (() -> Void)? = isChatPath ? nil : { [weak self] in
            self?.onboardingPixelReporter.measureTryVisitSiteDialogNewTabDismissButtonTapped()
            onManualDismiss()
        }

        return FadeInView {
            OnboardingRebranding.OnboardingTrySiteDialog(viewModel: viewModel, onManualDismiss: manualDismissAction)
        }
        .applyNewTabOnboardingBackground(backgroundType: isChatPath ? .tryVisitingASiteChatPath : .tryVisitingASiteNTP,
                                         keyboardBehavior: isChatPath ? .ignoreKeyboard : .adjustForKeyboard)
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

}

// MARK: - Add Favourite

private extension NewTabDaxDialogFactory {

    func createAddFavoriteDialog(message: String) -> some View {
        FadeInView {
            OnboardingRebranding.OnboardingAddFavorite(message: message)
        }
        .applyNewTabOnboardingBackground(backgroundType: .tryVisitingASiteNTP)
    }

}

// MARK: - Final Dialog (You've Got This! / Chat-Path Completion)

private extension NewTabDaxDialogFactory {

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
            self?.onboardingPixelReporter.measureScreenImpression(.end(.shown))
        }
    }

}

// MARK: - Subscription Promotion (Oh before I forget...)

private extension NewTabDaxDialogFactory {

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

        let isChatPath = daxDialogsFlowCoordinator.isChatFirstPath
        let title = UserText.SubscriptionPromotionOnboarding.Promo.title
        let message = switch onboardingFlowProvider.currentOnboardingFlow {
        case .default:
            if featureFlagger.isFeatureOn(.paidAIChat){
                createSubscriptionPromoMessage()
            } else {
                createSubscriptionPromoMessageDeprecated()
            }
        case .duckAI:
            AttributedString(UserText.Onboarding.DuckAICPP.Contextual.subscriptionMessage.preventWidows())
        }
        let dismissText = UserText.SubscriptionPromotionOnboarding.Buttons.Rebranding.skip
        let manualDismissAction: (() -> Void)? = isChatPath ? nil : { [weak self] in
            self?.onboardingSubscriptionPromotionHelper.fireDismissPixel()
            self?.onboardingPixelReporter.measureSubscriptionDialogNewTabDismissButtonTapped()
            onDismiss(true)
        }
        return FadeInView {
            OnboardingRebranding.OnboardingSubscriptionPromoDialog(
                title: title,
                message: message,
                proceedText: proceedButtonText,
                dismissText: dismissText,
                proceedAction: { [weak self] in
                    self?.onboardingPixelReporter.measureSubscriptionPromoEngageCTAAction()
                    self?.onboardingSubscriptionPromotionHelper.fireTapPixel()
                    let featurePage: OnboardingSubscriptionPromotionPage? = self?.onboardingFlowProvider.currentOnboardingFlow == .duckAI ? .duckAI : nil
                    let urlComponents = self?.onboardingSubscriptionPromotionHelper.redirectURLComponents(featurePage: featurePage)
                    // Pass onDismiss as a post-presentation callback so it fires only after
                    // the settings sheet is fully on screen — keeping the promo dialog visible
                    // until the sheet covers it completely, avoiding an NTP flash.
                    NotificationCenter.default.post(
                        name: .settingsDeepLinkNotification,
                        object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(redirectURLComponents: urlComponents),
                        userInfo: [SettingsDeepLinkUserInfoKey.onPresented: SettingsDeepLinkCallback(onPresented: { onDismiss(false) })]
                    )
                },
                dismissAction: { [weak self] in
                    self?.onboardingSubscriptionPromotionHelper.fireDismissPixel()
                    self?.onboardingPixelReporter.measureSubscriptionDialogNewTabDismissButtonTapped()
                    onDismiss(true)
                },
                onManualDismiss: manualDismissAction
            )
        }
        .applyNewTabOnboardingBackground(backgroundType: .privacyProTrial)
        .onFirstAppear { [weak self] in
            self?.onboardingSubscriptionPromotionHelper.fireImpressionPixel()
            self?.onboardingPixelReporter.measureSubscriptionPromoDialogShown()
            self?.daxDialogsFlowCoordinator.subscriptionPromotionDialogSeen = true
        }
    }

}
