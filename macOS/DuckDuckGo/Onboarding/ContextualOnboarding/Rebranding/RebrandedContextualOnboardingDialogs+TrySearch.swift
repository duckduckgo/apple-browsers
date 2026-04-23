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
        let title = NSAttributedString(string: UserText.ContextualOnboarding.onboardingTryASearchTitle)
        let message = NSAttributedString(string: UserText.ContextualOnboarding.onboardingTryASearchMessage)
        let viewModel: OnboardingSearchSuggestionsViewModel
        let onManualDismiss: () -> Void

        var body: some View {
            // First dialog pairs the bubble with the waving Dax animation on the left, with
            // Dax overlapping the bubble's bounding box (circle partly on top of the bubble's
            // tail side). We use ZStack-style `.overlay` so the duck can render outside the
            // bubble's frame without affecting its layout or width.
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                OnboardingBubbleView(
                    tailPosition: .leading(offset: 0.99, direction: .top),
                    arrowLength: 14,
                    arrowWidth: 22,
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
                .frame(maxWidth: 640)
                // Use legacy overlay API (macOS 11 compatible) — older signature takes the
                // content first and an alignment parameter. Dax sits on top of the bubble's
                // top-left area, with its spotlight circle top aligned to the bubble top.
                .overlay(
                    DaxWavingAnimation()
                        .frame(width: 130, height: 154)
                        .clipped()
                        .offset(x: -130, y: -21)
                        .allowsHitTesting(false),
                    alignment: .topLeading
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity)
        }
    }

}

// MARK: - Dax Waving Lottie

/// Waving-Dax Lottie loaded from the app's asset catalog as an `NSDataAsset`, so adding the
/// JSON didn't require touching the Xcode project file. Plays once on appear and holds on the
/// final frame.
private struct DaxWavingAnimation: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        // Lottie draws outside its bounds by default; clip so the animation honors the
        // SwiftUI .frame we give it rather than spilling over the bubble.
        container.layer?.masksToBounds = true
        attachAnimation(to: container, for: colorScheme)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Swap the animation if the user switches appearance while the dialog is visible.
        nsView.subviews.forEach { $0.removeFromSuperview() }
        attachAnimation(to: nsView, for: colorScheme)
    }

    private func attachAnimation(to container: NSView, for colorScheme: ColorScheme) {
        let assetName = colorScheme == .dark ? "dax-waving-dark" : "dax-waving-light"
        guard let data = NSDataAsset(name: assetName)?.data,
              let animation = try? JSONDecoder().decode(LottieAnimation.self, from: data) else {
            return
        }
        let view = LottieAnimationView(animation: animation)
        view.contentMode = .scaleAspectFit
        view.loopMode = .playOnce
        view.animationSpeed = 1.0
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        // Let the container resize the Lottie view via autoresizing rather than constraints —
        // LottieAnimationView returns its animation canvas as intrinsicContentSize, which was
        // fighting our layout constraints and forcing the view to render at 557×659. With
        // autoresizing the view tracks container.bounds exactly.
        view.autoresizingMask = [.width, .height]
        view.frame = container.bounds
        container.addSubview(view)
        view.play()
    }
}
