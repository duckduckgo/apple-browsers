//
//  AnimatedDaxLogoView.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import UIKit
import Lottie

final class AnimatedDaxLogoView: UIView, DaxLogoViewSwitching {
    private(set) lazy var logoAnimation = LottieAnimationView(name: Constant.daxLogoAnimationName)

    init() {
        super.init(frame: .zero)

        setUpSubviews()
    }

    func updateProgress(_ progress: CGFloat) {
        logoAnimation.currentProgress = progress
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        logoAnimation.translatesAutoresizingMaskIntoConstraints = false
        addSubview(logoAnimation)

        NSLayoutConstraint.activate([
            logoAnimation.leadingAnchor.constraint(equalTo: leadingAnchor),
            logoAnimation.trailingAnchor.constraint(equalTo: trailingAnchor),
            logoAnimation.topAnchor.constraint(equalTo: topAnchor),
            logoAnimation.bottomAnchor.constraint(equalTo: bottomAnchor),

            logoAnimation.heightAnchor.constraint(lessThanOrEqualToConstant: Metrics.maxLogoSize),
            logoAnimation.heightAnchor.constraint(equalToConstant: Metrics.maxLogoSize).withPriority(.defaultHigh)
        ])

    }

    private func updateAnimationForCurrentTraitCollection() {
        let progress = logoAnimation.currentProgress
        if traitCollection.userInterfaceStyle == .dark {
            logoAnimation.animation = LottieAnimation.named(Constant.daxLogoAnimationDarkName)
        } else {
            logoAnimation.animation = LottieAnimation.named(Constant.daxLogoAnimationName)
        }
        logoAnimation.currentProgress = progress
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            updateAnimationForCurrentTraitCollection()
        }
    }

    private struct Metrics {
        static let maxLogoSize: CGFloat = 162
    }

    private enum Constant {
        static let daxLogoAnimationName = "duckduckgo-ai-transition.json"
        static let daxLogoAnimationDarkName = "duckduckgo-ai-transition-dark.json"
    }
}
