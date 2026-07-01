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
    /// When true, the Lottie morph handles the search/duck.ai transition and the
    /// alpha-blending crossfade during swipe is skipped.
    var usesLottieTransition = false

    private var logoContainerView: UIView = UIView()

    private lazy var daxLogoView = AnimatedDaxLogoView()
    private var fireTabHostingController: UIHostingController<FireModeEmptyStateView>?

    private var isHomeDaxVisible: Bool = false
    private var isAIDaxVisible: Bool = false
    private var committedMode: TextEntryMode = .search
    private var forcedHidden: Bool = false

    private(set) var currentProgress: CGFloat = 0
    private var isAnimatingLogoTransition = false
    private var pendingTransitionToken: UUID?
    private var isSwipeInProgress = false
    private var escapeHatchBaseOffset: CGFloat = 0
    private(set) var logoYOffset: CGFloat = 0

    private(set) var containerYCenterConstraint: NSLayoutConstraint?

    private weak var centeringGuideOwner: UIView?
    private var centeringGuide: UILayoutGuide?

    // MARK: - Initialization

    init(isFireTab: Bool = false) {
        self.isFireTab = isFireTab
    }

    // MARK: - Public Methods
    
    /// `anchorView` is optional: pass `nil` to fill the parent's safe area (fire-tab-only use case —
    /// UTI hosts its input outside the content container so there's no in-container anchor to align to).
    func installInViewController(_ parentController: UIViewController,
                                 asSubviewOf parentView: UIView,
                                 anchorView: UIView? = nil,
                                 isTopBarPosition: Bool) {

        if !isFireTab && isTopBarPosition && anchorView == nil {
            assertionFailure("Non-fire top-bar Dax logo install requires an anchor view.")
            return
        }

        logoContainerView.translatesAutoresizingMaskIntoConstraints = false
        logoContainerView.isUserInteractionEnabled = isFireTab
        parentView.addSubview(logoContainerView)

        if isFireTab {
            installFireTabContent(in: parentController)
            installFireTabConstraints(parentView: parentView, anchorView: anchorView, isTopBarPosition: isTopBarPosition)
        } else {
            installDaxLogoContent()
            installDaxLogoConstraints(parentView: parentView, anchorView: anchorView, isTopBarPosition: isTopBarPosition)
        }

        parentView.bringSubviewToFront(logoContainerView)
    }

    func updateVisibility(isHomeDaxVisible: Bool, isAIDaxVisible: Bool, committedMode: TextEntryMode) {
        self.isHomeDaxVisible = isHomeDaxVisible
        self.isAIDaxVisible = isAIDaxVisible
        self.committedMode = committedMode
        self.isSwipeInProgress = false
        // Settle the morph to the committed mode — the single source of truth for which logo shows.
        // Skipped mid-morph so an in-flight transition isn't stomped.
        if !isAnimatingLogoTransition {
            currentProgress = committedProgress
        }

        updateState()
    }

    private var committedProgress: CGFloat { committedMode == .aiChat ? 1 : 0 }

    /// The Lottie animation's current frame progress (0 = search, 1 = duck.ai).
    var lottieProgress: CGFloat {
        daxLogoView.logoAnimation.currentProgress
    }

    /// Plays the Lottie from its current progress to the given target. Clears any in-flight
    /// `animateLogoTransition` state since this play interrupts it without a `finished == true` callback.
    func animateProgress(to targetProgress: CGFloat) {
        pendingTransitionToken = nil
        isAnimatingLogoTransition = false
        daxLogoView.animateProgress(to: targetProgress)
    }

    /// Whether the logo container is currently visible.
    var isLogoVisible: Bool {
        logoContainerView.alpha > 0 && !forcedHidden
    }

    /// Whether the logo should be visible for the committed state, independent of its scrubbed
    /// alpha. The single-active-logo alpha is `currentProgress`-scaled, so a stale progress can
    /// read alpha 0 even when the logo should show — callers deciding to morph must use this.
    var isLogoActiveForCurrentState: Bool {
        guard !forcedHidden else { return false }
        return committedMode == .aiChat ? isAIDaxVisible : isHomeDaxVisible
    }

    /// Plays the Lottie transition to the given mode.
    /// Call after `updateVisibility` has set the new state — this method restores
    /// the previous Lottie progress and animates to the target. If the logo was
    /// not visible before (e.g. favorites were covering it), snaps directly to
    /// the target without animating.
    func animateLogoTransition(toMode mode: TextEntryMode,
                               fromProgress previousProgress: CGFloat,
                               wasLogoVisible: Bool) {
        guard !isFireTab, !forcedHidden else { return }
        let targetProgress: CGFloat = mode == .aiChat ? 1 : 0
        guard previousProgress != targetProgress else { return }

        guard wasLogoVisible else {
            daxLogoView.updateProgress(targetProgress)
            // Keep currentProgress aligned with the committed mode even when snapping, or the
            // single-active-logo alpha (scaled by currentProgress) would read 0 next render.
            currentProgress = targetProgress
            return
        }

        isAnimatingLogoTransition = true
        let token = UUID()
        pendingTransitionToken = token
        daxLogoView.updateProgress(previousProgress)
        // Hold the container at full alpha for the whole morph; otherwise the single-active-logo
        // alpha left by `updateVisibility` (scaled by a not-yet-advanced currentProgress) keeps it
        // hidden until completion — the morph would play invisibly and only "appear at the end".
        updateState()
        // Token-gated: Lottie reports `finished == false` on interruption, so gating on
        // `finished` alone would leave the flag stuck across UTI sessions.
        daxLogoView.animateProgress(to: targetProgress) { [weak self] _ in
            guard self?.pendingTransitionToken == token else { return }
            self?.pendingTransitionToken = nil
            self?.isAnimatingLogoTransition = false
            self?.currentProgress = targetProgress
            self?.updateState()
        }
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

    func setLogoYOffset(_ offset: CGFloat) {
        guard logoYOffset != offset else { return }
        logoYOffset = offset
        updateLogoYOffset()
    }

    func updateSwipeProgress(_ progress: CGFloat) {
        let wasInProgress = isSwipeInProgress
        self.currentProgress = progress

        // A swipe is in progress once it moves away from 0, and stays in progress
        // until the mode change completes (which calls updateVisibility and resets
        // the flag). This prevents a one-frame flash when progress lands on 0 or 1
        // before the mode switch has been processed.
        if progress > 0 && progress < 1 {
            isSwipeInProgress = true
        } else if !wasInProgress {
            isSwipeInProgress = false
        }

        updateState()
    }

    /// Matches sibling scrollable content insets so the fire-tab empty state isn't clipped by the nav bar.
    func setFireTabContentInsets(_ insets: UIEdgeInsets) {
        fireTabHostingController?.additionalSafeAreaInsets = insets
    }

    /// The logo container's center Y in window coordinates, or `nil` if not installed.
    var logoWindowCenterY: CGFloat? {
        guard let window = logoContainerView.window else { return nil }
        let center = logoContainerView.convert(CGPoint(x: 0, y: logoContainerView.bounds.midY), to: window)
        return center.y
    }

    /// Removes the managed views from the hierarchy so the manager can be discarded.
    func tearDown() {
        fireTabHostingController?.willMove(toParent: nil)
        fireTabHostingController?.view.removeFromSuperview()
        fireTabHostingController?.removeFromParent()
        fireTabHostingController = nil
        logoContainerView.removeFromSuperview()
        if let centeringGuide {
            centeringGuideOwner?.removeLayoutGuide(centeringGuide)
        }
        centeringGuide = nil
        centeringGuideOwner = nil
    }

    // MARK: - Private Methods

    private func installFireTabConstraints(parentView: UIView, anchorView: UIView?, isTopBarPosition: Bool) {
        if let anchorView {
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
        } else {
            NSLayoutConstraint.activate([
                logoContainerView.topAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.topAnchor),
                logoContainerView.bottomAnchor.constraint(equalTo: parentView.safeAreaLayoutGuide.bottomAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            logoContainerView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
            logoContainerView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor)
        ])
    }

    private func installDaxLogoConstraints(parentView: UIView, anchorView: UIView?, isTopBarPosition: Bool) {
        let centeringGuide = UILayoutGuide()
        centeringGuide.identifier = "DaxLogoCenteringGuide"
        parentView.addLayoutGuide(centeringGuide)
        self.centeringGuide = centeringGuide
        self.centeringGuideOwner = parentView

        containerYCenterConstraint = logoContainerView.centerYAnchor.constraint(equalTo: centeringGuide.centerYAnchor)

        if let anchorView, isTopBarPosition {
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

    private func installFireTabContent(in parentController: UIViewController) {
        let rootView = FireModeEmptyStateView(type: .tab)
        let hostingController = UIHostingController(rootView: rootView)

        // Opaque NTP background so the fire empty state fully covers any favorites/suggestion tray content layered beneath.
        hostingController.view.backgroundColor = UIColor(designSystemColor: .background)
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
        } else if isFireTab {
            resolvedAlpha = (isHomeDaxVisible || isAIDaxVisible) ? 1 : 0
        } else if usesLottieTransition && isHomeDaxVisible && isAIDaxVisible {
            // UTI mode, both logo states active: the Lottie morph handles the
            // visual transition — keep alpha at 1 and scrub with swipe progress.
            if !isAnimatingLogoTransition {
                daxLogoView.updateProgress(currentProgress)
            }
            resolvedAlpha = 1
        } else if usesLottieTransition && isSwipeInProgress && (isHomeDaxVisible || isAIDaxVisible) {
            // Mid-swipe: only one logo state is active because the mode hasn't switched yet.
            // Keep the logo visible and scrub the Lottie so the morph plays during the swipe.
            daxLogoView.updateProgress(currentProgress)
            resolvedAlpha = 1
        } else if usesLottieTransition && isAnimatingLogoTransition {
            // A programmatic logo transition is in flight — don't stomp the Lottie.
            resolvedAlpha = 1
        } else if isHomeDaxVisible != isAIDaxVisible {
            // One logo active: visible only when its side matches the committed `currentProgress`.
            // When hidden, leave the lottie frame so the visible logo fades out instead of snapping.
            let daxAlpha = (isHomeDaxVisible ? 1 : 0) * (1 - currentProgress)
            let aiAlpha = (isAIDaxVisible ? 1 : 0) * currentProgress
            resolvedAlpha = max(daxAlpha, aiAlpha)

            if resolvedAlpha > 0 {
                daxLogoView.updateProgress(currentProgress)
            }
        } else if isHomeDaxVisible && isAIDaxVisible {
            daxLogoView.updateProgress(currentProgress)

            resolvedAlpha = 1
        } else {
            resolvedAlpha = 0
        }

        logoContainerView.alpha = resolvedAlpha
        if isFireTab {
            logoContainerView.isUserInteractionEnabled = resolvedAlpha > 0
        }

        updateLogoYOffset()
    }

    private func updateLogoYOffset() {
        containerYCenterConstraint?.constant = escapeHatchBaseOffset + logoYOffset
    }
}

protocol DaxLogoViewSwitching: UIView {
    func updateProgress(_ progress: CGFloat)
}
