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
    private enum ContextualPanelMetrics {
        static let trySearchPanelHeight: CGFloat = 200
        static let trySearchIllustrationOffsetY: CGFloat = 96
        static let searchDonePanelHeight: CGFloat = 140
        static let searchDoneIllustrationOffsetY: CGFloat = -40
        static let trySitePanelHeight: CGFloat = 240
        static let trySiteIllustrationOffsetY: CGFloat = 40
        static let trackersPanelHeight: CGFloat = 170
        static let trackersIllustrationOffsetY: CGFloat = 0
        static let firePanelHeight: CGFloat = 170
        static let highFivePanelHeight: CGFloat = 170
        static let highFiveIllustrationOffsetY: CGFloat = 0
    }

    private let onboardingPixelReporter: OnboardingPixelReporting
    private let fireCoordinator: FireCoordinator

    init(onboardingPixelReporter: OnboardingPixelReporting = OnboardingPixelReporter(), fireCoordinator: FireCoordinator) {
        self.onboardingPixelReporter = onboardingPixelReporter
        self.fireCoordinator = fireCoordinator
    }

    func makeView(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> AnyView {
        let dialogView: AnyView
        switch type {
        case .tryASearch:
            dialogView = AnyView(tryASearchDialog(delegate: delegate, onDismiss: onDismiss))
        case .searchDone(shouldFollowUp: let shouldFollowUp):
            dialogView = AnyView(searchDoneDialog(shouldFollowUp: shouldFollowUp, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed))
        case .tryASite:
            dialogView = AnyView(tryASiteDialog(delegate: delegate, onDismiss: onDismiss))
        case .trackers(message: let message, shouldFollowUp: let shouldFollowUp):
            dialogView = AnyView(trackersDialog(message: message, shouldFollowUp: shouldFollowUp, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed))
        case .tryFireButton:
            dialogView = AnyView(tryFireButtonDialog(onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed))
        case .highFive:
            dialogView = AnyView(highFiveDialog(onDismiss: onDismiss, onGotItPressed: onGotItPressed))
            onboardingPixelReporter.measureLastDialogShown()
        }

        let centeredView = HStack {
            Spacer()
            dialogView
                .frame(maxWidth: 640.0)
            Spacer()
        }
        .padding(.top, 16)
        .padding(.bottom, 24)

        let viewWithBackground: AnyView
        switch type {
        case .tryASearch:
            viewWithBackground = AnyView(
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .bottomTrailing) {
                        OnboardingTheme.macOSRebranding2026.colorPalette.background
                        OnboardingRebrandingImages.Contextual.tryASearchBackground
                            .offset(y: ContextualPanelMetrics.trySearchIllustrationOffsetY)
                    }
                    .frame(height: ContextualPanelMetrics.trySearchPanelHeight)
                    centeredView
                }
                .frame(height: ContextualPanelMetrics.trySearchPanelHeight)
                .clipped()
                .applyOnboardingTheme(.macOSRebranding2026)
            )
        case .searchDone:
            viewWithBackground = AnyView(
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .bottomTrailing) {
                        OnboardingTheme.macOSRebranding2026.colorPalette.background
                        OnboardingRebrandingImages.Contextual.searchDoneBackground
                            .offset(y: ContextualPanelMetrics.searchDoneIllustrationOffsetY)
                    }
                    centeredView
                }
                .clipped()
                .applyOnboardingTheme(.macOSRebranding2026)
            )
        case .tryASite:
            viewWithBackground = AnyView(
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .bottomTrailing) {
                        OnboardingTheme.macOSRebranding2026.colorPalette.background
                        OnboardingRebrandingImages.Contextual.tryASiteBackground
                            .offset(y: ContextualPanelMetrics.trySiteIllustrationOffsetY)
                    }
                    .frame(height: ContextualPanelMetrics.trySitePanelHeight)
                    centeredView
                }
                .frame(height: ContextualPanelMetrics.trySitePanelHeight)
                .clipped()
                .applyOnboardingTheme(.macOSRebranding2026)
            )
        case .trackers:
            viewWithBackground = AnyView(
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .bottomTrailing) {
                        OnboardingTheme.macOSRebranding2026.colorPalette.background
                        OnboardingRebrandingImages.Contextual.trackerBlockedBackground
                            .offset(y: ContextualPanelMetrics.trackersIllustrationOffsetY)
                    }
                    centeredView
                }
                .clipped()
                .applyOnboardingTheme(.macOSRebranding2026)
            )
        case .tryFireButton:
            viewWithBackground = AnyView(
                ZStack(alignment: .topLeading) {
                    OnboardingGradient()
                    centeredView
                }
                .clipped()
                .applyOnboardingTheme(.macOSRebranding2026)
            )
        case .highFive:
            viewWithBackground = AnyView(
                ZStack(alignment: .topLeading) {
                    ZStack(alignment: .bottomTrailing) {
                        OnboardingTheme.macOSRebranding2026.colorPalette.background
                        OnboardingRebrandingImages.Contextual.endOfJourneyBackground
                            .offset(y: ContextualPanelMetrics.highFiveIllustrationOffsetY)
                    }
                    .frame(height: ContextualPanelMetrics.highFivePanelHeight)
                    centeredView
                }
                .frame(height: ContextualPanelMetrics.highFivePanelHeight)
                .clipped()
                .applyOnboardingTheme(.macOSRebranding2026)
            )
        }

        #if DEBUG
        return AnyView(
            viewWithBackground.overlay(
                Text("REBRANDED")
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

    private func tryASearchDialog(delegate: OnboardingNavigationDelegate, onDismiss: @escaping () -> Void) -> some View {
        let suggestedSearchesProvider = OnboardingSuggestedSearchesProvider()
        let viewModel = OnboardingSearchSuggestionsViewModel(suggestedSearchesProvider: suggestedSearchesProvider, delegate: delegate)
        return OnboardingRebranding.OnboardingTrySearchDialog(viewModel: viewModel, onManualDismiss: onDismiss)
    }

    private func searchDoneDialog(shouldFollowUp: Bool, delegate: OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void) -> some View {
        let suggestedSitesProvider = OnboardingSuggestedSitesProvider(surpriseItemTitle: OnboardingSuggestedSitesProvider.surpriseItemTitle)
        let viewModel = OnboardingSiteSuggestionsViewModel(title: "", suggestedSitesProvider: suggestedSitesProvider, delegate: delegate)
        let gotIt = shouldFollowUp ? onGotItPressed : onDismiss
        return OnboardingRebranding.OnboardingSearchDoneDialog(
            shouldFollowUp: shouldFollowUp,
            initialPanelHeight: ContextualPanelMetrics.searchDonePanelHeight,
            followUpPanelHeight: ContextualPanelMetrics.trySitePanelHeight,
            viewModel: viewModel,
            gotItAction: gotIt,
            onManualDismiss: onDismiss
        )
    }

    private func tryASiteDialog(delegate: OnboardingNavigationDelegate, onDismiss: @escaping () -> Void) -> some View {
        let suggestedSitesProvider = OnboardingSuggestedSitesProvider(surpriseItemTitle: OnboardingSuggestedSitesProvider.surpriseItemTitle)
        let viewModel = OnboardingSiteSuggestionsViewModel(title: "", suggestedSitesProvider: suggestedSitesProvider, delegate: delegate)
        return OnboardingRebranding.OnboardingTrySiteDialog(viewModel: viewModel, onManualDismiss: onDismiss)
    }

    private func trackersDialog(message: NSAttributedString, shouldFollowUp: Bool, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> some View {
        let gotIt = shouldFollowUp ? onGotItPressed : onDismiss
        let viewModel = OnboardingFireButtonDialogViewModel(onboardingPixelReporter: onboardingPixelReporter, fireCoordinator: fireCoordinator, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)
        return OnboardingRebranding.OnboardingTrackersBlockedDialog(
            shouldFollowUp: shouldFollowUp,
            initialPanelHeight: ContextualPanelMetrics.trackersPanelHeight,
            followUpPanelHeight: ContextualPanelMetrics.firePanelHeight,
            message: message,
            blockedTrackersCTAAction: gotIt,
            viewModel: viewModel,
            onManualDismiss: onDismiss
        )
    }

    private func tryFireButtonDialog(onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> some View {
        let viewModel = OnboardingFireButtonDialogViewModel(onboardingPixelReporter: onboardingPixelReporter, fireCoordinator: fireCoordinator, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)
        return OnboardingRebranding.OnboardingFireDialog(
            viewModel: viewModel,
            initialPanelHeight: ContextualPanelMetrics.firePanelHeight,
            followUpPanelHeight: ContextualPanelMetrics.highFivePanelHeight,
            onManualDismiss: onDismiss
        )
    }

    private func highFiveDialog(onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void) -> some View {
        let action = {
            onDismiss()
            onGotItPressed()
        }
        return OnboardingRebranding.OnboardingEndOfJourneyDialog(highFiveAction: action, onManualDismiss: onDismiss)
    }
}
