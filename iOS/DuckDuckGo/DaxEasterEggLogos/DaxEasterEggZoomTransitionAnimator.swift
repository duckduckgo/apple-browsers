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

import UIKit

/// Custom transition animator for Dax Easter Egg logo zoom animations.
/// Provides smooth spring-damped transitions between omnibar logo and full-screen view.
class DaxEasterEggZoomTransitionAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    
    private let duration: TimeInterval = 0.4
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
        return duration
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
        
        // Add the destination view controller's view with clear background
        toViewController.view.frame = finalFrame
        toViewController.view.alpha = 0
        toViewController.view.backgroundColor = .clear
        
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
        
        // Calculate the final frame for the image (centered and scaled to fit)
        let finalImageFrame = calculateFinalImageFrame(for: finalFrame, imageSize: sourceImage?.size ?? CGSize(width: 100, height: 100))
        
        // Animate the transition
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
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
        
        // Get the current image from the full-screen view controller
        let currentImage = fromViewController.getCurrentImage()
        let currentImageFrame = fromViewController.getCurrentImageFrame()
        
        // Create a temporary image view for animation
        let tempImageView = UIImageView(image: currentImage)
        tempImageView.contentMode = .scaleAspectFit
        tempImageView.frame = currentImageFrame
        tempImageView.clipsToBounds = true
        containerView.addSubview(tempImageView)
        
        // Hide the original view
        fromViewController.view.alpha = 0
        
        // Animate back to exact source frame - no aspect ratio calculation needed
        // since the display image is already properly sized to match the original
        UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.curveEaseInOut]) {
            tempImageView.frame = self.sourceFrame
        } completion: { _ in
            tempImageView.removeFromSuperview()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
    
    private func calculateFinalImageFrame(for containerFrame: CGRect, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return containerFrame
        }
        
        let containerAspectRatio = containerFrame.width / containerFrame.height
        let imageAspectRatio = imageSize.width / imageSize.height
        
        let finalSize: CGSize
        if imageAspectRatio > containerAspectRatio {
            // Image is wider than container
            finalSize = CGSize(width: containerFrame.width, height: containerFrame.width / imageAspectRatio)
        } else {
            // Image is taller than container
            finalSize = CGSize(width: containerFrame.height * imageAspectRatio, height: containerFrame.height)
        }
        
        let finalOrigin = CGPoint(
            x: containerFrame.midX - finalSize.width / 2,
            y: containerFrame.midY - finalSize.height / 2
        )
        
        return CGRect(origin: finalOrigin, size: finalSize)
    }
}
