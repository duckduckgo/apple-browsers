//
//  ContextualDaxDialogsFactory.swift
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

import SwiftUI
import Core
import Onboarding

// MARK: - ContextualOnboardingEventDelegate

/// A delegate to inform about specific events happening during the contextual onboarding.
protocol ContextualOnboardingEventDelegate: AnyObject {
    func didAcknowledgeContextualOnboardingSearch()
    /// Inform the delegate that a dialog for blocked trackers have been shown to the user.
    func didShowContextualOnboardingTrackersDialog()
    /// Inform the delegate that the user did acknowledge the dialog for blocked trackers.
    func didAcknowledgeContextualOnboardingTrackersDialog()
    /// Inform the delegate that the user dismissed the contextual dialog.
    func didTapDismissContextualOnboardingAction()
    /// Inform the delegate that the user advanced past the visit-site dialog by picking a
    /// suggestion. Unlike `didTapDismissContextualOnboardingAction`, this only collapses the
    /// dialog UI — it does **not** reset `lastShownDaxDialogType` / `lastVisitedOnboardingWebsiteURL`
    /// — so the natural next contextual spec (e.g. trackers) can still surface once the chosen
    /// page finishes loading.
    func didNavigateAwayFromContextualOnboardingDialog()
}

// Composed delegate for Contextual Onboarding to decorate events also needed in New Tab Page.
typealias ContextualOnboardingDelegate = OnboardingNavigationDelegate & ContextualOnboardingEventDelegate

// MARK: - Contextual Dialogs Factory

protocol ContextualDaxDialogsFactory {
    func makeView(for spec: DaxDialogs.BrowsingSpec, delegate: ContextualOnboardingDelegate, onSizeUpdate: @escaping () -> Void) -> UIHostingController<AnyView>
}

final class DefaultContextualDaxDialogsFactory: ContextualDaxDialogsFactory {
    private let contextualOnboardingLogic: ContextualOnboardingLogic
    private let contextualOnboardingSettings: ContextualOnboardingSettings
    private let contextualOnboardingPixelReporter: OnboardingPixelReporting
    private let contextualOnboardingSiteSuggestionsProvider: OnboardingSuggestionsItemsProviding
    private let onboardingManager: OnboardingManaging

    init(
        contextualOnboardingLogic: ContextualOnboardingLogic,
        contextualOnboardingSettings: ContextualOnboardingSettings = DefaultDaxDialogsSettings(),
        contextualOnboardingPixelReporter: OnboardingPixelReporting,
        contextualOnboardingSiteSuggestionsProvider: OnboardingSuggestionsItemsProviding = OnboardingSuggestedSitesProvider(surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle),
        onboardingManager: OnboardingManaging = OnboardingManager()
    ) {
        self.contextualOnboardingSettings = contextualOnboardingSettings
        self.contextualOnboardingLogic = contextualOnboardingLogic
        self.contextualOnboardingPixelReporter = contextualOnboardingPixelReporter
        self.contextualOnboardingSiteSuggestionsProvider = contextualOnboardingSiteSuggestionsProvider
        self.onboardingManager = onboardingManager
    }

    func makeView(for spec: DaxDialogs.BrowsingSpec, delegate: ContextualOnboardingDelegate, onSizeUpdate: @escaping () -> Void) -> UIHostingController<AnyView> {
        let rootView: AnyView
        switch spec.type {
        case .afterSearch:
            rootView = AnyView(
                afterSearchDialog(
                    shouldFollowUpToWebsiteSearch: !contextualOnboardingSettings.userHasSeenTrackersDialog && !contextualOnboardingSettings.userHasSeenTryVisitSiteDialog,
                    delegate: delegate,
                    afterSearchPixelEvent: spec.pixelName,
                    onSizeUpdate: onSizeUpdate
                )
            )
        case .visitWebsite:
            rootView = AnyView(
                tryVisitingSiteDialog(
                    delegate: delegate
                )
            )
        case .siteIsMajorTracker, .siteOwnedByMajorTracker, .withMultipleTrackers, .withOneTracker, .withoutTrackers:
            rootView = AnyView(
                withTrackersDialog(
                    for: spec,
                    shouldFollowUpToFireDialog: !contextualOnboardingSettings.userHasSeenFireDialog,
                    delegate: delegate,
                    onSizeUpdate: onSizeUpdate
                )
            )
        case .fire(let fireVariant):
            rootView = AnyView(
                fireDialog(
                    title: spec.title,
                    message: spec.message,
                    delegate: delegate,
                    fireVariant: fireVariant,
                    pixelName: spec.pixelName,
                    allowsManualDismiss: spec.allowsManualDismiss
                )
            )
        case .final:
            rootView = AnyView(
                endOfJourneyDialog(
                    delegate: delegate,
                    pixelName: spec.pixelName
                )
            )
        }

        let viewWithBackground = rootView
            .onboardingDaxDialogStyle()
            .onboardingContextualBackgroundStyle(background: .gradientOnly)
        let hostingController = UIHostingController(rootView: AnyView(viewWithBackground))
        if #available(iOS 16.0, *) {
            hostingController.sizingOptions = [.intrinsicContentSize]
        }

