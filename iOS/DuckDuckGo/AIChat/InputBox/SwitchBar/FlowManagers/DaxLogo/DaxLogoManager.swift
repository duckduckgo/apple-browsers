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

    private lazy var daxLogoView = AnimatedDaxLogoView()

    private var isHomeDaxVisible: Bool = false
    private var isAIDaxVisible: Bool = false

    private var progress: CGFloat = 0

    private(set) var containerYCenterConstraint: NSLayoutConstraint?

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

protocol DaxLogoViewSwitching: UIView {
    func updateProgress(_ progress: CGFloat)
}
