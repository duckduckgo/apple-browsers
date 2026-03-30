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
import DesignResourcesKit

/// Manages the Dax logo view display and positioning
final class DaxLogoManager {
    
    // MARK: - Properties

    private let isFireTab: Bool

    private var logoContainerView: UIView = UIView()

    private lazy var daxLogoView = AnimatedDaxLogoView()
    private var fireTabHostingController: UIHostingController<FireModeEmptyStateView>?

    private var isHomeDaxVisible: Bool = false
    private var isAIDaxVisible: Bool = false
    private var forcedHidden: Bool = false

    private var progress: CGFloat = 0
    private var escapeHatchBaseOffset: CGFloat = 0

    private(set) var containerYCenterConstraint: NSLayoutConstraint?

    // MARK: - Initialization

    init(isFireTab: Bool = false) {
        self.isFireTab = isFireTab
    }

    // MARK: - Public Methods
    
    func installInViewController(_ parentController: UIViewController,
                                 asSubviewOf parentView: UIView,
                                 anchorView: UIView,
                                 isTopBarPosition: Bool,
                                 escapeHatch: EscapeHatchModel? = nil,
                                 onEscapeHatchTap: (() -> Void)? = nil) {

        logoContainerView.translatesAutoresizingMaskIntoConstraints = false
        logoContainerView.isUserInteractionEnabled = isFireTab
        parentView.addSubview(logoContainerView)

        if isFireTab {
            installFireTabContent(in: parentController, escapeHatch: escapeHatch, onEscapeHatchTap: onEscapeHatchTap)
            installFireTabConstraints(parentView: parentView, anchorView: anchorView, isTopBarPosition: isTopBarPosition)
        } else {
            installDaxLogoContent()
            installDaxLogoConstraints(parentView: parentView, anchorView: anchorView, isTopBarPosition: isTopBarPosition)
        }

        parentView.bringSubviewToFront(logoContainerView)
    }

    func updateVisibility(isHomeDaxVisible: Bool, isAIDaxVisible: Bool) {
        self.isHomeDaxVisible = isHomeDaxVisible
        self.isAIDaxVisible = isAIDaxVisible

        updateState()
    }

    func setForcedHidden(_ hidden: Bool) {
        guard forcedHidden != hidden else { return }
        forcedHidden = hidden
        updateState()
    }

    func setEscapeHatchBaseOffset(_ offset: CGFloat) {
        guard escapeHatchBaseOffset != offset else { return }
        escapeHatchBaseOffset = offset
        updateState()
    }

    func updateSwipeProgress(_ progress: CGFloat) {
        self.progress = progress

        updateState()
    }

    // MARK: - Private Methods

    private func installFireTabConstraints(parentView: UIView, anchorView: UIView, isTopBarPosition: Bool) {
        if isTopBarPosition {
            NSLayoutConstraint.activate([
                logoContainerView.topAnchor.constraint(equalTo: anchorView.bottomAnchor),
                logoContainerView.bottomAnchor.constraint(equalTo: parentView.keyboardLayoutGuide.topAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                logoContainerView.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor),
                logoContainerView.bottomAnchor.constraint(equalTo: anchorView.topAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            logoContainerView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            logoContainerView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor)
        ])
    }

    private func installDaxLogoConstraints(parentView: UIView, anchorView: UIView, isTopBarPosition: Bool) {
        let centeringGuide = UILayoutGuide()
        centeringGuide.identifier = "DaxLogoCenteringGuide"
        parentView.addLayoutGuide(centeringGuide)

        containerYCenterConstraint = logoContainerView.centerYAnchor.constraint(equalTo: centeringGuide.centerYAnchor)

        if isTopBarPosition {
            NSLayoutConstraint.activate([
                anchorView.bottomAnchor.constraint(equalTo: centeringGuide.topAnchor),
                parentView.keyboardLayoutGuide.topAnchor.constraint(equalTo: centeringGuide.bottomAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                parentView.topAnchor.constraint(equalTo: centeringGuide.topAnchor),
                parentView.keyboardLayoutGuide.topAnchor.constraint(equalTo: centeringGuide.bottomAnchor, constant: DefaultOmniBarView.expectedHeight)
            ])
        }

        NSLayoutConstraint.activate([

            // Position layout centering guide vertically between top view and keyboard
            parentView.leadingAnchor.constraint(equalTo: centeringGuide.leadingAnchor),
            parentView.trailingAnchor.constraint(equalTo: centeringGuide.trailingAnchor),

            // Center within the layout guide
            logoContainerView.topAnchor.constraint(greaterThanOrEqualTo: centeringGuide.topAnchor),
            logoContainerView.bottomAnchor.constraint(lessThanOrEqualTo: centeringGuide.bottomAnchor),
            logoContainerView.leadingAnchor.constraint(greaterThanOrEqualTo: centeringGuide.leadingAnchor),
            logoContainerView.trailingAnchor.constraint(lessThanOrEqualTo: centeringGuide.trailingAnchor),
            logoContainerView.centerXAnchor.constraint(equalTo: centeringGuide.centerXAnchor),
            containerYCenterConstraint!
        ])
    }

    private func installFireTabContent(in parentController: UIViewController,
                                       escapeHatch: EscapeHatchModel?,
                                       onEscapeHatchTap: (() -> Void)?) {
        let hostingController = UIHostingController(
            rootView: FireModeEmptyStateView(type: .tab,
                                             escapeHatch: escapeHatch,
                                             onEscapeHatchTap: onEscapeHatchTap))
        hostingController.view.backgroundColor = .clear
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        parentController.addChild(hostingController)
        logoContainerView.addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: logoContainerView.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: logoContainerView.bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: logoContainerView.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: logoContainerView.trailingAnchor)
        ])

        hostingController.didMove(toParent: parentController)
        fireTabHostingController = hostingController
    }

    private func installDaxLogoContent() {
        logoContainerView.addSubview(daxLogoView)
        daxLogoView.frame = logoContainerView.bounds
        daxLogoView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        daxLogoView.setContentHuggingPriority(.defaultHigh, for: .vertical)
    }

    private func updateState() {
        let resolvedAlpha: CGFloat

        if forcedHidden {
            resolvedAlpha = 0
        } else if isHomeDaxVisible != isAIDaxVisible {
            if !isFireTab {
                daxLogoView.updateProgress(isAIDaxVisible ? 1 : 0)
            }

            let homeLogoProgress = 1 - progress
            let aiLogoProgress = progress

            let homeDaxAlphaCoefficient: CGFloat = isHomeDaxVisible ? 1 : 0
            let aiDaxAlphaCoefficient: CGFloat = isAIDaxVisible ? 1 : 0

            let daxAlpha = homeDaxAlphaCoefficient * homeLogoProgress
            let aiAlpha = aiDaxAlphaCoefficient * aiLogoProgress

            resolvedAlpha = max(daxAlpha, aiAlpha)
        } else if isHomeDaxVisible && isAIDaxVisible {
            if !isFireTab {
                daxLogoView.updateProgress(progress)
            }

            resolvedAlpha = 1
        } else {
            resolvedAlpha = 0
        }

        logoContainerView.alpha = resolvedAlpha
        if isFireTab {
            logoContainerView.isUserInteractionEnabled = resolvedAlpha > 0
        }

        containerYCenterConstraint?.constant = escapeHatchBaseOffset
    }
}

protocol DaxLogoViewSwitching: UIView {
    func updateProgress(_ progress: CGFloat)
}