        return hostingController
    }

    private func afterSearchDialog(
        shouldFollowUpToWebsiteSearch: Bool,
        delegate: ContextualOnboardingDelegate,
        afterSearchPixelEvent: Pixel.Event,
        onSizeUpdate: @escaping () -> Void
    ) -> some View {

        func dialogMessage() -> NSAttributedString {
            let message = UserText.Onboarding.ContextualOnboarding.onboardingFirstSearchDoneMessage
            let boldRange = message.range(of: "DuckDuckGo Search")
            return message.attributed.with(attribute: .font, value: UIFont.daxBodyBold(), in: boldRange)
        }

        let viewModel = OnboardingSiteSuggestionsViewModel(
            title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle,
            suggestedSitesProvider: contextualOnboardingSiteSuggestionsProvider,
            delegate: delegate,
            onSuggestionPressed: { [weak self] in
                self?.contextualOnboardingPixelReporter.measureTryVisitSiteDialogSuggestedSiteTapped()
            }
        )

        // If should not show websites search after searching inform the delegate that the user dimissed the dialog, otherwise let the dialog handle it.
        let gotItAction: () -> Void = if shouldFollowUpToWebsiteSearch {
            { [weak delegate, weak self] in
                self?.contextualOnboardingPixelReporter.measureSearchResultsDialogGotItAction()
                onSizeUpdate()
                delegate?.didAcknowledgeContextualOnboardingSearch()
                self?.contextualOnboardingLogic.setTryVisitSiteMessageSeen()
                self?.contextualOnboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTryVisitSiteUnique)
                self?.contextualOnboardingPixelReporter.measureScreenImpression(.visitSite(.shown))
            }
        } else {
            { [weak delegate, weak self] in
                self?.contextualOnboardingPixelReporter.measureSearchResultsDialogGotItAction()
                delegate?.didTapDismissContextualOnboardingAction()
            }
        }

        let onManualDismiss: (_ isShowingTryVisitSiteDialog: Bool) -> Void = { [weak delegate, weak self] isShowingTryVisitSiteDialog in
            if isShowingTryVisitSiteDialog {
                self?.contextualOnboardingPixelReporter.measureTryVisitSiteDialogDismissButtonTapped()
            } else {
                self?.contextualOnboardingPixelReporter.measureSearchResultDialogDismissButtonTapped()
            }
            delegate?.didTapDismissContextualOnboardingAction()
        }

        return OnboardingFirstSearchDoneDialog(
            message: dialogMessage(),
            shouldFollowUp: shouldFollowUpToWebsiteSearch,
            viewModel: viewModel,
            gotItAction: gotItAction,
            onManualDismiss: onManualDismiss
        )
        .onFirstAppear { [weak self] in
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: afterSearchPixelEvent)
            self?.contextualOnboardingPixelReporter.measureScreenImpression(.searchResults(.shown))
        }
    }

    private func tryVisitingSiteDialog(delegate: ContextualOnboardingDelegate) -> some View {
        let viewModel = OnboardingSiteSuggestionsViewModel(
            title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle,
            suggestedSitesProvider: contextualOnboardingSiteSuggestionsProvider,
            delegate: delegate,
            onSuggestionPressed: { [weak self] in
                self?.contextualOnboardingPixelReporter.measureTryVisitSiteDialogSuggestedSiteTapped()
            }
        )

        let onManualDismiss: () -> Void = { [weak delegate, weak self] in
            self?.contextualOnboardingPixelReporter.measureTryVisitSiteDialogDismissButtonTapped()
            delegate?.didTapDismissContextualOnboardingAction()
        }

        return OnboardingTryVisitingSiteDialog(
            logoPosition: .left,
            viewModel: viewModel,
            onManualDismiss: onManualDismiss
        )
        .onFirstAppear { [weak self] in
            self?.contextualOnboardingLogic.setTryVisitSiteMessageSeen()
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTryVisitSiteUnique)
            self?.contextualOnboardingPixelReporter.measureScreenImpression(.visitSite(.shown))
        }
    }

    private func withTrackersDialog(
        for spec: DaxDialogs.BrowsingSpec,
        shouldFollowUpToFireDialog: Bool,
        delegate: ContextualOnboardingDelegate,
        onSizeUpdate: @escaping () -> Void
    ) -> some View {
        let attributedMessage = spec.message.attributedStringFromMarkdown(color: ThemeManager.shared.currentTheme.daxDialogTextColor)

        let onManualDismiss: (_ isShowingFireDialog: Bool) -> Void = { [weak delegate, weak self] isShowingFireDialog in
            // Hide Pulsing animation for Privacy Shield or Fire Dialog
            ViewHighlighter.hideAll()

            if isShowingFireDialog {
                self?.contextualOnboardingPixelReporter.measureFireDialogDismissButtonTapped()
            } else {
                // Set Fire dialog seen. In this way when we open a new tab we show the final dialog.
                self?.contextualOnboardingLogic.setFireEducationMessageSeen()
                self?.contextualOnboardingPixelReporter.measureTrackersDialogDismissButtonTapped()
            }
            delegate?.didTapDismissContextualOnboardingAction()
        }

        return OnboardingTrackersDoneDialog(
            shouldFollowUp: shouldFollowUpToFireDialog,
            message: attributedMessage,
            blockedTrackersCTAAction: { [weak self, weak delegate] in
                self?.contextualOnboardingPixelReporter.measureTrackersDialogGotItAction()

                // If the user has not seen the fire dialog yet proceed to the fire dialog, otherwise dismiss the dialog.
                if self?.contextualOnboardingSettings.userHasSeenFireDialog == true {
                    delegate?.didTapDismissContextualOnboardingAction()
                } else {
                    onSizeUpdate()
                    delegate?.didAcknowledgeContextualOnboardingTrackersDialog()
                    self?.contextualOnboardingPixelReporter.measureScreenImpression(event: .daxDialogsFireEducationShownUnique)
                    self?.contextualOnboardingPixelReporter.measureScreenImpression(.fireButton(.shown))
                }
            },
            onManualDismiss: onManualDismiss
        )
        .onAppear { [weak delegate] in
            delegate?.didShowContextualOnboardingTrackersDialog()
        }
        .onFirstAppear { [weak self] in
            // Fire the general dialog impression pixel for all users, plus an additional
            // chat-path-specific pixel when the user is in the Duck.ai experiment flow.
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: spec.pixelName)
            if self?.contextualOnboardingSettings.chatPathPhase == .trackerToEOJ {
                self?.contextualOnboardingPixelReporter.measureScreenImpression(event: .onboardingChatPathTrackersBlockedUnique)
            }
            self?.contextualOnboardingPixelReporter.measureScreenImpression(.trackersBlocked(.shown))
        }
    }

    private func fireDialog(
        title: String?,
        message: String,
        delegate: ContextualOnboardingDelegate,
        fireVariant: DaxDialogs.BrowsingSpec.SpecType.FireVariant,
        pixelName: Pixel.Event,
        allowsManualDismiss: Bool
    ) -> some View {
        let onManualDismiss: (() -> Void)? = allowsManualDismiss ? { [weak delegate, weak self] in
            self?.contextualOnboardingPixelReporter.measureFireDialogDismissButtonTapped()
            delegate?.didTapDismissContextualOnboardingAction()
        } : nil

        return OnboardingFireDialog(title: title, message: message, onManualDismiss: onManualDismiss)
            .onFirstAppear { [weak self] in
                guard let self else { return }
                switch fireVariant {
                case .standard:
                    self.contextualOnboardingPixelReporter.measureScreenImpression(event: pixelName)
                case .duckAIOnboarding:
                    if self.onboardingManager.currentOnboardingFlow == .default {
                        self.contextualOnboardingPixelReporter.measureDuckAIExperimentFireDialogImpression()
                    }
                }
                self.contextualOnboardingPixelReporter.measureScreenImpression(.fireButton(.shown))
            }
    }

    private func endOfJourneyDialog(
        delegate: ContextualOnboardingDelegate,
        pixelName: Pixel.Event
    ) -> some View {
        let dismissAction = { [weak delegate, weak self] in
            delegate?.didTapDismissContextualOnboardingAction()
            self?.contextualOnboardingPixelReporter.measureEndOfJourneyDialogCTAAction()
        }

        let onManualDismiss: () -> Void = { [weak delegate, weak self] in
            self?.contextualOnboardingPixelReporter.measureEndOfJourneyDialogDismissButtonTapped()
            delegate?.didTapDismissContextualOnboardingAction()
        }

        return OnboardingFinalDialog(
            logoPosition: .left,
            message: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenMessage,
            cta: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenButton,
            dismissAction: dismissAction,
            onManualDismiss: onManualDismiss
        )
        .onFirstAppear { [weak self] in
            self?.contextualOnboardingLogic.setFinalOnboardingDialogSeen()
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: pixelName)
            self?.contextualOnboardingPixelReporter.measureScreenImpression(.end(.shown))
        }
    }

}

// MARK: - Contextual Onboarding Settings

protocol ContextualOnboardingSettings {
    var userHasSeenTrackersDialog: Bool { get }
    var userHasSeenFireDialog: Bool { get }
    var userHasSeenTryVisitSiteDialog: Bool { get }
    /// The current phase of the Duck.ai chat-first onboarding path.
    var chatPathPhase: DaxDialogs.ChatPathPhase { get }
}

extension DefaultDaxDialogsSettings: ContextualOnboardingSettings {
    
    var userHasSeenTrackersDialog: Bool {
        browsingWithTrackersShown ||
        browsingWithoutTrackersShown ||
        browsingMajorTrackingSiteShown
    }
    
    var userHasSeenFireDialog: Bool {
        fireMessageExperimentShown
    }

    var userHasSeenTryVisitSiteDialog: Bool {
        tryVisitASiteShown
    }

}
