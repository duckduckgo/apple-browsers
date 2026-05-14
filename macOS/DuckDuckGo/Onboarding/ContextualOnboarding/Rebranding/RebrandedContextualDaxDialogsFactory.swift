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

// MARK: - Shared Layout

extension OnboardingRebranding {
    /// Layout metrics shared across every rebranded contextual onboarding dialog. Values unique
    /// to a single dialog live in that dialog's private `Layout` struct at the top of its file,
    /// so per-screen tweaks stay local.
    enum Layout {
        /// Maximum bubble width before the dialog stops growing horizontally.
        static let bubbleMaxWidth: CGFloat = 640
        /// Uniform vertical padding applied to every panel that wraps a bubble.
        static let panelTopPadding: CGFloat = 24
        static let panelBottomPadding: CGFloat = 32
        /// Bubble tail (arrow) dimensions used by every dialog that shows a tail.
        static let bubbleArrowLength: CGFloat = 28
        static let bubbleArrowWidth: CGFloat = 44
        /// Duration for in-place content transitions (searchDone→tryASite, trackers→fire).
        static let inlineTransitionDuration: Double = 0.3
        /// Duration of a single fade phase (out or in) when swapping layered bubble/background.
        /// Fade-out and fade-in run back-to-back so the whole swap takes 2× this value.
        static let screenTransitionPhaseDuration: Double = 0.2

        /// Waving-Dax overlay metrics — shared by the tryASearch, tryASite, and highFive dialogs.
        /// The offset places Dax to the left of the bubble and slightly above its top edge.
        enum DaxWaving {
            static let width: CGFloat = 130
            static let height: CGFloat = 154
            static let offsetX: CGFloat = -130
            static let offsetY: CGFloat = -21
        }

        /// Bottom-edge shadow applied to the panel background for subtle depth.
        enum PanelShadow {
            static let opacity: Double = 0.06
            static let height: CGFloat = 8
        }

        /// 1px hairline rule along the bottom of the panel to separate it from content below.
        enum PanelBorder {
            static let height: CGFloat = 1
            static let lightColor = Color(red: 0.85, green: 0.85, blue: 0.85)
            static let darkColor = Color(red: 0.25, green: 0.25, blue: 0.25)
        }
    }
}

/// 1px hairline rule applied along the bottom edge of the panel background.
/// Uses `Color`s switched by `colorScheme` because `Color(nsColor:)` with a
/// dynamic provider requires macOS 12+ and can't be stored in a `static let`.
private struct PanelBottomBorder: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        (colorScheme == .dark
            ? OnboardingRebranding.Layout.PanelBorder.darkColor
            : OnboardingRebranding.Layout.PanelBorder.lightColor)
            .frame(height: OnboardingRebranding.Layout.PanelBorder.height)
    }
}

struct RebrandedContextualDaxDialogsFactory: ContextualDaxDialogsFactory {

    private let onboardingPixelReporter: OnboardingPixelReporting
    private let fireCoordinator: FireCoordinator

    init(onboardingPixelReporter: OnboardingPixelReporting = OnboardingPixelReporter(), fireCoordinator: FireCoordinator) {
        self.onboardingPixelReporter = onboardingPixelReporter
        self.fireCoordinator = fireCoordinator
    }

    func makeView(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void, onSuggestionPressed: @escaping () -> Void) -> AnyView {
        AnyView(
            ContextualDialogView(
                type: type,
                delegate: delegate,
                onDismiss: onDismiss,
                onManualDismiss: onManualDismiss,
                onGotItPressed: onGotItPressed,
                onFireButtonPressed: onFireButtonPressed,
                onSuggestionPressed: onSuggestionPressed,
                factory: self
            )
        )
    }

