//
//  RebrandedContextualDaxDialogFactory.swift
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
import Core
import Onboarding

final class RebrandedContextualDaxDialogFactory: ContextualDaxDialogsFactory {
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

        let hostingController = UIHostingController(rootView: rootView)
        if #available(iOS 16.0, *) {
            hostingController.sizingOptions = [.intrinsicContentSize]
        }

        return hostingController
    }

}

// MARK: - Anonymous Search Completed

private extension RebrandedContextualDaxDialogFactory {

    func afterSearchDialog(
        shouldFollowUpToWebsiteSearch: Bool,
        delegate: ContextualOnboardingDelegate,
        afterSearchPixelEvent: Pixel.Event,
        onSizeUpdate: @escaping () -> Void
    ) -> some View {

        let viewModel = OnboardingSiteSuggestionsViewModel(title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle, suggestedSitesProvider: contextualOnboardingSiteSuggestionsProvider, delegate: delegate)

        // If should not show websites search after searching inform the delegate that the user dismissed the dialog, otherwise let the dialog handle it.
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

        return OnboardingConditionalCenteredScrollableContainerView {
            OnboardingRebranding.OnboardingSearchDoneDialog(
                shouldFollowUp: shouldFollowUpToWebsiteSearch,
                viewModel: viewModel,
                gotItAction: gotItAction,
                onManualDismiss: onManualDismiss
            )
        }
        .applyAnimatedContextualOnboardingBackground(backgroundType: .tryASearchCompleted)
        .onFirstAppear { [weak self] in
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: afterSearchPixelEvent)
        }
    }

}

// MARK: - Try Visiting Site

private extension RebrandedContextualDaxDialogFactory {

    // This could be removed. Originally this was in place to represent the dialog if the user refreshed or quit and relaunched the app.
    func tryVisitingSiteDialog(delegate: ContextualOnboardingDelegate) -> some View {
        let viewModel = OnboardingSiteSuggestionsViewModel(
            title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle,
            suggestedSitesProvider: contextualOnboardingSiteSuggestionsProvider,
            delegate: delegate
        )

        let onManualDismiss: () -> Void = { [weak delegate, weak self] in
            self?.contextualOnboardingPixelReporter.measureTryVisitSiteDialogDismissButtonTapped()
            delegate?.didTapDismissContextualOnboardingAction()
        }

        return OnboardingRebranding.OnboardingTrySiteDialog(
            viewModel: viewModel,
            onManualDismiss: onManualDismiss
        )
        .applyAnimatedContextualOnboardingBackground(backgroundType: .tryVisitingASiteNTP)
        .onFirstAppear { [weak self] in
            self?.contextualOnboardingLogic.setTryVisitSiteMessageSeen()
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: .onboardingContextualTryVisitSiteUnique)
        }
    }

}

// MARK: - Trackers Blocked

private extension RebrandedContextualDaxDialogFactory {

    func withTrackersDialog(
        for spec: DaxDialogs.BrowsingSpec,
        shouldFollowUpToFireDialog: Bool,
        delegate: ContextualOnboardingDelegate,
        onSizeUpdate: @escaping () -> Void
    ) -> some View {
        let attributedMessage = attributedStringFromLegacyMarkdown(spec.message)

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

        return OnboardingConditionalCenteredScrollableContainerView {
            OnboardingRebranding.OnboardingTrackersBlockedDialog(
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
        }
        .applyAnimatedContextualOnboardingBackground(backgroundType: .trackers)
        .onAppear { [weak delegate] in
            delegate?.didShowContextualOnboardingTrackersDialog()
        }
        .onFirstAppear { [weak self] in
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: spec.pixelName)
        }
    }

}

// MARK: - Fire

private extension RebrandedContextualDaxDialogFactory {

    func fireDialog(
        delegate: ContextualOnboardingDelegate,
        pixelName: Pixel.Event
    ) -> some View {
        let onManualDismiss: () -> Void = { [weak delegate, weak self] in
            self?.contextualOnboardingPixelReporter.measureFireDialogDismissButtonTapped()
            delegate?.didTapDismissContextualOnboardingAction()
        }

        return OnboardingConditionalCenteredScrollableContainerView {
            OnboardingRebranding.OnboardingFireDialog(onManualDismiss: onManualDismiss)
        }
        .applyAnimatedContextualOnboardingBackground(backgroundType: .fireDialog)
        .onFirstAppear { [weak self] in
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: pixelName)
        }
    }

}

// MARK: - End Of Journey (You've got This!)

private extension RebrandedContextualDaxDialogFactory {

    func endOfJourneyDialog(
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

        return OnboardingConditionalCenteredScrollableContainerView {
            OnboardingRebranding.OnboardingEndOfJourneyDialog(
                message: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenMessage,
                cta: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenButton,
                dismissAction: dismissAction,
                onManualDismiss: onManualDismiss
            )
        }
        .applyAnimatedContextualOnboardingBackground(backgroundType: .endOfJourney)
        .onFirstAppear { [weak self] in
            self?.contextualOnboardingLogic.setFinalOnboardingDialogSeen()
            self?.contextualOnboardingPixelReporter.measureScreenImpression(event: pixelName)
        }
    }

}

// MARK: - Helpers

private extension RebrandedContextualDaxDialogFactory {

    // Converts a string with single asterisks for bold (*text*) to an AttributedString using native markdown parsing.
    // Native markdown requires double asterisks for bold (**text**), so this helper converts the format.
    func attributedStringFromLegacyMarkdown(_ string: String) -> AttributedString {
        // Convert *text* to **text** for native markdown parsing using regex
        // Matches *text* but not escaped \* or already doubled **
        // - (?<!\*) - Negative lookbehind: ensure no * before
        // - \* - Match a single *
        // - (?!\*) - Negative lookahead: ensure no * after
        // - ([^\*]+) - Capture group: one or more non-asterisk characters
        // - \*(?!\*) - Match closing single * (not followed by another *)
        let markdown = string.replacingOccurrences(
            of: #"(?<!\*)\*(?!\*)([^\*]+)\*(?!\*)"#,
            with: "**$1**",
            options: .regularExpression
        )

        // Parse with native AttributedString markdown support
        do {
            return try AttributedString(
                markdown: markdown,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        } catch {
            // Fallback to plain text if parsing fails
            return AttributedString(string)
        }
    }
    
}
