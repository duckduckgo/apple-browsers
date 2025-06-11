//
//  OmniBarTransition.swift
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

protocol OmniBarTransitionProxy {
    var fieldContainerLayoutGuide: UILayoutGuide { get }
}

class OmniBarTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let sourceGuide: UILayoutGuide
    private let targetGuide: UILayoutGuide
    private let containerView: UIView
    
    init(sourceGuide: UILayoutGuide, targetGuide: UILayoutGuide, containerView: UIView) {
        self.sourceGuide = sourceGuide
        self.targetGuide = targetGuide
        self.containerView = containerView
        super.init()
    }
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return 0.5
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let toVC = transitionContext.viewController(forKey: .to) else { return }
        
        let containerView = transitionContext.containerView
        let toView = toVC.view!
        
        // Add the target view controller's view to the container
        containerView.addSubview(toView)
        toView.alpha = 0
        
        // Create a snapshot of the source view
        let sourceFrame = sourceGuide.layoutFrame
        let sourceSnapshot = UIView(frame: sourceFrame)
        sourceSnapshot.backgroundColor = .clear
        containerView.addSubview(sourceSnapshot)
        
        // Set up initial constraints
        NSLayoutConstraint.activate([
            sourceGuide.topAnchor.constraint(equalTo: targetGuide.topAnchor),
            sourceGuide.leadingAnchor.constraint(equalTo: targetGuide.leadingAnchor),
            sourceGuide.trailingAnchor.constraint(equalTo: targetGuide.trailingAnchor)
        ])
        
        // Force layout to get the final frame
        containerView.layoutIfNeeded()
        
        // Animate the transition
        UIViewPropertyAnimator(duration: transitionDuration(using: transitionContext), dampingRatio: 0.8) {
            toView.alpha = 1
            sourceSnapshot.frame = self.targetGuide.layoutFrame
        }.startAnimation()
        
        // Clean up and complete the transition
        UIView.animate(withDuration: 0.3, delay: 0.2) {
            sourceSnapshot.alpha = 0
        } completion: { _ in
            sourceSnapshot.removeFromSuperview()
            transitionContext.completeTransition(true)
        }
    }
}

extension UIViewController {
    func presentWithOmniBarTransition(_ viewController: UIViewController, from sourceGuide: UILayoutGuide, to targetGuide: UILayoutGuide) {
        viewController.modalPresentationStyle = .overFullScreen
        viewController.transitioningDelegate = self
        
        let transition = OmniBarTransition(sourceGuide: sourceGuide, targetGuide: targetGuide, containerView: view)
        self.present(viewController, animated: true)
    }
}

extension UIViewController: UIViewControllerTransitioningDelegate {
    public func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        guard let sourceVC = source as? OmniBarTransitionProxy,
              let targetVC = presented as? OmniBarTransitionProxy else {
            return nil
        }
        
        return OmniBarTransition(
            sourceGuide: sourceVC.fieldContainerLayoutGuide,
            targetGuide: targetVC.fieldContainerLayoutGuide,
            containerView: view
        )
    }
}
