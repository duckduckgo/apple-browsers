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
}

class OmniBarEditingStateAnimator {

    weak var transitionDelegate: OmniBarEditingStateTransitionDelegate?

    private var topSwitchBarConstraint: NSLayoutConstraint?

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
            let heightConstraint = transitionDelegate.switchBarVC.view.heightAnchor.constraint(equalToConstant: expectedStartFrame.height)
            heightConstraint.isActive = true
            topPositionAppearance(expectedStartFrame: expectedStartFrame, heightConstraint: heightConstraint)
        } else {
            bottomPositionAppearance()
        }

    }

    private func topPositionAppearance(expectedStartFrame: CGRect, heightConstraint: NSLayoutConstraint) {

        guard let transitionDelegate else { return }

        topSwitchBarConstraint = transitionDelegate.switchBarVC.view.topAnchor.constraint(equalTo: transitionDelegate.rootView.topAnchor, constant: expectedStartFrame.minY)
        topSwitchBarConstraint?.isActive = true
        transitionDelegate.switchBarVC.setExpanded(false)
        transitionDelegate.switchBarVC.view.alpha = 0.0
        transitionDelegate.rootView.alpha = 0.0
        transitionDelegate.rootView.backgroundColor = .clear

        transitionDelegate.rootView.layoutIfNeeded()

        // Create animators
        let fadeAnimatorDuration = 0.2
        let backgroundFadeAnimator = UIViewPropertyAnimator(duration: fadeAnimatorDuration, curve: .easeIn) {
            transitionDelegate.switchBarVC.view.alpha = 1.0
            transitionDelegate.rootView.alpha = 1.0
            transitionDelegate.rootView.backgroundColor = UIColor(designSystemColor: .background)
        }

        let expandAnimator = UIViewPropertyAnimator(duration: 0.55, dampingRatio: 0.65) {
            transitionDelegate.switchBarVC.setExpanded(true)
            heightConstraint.isActive = false

            transitionDelegate.rootView.layoutIfNeeded()
        }

        // Schedule animations
        backgroundFadeAnimator.addCompletion { _ in
            transitionDelegate.switchBarVC.focusTextField()
            expandAnimator.startAnimation()
        }

        // Start animations
        backgroundFadeAnimator.startAnimation()
    }

    private func bottomPositionAppearance() {

        guard let transitionDelegate else { return }

        topSwitchBarConstraint = transitionDelegate.switchBarVC.view.topAnchor.constraint(equalTo: transitionDelegate.rootView.safeAreaLayoutGuide.topAnchor, constant: 80)
        topSwitchBarConstraint?.isActive = true
        transitionDelegate.switchBarVC.setExpanded(true)
        transitionDelegate.switchBarVC.view.alpha = 0.0

        transitionDelegate.rootView.layoutIfNeeded()

        // Create animators
        let animator = UIViewPropertyAnimator(duration: 0.3, dampingRatio: 0.75) {
            transitionDelegate.rootView.backgroundColor = UIColor(designSystemColor: .background)
            transitionDelegate.switchBarVC.view.alpha = 1.0
            self.topSwitchBarConstraint?.constant = 20

            transitionDelegate.rootView.layoutIfNeeded()
        }

        // Schedule animations
        animator.addCompletion { _ in
            transitionDelegate.switchBarVC.focusTextField()
        }

        // Start animations
        animator.startAnimation()
    }

    private func topPositionDismissal(_ completion: (() -> Void)?) {

        guard let transitionDelegate else { return }

        // Create animators
        let collapseDuration: TimeInterval = 0.3
        let collapseAnimator = UIViewPropertyAnimator(duration: collapseDuration, dampingRatio: 0.7) {
            transitionDelegate.switchBarVC.setExpanded(false)
            if let expectedStartFrame = transitionDelegate.expectedStartFrame {
                let heightConstraint = transitionDelegate.switchBarVC.view.heightAnchor.constraint(equalToConstant: expectedStartFrame.height)
                heightConstraint.isActive = true
            }

            transitionDelegate.rootView.layoutIfNeeded()
        }

        let backgroundFadeAnimator = UIViewPropertyAnimator(duration: 0.15, curve: .easeIn) {
            transitionDelegate.rootView.alpha = 0.0
            transitionDelegate.switchBarVC.view.alpha = 0.0
        }

        backgroundFadeAnimator.addCompletion { _ in
            completion?()
        }

        // Start animations
        collapseAnimator.startAnimation()
        backgroundFadeAnimator.startAnimation(afterDelay: collapseDuration * 0.6)
    }

    private func bottomPositionDismissal(_ completion: (() -> Void)?) {

        guard let transitionDelegate else { return }

        let animator = UIViewPropertyAnimator(duration: 0.25, curve: .easeInOut) {
            transitionDelegate.rootView.backgroundColor = .clear
            transitionDelegate.switchBarVC.view.alpha = 0.0
            self.topSwitchBarConstraint?.constant = 80

            transitionDelegate.rootView.layoutIfNeeded()
        }

        animator.addCompletion { _ in
            completion?()
        }

        animator.startAnimation()
    }
}
