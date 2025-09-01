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
        
        let availableWidth = containerFrame.width - safeAreaInsets.left - safeAreaInsets.right - (safeAreaPadding * 2)
        let availableHeight = containerFrame.height - safeAreaInsets.top - safeAreaInsets.bottom - (safeAreaPadding * 2)
        
        // Convert image pixel dimensions to points with max 2x upscaling (balance of quality and visibility)
        let scale = UIScreen.main.scale
        let maxUpscaleFactor: CGFloat = 2.0
        let imageWidthInPoints = min(imageSize.width / scale * maxUpscaleFactor, imageSize.width)
        let imageHeightInPoints = min(imageSize.height / scale * maxUpscaleFactor, imageSize.height)
        
        // Don't scale beyond actual image size to prevent blurriness
        let maxWidth = min(availableWidth, imageWidthInPoints)
        let maxHeight = min(availableHeight, imageHeightInPoints)
        
        let imageAspectRatio = imageSize.width / imageSize.height
        
        let finalSize: CGSize
        if imageAspectRatio > maxWidth / maxHeight {
            finalSize = CGSize(width: maxWidth, height: maxWidth / imageAspectRatio)
        } else {
            finalSize = CGSize(width: maxHeight * imageAspectRatio, height: maxHeight)
        }
        
        // Ensure pixel-aligned positioning to prevent blur
        let x = round((containerFrame.midX - finalSize.width / 2) * scale) / scale
        let y = round((containerFrame.midY - finalSize.height / 2) * scale) / scale
        let width = round(finalSize.width * scale) / scale
        let height = round(finalSize.height * scale) / scale
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Full-screen viewer for Dax Easter Egg logos with custom transition support
class DaxEasterEggFullScreenViewController: UIViewController {
    
    private let imageView = UIImageView()
    private let closeButton = UIButton(type: .system)
    
    private let imageURL: URL?
    private let sourceFrame: CGRect
    private let sourceImage: UIImage?
    private weak var sourceViewController: OmniBarViewController?
    
    /// Initialize with image URL and transition parameters
    /// - Parameters:
    ///   - imageURL: URL to load high-res image from
    ///   - placeholderImage: Image to show during loading (unused - sourceImage preferred)
    ///   - sourceFrame: Original frame for transition animation
    ///   - sourceImage: Image to use for transition and fallback
    ///   - sourceViewController: The OmniBarViewController for getting current logo frame after rotation
    init(imageURL: URL?, placeholderImage: UIImage? = nil, sourceFrame: CGRect = .zero, sourceImage: UIImage? = nil, sourceViewController: OmniBarViewController? = nil) {
        self.imageURL = imageURL
        self.sourceFrame = sourceFrame
        self.sourceImage = sourceImage ?? placeholderImage
        self.sourceViewController = sourceViewController
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
        view.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        imageView.contentMode = .scaleAspectFit
        
        setupCloseButton()
        
        view.addSubview(imageView)
        view.addSubview(closeButton)
        
        imageView.translatesAutoresizingMaskIntoConstraints = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    private func setupCloseButton() {
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = .clear
        closeButton.layer.cornerRadius = 22
        closeButton.addTarget(self, action: #selector(dismissViewController), for: .touchUpInside)
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
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }
    
    @objc private func dismissViewController() {
        dismiss(animated: true)
    }
    
    /// Called by transition animator when animation completes - loads high-res image
    func transitionDidComplete() {
        imageView.alpha = 1
        if let imageURL = imageURL {
            imageView.kf.setImage(with: imageURL, placeholder: sourceImage) { [weak self] result in
                if case .success(let value) = result {
                    // Now we have the actual image with real dimensions
                    self?.adjustLayoutForActualImageSize(value.image.size)
                }
            }
        }
    }
    
    /// Returns current image for transition animation
    func getCurrentImage() -> UIImage? {
        imageView.image
    }
    
    /// Adjusts the layout to use the actual downloaded image size to prevent blurriness
    private func adjustLayoutForActualImageSize(_ actualImageSize: CGSize) {
        let newFrame = DaxEasterEggLayout.calculateLogoFrame(
            for: actualImageSize,
            in: view.bounds,
            safeAreaInsets: view.safeAreaInsets
        )
        
        // Only animate if the frame actually changed
        guard newFrame != imageView.frame else { return }
        
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) {
            self.imageView.frame = newFrame
        }
    }
    
}


// MARK: - UIViewControllerTransitioningDelegate
extension DaxEasterEggFullScreenViewController: UIViewControllerTransitioningDelegate {
    
    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        DaxEasterEggZoomTransitionAnimator(sourceFrame: sourceFrame, sourceImage: sourceImage, isPresenting: true)
    }
    
    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        // Get the current source frame in case device rotated while in full-screen
        let currentSourceFrame = getCurrentSourceFrame() ?? sourceFrame
        return DaxEasterEggZoomTransitionAnimator(sourceFrame: currentSourceFrame, sourceImage: sourceImage, isPresenting: false)
    }
    
    /// Get the current frame of the logo in the presenting view, accounting for rotation
    private func getCurrentSourceFrame() -> CGRect? {
        guard let sourceVC = sourceViewController else { return nil }
        return sourceVC.getCurrentLogoFrame()
    }
}
