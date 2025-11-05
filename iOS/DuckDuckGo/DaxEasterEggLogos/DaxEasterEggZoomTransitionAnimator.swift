//
//  DaxEasterEggZoomTransitionAnimator.swift
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

// MARK: - Animation Constants

private extension DaxEasterEggZoomTransitionAnimator {
    /// Duration for zoom transition animations
    static let animationDuration: TimeInterval = 0.4
    /// Padding around safe area for full-screen logo display
    static let safeAreaPadding: CGFloat = 60.0
}

import UIKit

/// Custom transition animator for Dax Easter Egg logo zoom animations.
/// Provides smooth spring-damped transitions between omnibar logo and full-screen view.
class DaxEasterEggZoomTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    
    private let sourceFrame: CGRect
    private let sourceImage: UIImage?
    private let isPresenting: Bool
    
    init(sourceFrame: CGRect, sourceImage: UIImage?, isPresenting: Bool) {
        self.sourceFrame = sourceFrame
        self.sourceImage = sourceImage
        self.isPresenting = isPresenting
        super.init()
    }
    
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        return Self.animationDuration
    }
    
    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        if isPresenting {
            animatePresentation(using: transitionContext)
        } else {
            animateDismissal(using: transitionContext)
        }
    }
    
    private func animatePresentation(using transitionContext: UIViewControllerContextTransitioning) {
        guard let toViewController = transitionContext.viewController(forKey: .to) as? DaxEasterEggFullScreenViewController else {
            transitionContext.completeTransition(false)
            return
        }
        
        let containerView = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: toViewController)
        
        // Add the destination view controller's view
        toViewController.view.frame = finalFrame
        toViewController.view.alpha = 0
        
        // Ensure container view also has clear background for the transition
        containerView.backgroundColor = .clear
        containerView.addSubview(toViewController.view)
        
        // Create a temporary image view for animation with better quality
        let tempImageView = UIImageView(image: sourceImage)
        tempImageView.contentMode = .scaleAspectFit
        tempImageView.frame = sourceFrame
        tempImageView.clipsToBounds = true
        tempImageView.layer.minificationFilter = .trilinear
        tempImageView.layer.magnificationFilter = .trilinear
        containerView.addSubview(tempImageView)
        
        let finalImageFrame = DaxEasterEggLayout.calculateLogoFrame(
            for: sourceImage?.size ?? CGSize(width: 100, height: 100),
            in: finalFrame,
            safeAreaInsets: toViewController.view.safeAreaInsets
        )
        
        // Animate the transition using spring with high damping to prevent overshoot
        UIView.animate(withDuration: Self.animationDuration, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
            tempImageView.frame = finalImageFrame
            toViewController.view.alpha = 1
        } completion: { _ in
            tempImageView.removeFromSuperview()
            // Notify the view controller that transition is complete so it can load the full-res image
            toViewController.transitionDidComplete()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
    
    private func animateDismissal(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromViewController = transitionContext.viewController(forKey: .from) as? DaxEasterEggFullScreenViewController else {
            transitionContext.completeTransition(false)
            return
        }
        
        let containerView = transitionContext.containerView
        let finalFrame = transitionContext.finalFrame(for: fromViewController)
        
        // Get the current image from the full-screen view controller
        let currentImage = fromViewController.getCurrentImage()
        
        let calculatedImageFrame = DaxEasterEggLayout.calculateLogoFrame(
            for: currentImage?.size ?? CGSize(width: 100, height: 100),
            in: finalFrame,
            safeAreaInsets: fromViewController.view.safeAreaInsets
        )
        
        // Create a temporary image view for animation, starting from the calculated frame
        let tempImageView = UIImageView(image: currentImage)
        tempImageView.contentMode = .scaleAspectFit
        tempImageView.frame = calculatedImageFrame
        tempImageView.clipsToBounds = true
        containerView.addSubview(tempImageView)
        
        // Hide the original view
        fromViewController.view.alpha = 0
        
        // Animate back to source frame using spring with high damping to prevent overshoot
        UIView.animate(withDuration: Self.animationDuration, delay: 0, usingSpringWithDamping: 1.0, initialSpringVelocity: 0, options: [.curveEaseInOut]) {
            tempImageView.frame = self.sourceFrame
        } completion: { _ in
            tempImageView.removeFromSuperview()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
    
    private func calculateAdjustedFrame(for viewFrame: CGRect, viewController: UIViewController) -> CGRect {
        let safeAreaInsets = viewController.view.safeAreaInsets
        let padding = Self.safeAreaPadding
        
        // Calculate the available frame within safe area + padding
        return CGRect(
            x: viewFrame.origin.x + safeAreaInsets.left + padding,
            y: viewFrame.origin.y + safeAreaInsets.top + padding,
            width: viewFrame.width - safeAreaInsets.left - safeAreaInsets.right - (padding * 2),
            height: viewFrame.height - safeAreaInsets.top - safeAreaInsets.bottom - (padding * 2)
        )
    }
    
}
