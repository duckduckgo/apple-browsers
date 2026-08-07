//
//  SearchExperienceToggleAnimationView.swift
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

import Lottie
import SwiftUI
import UIKit

// MARK: - SwiftUI wrapper

/// Animated illustration for the "Search & Duck.ai" picker option on the Search Experience
/// onboarding screen. Renders a looping Lottie animation that shows the address-bar toggle
/// switching between Search and AI Chat modes.
///
/// The animation consists of two stacked Lottie layers that always loop in sync:
///  - **Grey layer** (always visible and always animating): the base illustration.
///  - **Coloured layer** (fades in when `isDuckAISelected` is `true`): the highlighted version.
///
/// Both layers run the same loop sequence simultaneously so they stay perfectly in sync:
///  1. 4-second initial delay before the first play (accounts for screen reveal animation).
///  2. Play forward (frames 1 → 50): toggle switches to AI Chat.
///  3. 2.5-second pause.
///  4. Play in reverse (frames 50 → 1): toggle switches back to Search.
///  5. 2-second pause, then repeat from step 2.
///
/// When `isDuckAISelected` changes the coloured layer fades in or out while the grey layer
/// continues animating underneath without interruption.
struct SearchExperienceToggleAnimationView: UIViewRepresentable {

    let isDuckAISelected: Bool

    func makeUIView(context: UIViewRepresentableContext<SearchExperienceToggleAnimationView>) -> SearchExperienceToggleUIView {
        SearchExperienceToggleUIView()
    }

    func updateUIView(_ uiView: SearchExperienceToggleUIView, context: UIViewRepresentableContext<SearchExperienceToggleAnimationView>) {
        uiView.setSelected(isDuckAISelected, animated: context.transaction.animation != nil)
    }
}

// MARK: - UIKit implementation

final class SearchExperienceToggleUIView: UIView {

    // MARK: - Animation asset names
    //
    // .lottie files located next to this Swift file:
    //   OnboardingSearchAIToggle.lottie           – light mode, coloured
    //   OnboardingSearchAIToggle_dark.lottie      – dark mode, coloured
    //   OnboardingSearchAIToggleGrey.lottie       – light mode, grey (base)
    //   OnboardingSearchAIToggleGrey_dark.lottie  – dark mode, grey (base)

    private enum Assets {
        static let coloredLight = "OnboardingSearchAIToggle"
        static let coloredDark  = "OnboardingSearchAIToggle_dark"
        static let greyLight    = "OnboardingSearchAIToggleGrey"
        static let greyDark     = "OnboardingSearchAIToggleGrey_dark"
    }

    // MARK: - Animation timing

    private enum Timing {
        /// Delay before the very first loop play after the view appears.
        static let initialDelay: TimeInterval = 4.0
        /// Pause between the forward play and the reverse play within a single cycle.
        static let pauseAfterForward: TimeInterval = 2.5
        /// Pause after the reverse play before the next cycle starts.
        static let pauseAfterReverse: TimeInterval = 2.0
        /// Frame range used for the toggle transition.
        static let fromFrame: AnimationFrameTime = 1
        static let toFrame: AnimationFrameTime = 50
        /// Duration for fading the coloured layer in/out on selection change.
        static let coloredFadeDuration: TimeInterval = 0.25
    }

    // MARK: - Subviews

    private let greyView = LottieAnimationView()
    private let coloredView = LottieAnimationView()

    // MARK: - State

    /// Cancels in-flight scheduled work items (delays between loop stages).
    private var pendingWork: DispatchWorkItem?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setUp() {
        for animView in [greyView, coloredView] {
            animView.contentMode = .scaleAspectFit
            animView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(animView)
            NSLayoutConstraint.activate([
                animView.leadingAnchor.constraint(equalTo: leadingAnchor),
                animView.trailingAnchor.constraint(equalTo: trailingAnchor),
                animView.topAnchor.constraint(equalTo: topAnchor),
                animView.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }

        // Coloured starts hidden; revealed by the first setSelected call.
        coloredView.alpha = 0

        loadAnimationsAndStartLoop()
    }

    // MARK: - Animation loading

    private var coloredAnimationName: String {
        traitCollection.userInterfaceStyle == .dark ? Assets.coloredDark : Assets.coloredLight
    }

    private var greyAnimationName: String {
        traitCollection.userInterfaceStyle == .dark ? Assets.greyDark : Assets.greyLight
    }

    private func loadAnimationsAndStartLoop() {
        let greyName = greyAnimationName
        let coloredName = coloredAnimationName
        Task { @MainActor [weak self] in
            guard let self else { return }
            async let grey = try? DotLottieFile.named(greyName)
            async let colored = try? DotLottieFile.named(coloredName)
            if let g = await grey { greyView.loadAnimation(from: g) }
            if let c = await colored { coloredView.loadAnimation(from: c) }
            startLoop()
        }
    }

    // MARK: - Public API

    /// Shows or hides the coloured overlay. The grey animation always keeps looping.
    func setSelected(_ selected: Bool, animated: Bool) {
        let targetAlpha: CGFloat = selected ? 1 : 0
        guard coloredView.alpha != targetAlpha else { return }
        UIView.animate(withDuration: animated ? Timing.coloredFadeDuration : 0) {
            self.coloredView.alpha = targetAlpha
        }
    }

    // MARK: - Always-on animation loop
    //
    // Both grey and coloured run the exact same sequence simultaneously so they stay
    // in sync regardless of which layer the user sees. Only grey drives the timing;
    // coloured mirrors every play call so it is frame-accurate when faded in.

    private func startLoop() {
        schedule(delay: Timing.initialDelay) { [weak self] in
            self?.playForward()
        }
    }

    private func playForward() {
        let forward = { (view: LottieAnimationView, completion: @escaping (Bool) -> Void) in
            view.play(fromFrame: Timing.fromFrame, toFrame: Timing.toFrame, loopMode: .playOnce, completion: completion)
        }

        // Grey drives the timing; coloured mirrors without its own completion handler.
        forward(coloredView) { _ in }
        forward(greyView) { [weak self] finished in
            guard finished, let self else { return }
            self.schedule(delay: Timing.pauseAfterForward) { [weak self] in
                self?.playReverse()
            }
        }
    }

    private func playReverse() {
        let reverse = { (view: LottieAnimationView, completion: @escaping (Bool) -> Void) in
            view.play(fromFrame: Timing.toFrame, toFrame: Timing.fromFrame, loopMode: .playOnce, completion: completion)
        }

        reverse(coloredView) { _ in }
        reverse(greyView) { [weak self] finished in
            guard finished, let self else { return }
            self.schedule(delay: Timing.pauseAfterReverse) { [weak self] in
                self?.playForward()
            }
        }
    }

    // MARK: - Work item helpers

    private func schedule(delay: TimeInterval, block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        pendingWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Dark / light mode

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }

        // Stop pending delays and playing animations.
        pendingWork?.cancel()
        pendingWork = nil
        greyView.stop()
        coloredView.stop()

        // Reload with new colour-scheme assets and restart the loop from the beginning.
        loadAnimationsAndStartLoop()
    }
}
