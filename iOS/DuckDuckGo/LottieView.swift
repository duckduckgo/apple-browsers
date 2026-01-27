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

/// A SwiftUI wrapper for Lottie animations.
///
/// ## Sizing Behavior
///
/// By default (`respectBounds: false`), the `LottieAnimationView` is returned directly.
/// This works for most animations but can cause issues with large animations (e.g., 960x960)
/// that overflow their SwiftUI `.frame()` bounds because:
/// - `UIViewRepresentable` views use their intrinsic content size
/// - SwiftUI's `.frame()` only *proposes* a size but doesn't enforce it without Auto Layout
///
/// When `respectBounds: true`, the animation is wrapped in a container `UIView` with
/// Auto Layout constraints pinning all edges. This forces the animation to scale down
/// to fit the SwiftUI-proposed frame via `scaleAspectFit`.
///
/// ## Why `animationView` is stored as a property
///
/// Although SwiftUI structs are value types that get recreated, `LottieAnimationView` is
/// a reference type (class). The property is initialized once per struct instance, and
/// `makeUIView` is only called once when the view is first created. In `updateUIView`,
/// we access `self.animationView` directly rather than the `uiView` parameter because
/// when `respectBounds: true`, the parameter is the container—not the animation view.
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

    let delay: TimeInterval
    var isAnimating: Binding<Bool>
    private let loopMode: LoopMode
    private let animationImageProvider: AnimationImageProvider?
    private let valueProvider: ValueProvider?
    
    /// When `true`, wraps the animation in a container with Auto Layout constraints
    /// to ensure it respects SwiftUI's `.frame()` size. Use this for animations with
    /// large native dimensions that would otherwise overflow their bounds.
    private let respectBounds: Bool

    let animationName: String
    let animation: LottieAnimation?
    
    /// Stored as a property (not local to `makeUIView`) so `updateUIView` can access it
    /// regardless of whether we return the animation directly or wrapped in a container.
    let animationView = LottieAnimationView()

    init(
        lottieFile: String,
        delay: TimeInterval = 0,
        loopMode: LoopMode = .mode(.playOnce),
        isAnimating: Binding<Bool> = .constant(true),
        animationImageProvider: AnimationImageProvider? = nil,
        valueProvider: ValueProvider? = nil,
        respectBounds: Bool = false
    ) {
        self.animationName = lottieFile
        self.animation = LottieAnimation.named(lottieFile)
        self.delay = delay
        self.isAnimating = isAnimating
        self.loopMode = loopMode
        self.animationImageProvider = animationImageProvider
        self.valueProvider = valueProvider
        self.respectBounds = respectBounds
    }

    func makeUIView(context: Context) -> some UIView {
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

        if !respectBounds {
            // Default behavior: return the animation view directly.
            return animationView as UIView
        } else {
            // Constrained behavior: wrap in a container with Auto Layout.
            // The container receives SwiftUI's proposed size, and the animation is
            // pinned to all edges, forcing it to scale down if needed.
            let containerView = UIView()
            containerView.backgroundColor = .clear
            animationView.clipsToBounds = true
            animationView.translatesAutoresizingMaskIntoConstraints = false

            containerView.addSubview(animationView)
            NSLayoutConstraint.activate([
                animationView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                animationView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                animationView.topAnchor.constraint(equalTo: containerView.topAnchor),
                animationView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])
            
            return containerView
        }
    }
 
    func updateUIView(_ uiView: UIViewType, context: Context) {
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
