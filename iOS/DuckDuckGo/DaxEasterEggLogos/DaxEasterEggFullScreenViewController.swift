//
//  DaxEasterEggFullScreenViewController.swift
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
import Kingfisher
import os.log

// MARK: - Layout Calculator

/// Utility for calculating DaxEasterEgg logo frames with consistent sizing across components
struct DaxEasterEggLayout {
    private static let safeAreaPadding: CGFloat = 60.0
    private static let logoSizeRatio: CGFloat = 0.4
    
    /// Calculate the frame for a logo constrained to 40% of screen size and safe area boundaries
    static func calculateLogoFrame(for imageSize: CGSize, in containerFrame: CGRect, safeAreaInsets: UIEdgeInsets) -> CGRect {
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return containerFrame
        }
        
        let screenSize = UIScreen.main.bounds.size
        let targetWidth = screenSize.width * logoSizeRatio
        let targetHeight = screenSize.height * logoSizeRatio
        
        let availableWidth = containerFrame.width - safeAreaInsets.left - safeAreaInsets.right - (safeAreaPadding * 2)
        let availableHeight = containerFrame.height - safeAreaInsets.top - safeAreaInsets.bottom - (safeAreaPadding * 2)
        
        let maxWidth = min(targetWidth, availableWidth)
        let maxHeight = min(targetHeight, availableHeight)
        
        let imageAspectRatio = imageSize.width / imageSize.height
        
        let finalSize: CGSize
        if imageAspectRatio > maxWidth / maxHeight {
            finalSize = CGSize(width: maxWidth, height: maxWidth / imageAspectRatio)
        } else {
            finalSize = CGSize(width: maxHeight * imageAspectRatio, height: maxHeight)
        }
        
        return CGRect(
            x: containerFrame.midX - finalSize.width / 2,
            y: containerFrame.midY - finalSize.height / 2,
            width: finalSize.width,
            height: finalSize.height
        )
    }
}

/// Full-screen viewer for Dax Easter Egg logos with custom transition support
class DaxEasterEggFullScreenViewController: UIViewController {
    
    private let imageView = UIImageView()
    
    private let imageURL: URL?
    private let sourceFrame: CGRect
    private let sourceImage: UIImage?
    
    /// Initialize with image URL and transition parameters
    /// - Parameters:
    ///   - imageURL: URL to load high-res image from
    ///   - placeholderImage: Image to show during loading (unused - sourceImage preferred)
    ///   - sourceFrame: Original frame for transition animation
    ///   - sourceImage: Image to use for transition and fallback
    init(imageURL: URL?, placeholderImage: UIImage? = nil, sourceFrame: CGRect = .zero, sourceImage: UIImage? = nil) {
        self.imageURL = imageURL
        self.sourceFrame = sourceFrame
        self.sourceImage = sourceImage ?? placeholderImage
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        transitioningDelegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupGestures()
        
        imageView.image = sourceImage
        imageView.alpha = 0
    }
    
    private func setupUI() {
        view.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        view.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = true
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let frame = DaxEasterEggLayout.calculateLogoFrame(
            for: sourceImage?.size ?? CGSize(width: 100, height: 100),
            in: view.bounds,
            safeAreaInsets: view.safeAreaInsets
        )
        imageView.frame = frame
    }
    
    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissViewController))
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc private func dismissViewController() {
        dismiss(animated: true)
    }
    
    /// Called by transition animator when animation completes - loads high-res image
    func transitionDidComplete() {
        imageView.alpha = 1
        if let imageURL = imageURL {
            imageView.kf.setImage(with: imageURL, placeholder: sourceImage)
        }
    }
    
    /// Returns current image for transition animation
    func getCurrentImage() -> UIImage? {
        imageView.image
    }
    
}


// MARK: - UIViewControllerTransitioningDelegate
extension DaxEasterEggFullScreenViewController: UIViewControllerTransitioningDelegate {
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        DaxEasterEggZoomTransitionAnimator(sourceFrame: sourceFrame, sourceImage: sourceImage, isPresenting: true)
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        DaxEasterEggZoomTransitionAnimator(sourceFrame: sourceFrame, sourceImage: sourceImage, isPresenting: false)
    }
}
