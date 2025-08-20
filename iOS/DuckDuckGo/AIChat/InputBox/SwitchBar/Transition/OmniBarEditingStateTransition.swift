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

final class OmniBarEditingStateTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPresenting: Bool
    private let isTopBarPosition: Bool

    private struct TransitionOffsets {
        let switcherYOffset: CGFloat
        let contentYOffset: CGFloat
        let barYOffset: CGFloat
        let logoYOffset: CGFloat
    }

    private func calculateOffsets(switchBarTextViewMinY: CGFloat) -> TransitionOffsets {
        let switcherMultiplier: CGFloat = isTopBarPosition ? 1 : -1

        let switcherYOffset = switchBarTextViewMinY * switcherMultiplier

        let contentYOffset: CGFloat = switchBarTextViewMinY * switcherMultiplier

        let barYOffset: CGFloat = isTopBarPosition ? switchBarTextViewMinY : 0

        let baseLogoOffset: CGFloat = isTopBarPosition ? 0 : -(DefaultOmniBarView.expectedHeight + Constants.toolbarHeight)
        let logoYOffsetWithSwitcher = baseLogoOffset + switcherYOffset

        return TransitionOffsets(
            switcherYOffset: switcherYOffset,
            contentYOffset: contentYOffset,
            barYOffset: barYOffset,
            logoYOffset: logoYOffsetWithSwitcher
        )
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
            animateAppear(transitionContext: transitionContext)
        } else {
            animateDismiss(transitionContext: transitionContext)
        }
    }

    private var dampingRatio: CGFloat {
        if isPresenting {
            return isTopBarPosition ? Constants.TopTransition.expandDampingRatio : Constants.BottomTransition.expandDampingRatio
        } else {
            return isTopBarPosition ? Constants.TopTransition.collapseDampingRatio : Constants.BottomTransition.collapseDampingRatio
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

        let switchBarTextViewMinY = toVC.switchBarVC.textEntryViewController.view.frame.minY
        let offsets = calculateOffsets(switchBarTextViewMinY: switchBarTextViewMinY)

        toVC.view.layer.sublayerTransform = CATransform3DMakeTranslation(0, -offsets.switcherYOffset, 0)
        toVC.view.alpha = 0
        toVC.actionBarView?.alpha = 0
        toVC.switchBarVC.textEntryViewController.isExpandable = false
        toVC.setLogoYOffset(offsets.logoYOffset)

        toVC.view.layoutIfNeeded()

        let duration = transitionDuration(using: transitionContext)
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: dampingRatio) {

            toVC.view.alpha = 1.0
            toVC.view.layer.sublayerTransform = CATransform3DIdentity
            toVC.switchBarVC.textEntryViewController.isExpandable = true
            toVC.setLogoYOffset(0)
            toVC.view.layoutIfNeeded()

            fromVC.hide(with: offsets.barYOffset, contentYOffset: offsets.contentYOffset)
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

    private func animateDismiss(transitionContext: UIViewControllerContextTransitioning) {

        guard let fromVC = transitionContext.viewController(forKey: .from) as? (UIViewController & OmniBarEditingStateTransitioning),
              let toVC = transitionContext.viewController(forKey: .to) as? (UIViewController & MainViewEditingStateTransitioning) else {
            transitionContext.completeTransition(false)
            return
        }

        let switchBarTextViewMinY = fromVC.switchBarVC.textEntryViewController.view.frame.minY
        let offsets = calculateOffsets(switchBarTextViewMinY: switchBarTextViewMinY)

        // Dismissing animation
        let duration = transitionDuration(using: transitionContext)
        let animator = UIViewPropertyAnimator(duration: duration, dampingRatio: dampingRatio) {

            fromVC.view.layer.sublayerTransform = CATransform3DMakeTranslation(0, -offsets.switcherYOffset, 0)
            fromVC.switchBarVC.textEntryViewController.isExpandable = false
            fromVC.setLogoYOffset(offsets.logoYOffset)
            fromVC.view.alpha = 0
            fromVC.view.layoutIfNeeded()

            toVC.show()
            toVC.view.layoutIfNeeded()
        }

        animator.addCompletion { position in
            transitionContext.completeTransition(position == .end)
        }

        let actionBarAnimator = UIViewPropertyAnimator(duration: duration / 3.0, curve: .easeIn) {
            fromVC.actionBarView?.alpha = 0
        }

        actionBarAnimator.startAnimation()
        animator.startAnimation()
    }

    private struct Constants {
        static let expandDuration: TimeInterval = 0.6
        static let collapseDuration: TimeInterval = 0.5
        static let toolbarHeight: CGFloat = 49

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
