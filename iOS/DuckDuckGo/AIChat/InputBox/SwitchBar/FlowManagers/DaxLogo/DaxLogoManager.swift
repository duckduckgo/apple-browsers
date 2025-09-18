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

    let animated: Bool

    private var logoContainerView: UIView = UIView()

    private lazy var daxLogoView: DaxLogoViewSwitching = {
        (animated ? AnimatedDaxLogoView() : StaticDaxLogoView()) as DaxLogoViewSwitching
    }()

    private var isHomeDaxVisible: Bool = false
    private var isAIDaxVisible: Bool = false

    private var progress: CGFloat = 0

    private(set) var containerYCenterConstraint: NSLayoutConstraint?

    init(animated: Bool) {
        self.animated = animated
    }

    // MARK: - Public Methods
    
    func installInViewController(_ viewController: UIViewController, asSubviewOf parentView: UIView, belowView topView: UIView) {

        logoContainerView.translatesAutoresizingMaskIntoConstraints = false
        logoContainerView.isUserInteractionEnabled = false
        parentView.addSubview(logoContainerView)

        logoContainerView.addSubview(daxLogoView)
        daxLogoView.frame = logoContainerView.bounds
        daxLogoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        daxLogoView.setContentHuggingPriority(.defaultHigh, for: .vertical)

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
            containerYCenterConstraint!
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
        if isHomeDaxVisible != isAIDaxVisible {
            // Keep progress in one state, only update alpha
            daxLogoView.updateProgress(isAIDaxVisible ? 1 : 0)

            let homeLogoProgress = 1 - progress
            let aiLogoProgress = progress

            let homeDaxAlphaCoefficient: CGFloat = isHomeDaxVisible ? 1 : 0
            let aiDaxAlphaCoefficient: CGFloat = isAIDaxVisible ? 1 : 0

            let daxAlpha = homeDaxAlphaCoefficient * homeLogoProgress
            let aiAlpha = aiDaxAlphaCoefficient * aiLogoProgress

            daxLogoView.alpha = max(daxAlpha, aiAlpha)
        } else if isHomeDaxVisible && isAIDaxVisible {
            // Modify progress, don't modify alpha
            daxLogoView.updateProgress(progress)

            daxLogoView.alpha = 1
        } else {
            daxLogoView.alpha = 0
        }

    }
}

private final class StaticDaxLogoView: UIView, DaxLogoViewSwitching {
    private let homeDaxLogoView = DaxLogoView(isAIDax: false)
    private let aiDaxLogoView = DaxLogoView(isAIDax: true)

    init() {
        super.init(frame: .zero)

        setUpSubviews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateProgress(_ progress: CGFloat) {
        let homeLogoProgress = 1 - progress
        let aiLogoProgress = progress

        homeDaxLogoView.textImage.alpha = homeLogoProgress
        aiDaxLogoView.alpha = aiLogoProgress
    }

    private func setUpSubviews() {

        homeDaxLogoView.translatesAutoresizingMaskIntoConstraints = false
        aiDaxLogoView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(homeDaxLogoView)
        addSubview(aiDaxLogoView)

        NSLayoutConstraint.activate([
            homeDaxLogoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            homeDaxLogoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            homeDaxLogoView.topAnchor.constraint(equalTo: topAnchor),
            homeDaxLogoView.bottomAnchor.constraint(equalTo: bottomAnchor),

            aiDaxLogoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            aiDaxLogoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            aiDaxLogoView.topAnchor.constraint(equalTo: topAnchor),
            aiDaxLogoView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
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

protocol DaxLogoViewSwitching: UIView {
    func updateProgress(_ progress: CGFloat)
}