    fileprivate func makeBubbleView(for type: ContextualDialogType, delegate: any OnboardingNavigationDelegate, onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void, onSuggestionPressed: @escaping () -> Void) -> AnyView {
        switch type {
        case .tryASearch:
            return AnyView(tryASearchDialog(delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onSuggestionPressed: onSuggestionPressed))
        case .searchDone(shouldFollowUp: let shouldFollowUp):
            return AnyView(searchDoneDialog(shouldFollowUp: shouldFollowUp, delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onSuggestionPressed: onSuggestionPressed))
        case .tryASite:
            return AnyView(tryASiteDialog(delegate: delegate, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onSuggestionPressed: onSuggestionPressed))
        case .trackers(message: let message, shouldFollowUp: let shouldFollowUp):
            return AnyView(trackersDialog(message: message, shouldFollowUp: shouldFollowUp, onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed))
        case .tryFireButton:
            return AnyView(tryFireButtonDialog(onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed))
        case .highFive:
            onboardingPixelReporter.measureLastDialogShown()
            return AnyView(highFiveDialog(onDismiss: onDismiss, onManualDismiss: onManualDismiss, onGotItPressed: onGotItPressed))
        }
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
        // Bottom-edge shadow that separates the panel from the content below it. Applied as
        // an overlay so it doesn't alter the layout of the background ZStack.
        .overlay(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.black.opacity(OnboardingRebranding.Layout.PanelShadow.opacity),
                    Color.black.opacity(0)
                ]),
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: OnboardingRebranding.Layout.PanelShadow.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
        )
        .overlay(
            PanelBottomBorder()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)
        )
    }

    /// macOS illustrations from the app's asset catalog (iPad ships its own via the shared
    /// Onboarding package).
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
        return OnboardingRebranding.OnboardingSearchDoneDialog(
            shouldFollowUp: shouldFollowUp,
            viewModel: viewModel,
            gotItAction: gotIt,
            onManualDismiss: onManualDismiss,
            onContentTransition: nil
        )
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
        return OnboardingRebranding.OnboardingTrackersBlockedDialog(
            shouldFollowUp: true,
            message: message,
            blockedTrackersCTAAction: gotIt,
            viewModel: viewModel,
            onManualDismiss: onManualDismiss,
            onContentTransition: nil
        )
    }

    private func tryFireButtonDialog(onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void, onFireButtonPressed: @escaping () -> Void) -> some View {
        let viewModel = OnboardingFireButtonDialogViewModel(onboardingPixelReporter: onboardingPixelReporter, fireCoordinator: fireCoordinator, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)
        return OnboardingRebranding.OnboardingFireDialog(viewModel: viewModel, onManualDismiss: onManualDismiss, onContentTransition: nil)
    }

    private func highFiveDialog(onDismiss: @escaping () -> Void, onManualDismiss: @escaping () -> Void, onGotItPressed: @escaping () -> Void) -> some View {
        let action = {
            onDismiss()
            onGotItPressed()
        }
        return OnboardingRebranding.OnboardingEndOfJourneyDialog(highFiveAction: action, onManualDismiss: onManualDismiss)
    }
}

// MARK: - Animated Dialog Wrapper

private struct ContextualDialogView: View {
    @State private var opacity: Double = 0
    @State private var isDismissing = false

    let type: ContextualDialogType
    let delegate: any OnboardingNavigationDelegate
    let onDismiss: () -> Void
    let onManualDismiss: () -> Void
    let onGotItPressed: () -> Void
    let onFireButtonPressed: () -> Void
    let onSuggestionPressed: () -> Void
    let factory: RebrandedContextualDaxDialogsFactory

    private let duration = OnboardingRebranding.Layout.screenTransitionPhaseDuration

    var body: some View {
        factory.makeBubbleView(
            for: type,
            delegate: delegate,
            onDismiss: { fade(then: onDismiss) },
            onManualDismiss: { fade(then: onManualDismiss) },
            onGotItPressed: onGotItPressed,
            onFireButtonPressed: onFireButtonPressed,
            onSuggestionPressed: onSuggestionPressed
        )
        .background(RebrandedContextualDaxDialogsFactory.backgroundView(for: type))
        .clipped()
        .applyOnboardingTheme(.macOSRebranding2026)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: duration)) { opacity = 1 }
        }
    }

    private func fade(then action: @escaping () -> Void) {
        guard !isDismissing else { return }
        isDismissing = true
        withAnimation(.easeOut(duration: duration)) { opacity = 0 }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            action()
        }
    }
}

// MARK: - Panel Layout Modifier

extension View {
    /// Renders the bubble with consistent vertical padding, letting the panel size itself
    /// entirely from the bubble's intrinsic height. No floor — long text in any language
    /// grows the panel naturally.
    func contextualOnboardingPanelLayout() -> some View {
        HStack(spacing: 0) {
            Spacer()
            self
                .frame(maxWidth: OnboardingRebranding.Layout.bubbleMaxWidth)
            Spacer()
        }
        .padding(.top, OnboardingRebranding.Layout.panelTopPadding)
        .padding(.bottom, OnboardingRebranding.Layout.panelBottomPadding)
        .frame(maxWidth: .infinity)
    }
}
