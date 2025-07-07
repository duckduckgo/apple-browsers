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
}

// Composed delegate for Contextual Onboarding to decorate events also needed in New Tab Page.
typealias ContextualOnboardingDelegate = OnboardingNavigationDelegate & ContextualOnboardingEventDelegate

// MARK: - Contextual Dialogs Factory

protocol ContextualDaxDialogsFactory {
    func makeView(for spec: DaxDialogs.BrowsingSpec, delegate: ContextualOnboardingDelegate, onSizeUpdate: @escaping () -> Void) -> UIHostingController<AnyView>
}

final class ExperimentContextualDaxDialogsFactory: ContextualDaxDialogsFactory {
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
        case .fire:
            rootView = AnyView(
                fireDialog(
                    delegate: delegate,
                    pixelName: spec.pixelName
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

        let viewModel = OnboardingSiteSuggestionsViewModel(title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle, suggestedSitesProvider: contextualOnboardingSiteSuggestionsProvider, delegate: delegate)

        // If should not show websites search after searching inform the delegate that the user dimissed the dialog, otherwise let the dialog handle it.
        let gotItAction: () -> Void = if shouldFollowUpToWebsiteSearch {
            { [weak delegate, weak self] in
                onSizeUpdate()
                delegate?.didAcknowledgeContextualOnboardingSearch()
                self?.contextualOnboardingLogic.setTryVisitSiteMessageSeen()
                self?.contextualOnboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTryVisitSiteUnique)
            }
        } else {
            { [weak delegate] in
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
        }
    }

    private func tryVisitingSiteDialog(delegate: ContextualOnboardingDelegate) -> some View {
        let viewModel = OnboardingSiteSuggestionsViewModel(
            title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle,
            suggestedSitesProvider: contextualOnboardingSiteSuggestionsProvider,
            delegate: delegate
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
                // If the user has not seen the fire dialog yet proceed to the fire dialog, otherwise dismiss the dialog.
                if self?.contextualOnboardingSettings.userHasSeenFireDialog == true {
                    delegate?.didTapDismissContextualOnboardingAction()
                } else {
                    onSizeUpdate()
                    delegate?.didAcknowledgeContextualOnboardingTrackersDialog()
                    self?.contextualOnboardingPixelReporter.measureScreenImpression(event: .daxDialogsFireEducationShownUnique)
                }
            },
            onManualDismiss: onManualDismiss
        )
        .onAppear { [weak delegate] in
            delegate?.didShowContextualOnboardingTrackersDialog()
        }
        .onFirstAppear { [weak self] in
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: spec.pixelName)
        }
    }

    private func fireDialog(
        delegate: ContextualOnboardingDelegate,
        pixelName: Pixel.Event
    ) -> some View {
        let onManualDismiss: () -> Void = { [weak delegate, weak self] in
            self?.contextualOnboardingPixelReporter.measureFireDialogDismissButtonTapped()
            delegate?.didTapDismissContextualOnboardingAction()
        }

        return OnboardingFireDialog(onManualDismiss: onManualDismiss)
            .onFirstAppear { [weak self] in
                self?.contextualOnboardingPixelReporter.measureScreenImpression(event: pixelName)
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
        }
    }

}

// MARK: - Contextual Onboarding Settings

protocol ContextualOnboardingSettings {
    var userHasSeenTrackersDialog: Bool { get }
    var userHasSeenFireDialog: Bool { get }
    var userHasSeenTryVisitSiteDialog: Bool { get }
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
