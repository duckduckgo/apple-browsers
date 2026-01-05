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
import Core
import DesignResourcesKit
import PrivacyConfig
import os.log

/// Utility for calculating DaxEasterEgg logo frames with consistent sizing across components.
struct DaxEasterEggLayout {
    private static let safeAreaPadding: CGFloat = 60.0

    /// Calculate the frame for a logo constrained within safe area boundaries.
    static func calculateLogoFrame(for imageSize: CGSize, in containerFrame: CGRect, safeAreaInsets: UIEdgeInsets) -> CGRect {
        guard imageSize.width > 0 && imageSize.height > 0 else {
            return containerFrame
        }

        let availableWidth = containerFrame.width - safeAreaInsets.left - safeAreaInsets.right - (safeAreaPadding * 2)
        let availableHeight = containerFrame.height - safeAreaInsets.top - safeAreaInsets.bottom - (safeAreaPadding * 2)

        let scale = UIScreen.main.scale
        let maxUpscaleFactor: CGFloat = 2.0
        let imageWidthInPoints = min(imageSize.width / scale * maxUpscaleFactor, imageSize.width)
        let imageHeightInPoints = min(imageSize.height / scale * maxUpscaleFactor, imageSize.height)

        let maxWidth = min(availableWidth, imageWidthInPoints)
        let maxHeight = min(availableHeight, imageHeightInPoints)

        let imageAspectRatio = imageSize.width / imageSize.height

        let finalSize: CGSize
        if imageAspectRatio > maxWidth / maxHeight {
            finalSize = CGSize(width: maxWidth, height: maxWidth / imageAspectRatio)
        } else {
            finalSize = CGSize(width: maxHeight * imageAspectRatio, height: maxHeight)
        }

        let x = round((containerFrame.midX - finalSize.width / 2) * scale) / scale
        let y = round((containerFrame.midY - finalSize.height / 2) * scale) / scale
        let width = round(finalSize.width * scale) / scale
        let height = round(finalSize.height * scale) / scale

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

/// Full-screen viewer for Dax Easter Egg logos with custom transition support.
class DaxEasterEggFullScreenViewController: UIViewController {

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let setAsLogoButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)

    private let imageURL: URL?
    private let sourceFrame: CGRect
    private let sourceImage: UIImage?
    private weak var sourceViewController: OmniBarViewController?
    private let logoStore: DaxEasterEggLogoStoring
    private let featureFlagger: FeatureFlagger
    private var actualImageSize: CGSize?

    init(imageURL: URL?,
         placeholderImage: UIImage? = nil,
         sourceFrame: CGRect = .zero,
         sourceImage: UIImage? = nil,
         sourceViewController: OmniBarViewController? = nil,
         logoStore: DaxEasterEggLogoStoring,
         featureFlagger: FeatureFlagger) {
        self.imageURL = imageURL
        self.sourceFrame = sourceFrame
        self.sourceImage = sourceImage ?? placeholderImage
        self.sourceViewController = sourceViewController
        self.logoStore = logoStore
        self.featureFlagger = featureFlagger
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

        setupTitleLabel()
        setupCloseButton()
        setupSetAsLogoButton()

        view.addSubview(imageView)
        view.addSubview(titleLabel)
        view.addSubview(closeButton)
        view.addSubview(setAsLogoButton)

        imageView.translatesAutoresizingMaskIntoConstraints = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        setAsLogoButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 100),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 30),
            closeButton.heightAnchor.constraint(equalToConstant: 30),

            setAsLogoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            setAsLogoButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
    }

    private func setupTitleLabel() {
        guard featureFlagger.isFeatureOn(.daxEasterEggPermanentLogo), imageURL != nil else {
            titleLabel.isHidden = true
            return
        }

        titleLabel.text = UserText.daxEasterEggFoundTitle
        titleLabel.font = UIFont.boldAppFont(ofSize: 20)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.alpha = 0
        titleLabel.isHidden = isCurrentLogoStored
    }

    private func setupCloseButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let xImage = UIImage(systemName: "xmark", withConfiguration: config)
        closeButton.setImage(xImage, for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(dismissViewController), for: .touchUpInside)
    }

    private func setupSetAsLogoButton() {
        guard featureFlagger.isFeatureOn(.daxEasterEggPermanentLogo), imageURL != nil else {
            setAsLogoButton.isHidden = true
            return
        }

        updateSetAsLogoButtonTitle()
        setAsLogoButton.titleLabel?.font = UIFont.boldAppFont(ofSize: 15)
        setAsLogoButton.setTitleColor(UIColor(designSystemColor: .buttonsPrimaryText), for: .normal)
        setAsLogoButton.backgroundColor = UIColor(designSystemColor: .buttonsPrimaryDefault)
        setAsLogoButton.contentEdgeInsets = UIEdgeInsets(top: 14, left: 24, bottom: 14, right: 24)
        setAsLogoButton.layer.cornerRadius = 8
        setAsLogoButton.alpha = 0
        setAsLogoButton.addTarget(self, action: #selector(setAsLogoButtonTapped), for: .touchUpInside)
    }

    private var isCurrentLogoStored: Bool {
        guard let currentURL = imageURL?.absoluteString else { return false }
        return logoStore.logoURL == currentURL
    }

    private func updateSetAsLogoButtonTitle() {
        let title: String
        if isCurrentLogoStored {
            title = UserText.daxEasterEggResetToDefault
        } else {
            title = UserText.daxEasterEggSwitchToThisLogo
        }
        setAsLogoButton.setTitle(title, for: .normal)
    }

    @objc private func setAsLogoButtonTapped() {
        if isCurrentLogoStored {
            logoStore.clearLogo()
            Pixel.fire(pixel: .daxEasterEggLogoResetToDefault)
        } else if let urlString = imageURL?.absoluteString {
            logoStore.setLogo(url: urlString)
            Pixel.fire(pixel: .daxEasterEggLogoSetAsPermanent)
        }
        dismiss(animated: true)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let imageSize = actualImageSize ?? sourceImage?.size ?? CGSize(width: 100, height: 100)
        let frame = DaxEasterEggLayout.calculateLogoFrame(
            for: imageSize,
            in: view.bounds,
            safeAreaInsets: view.safeAreaInsets
        )
        imageView.frame = frame
    }
    
    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:)))
        tapGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(tapGesture)
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: view)
        let hitView = view.hitTest(location, with: nil)
        if hitView == view || hitView == imageView {
            dismissViewController()
        }
    }
    
    @objc private func dismissViewController() {
        dismiss(animated: true)
    }

    /// Called by transition animator when animation completes to load high-res image.
    func transitionDidComplete() {
        imageView.alpha = 1

        UIView.animate(withDuration: 0.25) {
            self.titleLabel.alpha = 1
            self.setAsLogoButton.alpha = 1
        }

        if let imageURL = imageURL {
            imageView.kf.setImage(with: imageURL, placeholder: sourceImage) { [weak self] result in
                if case .success(let value) = result {
                    self?.adjustLayoutForActualImageSize(value.image.size)
                }
            }
        }
    }

    /// Returns current image for transition animation.
    func getCurrentImage() -> UIImage? {
        imageView.image
    }

    /// Hides the source logo during transition to avoid duplicate logos.
    func hideSourceLogo() {
        sourceViewController?.hideLogoForTransition()
    }

    /// Shows the source logo after transition completes.
    func showSourceLogo() {
        sourceViewController?.showLogoAfterTransition()
    }

    /// Adjusts the layout to use the actual downloaded image size.
    private func adjustLayoutForActualImageSize(_ imageSize: CGSize) {
        actualImageSize = imageSize
        let newFrame = DaxEasterEggLayout.calculateLogoFrame(
            for: imageSize,
            in: view.bounds,
            safeAreaInsets: view.safeAreaInsets
        )
        guard newFrame != imageView.frame else { return }
        UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut]) {
            self.imageView.frame = newFrame
        }
    }
}

extension DaxEasterEggFullScreenViewController: UIViewControllerTransitioningDelegate {

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        DaxEasterEggZoomTransitionAnimator(sourceFrame: sourceFrame, sourceImage: sourceImage, isPresenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let currentSourceFrame = sourceViewController?.getCurrentLogoFrame() ?? sourceFrame
        return DaxEasterEggZoomTransitionAnimator(sourceFrame: currentSourceFrame, sourceImage: sourceImage, isPresenting: false)
    }
}
