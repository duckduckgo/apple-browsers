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

    private var logoContainerView: UIView = UIView()

    private var homeDaxLogoView = DaxLogoView(isAIDax: false)
    private var aiDaxLogoView = DaxLogoView(isAIDax: true)

    private var isHomeDaxVisible: Bool = false
    private var isAIDaxVisible: Bool = false

    private var progress: CGFloat = 0

    private(set) var containerYCenterConstraint: NSLayoutConstraint?

    // MARK: - Public Methods
    
    func installInViewController(_ viewController: UIViewController, asSubviewOf parentView: UIView, belowView topView: UIView) {

        logoContainerView.translatesAutoresizingMaskIntoConstraints = false
        logoContainerView.isUserInteractionEnabled = false
        parentView.addSubview(logoContainerView)

        logoContainerView.addSubview(homeDaxLogoView)
        homeDaxLogoView.translatesAutoresizingMaskIntoConstraints = false
        homeDaxLogoView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        logoContainerView.addSubview(aiDaxLogoView)
        aiDaxLogoView.translatesAutoresizingMaskIntoConstraints = false
        aiDaxLogoView.setContentHuggingPriority(.defaultHigh, for: .vertical)

        let centeringGuide = UILayoutGuide()
        centeringGuide.identifier = "DaxLogoCenteringGuide"
        parentView.addLayoutGuide(centeringGuide)

        containerYCenterConstraint = logoContainerView.centerYAnchor.constraint(equalTo: centeringGuide.centerYAnchor)

        NSLayoutConstraint.activate([

            // Position layout centering guide vertically between top view and keyboard
            parentView.leadingAnchor.constraint(equalTo: centeringGuide.leadingAnchor),
            parentView.trailingAnchor.constraint(equalTo: centeringGuide.trailingAnchor),
            topView.bottomAnchor.constraint(equalTo: centeringGuide.topAnchor),
            parentView.keyboardLayoutGuide.topAnchor.constraint(equalTo: centeringGuide.bottomAnchor),

            // Center within the layout guide
            logoContainerView.topAnchor.constraint(greaterThanOrEqualTo: centeringGuide.topAnchor),
            logoContainerView.bottomAnchor.constraint(lessThanOrEqualTo: centeringGuide.bottomAnchor),
            logoContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: centeringGuide.leadingAnchor),
            logoContainerView.trailingAnchor.constraint(lessThanOrEqualTo: centeringGuide.trailingAnchor),
            logoContainerView.centerXAnchor.constraint(equalTo: centeringGuide.centerXAnchor),
            containerYCenterConstraint!,

            homeDaxLogoView.leadingAnchor.constraint(equalTo: logoContainerView.leadingAnchor),
            homeDaxLogoView.trailingAnchor.constraint(equalTo: logoContainerView.trailingAnchor),
            homeDaxLogoView.topAnchor.constraint(equalTo: logoContainerView.topAnchor),
            homeDaxLogoView.bottomAnchor.constraint(equalTo: logoContainerView.bottomAnchor),

            aiDaxLogoView.leadingAnchor.constraint(equalTo: logoContainerView.leadingAnchor),
            aiDaxLogoView.trailingAnchor.constraint(equalTo: logoContainerView.trailingAnchor),
            aiDaxLogoView.topAnchor.constraint(equalTo: logoContainerView.topAnchor),
            aiDaxLogoView.bottomAnchor.constraint(equalTo: logoContainerView.bottomAnchor),
        ])

        parentView.bringSubviewToFront(logoContainerView)
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

        let homeLogoProgress = 1 - progress
        let aiLogoProgress = progress

        if isHomeDaxVisible == isAIDaxVisible {
            homeDaxLogoView.alpha = isHomeDaxVisible ? 1.0 : 0.0
            homeDaxLogoView.textImage.alpha = isHomeDaxVisible ? homeLogoProgress : 0
            aiDaxLogoView.alpha = isAIDaxVisible ? aiLogoProgress : 0
        } else {
            // Fade out home only when one logo is visible - prevents flashing
            homeDaxLogoView.alpha = isHomeDaxVisible ? Easing.inOutCirc(homeLogoProgress) : 0
            homeDaxLogoView.textImage.alpha = 1.0
            aiDaxLogoView.alpha = isAIDaxVisible ? Easing.inOutCirc(aiLogoProgress) : 0
        }
    }
}

private final class DaxLogoView: UIView {
    private(set) lazy var logoImage = UIImageView(image: UIImage(resource: isAIDax ? .duckAI : .searchDax))
    private(set) lazy var textImage = UIImageView(image: UIImage(resource: isAIDax ? .textDuckAi : .textDuckDuckGo))

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

        stackView.spacing = Metrics.spacing
        stackView.axis = .vertical

        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: 0),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            logoImage.heightAnchor.constraint(lessThanOrEqualToConstant: Metrics.maxLogoSize),
            logoImage.heightAnchor.constraint(equalToConstant: Metrics.maxLogoSize).withPriority(.defaultHigh)
        ])

        logoImage.contentMode = .scaleAspectFit
        textImage.contentMode = .center

    }

    private struct Metrics {
        static let maxLogoSize: CGFloat = 96
        static let spacing: CGFloat = 12
    }
}
