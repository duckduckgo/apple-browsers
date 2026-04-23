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
    /// Panel heights sized to fit each dialog's bubble content.
    /// The illustration is pinned to the bottom at its natural size and can overlap
    /// the bubble visually.
    enum ContextualPanelMetrics {
        static let trySearchPanelHeight: CGFloat = 180
        static let searchDonePanelHeight: CGFloat = 150
        static let trySitePanelHeight: CGFloat = 240
        static let trackersPanelHeight: CGFloat = 150
        static let firePanelHeight: CGFloat = 140
        static let highFivePanelHeight: CGFloat = 150
    }

    private let onboardingPixelReporter: OnboardingPixelReporting
    private let fireCoordinator: FireCoordinator

    init(onboardingPixelReporter: OnboardingPixelReporting = OnboardingPixelReporter(), fireCoordinator: FireCoordinator) {
        self.onboardingPixelReporter = onboardingPixelReporter
        self.fireCoordinator = fireCoordinator
    }

    func makeView(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> AnyView {
        let bubble = makeBubbleView(for: type, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)

        let viewWithBackground = AnyView(
            bubble
                .background(Self.backgroundView(for: type))
                .clipped()
                .applyOnboardingTheme(.macOSRebranding2026)
        )

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
        return viewWithBackground
        #endif
    }

    /// Returns just the bubble view (no background) for layered composition.
    func makeBubbleView(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> AnyView {
        switch type {
        case .tryASearch:
            return AnyView(tryASearchDialog(delegate: delegate, onDismiss: onDismiss))
        case .searchDone(shouldFollowUp: let shouldFollowUp):
            return AnyView(searchDoneDialog(shouldFollowUp: shouldFollowUp, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed))
        case .tryASite:
            return AnyView(tryASiteDialog(delegate: delegate, onDismiss: onDismiss))
        case .trackers(message: let message, shouldFollowUp: let shouldFollowUp):
            return AnyView(trackersDialog(message: message, shouldFollowUp: shouldFollowUp, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed))
        case .tryFireButton:
            return AnyView(tryFireButtonDialog(onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed))
        case .highFive:
            onboardingPixelReporter.measureLastDialogShown()
            return AnyView(highFiveDialog(onDismiss: onDismiss, onGotItPressed: onGotItPressed))
        }
    }

    func makeLayeredViews(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> LayeredDialogViews? {
        let bubble = makeBubbleView(for: type, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)
        let themedBubble = AnyView(bubble.applyOnboardingTheme(.macOSRebranding2026))
        let themedBackground = AnyView(
            Self.backgroundView(for: type)
                .applyOnboardingTheme(.macOSRebranding2026)
        )

        #if DEBUG
        let debugBubble = AnyView(
            themedBubble.overlay(
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
        return LayeredDialogViews(bubble: debugBubble, background: themedBackground)
        #else
        return LayeredDialogViews(bubble: themedBubble, background: themedBackground)
        #endif
    }

    // MARK: - Background

    static func backgroundView(for type: ContextualDialogType) -> AnyView {
        AnyView(
            background(for: type)
                .clipped()
        )
    }

    @ViewBuilder
    private static func background(for type: ContextualDialogType) -> some View {
        ZStack(alignment: .bottomTrailing) {
            OnboardingTheme.macOSRebranding2026.colorPalette.background
            illustration(for: type)
        }
    }

    /// macOS-only illustrations loaded from the app's asset catalog
    /// (`macOS/DuckDuckGo/Assets.xcassets/OnboardingContextual/`).
    /// iPad uses the shared Onboarding package, so those assets are untouched.
    private static func illustration(for type: ContextualDialogType) -> Image {
        switch type {
        case .tryASearch:
            return Image("contextual-bg-try-search")
        case .searchDone:
            return Image("contextual-bg-search-done")
        case .tryASite:
            return Image("contextual-bg-try-site")
        case .trackers:
            return Image("contextual-bg-trackers")
        case .tryFireButton:
            return Image("contextual-bg-fire")
        case .highFive:
            return Image("contextual-bg-end-of-journey")
        }
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
            message: Self.collapseDoubleNewlines(message),
            blockedTrackersCTAAction: gotIt,
            viewModel: viewModel,
            onManualDismiss: onDismiss
        )
    }

    /// The localized tracker copy uses `\n\n` to separate the main message from the shield hint,
    /// which renders as a large gap in the rebranded bubble. Collapse to a single newline so
    /// the secondary line sits directly below the message.
    private static func collapseDoubleNewlines(_ source: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.mutableString.replaceOccurrences(of: "\n\n", with: "\n", range: fullRange)
        return mutable
    }

    private func tryFireButtonDialog(onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> some View {
        let viewModel = OnboardingFireButtonDialogViewModel(onboardingPixelReporter: onboardingPixelReporter, fireCoordinator: fireCoordinator, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)
        return OnboardingRebranding.OnboardingFireDialog(
            viewModel: viewModel,
            panelHeight: ContextualPanelMetrics.firePanelHeight,
            onManualDismiss: onDismiss
        )
    }

    private func highFiveDialog(onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void) -> some View {
        let action = {
            onDismiss()
            onGotItPressed()
        }
        return OnboardingRebranding.OnboardingEndOfJourneyDialog(
            panelHeight: ContextualPanelMetrics.highFivePanelHeight,
            highFiveAction: action,
            onManualDismiss: onDismiss
        )
    }
}

// MARK: - Panel Layout Modifier

extension View {
    func contextualOnboardingPanelLayout(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                self
                    .frame(maxWidth: 640)
                Spacer()
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}
