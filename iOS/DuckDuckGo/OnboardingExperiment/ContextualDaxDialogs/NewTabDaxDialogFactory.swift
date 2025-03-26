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

typealias DaxDialogsFlowCoordinator = ContextualOnboardingLogic & PrivacyProPromotionCoordinating

protocol NewTabDaxDialogProvider {
    associatedtype DaxDialog: View

    /// Creates a Dax dialog for a given home screen specification.
    ///
    /// - Parameters:
    ///   - homeDialog: The specific `DaxDialogs.HomeScreenSpec` configuration that determines the dialog's content.
    ///   - onDismiss: A closure that is executed when the dialog is dismissed.
    ///     - `activateSearch`: A Boolean value indicating whether the search should be activated after dismissal (i.e if the omnibar should become the first responder)
    ///
    /// - Returns: A view conforming to `DaxDialog` that represents the Dax dialog.
    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec, onDismiss: @escaping (_ activateSearch: Bool) -> Void) -> DaxDialog
}

final class NewTabDaxDialogFactory: NewTabDaxDialogProvider {
    private var delegate: OnboardingNavigationDelegate?
    private var daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator
    private let onboardingPixelReporter: OnboardingPixelReporting
    private let onboardingPrivacyProPromoExperiment: any OnboardingPrivacyProPromoExperimenting

    init(
        delegate: OnboardingNavigationDelegate?,
        daxDialogsFlowCoordinator: DaxDialogsFlowCoordinator,
        onboardingPixelReporter: OnboardingPixelReporting,
        onboardingPrivacyProPromoExperiment: OnboardingPrivacyProPromoExperimenting = OnboardingPrivacyProPromoExperiment()
    ) {
        self.delegate = delegate
        self.daxDialogsFlowCoordinator = daxDialogsFlowCoordinator
        self.onboardingPixelReporter = onboardingPixelReporter
        self.onboardingPrivacyProPromoExperiment = onboardingPrivacyProPromoExperiment
    }

    @ViewBuilder
    func createDaxDialog(for homeDialog: DaxDialogs.HomeScreenSpec, onDismiss: @escaping (_ activateSearch: Bool) -> Void) -> some View {
        switch homeDialog {
        case .initial:
            createInitialDialog()
        case .addFavorite:
            createAddFavoriteDialog(message: homeDialog.message)
        case .subsequent:
            createSubsequentDialog()
        case .final:
            createFinalDialog(onDismiss: onDismiss)
        case .privacyProPromotion:
            createPrivacyProPromoDialog(onDismiss: onDismiss)
        default:
            EmptyView()
        }
    }

    private func createInitialDialog() -> some View {
        let viewModel = OnboardingSearchSuggestionsViewModel(suggestedSearchesProvider: OnboardingSuggestedSearchesProvider(), delegate: delegate, pixelReporter: onboardingPixelReporter)
        let message = UserText.Onboarding.ContextualOnboarding.onboardingTryASearchMessage
        return FadeInView {
            OnboardingTrySearchDialog(message: message, viewModel: viewModel)
                .onboardingDaxDialogStyle()
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
        .onFirstAppear { [weak self] in
            self?.daxDialogsFlowCoordinator.setTryAnonymousSearchMessageSeen()
            self?.onboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTrySearchUnique)
        }
    }

    private func createSubsequentDialog() -> some View {
        let viewModel = OnboardingSiteSuggestionsViewModel(title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteNTPTitle, suggestedSitesProvider: OnboardingSuggestedSitesProvider(surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle), delegate: delegate, pixelReporter: onboardingPixelReporter)
        return FadeInView {
            OnboardingTryVisitingSiteDialog(logoPosition: .top, viewModel: viewModel)
                .onboardingDaxDialogStyle()
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
        .onFirstAppear { [weak self] in
            self?.daxDialogsFlowCoordinator.setTryVisitSiteMessageSeen()
            self?.onboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTryVisitSiteUnique)
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
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
    }

    private func createFinalDialog(onDismiss: @escaping (_ activateSearch: Bool) -> Void) -> some View {
        let dismissAction = { [weak self] in
            self?.onboardingPixelReporter.measureEndOfJourneyDialogCTAAction()
            onDismiss(true)
        }

        return FadeInView {
            OnboardingFinalDialog(
                logoPosition: .top,
                message: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenMessage,
                cta: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenButton,
                dismissAction: dismissAction
            )
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
        .onFirstAppear { [weak self] in
            self?.daxDialogsFlowCoordinator.setFinalOnboardingDialogSeen()
            self?.onboardingPixelReporter.measureScreenImpression(event: .daxDialogsEndOfJourneyNewTabUnique)
        }
    }
}

private extension NewTabDaxDialogFactory {
    private func createPrivacyProPromoDialog(onDismiss: @escaping (_ activateSearch: Bool) -> Void) -> some View {

        return FadeInView {
            PrivacyProPromotionView(title: UserText.PrivacyProPromotionOnboarding.Promo.title,
                                    message: UserText.PrivacyProPromotionOnboarding.Promo.message(),
                                    proceedText: UserText.PrivacyProPromotionOnboarding.Buttons.learnMore,
                                    dismissText: UserText.PrivacyProPromotionOnboarding.Buttons.skip,
                                    proceedAction: { [weak self] in
                self?.onboardingPrivacyProPromoExperiment.fireTapPixel()
                let urlComponents = OnboardingPrivacyProPromoExperiment().redirectURLComponents()
                NotificationCenter.default.post(
                    name: .settingsDeepLinkNotification,
                    object: SettingsViewModel.SettingsDeepLinkSection.subscriptionFlow(redirectURLComponents: urlComponents),
                    userInfo: nil
                )
                onDismiss(false)
            },
                                    dismissAction: { [weak self] in
                self?.onboardingPrivacyProPromoExperiment.fireDismissPixel()
                onDismiss(true)
            })
        }
        .onboardingContextualBackgroundStyle(background: .illustratedGradient)
        .onFirstAppear { [weak self] in
            self?.onboardingPrivacyProPromoExperiment.fireImpressionPixel()
            self?.daxDialogsFlowCoordinator.privacyProPromotionDialogSeen = true
        }
    }
}

struct FadeInView<Content: View>: View {
    var content: Content
    @State private var opacity: Double = 0

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeIn(duration: 0.4)) {
                    opacity = 1.0
                }
            }
    }
}
