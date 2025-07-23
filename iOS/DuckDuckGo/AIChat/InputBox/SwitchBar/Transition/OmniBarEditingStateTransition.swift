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
        Constants.TopTransition.expandDuration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromVC = transitionContext.viewController(forKey: .from),
              let toVC = transitionContext.viewController(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView

        if isPresenting {
            // Presenting animation
            containerView.addSubview(toVC.view)
            toVC.view.alpha = 0
            toVC.view.transform = CGAffineTransform(translationX: 0, y: -76)

            let animator = UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext),
                                   dampingRatio: 0.65) {
                toVC.view.alpha = 1
                toVC.view.transform = .identity
            }

            animator.addCompletion { position in
                transitionContext.completeTransition(position == .end)
            }

            animator.startAnimation()
        } else {
            // Dismissing animation
            UIView.animate(withDuration: transitionDuration(using: transitionContext)) {
                fromVC.view.alpha = 0
                fromVC.view.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            } completion: { finished in
                transitionContext.completeTransition(finished)
            }
        }
    }

    private struct Constants {
        struct BottomTransition {
            static let yOffset: CGFloat = 150
            static let finalYOffset: CGFloat = 16
            static let dismissDuration: TimeInterval = 0.25
            static let appearanceDuration: TimeInterval = 0.25
        }

        struct TopTransition {
            static let fadeInDuration: TimeInterval = 0.2
            static let expandDuration: TimeInterval = 0.6
            static let expandDampingRatio: CGFloat = 0.7
            static let collapseDuration: TimeInterval = 0.5
            static let collapseDampingRatio: CGFloat = 0.65
            static let fadeOutDuration: TimeInterval = 0.15
            static let fadeOutDelay: TimeInterval = collapseDuration * 0.35
        }
    }
}
