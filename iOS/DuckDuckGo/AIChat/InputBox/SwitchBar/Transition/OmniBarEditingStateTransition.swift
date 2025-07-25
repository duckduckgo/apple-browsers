//
//  OmniBarEditingStateTransition.swift
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

class OmniBarEditingStateTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPresenting: Bool

    init(isPresenting: Bool) {
        self.isPresenting = isPresenting
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        if isPresenting {
            return Constants.TopTransition.expandDuration
        } else {
            return Constants.TopTransition.collapseDuration
        }
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {

        transitionContext.containerView.backgroundColor = .clear

        if isPresenting {
            animateAppear(transitionContext: transitionContext)
        } else {
            animateDismiss(transitionContext: transitionContext)
        }
    }

    private func animateAppear(transitionContext: UIViewControllerContextTransitioning) {
        guard let fromVC = transitionContext.viewController(forKey: .from) as? (UIViewController & MainViewEditingStateTransitioning),
              let toVC = transitionContext.viewController(forKey: .to) as? (UIViewController & OmniBarEditingStateTransitioning) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView

        containerView.addSubview(toVC.view)

        let yOffset = toVC.switchBarVC.textEntryViewController.view.frame.minY

        toVC.view.frame = containerView.bounds.offsetBy(dx: 0, dy: -yOffset)
        toVC.view.alpha = 0
        toVC.switchBarVC.setExpanded(false)

        if let height = toVC.expectedStartFrame?.height {
            toVC.switchBarVC.textEntryViewController.containerStaticHeightConstraint?.constant = height
        }
        toVC.view.layoutIfNeeded()

        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext),
                                              dampingRatio: Constants.TopTransition.expandDampingRatio) {

            toVC.view.alpha = 1.0
            toVC.view.frame = containerView.bounds
            toVC.switchBarVC.setExpanded(true)
            toVC.view.layoutIfNeeded()

            fromVC.hide(with: yOffset)
            fromVC.view.layoutIfNeeded()
        }

        animator.addCompletion { position in
            transitionContext.completeTransition(position == .end)
        }

        animator.startAnimation()
    }

    private func animateDismiss(transitionContext: UIViewControllerContextTransitioning) {

        guard let fromVC = transitionContext.viewController(forKey: .from) as? (UIViewController & OmniBarEditingStateTransitioning),
              let toVC = transitionContext.viewController(forKey: .to) as? (UIViewController & MainViewEditingStateTransitioning) else {
            transitionContext.completeTransition(false)
            return
        }

        let yOffset = fromVC.switchBarVC.textEntryViewController.view.frame.minY

        // Dismissing animation
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext),
                                              dampingRatio: Constants.TopTransition.collapseDampingRatio) {

            fromVC.view.frame = fromVC.view.frame.offsetBy(dx: 0, dy: -yOffset)
            fromVC.switchBarVC.setExpanded(false)
            fromVC.view.layoutIfNeeded()

            fromVC.view.alpha = 0
            toVC.show()
            toVC.view.layoutIfNeeded()
        }

        animator.addCompletion { position in
            transitionContext.completeTransition(position == .end)
        }

        animator.startAnimation()
    }

    private struct Constants {
        struct BottomTransition {
            static let yOffset: CGFloat = 150
            static let finalYOffset: CGFloat = 16
            static let dismissDuration: TimeInterval = 0.25
            static let appearanceDuration: TimeInterval = 0.25
        }

        struct TopTransition {
            static let expandDuration: TimeInterval = 0.6
            static let expandDampingRatio: CGFloat = 0.65
            static let collapseDuration: TimeInterval = 0.5
            static let collapseDampingRatio: CGFloat = 0.7
        }
    }
}
