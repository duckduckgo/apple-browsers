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
    /// Kept only for API compatibility with the existing dialog signatures —
    /// all panels now size themselves to their bubble content plus uniform vertical
    /// padding, so these values are no longer used as a layout floor.
    enum ContextualPanelMetrics {
        static let trySearchPanelHeight: CGFloat = 0
        static let searchDonePanelHeight: CGFloat = 0
        static let trySitePanelHeight: CGFloat = 0
        static let trackersPanelHeight: CGFloat = 0
        static let firePanelHeight: CGFloat = 0
        static let highFivePanelHeight: CGFloat = 0
    }

    private let onboardingPixelReporter: OnboardingPixelReporting
    private let fireCoordinator: FireCoordinator

    init(onboardingPixelReporter: OnboardingPixelReporting = OnboardingPixelReporter(), fireCoordinator: FireCoordinator) {
        self.onboardingPixelReporter = onboardingPixelReporter
        self.fireCoordinator = fireCoordinator
    }

    func makeView(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> AnyView {
        let bubble = makeBubbleView(for: type, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed, onInlineTransition: nil)

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
    /// `onInlineTransition` is invoked with the follow-up dialog type when a dialog performs
    /// an in-place content swap (e.g. searchDone → tryASite). The host uses this to swap the
    /// background illustration so it matches the displayed bubble content.
    func makeBubbleView(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void, onInlineTransition: ((ContextualDialogType) -> Void)?) -> AnyView {
        switch type {
        case .tryASearch:
            return AnyView(tryASearchDialog(delegate: delegate, onDismiss: onDismiss))
        case .searchDone(shouldFollowUp: let shouldFollowUp):
            return AnyView(searchDoneDialog(shouldFollowUp: shouldFollowUp, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onInlineTransition: onInlineTransition))
        case .tryASite:
            return AnyView(tryASiteDialog(delegate: delegate, onDismiss: onDismiss))
        case .trackers(message: let message, shouldFollowUp: let shouldFollowUp):
            return AnyView(trackersDialog(message: message, shouldFollowUp: shouldFollowUp, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed, onInlineTransition: onInlineTransition))
        case .tryFireButton:
            return AnyView(tryFireButtonDialog(onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed))
        case .highFive:
            onboardingPixelReporter.measureLastDialogShown()
            return AnyView(highFiveDialog(onDismiss: onDismiss, onGotItPressed: onGotItPressed))
        }
    }

    func makeLayeredViews(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void, onInlineTransition: ((ContextualDialogType) -> Void)?) -> LayeredDialogViews? {
        let bubble = makeBubbleView(for: type, delegate: delegate, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed, onInlineTransition: onInlineTransition)
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

    func makeBackgroundView(for type: ContextualDialogType) -> AnyView? {
        AnyView(
            Self.backgroundView(for: type)
                .applyOnboardingTheme(.macOSRebranding2026)
        )
    }

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

    private func searchDoneDialog(shouldFollowUp: Bool, delegate: OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onInlineTransition: ((ContextualDialogType) -> Void)?) -> some View {
        let suggestedSitesProvider = OnboardingSuggestedSitesProvider(surpriseItemTitle: OnboardingSuggestedSitesProvider.surpriseItemTitle)
        let viewModel = OnboardingSiteSuggestionsViewModel(title: "", suggestedSitesProvider: suggestedSitesProvider, delegate: delegate)
        let gotIt = shouldFollowUp ? onGotItPressed : onDismiss
        return OnboardingRebranding.OnboardingSearchDoneDialog(
            shouldFollowUp: shouldFollowUp,
            initialPanelHeight: ContextualPanelMetrics.searchDonePanelHeight,
            followUpPanelHeight: ContextualPanelMetrics.trySitePanelHeight,
            viewModel: viewModel,
            gotItAction: gotIt,
            onManualDismiss: onDismiss,
            onContentTransition: { onInlineTransition?(.tryASite) }
        )
    }

    private func tryASiteDialog(delegate: OnboardingNavigationDelegate, onDismiss: @escaping () -> Void) -> some View {
        let suggestedSitesProvider = OnboardingSuggestedSitesProvider(surpriseItemTitle: OnboardingSuggestedSitesProvider.surpriseItemTitle)
        let viewModel = OnboardingSiteSuggestionsViewModel(title: "", suggestedSitesProvider: suggestedSitesProvider, delegate: delegate)
        return OnboardingRebranding.OnboardingTrySiteDialog(viewModel: viewModel, onManualDismiss: onDismiss)
    }

    private func trackersDialog(message: NSAttributedString, shouldFollowUp: Bool, onDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void, onInlineTransition: ((ContextualDialogType) -> Void)?) -> some View {
        let gotIt = shouldFollowUp ? onGotItPressed : onDismiss
        let viewModel = OnboardingFireButtonDialogViewModel(onboardingPixelReporter: onboardingPixelReporter, fireCoordinator: fireCoordinator, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)
        return OnboardingRebranding.OnboardingTrackersBlockedDialog(
            shouldFollowUp: shouldFollowUp,
            initialPanelHeight: ContextualPanelMetrics.trackersPanelHeight,
            followUpPanelHeight: ContextualPanelMetrics.firePanelHeight,
            message: Self.collapseDoubleNewlines(message),
            blockedTrackersCTAAction: gotIt,
            viewModel: viewModel,
            onManualDismiss: onDismiss,
            onContentTransition: { onInlineTransition?(.tryFireButton) }
        )
    }

    /// The localized tracker copy uses `\n\n` to separate the main message from the shield hint,
    /// which renders as a large gap in the rebranded bubble. Collapse to a single newline and
    /// add a small paragraph spacing so the secondary line is visually distinct without the
    /// exaggerated blank line the double newline produces.
    private static func collapseDoubleNewlines(_ source: NSAttributedString) -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.mutableString.replaceOccurrences(of: "\n\n", with: "\n", range: fullRange)

        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 8
        mutable.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: mutable.length))
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
    /// Renders the bubble with consistent vertical padding, letting the panel size itself
    /// entirely from the bubble's intrinsic height. No floor — long text in any language
    /// grows the panel naturally. The `height` parameter is ignored.
    func contextualOnboardingPanelLayout(height: CGFloat) -> some View {
        HStack(spacing: 0) {
            Spacer()
            self
                .frame(maxWidth: 640)
            Spacer()
        }
        .padding(.top, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity)
    }
}
