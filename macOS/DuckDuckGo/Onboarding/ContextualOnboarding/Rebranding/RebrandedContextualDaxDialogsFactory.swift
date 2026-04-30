//
//  RebrandedContextualDaxDialogsFactory.swift
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

struct RebrandedContextualDaxDialogsFactory: ContextualDaxDialogsFactory {
    private enum TrySearchMetrics {
        static let panelHeight: CGFloat = 208
        static let illustrationOffsetY: CGFloat = 50
    }

    private let onboardingPixelReporter: OnboardingPixelReporting
    private let fireCoordinator: FireCoordinator

    init(onboardingPixelReporter: OnboardingPixelReporting = OnboardingPixelReporter(), fireCoordinator: FireCoordinator) {
        self.onboardingPixelReporter = onboardingPixelReporter
        self.fireCoordinator = fireCoordinator
    }

    func makeView(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void, onSuggestionPressed: @escaping () -> Void) -> AnyView {
        let dialogView: AnyView
        switch type {
        case .tryASearch:
            dialogView = AnyView(tryASearchDialog(delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onSuggestionPressed: onSuggestionPressed))
        case .searchDone(shouldFollowUp: let shouldFollowUp):
            dialogView = AnyView(searchDoneDialog(shouldFollowUp: shouldFollowUp, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onSuggestionPressed: onSuggestionPressed))
        case .tryASite:
            dialogView = AnyView(tryASiteDialog(delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onSuggestionPressed: onSuggestionPressed))
        case .trackers(message: let message, shouldFollowUp: let shouldFollowUp):
            dialogView = AnyView(trackersDialog(message: message, shouldFollowUp: shouldFollowUp, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed))
        case .tryFireButton:
            dialogView = AnyView(tryFireButtonDialog(onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed))
        case .highFive:
            dialogView = AnyView(highFiveDialog(onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed))
            onboardingPixelReporter.measureLastDialogShown()
        }
        onboardingPixelReporter.measureDialogShown(dialogType: type)

        let centeredView = HStack {
            Spacer()
            dialogView
                .frame(maxWidth: 640.0)
            Spacer()
        }

        let viewWithBackground: AnyView
        switch type {
        case .tryASearch:
            viewWithBackground = AnyView(
                ZStack(alignment: .bottomTrailing) {
                    OnboardingTheme.macOSRebranding2026.colorPalette.background

                    OnboardingRebrandingImages.Contextual.tryASearchBackground
                        .offset(y: TrySearchMetrics.illustrationOffsetY)

                    centeredView
                        .padding(.horizontal)
                        .frame(maxHeight: .infinity)
                }
                .frame(height: TrySearchMetrics.panelHeight)
                .clipped()
                .applyOnboardingTheme(.macOSRebranding2026)
            )
        default:
            viewWithBackground = AnyView(
                centeredView
                    .padding()
                    .background(OnboardingGradient())
                    .applyOnboardingTheme(.macOSRebranding2026)
            )
        }

        #if DEBUG
        return AnyView(
            viewWithBackground.overlay(
                Text(verbatim: "REBRANDED")
                    .font(.caption2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .cornerRadius(4)
                    .padding(8),
                alignment: .topTrailing
            )
        )
        #else
        return AnyView(viewWithBackground)
        #endif
    }

    // MARK: - Private Dialog Builders

    private func tryASearchDialog(delegate: OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onSuggestionPressed: @escaping () -> Void) -> some View {
        let suggestedSearchesProvider = OnboardingSuggestedSearchesProvider()
        let viewModel = OnboardingSearchSuggestionsViewModel(suggestedSearchesProvider: suggestedSearchesProvider, delegate: delegate, onSuggestionPressed: onSuggestionPressed)
        return OnboardingRebranding.OnboardingTrySearchDialog(viewModel: viewModel, onManualDismiss: onManualDismiss)
    }

    private func searchDoneDialog(shouldFollowUp: Bool, delegate: OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onSuggestionPressed: @escaping () -> Void) -> some View {
        let suggestedSitesProvider = OnboardingSuggestedSitesProvider(surpriseItemTitle: OnboardingSuggestedSitesProvider.surpriseItemTitle)
        let viewModel = OnboardingSiteSuggestionsViewModel(title: "", suggestedSitesProvider: suggestedSitesProvider, delegate: delegate, onSuggestionPressed: onSuggestionPressed)
        let onDismissGotIt = {
            onboardingPixelReporter.measureGotItPressed(dialogType: .searchDone(shouldFollowUp: shouldFollowUp))
            onDismiss()
        }
        let gotIt = shouldFollowUp ? onGotItPressed : onDismissGotIt
        return OnboardingRebranding.OnboardingSearchDoneDialog(shouldFollowUp: shouldFollowUp, viewModel: viewModel, gotItAction: gotIt, onManualDismiss: onManualDismiss)
    }

    private func tryASiteDialog(delegate: OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onSuggestionPressed: @escaping () -> Void) -> some View {
        let suggestedSitesProvider = OnboardingSuggestedSitesProvider(surpriseItemTitle: OnboardingSuggestedSitesProvider.surpriseItemTitle)
        let viewModel = OnboardingSiteSuggestionsViewModel(title: "", suggestedSitesProvider: suggestedSitesProvider, delegate: delegate, onSuggestionPressed: onSuggestionPressed)
        return OnboardingRebranding.OnboardingTrySiteDialog(viewModel: viewModel, onManualDismiss: onManualDismiss)
    }

    private func trackersDialog(message: NSAttributedString, shouldFollowUp: Bool, onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> some View {
        let onDismissGotIt = {
            onboardingPixelReporter.measureGotItPressed(dialogType: .trackers(message: message, shouldFollowUp: shouldFollowUp))
            onDismiss()
        }
        let gotIt = shouldFollowUp ? onGotItPressed : onDismissGotIt
        let viewModel = OnboardingFireButtonDialogViewModel(onboardingPixelReporter: onboardingPixelReporter, fireCoordinator: fireCoordinator, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)
        return OnboardingRebranding.OnboardingTrackersBlockedDialog(shouldFollowUp: true, message: message, blockedTrackersCTAAction: gotIt, viewModel: viewModel, onManualDismiss: onManualDismiss)
    }

    private func tryFireButtonDialog(onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> some View {
        let viewModel = OnboardingFireButtonDialogViewModel(onboardingPixelReporter: onboardingPixelReporter, fireCoordinator: fireCoordinator, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)
        return OnboardingRebranding.OnboardingFireDialog(viewModel: viewModel, onManualDismiss: onManualDismiss)
    }

    private func highFiveDialog(onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void) -> some View {
        let action = {
            onDismiss()
            onGotItPressed()
        }
        return OnboardingRebranding.OnboardingEndOfJourneyDialog(highFiveAction: action, onManualDismiss: onManualDismiss)
    }
}
