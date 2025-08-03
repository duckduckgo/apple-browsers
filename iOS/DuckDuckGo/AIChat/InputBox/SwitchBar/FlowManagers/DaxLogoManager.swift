//
//  DaxLogoManager.swift
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

import Foundation
import UIKit
import UIComponents
import SwiftUI

/// Manages the Dax logo view display and positioning
final class DaxLogoManager {
    
    // MARK: - Properties

    private(set) var homeDaxLogoView: UIView = DaxLogoView(isAIDax: false)
    private(set) var aiDaxLogoView: UIView = DaxLogoView(isAIDax: true)

    private var isHomeDaxVisible: Bool = false
    private var isAIDaxVisible: Bool = false

    private var progress: CGFloat = 0

    // MARK: - Public Methods
    
    func installInViewController(_ viewController: UIViewController, belowView topView: UIView) {

        viewController.view.addSubview(homeDaxLogoView)
        homeDaxLogoView.translatesAutoresizingMaskIntoConstraints = false
        homeDaxLogoView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        viewController.view.addSubview(aiDaxLogoView)
        aiDaxLogoView.translatesAutoresizingMaskIntoConstraints = false
        aiDaxLogoView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let centeringGuide = UILayoutGuide()
        centeringGuide.identifier = "DaxLogoCenteringGuide"
        viewController.view.addLayoutGuide(centeringGuide)

        NSLayoutConstraint.activate([

            // Position layout centering guide vertically between top view and keyboard
            viewController.view.leadingAnchor.constraint(equalTo: centeringGuide.leadingAnchor),
            viewController.view.trailingAnchor.constraint(equalTo: centeringGuide.trailingAnchor),
            topView.bottomAnchor.constraint(equalTo: centeringGuide.topAnchor),
            viewController.view.keyboardLayoutGuide.topAnchor.constraint(equalTo: centeringGuide.bottomAnchor),

            // Center within the layout guide
            homeDaxLogoView.topAnchor.constraint(greaterThanOrEqualTo: centeringGuide.topAnchor),
            homeDaxLogoView.bottomAnchor.constraint(lessThanOrEqualTo: centeringGuide.bottomAnchor),
            homeDaxLogoView.leadingAnchor.constraint(greaterThanOrEqualTo: centeringGuide.leadingAnchor),
            homeDaxLogoView.trailingAnchor.constraint(lessThanOrEqualTo: centeringGuide.trailingAnchor),
            homeDaxLogoView.centerXAnchor.constraint(equalTo: centeringGuide.centerXAnchor),
            homeDaxLogoView.centerYAnchor.constraint(equalTo: centeringGuide.centerYAnchor),

            aiDaxLogoView.topAnchor.constraint(greaterThanOrEqualTo: centeringGuide.topAnchor),
            aiDaxLogoView.bottomAnchor.constraint(lessThanOrEqualTo: centeringGuide.bottomAnchor),
            aiDaxLogoView.leadingAnchor.constraint(greaterThanOrEqualTo: centeringGuide.leadingAnchor),
            aiDaxLogoView.trailingAnchor.constraint(lessThanOrEqualTo: centeringGuide.trailingAnchor),
            aiDaxLogoView.centerXAnchor.constraint(equalTo: centeringGuide.centerXAnchor),
            aiDaxLogoView.centerYAnchor.constraint(equalTo: centeringGuide.centerYAnchor)
        ])

        viewController.view.sendSubviewToBack(aiDaxLogoView)
        viewController.view.sendSubviewToBack(homeDaxLogoView)
    }

    func updateVisibility(isHomeDaxVisible: Bool, isAIDaxVisible: Bool) {
        self.isHomeDaxVisible = isHomeDaxVisible
        self.isAIDaxVisible = isAIDaxVisible

        updateState()
    }

    func updateSwipeProgress(_ progress: CGFloat) {
        self.progress = progress

        updateState()
    }

    private func updateState() {
        homeDaxLogoView.alpha = isHomeDaxVisible ? Easing.inOutCirc(1 - progress) : 0
        aiDaxLogoView.alpha = isAIDaxVisible ? Easing.inOutCirc(progress) : 0

        aiDaxLogoView.transform = CGAffineTransform(translationX: translation(for: aiDaxLogoView, progress: progress), y: 0)
        homeDaxLogoView.transform = CGAffineTransform(translationX: -translation(for: homeDaxLogoView, progress: 1-progress), y: 0)
    }

    private func translation(for logoView: UIView, progress: CGFloat) -> CGFloat {
        (1 - progress) * (logoView.center.x + logoView.bounds.width/2.0)
    }
}

private final class DaxLogoView: UIView {
    private(set) lazy var logoImage = UIImageView(image: UIImage(resource: isAIDax ? .duckAI : .home))
    let textImage = UIImageView(image: UIImage(resource: .textDuckDuckGo))

    private let stackView = UIStackView()
    private let isAIDax: Bool

    init(isAIDax: Bool) {
        self.isAIDax = isAIDax
        super.init(frame: .zero)

        setUpSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpSubviews() {
        stackView.addArrangedSubview(logoImage)
        stackView.addArrangedSubview(textImage)

        textImage.tintColor = UIColor(designSystemColor: .textPrimary)

        stackView.spacing = Metrics.spacing(isDuckAI: isAIDax)
        stackView.axis = .vertical

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        let maxSize = Metrics.maxLogoSize(isDuckAI: isAIDax)
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: isAIDax ? -Metrics.paddingDiff/2 : 0),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            logoImage.heightAnchor.constraint(lessThanOrEqualToConstant: maxSize),
            logoImage.heightAnchor.constraint(equalToConstant: maxSize).withPriority(.defaultHigh)
        ])

        logoImage.contentMode = .scaleAspectFit
        textImage.contentMode = .center

    }

    private struct Metrics {
        static let maxLogoSize: CGFloat = 96
        static let maxDuckAILogoSize: CGFloat = 140
        static let spacing: CGFloat = 12

        // DuckAI logo contains padding around an icon. Calculating the difference to compensate in the layout.
        static let paddingDiff: CGFloat = maxDuckAILogoSize - maxLogoSize

        static func maxLogoSize(isDuckAI: Bool) -> CGFloat {
            isDuckAI ? maxDuckAILogoSize : maxLogoSize
        }

        static func spacing(isDuckAI: Bool) -> CGFloat {
            // For AI mode, adjust the spacing by subtracting half of the padding difference.
            // This ensures the layout remains visually balanced despite the larger AI logo size.
            isDuckAI ? spacing - (paddingDiff/2) : spacing
        }
    }
}
