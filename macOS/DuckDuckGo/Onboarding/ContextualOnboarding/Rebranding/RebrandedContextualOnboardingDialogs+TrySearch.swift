//
//  RebrandedContextualOnboardingDialogs+TrySearch.swift
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
import Onboarding
import Lottie

// MARK: - Try Anonymous Search

extension OnboardingRebranding {

    struct OnboardingTrySearchDialog: View {
        /// Layout values unique to the tryASearch dialog. Shared metrics (bubble width,
        /// arrow dimensions, paddings, Dax frame) live on `OnboardingRebranding.Layout`.
        private enum Layout {
            /// Bubble tail anchor along the leading edge. Near 1.0 so the tail sits close to the
            /// top, pointing up-left toward the waving Dax overlay.
            static let tailOffset: CGFloat = 0.99
        }

        let title = NSAttributedString(string: UserText.ContextualOnboarding.onboardingTryASearchTitle)
        let message = NSAttributedString(string: UserText.ContextualOnboarding.onboardingTryASearchMessage)
        let viewModel: OnboardingSearchSuggestionsViewModel
        let onManualDismiss: () -> Void

        var body: some View {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                OnboardingBubbleView(
                    tailPosition: .leading(offset: Layout.tailOffset, direction: .top),
                    arrowLength: OnboardingRebranding.Layout.bubbleArrowLength,
                    arrowWidth: OnboardingRebranding.Layout.bubbleArrowWidth,
                    content: {
                        OnboardingRebranding.ContextualDaxDialogContent(
                            orientation: .horizontalStack(alignment: .top),
                            title: title,
                            message: message
                        ) {
                            OnboardingRebranding.ContextualOnboardingListView(
                                list: viewModel.itemsList,
                                action: viewModel.listItemPressed
                            )
                        }
                    }
                )
                .onboardingDismissable(onManualDismiss)
                .frame(maxWidth: OnboardingRebranding.Layout.bubbleMaxWidth)
                .overlay(
                    DaxWavingAnimation()
                        .frame(
                            width: OnboardingRebranding.Layout.DaxWaving.width,
                            height: OnboardingRebranding.Layout.DaxWaving.height
                        )
                        .clipped()
                        .offset(
                            x: OnboardingRebranding.Layout.DaxWaving.offsetX,
                            y: OnboardingRebranding.Layout.DaxWaving.offsetY
                        )
                        .allowsHitTesting(false),
                    alignment: .topLeading
                )
                Spacer(minLength: 0)
            }
            .padding(.top, OnboardingRebranding.Layout.panelTopPadding)
            .padding(.bottom, OnboardingRebranding.Layout.panelBottomPadding)
            .frame(maxWidth: .infinity)
        }
    }

}

// MARK: - Dax Waving Lottie

/// Waving-Dax Lottie shared by the tryASearch, tryASite, and highFive dialogs. Plays once
/// on appear and holds on the final frame. Swapped for the correct light/dark asset when
/// the effective appearance changes.
struct DaxWavingAnimation: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        // Lottie draws outside its bounds by default; clip so it honors the SwiftUI frame.
        container.layer?.masksToBounds = true
        attachAnimation(to: container, for: colorScheme)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.subviews.forEach { $0.removeFromSuperview() }
        attachAnimation(to: nsView, for: colorScheme)
    }

    private func attachAnimation(to container: NSView, for colorScheme: ColorScheme) {
        let assetName = colorScheme == .dark ? "dax-waving-dark" : "dax-waving-light"
        guard let animation = LottieAnimation.asset(assetName, bundle: .main) else {
            return
        }
        let view = LottieAnimationView(animation: animation)
        view.contentMode = .scaleAspectFit
        view.loopMode = .playOnce
        view.animationSpeed = 1.0
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        // Use autoresizing instead of constraints — LottieAnimationView's intrinsic content size
        // reflects the animation canvas (557×659 here) and fights the SwiftUI frame.
        view.autoresizingMask = [.width, .height]
        view.frame = container.bounds
        container.addSubview(view)
        view.play()
    }
}
