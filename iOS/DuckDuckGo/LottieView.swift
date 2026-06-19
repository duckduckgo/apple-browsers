//
//  LottieView.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import Lottie

/// Consider using Lottie.LottieView instead, as it's more feature rich and well-maintained.
struct LottieView: UIViewRepresentable {

    struct LoopWithIntroTiming {
        let skipIntro: Bool
        let introStartFrame: AnimationFrameTime
        let introEndFrame: AnimationFrameTime
        let loopStartFrame: AnimationFrameTime
        let loopEndFrame: AnimationFrameTime
    }

    enum LoopMode {
        case mode(LottieLoopMode)
        case withIntro(LoopWithIntroTiming)
    }

    struct ValueProvider {
        let provider: AnyValueProvider
        let keypath: AnimationKeypath
    }

    /// Hosts a `LottieAnimationView`. When `contentSize` is `nil` the container reports the
    /// animation's own intrinsic size, matching the implicit sizing existing callers rely on.
    /// When set, it reports that size as its intrinsic content size so SwiftUI sizes the view
    /// explicitly — this is necessary to constrain animations that are larger than their intended display area.
    ///
    final class ContainerView: UIView {
        let animationView = LottieAnimationView()
        var contentSize: CGSize? {
            didSet { invalidateIntrinsicContentSize() }
        }

        override var intrinsicContentSize: CGSize {
            contentSize ?? animationView.intrinsicContentSize
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            animationView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(animationView)
            NSLayoutConstraint.activate([
                animationView.leadingAnchor.constraint(equalTo: leadingAnchor),
                animationView.trailingAnchor.constraint(equalTo: trailingAnchor),
                animationView.topAnchor.constraint(equalTo: topAnchor),
                animationView.bottomAnchor.constraint(equalTo: bottomAnchor)
            ])
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    let delay: TimeInterval
    var isAnimating: Binding<Bool>
    private let loopMode: LoopMode
    private let animationImageProvider: AnimationImageProvider?
    private let valueProvider: ValueProvider?
    private let contentSize: CGSize?

    let animationName: String
    let animation: LottieAnimation?
    let containerView = ContainerView(frame: .zero)

    init(
        lottieFile: String,
        delay: TimeInterval = 0,
        loopMode: LoopMode = .mode(.playOnce),
        isAnimating: Binding<Bool> = .constant(true),
        animationImageProvider: AnimationImageProvider? = nil,
        valueProvider: ValueProvider? = nil,
        contentSize: CGSize? = nil
    ) {
        self.animationName = lottieFile
        self.animation = LottieAnimation.named(lottieFile)
        self.delay = delay
        self.isAnimating = isAnimating
        self.loopMode = loopMode
        self.animationImageProvider = animationImageProvider
        self.valueProvider = valueProvider
        self.contentSize = contentSize
    }

    func makeUIView(context: Context) -> ContainerView {
        let animationView = containerView.animationView
        containerView.contentSize = contentSize
        animationView.animation = animation
        animationView.contentMode = .scaleAspectFit
        animationView.clipsToBounds = false
        if let animationImageProvider {
            animationView.imageProvider = animationImageProvider
        }
        if let valueProvider {
            animationView.setValueProvider(valueProvider.provider, keypath: valueProvider.keypath)
        }

        switch loopMode {
        case .mode(let lottieLoopMode): animationView.loopMode = lottieLoopMode
        case .withIntro: break
        }

        return containerView
    }

    func updateUIView(_ uiView: ContainerView, context: Context) {
        let animationView = uiView.animationView

        if animationView.isAnimationPlaying, !isAnimating.wrappedValue {
            animationView.stop()
            return
        }

        // If the view is not animating and the progress is 0, apply an animation-specific hack.
        // The VPN startup animations have an issue with the initial frame that is introduced when backgrounding and foregrounding the app.
        // The issue can be reproduced using the official Lottie SwiftUI wrapped, so instead it is being worked around by resetting the animation
        // when appropriate.
        if !isAnimating.wrappedValue, animationView.currentProgress == 0 {
            if animationView.currentFrame == 0, self.animationName.hasPrefix("vpn-") {
                animationView.animation = nil
                animationView.animation = self.animation
            }
        }

        guard isAnimating.wrappedValue, !animationView.isAnimationPlaying else {
            return
        }

        if animationView.loopMode == .playOnce && animationView.currentProgress == 1 {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            switch loopMode {
            case .mode:
                animationView.play(completion: { _ in
                    self.isAnimating.wrappedValue = false
                })
            case .withIntro(let timing):
                if timing.skipIntro {
                    animationView.play(fromFrame: timing.loopStartFrame, toFrame: timing.loopEndFrame, loopMode: .loop)
                } else {
                    animationView.play(fromFrame: timing.introStartFrame, toFrame: timing.introEndFrame, loopMode: .playOnce) { _ in
                        animationView.play(fromFrame: timing.loopStartFrame, toFrame: timing.loopEndFrame, loopMode: .loop)
                    }
                }
            }
        }
    }
}
