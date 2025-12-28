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
import BrowserServicesKit
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
    private let closeButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let setAsLogoButton = UIButton(type: .system)

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
        view.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        imageView.contentMode = .scaleAspectFit

        setupCloseButton()
        setupTitleLabel()
        setupSetAsLogoButton()

        view.addSubview(imageView)
        view.addSubview(closeButton)
        view.addSubview(titleLabel)
        view.addSubview(setAsLogoButton)

        imageView.translatesAutoresizingMaskIntoConstraints = true
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        setAsLogoButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),

            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 80),
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),

            setAsLogoButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            setAsLogoButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40)
        ])
    }
    
    private func setupCloseButton() {
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = .clear
        closeButton.layer.cornerRadius = 22
        closeButton.addTarget(self, action: #selector(dismissViewController), for: .touchUpInside)
    }

    private func setupTitleLabel() {
        titleLabel.text = UserText.daxEasterEggFoundTitle
        titleLabel.font = UIFont.boldAppFont(ofSize: 20)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 1
        titleLabel.layer.shadowColor = UIColor.black.cgColor
        titleLabel.layer.shadowOffset = CGSize(width: 0, height: 1)
        titleLabel.layer.shadowOpacity = 0.5
        titleLabel.layer.shadowRadius = 2
        titleLabel.alpha = 0
    }

    private func setupSetAsLogoButton() {
        guard featureFlagger.isFeatureOn(.daxEasterEggPermanentLogo), imageURL != nil else {
            setAsLogoButton.isHidden = true
            titleLabel.isHidden = true
            return
        }
        updateSetAsLogoButtonTitle()
        setAsLogoButton.titleLabel?.font = UIFont.boldAppFont(ofSize: 15)
        setAsLogoButton.setTitleColor(UIColor(designSystemColor: .buttonsPrimaryText), for: .normal)
        setAsLogoButton.backgroundColor = UIColor(designSystemColor: .buttonsPrimaryDefault)
        setAsLogoButton.layer.cornerRadius = 12
        setAsLogoButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 24, bottom: 16, right: 24)
        setAsLogoButton.addTarget(self, action: #selector(setAsLogoButtonTapped), for: .touchUpInside)
        setAsLogoButton.alpha = 0
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
            updateSetAsLogoButtonTitle()
        } else if let urlString = imageURL?.absoluteString {
            logoStore.setLogo(url: urlString)
            Pixel.fire(pixel: .daxEasterEggLogoSetAsPermanent)
            dismiss(animated: true)
        }
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
