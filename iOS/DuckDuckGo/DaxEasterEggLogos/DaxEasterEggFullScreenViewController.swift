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

// MARK: - Layout Constants

private extension DaxEasterEggFullScreenViewController {
    /// Padding around safe area for full-screen logo display
    static let safeAreaPadding: CGFloat = 60.0
}

/// Full-screen viewer for Dax Easter Egg logos with custom transition support.
/// Displays logos in a centered, appropriately sized view with safe area padding.
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
        
        // Start with source image, load high-res after transition completes
        imageView.image = sourceImage
        imageView.alpha = 0
    }
    
    private func setupUI() {
        view.backgroundColor = .clear
        
        // Configure image view
        imageView.contentMode = .scaleAspectFit
        
        // Setup view hierarchy and constraints
        view.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        
        // Add padding around the safe area
        let padding = Self.safeAreaPadding
        
        NSLayoutConstraint.activate([
            // ImageView respects safe area with additional padding
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: padding),
            imageView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: padding),
            imageView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -padding),
            imageView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -padding)
        ])
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
    
    // MARK: - Transition Support
    
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
