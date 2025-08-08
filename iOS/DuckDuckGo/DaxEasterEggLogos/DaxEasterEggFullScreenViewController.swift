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

/// Full-screen viewer for Dax Easter Egg logos with zoom and custom transition support.
/// Provides smooth zoom animations and pinch-to-zoom functionality.
class DaxEasterEggFullScreenViewController: UIViewController {
    
    private let scrollView = UIScrollView()
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
        
        // Configure scroll view for zoom (1x-3x)
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 3.0
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        
        // Configure image view
        imageView.contentMode = .scaleAspectFit
        
        // Setup view hierarchy and constraints
        view.addSubview(scrollView)
        scrollView.addSubview(imageView)
        
        [scrollView, imageView].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        
        NSLayoutConstraint.activate([
            // ScrollView fills entire view
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // ImageView fills scrollView
            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
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
    
    /// Returns current image frame adjusted for zoom and scroll offset
    func getCurrentImageFrame() -> CGRect {
        let zoomScale = scrollView.zoomScale
        let adjustedFrame = CGRect(
            x: (imageView.frame.origin.x - scrollView.contentOffset.x) / zoomScale,
            y: (imageView.frame.origin.y - scrollView.contentOffset.y) / zoomScale,
            width: imageView.frame.width / zoomScale,
            height: imageView.frame.height / zoomScale
        )
        return scrollView.convert(adjustedFrame, to: view)
    }
}

// MARK: - UIScrollViewDelegate
extension DaxEasterEggFullScreenViewController: UIScrollViewDelegate {
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerImageViewInScrollView()
    }
    
    /// Centers the image view when it's smaller than the scroll view bounds
    private func centerImageViewInScrollView() {
        let boundsSize = scrollView.bounds.size
        var frameToCenter = imageView.frame
        
        // Center horizontally if image is narrower than bounds
        frameToCenter.origin.x = frameToCenter.size.width < boundsSize.width
            ? (boundsSize.width - frameToCenter.size.width) / 2
            : 0
        
        // Center vertically if image is shorter than bounds
        frameToCenter.origin.y = frameToCenter.size.height < boundsSize.height
            ? (boundsSize.height - frameToCenter.size.height) / 2
            : 0
        
        imageView.frame = frameToCenter
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
