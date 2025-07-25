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
    private let isTopBarPosition: Bool

    private var yOffsetFactor: CGFloat {
        // We want bigger offset and move upwards while transitioning from bottom
        isTopBarPosition ? 1 : -2
    }

    init(isPresenting: Bool, addressBarPosition: AddressBarPosition) {
        self.isPresenting = isPresenting
        self.isTopBarPosition = addressBarPosition == .top
        super.init()
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        if isPresenting {
            return Constants.expandDuration
        } else {
            return Constants.collapseDuration
        }
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {

        transitionContext.containerView.backgroundColor = .clear

        if isPresenting {
            animateAppear(transitionContext: transitionContext, isTopBarPosition: isTopBarPosition)
        } else {
            animateDismiss(transitionContext: transitionContext, isTopBarPosition: isTopBarPosition)
        }
    }

    private func dampingRatio() -> CGFloat {
        if isPresenting {
            return isTopBarPosition ? Constants.TopTransition.expandDampingRatio : Constants.BottomTransition.expandDampingRatio
        } else {
            return isTopBarPosition ? Constants.TopTransition.collapseDampingRatio : Constants.BottomTransition.collapseDampingRatio
        }
    }

    private func animateAppear(transitionContext: UIViewControllerContextTransitioning, isTopBarPosition: Bool) {
        guard let fromVC = transitionContext.viewController(forKey: .from) as? (UIViewController & MainViewEditingStateTransitioning),
              let toVC = transitionContext.viewController(forKey: .to) as? (UIViewController & OmniBarEditingStateTransitioning) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView

        containerView.addSubview(toVC.view)

        let yOffset = toVC.switchBarVC.textEntryViewController.view.frame.minY * yOffsetFactor

        toVC.view.frame = containerView.bounds.offsetBy(dx: 0, dy: -yOffset)
        toVC.view.alpha = 0
        toVC.actionBarView?.alpha = 0
        toVC.switchBarVC.textEntryViewController.isExpandable = false

        toVC.view.layoutIfNeeded()

        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext),
                                              dampingRatio: dampingRatio()) {

            toVC.view.alpha = 1.0
            toVC.view.frame = containerView.bounds
            toVC.switchBarVC.textEntryViewController.isExpandable = true
            toVC.view.layoutIfNeeded()

            // Move source content only half way when transitioning from bottom position
            fromVC.hide(with: isTopBarPosition ? yOffset : yOffset/2)
            fromVC.view.layoutIfNeeded()
        }

        animator.addAnimations({
            toVC.actionBarView?.alpha = 1
        }, delayFactor: 0.3)

        animator.addCompletion { position in
            transitionContext.completeTransition(position == .end)
        }

        animator.startAnimation()
    }

    private func animateDismiss(transitionContext: UIViewControllerContextTransitioning, isTopBarPosition: Bool) {

        guard let fromVC = transitionContext.viewController(forKey: .from) as? (UIViewController & OmniBarEditingStateTransitioning),
              let toVC = transitionContext.viewController(forKey: .to) as? (UIViewController & MainViewEditingStateTransitioning) else {
            transitionContext.completeTransition(false)
            return
        }

        let yOffset = fromVC.switchBarVC.textEntryViewController.view.frame.minY * yOffsetFactor

        // Dismissing animation
        let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext),
                                              dampingRatio: dampingRatio()) {

            fromVC.view.frame = fromVC.view.frame.offsetBy(dx: 0, dy: -yOffset)
            fromVC.switchBarVC.textEntryViewController.isExpandable = false
            fromVC.view.alpha = 0
            fromVC.view.layoutIfNeeded()

            toVC.show()
            toVC.view.layoutIfNeeded()
        }

        animator.addCompletion { position in
            transitionContext.completeTransition(position == .end)
        }

        let actionBarAnimator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext) / 3.0, curve: .easeIn) {
            fromVC.actionBarView?.alpha = 0
        }

        actionBarAnimator.startAnimation()
        animator.startAnimation()
    }

    private struct Constants {
        static let expandDuration: TimeInterval = 0.6
        static let collapseDuration: TimeInterval = 0.5

        struct BottomTransition {
            static let collapseDampingRatio: CGFloat = 0.75
            static let expandDampingRatio: CGFloat = 0.7
        }

        struct TopTransition {
            static let expandDampingRatio: CGFloat = 0.65
            static let collapseDampingRatio: CGFloat = 0.7
        }
    }
}
