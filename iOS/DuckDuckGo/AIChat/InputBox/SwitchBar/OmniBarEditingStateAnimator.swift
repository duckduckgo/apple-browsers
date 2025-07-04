//
//  OmniBarEditingStateAnimator.swift
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

protocol OmniBarEditingStateTransitionDelegate: AnyObject {
    var rootView: UIView { get }
    var expectedStartFrame: CGRect? { get }
    var isTopBarPosition: Bool { get }
    var switchBarVC: SwitchBarViewController { get }
    var logoView: UIView? { get }
}

final class OmniBarEditingStateAnimator {

    weak var transitionDelegate: OmniBarEditingStateTransitionDelegate?

    private var topSwitchBarConstraint: NSLayoutConstraint?
    private var switchBarHeightConstraint: NSLayoutConstraint?

    func animateDismissal(_ completion: (() -> Void)? = nil) {

        guard let transitionDelegate else {
            completion?()
            return
        }

        transitionDelegate.rootView.layoutIfNeeded()

        if transitionDelegate.isTopBarPosition {
            topPositionDismissal(completion)
        } else {
            bottomPositionDismissal(completion)
        }
    }

    func animateAppearance() {
        guard let transitionDelegate else { return }

        guard let expectedStartFrame = transitionDelegate.expectedStartFrame else {
            transitionDelegate.switchBarVC.setExpanded(true)
            return
        }

        if transitionDelegate.isTopBarPosition {
            switchBarHeightConstraint = transitionDelegate.switchBarVC.view.heightAnchor.constraint(equalToConstant: expectedStartFrame.height)
            switchBarHeightConstraint?.isActive = true
            topPositionAppearance(expectedStartFrame: expectedStartFrame)
        } else {
            bottomPositionAppearance()
        }

    }

    private func topPositionAppearance(expectedStartFrame: CGRect) {

        guard let transitionDelegate else { return }

        topSwitchBarConstraint = transitionDelegate.switchBarVC.view.topAnchor.constraint(equalTo: transitionDelegate.rootView.topAnchor,
                                                                                          constant: expectedStartFrame.minY)
        topSwitchBarConstraint?.isActive = true
        transitionDelegate.switchBarVC.setExpanded(false)
        transitionDelegate.switchBarVC.view.alpha = 0.0
        transitionDelegate.rootView.alpha = 0.0
        transitionDelegate.rootView.backgroundColor = .clear

        transitionDelegate.rootView.layoutIfNeeded()

        // Create animators
        let backgroundFadeAnimator = UIViewPropertyAnimator(duration: Constants.TopTransition.fadeInDuration, curve: .easeIn) {
            transitionDelegate.switchBarVC.view.alpha = 1.0
            transitionDelegate.rootView.alpha = 1.0
            transitionDelegate.rootView.backgroundColor = UIColor(designSystemColor: .background)
        }

        let expandAnimator = UIViewPropertyAnimator(duration: Constants.TopTransition.expandDuration,
                                                    dampingRatio: Constants.TopTransition.expandDampingRatio) {
            transitionDelegate.switchBarVC.setExpanded(true)
            self.switchBarHeightConstraint?.isActive = false

            transitionDelegate.rootView.layoutIfNeeded()
        }

        // Schedule animations
        backgroundFadeAnimator.addCompletion { _ in
            expandAnimator.startAnimation()
        }

        // Start animations
        backgroundFadeAnimator.startAnimation()
    }

    private func topPositionDismissal(_ completion: (() -> Void)?) {

        guard let transitionDelegate else { return }

        // Create animators
        let collapseAnimator = UIViewPropertyAnimator(duration: Constants.TopTransition.collapseDuration,
                                                      dampingRatio: Constants.TopTransition.collapseDampingRatio) {
            transitionDelegate.switchBarVC.setExpanded(false)
            self.switchBarHeightConstraint?.isActive = true
            
            transitionDelegate.switchBarVC.view.alpha = 0.5
            transitionDelegate.logoView?.alpha = 0.5

            transitionDelegate.rootView.layoutIfNeeded()
        }

        let backgroundFadeAnimator = UIViewPropertyAnimator(duration: Constants.TopTransition.fadeOutDuration, curve: .easeIn) {
            transitionDelegate.rootView.alpha = 0.0
            transitionDelegate.switchBarVC.view.alpha = 0.0
        }

        backgroundFadeAnimator.addCompletion { _ in
            completion?()
        }

        // Start animations
        collapseAnimator.startAnimation()
        backgroundFadeAnimator.startAnimation(afterDelay: Constants.TopTransition.fadeOutDelay)
    }

    private func bottomPositionAppearance() {

        guard let transitionDelegate else { return }

        topSwitchBarConstraint = transitionDelegate.switchBarVC.view.topAnchor.constraint(equalTo: transitionDelegate.rootView.safeAreaLayoutGuide.topAnchor,
                                                                                          constant: Constants.BottomTransition.yOffset)
        topSwitchBarConstraint?.isActive = true
        transitionDelegate.switchBarVC.setExpanded(true)
        transitionDelegate.rootView.alpha = 0.0

        transitionDelegate.rootView.layoutIfNeeded()

        // Create animators
        let animator = UIViewPropertyAnimator(duration: Constants.BottomTransition.appearanceDuration,
                                              dampingRatio: Constants.BottomTransition.appearanceDampingRatio) {
            transitionDelegate.rootView.alpha = 1.0
            self.topSwitchBarConstraint?.constant = Constants.BottomTransition.finalYOffset

            transitionDelegate.rootView.layoutIfNeeded()
        }

        // Start animations
        animator.startAnimation()
    }

    private func bottomPositionDismissal(_ completion: (() -> Void)?) {

        guard let transitionDelegate else { return }

        let animator = UIViewPropertyAnimator(duration: Constants.BottomTransition.dismissDuration, curve: .easeInOut) {
            self.topSwitchBarConstraint?.constant = Constants.BottomTransition.yOffset

            transitionDelegate.rootView.layoutIfNeeded()
        }

        animator.addAnimations({
            transitionDelegate.rootView.alpha = 0.0
        }, delayFactor: 0.5)

        animator.addCompletion { _ in
            completion?()
        }

        animator.startAnimation()
    }

    private struct Constants {
        struct BottomTransition {
            static let yOffset: CGFloat = 150
            static let finalYOffset: CGFloat = 16
            static let dismissDuration: TimeInterval = 0.25
            static let appearanceDuration: TimeInterval = 0.55
            static let appearanceDampingRatio: CGFloat = 0.65
        }

        struct TopTransition {
            static let fadeInDuration: TimeInterval = 0.2
            static let expandDuration: TimeInterval = 0.55
            static let expandDampingRatio: CGFloat = 0.65
            static let collapseDuration: TimeInterval = 0.4
            static let collapseDampingRatio: CGFloat = 0.7
            static let fadeOutDuration: TimeInterval = 0.15
            static let fadeOutDelay: TimeInterval = collapseDuration * 0.65
        }
    }
}
