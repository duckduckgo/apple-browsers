//
//  TabFaviconView.swift
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

import AppKit
import DesignResourcesKit

final class TabFaviconView: NSView {

    private let loadingPolicy = DefaultLoadingIndicatorPolicy()
    private let imageView = FaviconImageView()
    private let placeholderView = LetterView()
    private let spinnerView = SpinnerView()

    var displaysImage: Bool {
        imageView.image != nil
    }

    var imageTintColor: NSColor? {
        get {
            imageView.contentTintColor
        }
        set {
            imageView.contentTintColor = newValue
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupSubviews()
        setupImageView()
        setupSpinnerView()
        setupPlaceholderView()
        setupConstraints()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        refreshImageLayerLocation()
    }
}

extension TabFaviconView {

    func startSpinnerIfNeeded(isLoading: Bool, url: URL?, error: Error?) {
        guard shouldStartSpinner(isLoading: isLoading, url: url, error: error) else {
            stopSpinner()
            return
        }

        startSpinner()
    }

    func startSpinner() {
        spinnerView.startAnimating()
        resizeImageIfNeeded(scaleDown: true)
    }

    func stopSpinner(animated: Bool = true) {
        spinnerView.stopAnimating(animated: animated)
        resizeImageIfNeeded(scaleDown: false)
    }

    func refreshSpinnerColorsIfNeeded(rendered: Bool) {
        spinnerView.refreshSpinnerColorsIfNeeded(rendered: rendered)
    }

    /// Renders a given Favicon, with a crossfade animation.
    ///
    /// - Important:
    ///     In order to avoid flickering triggered during CollectionView reload (ie. Pinning / Unpinning a tab), we'll skip Crossfading whenever the View was effectively reset.
    ///
    func displayFavicon(favicon: NSImage?, url: URL?) {
        let targetImage = favicon
        if shouldCrossfadeFavicon(newFavicon: targetImage) {
            imageView.applyCrossfadeTransition(timingFunction: FaviconAnimation.animationTimingFunction, duration: FaviconAnimation.animationDuration)
        }

        imageView.image = targetImage

        placeholderView.isShown = shouldDisplayPlaceholderView(favicon: favicon, url: url)
        placeholderView.displayURL(url)
    }

    func reset() {
        stopSpinner(animated: false)
        imageView.image = nil
        placeholderView.isShown = false
    }
}

private extension TabFaviconView {

    func shouldCrossfadeFavicon(newFavicon: NSImage?) -> Bool {
        loadingPolicy.shouldCrossfadeFavicon(newFavicon: newFavicon, oldFavicon: imageView.image, displaysPlaceholder: placeholderView.isShown)
    }

    func shouldStartSpinner(isLoading: Bool, url: URL?, error: Error?) -> Bool {
        loadingPolicy.shouldShowLoadingIndicator(isLoading: isLoading, url: url, error: error)
    }
}

private extension TabFaviconView {

    func setupSubviews() {
        addSubview(imageView)
        addSubview(spinnerView)
        imageView.addSubview(placeholderView)
    }

    func setupImageView() {
        imageView.imageScaling = .scaleProportionallyDown
        imageView.wantsLayer = true
    }

    func setupSpinnerView() {
        spinnerView.setAccessibilityLabel("TabFaviconView.spinner")
        spinnerView.setAccessibilityRole(.progressIndicator)
    }

    func setupPlaceholderView() {
        placeholderView.backgroundShape = .circle
        placeholderView.labelFont = NSFont.systemFont(ofSize: 9, weight: .bold)
    }

    func setupConstraints() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: FaviconMetrics.imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: FaviconMetrics.imageSize.height)
        ])

        spinnerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinnerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinnerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinnerView.widthAnchor.constraint(equalTo: imageView.widthAnchor, constant: FaviconMetrics.spinnerPadding * 2),
            spinnerView.heightAnchor.constraint(equalTo: imageView.heightAnchor, constant: FaviconMetrics.spinnerPadding * 2)
        ])

        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            placeholderView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: imageView.topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor)
        ])
    }
}

private extension TabFaviconView {

    func refreshImageLayerLocation() {
        let targetPositionX = bounds.width * 0.5
        let targetPositionY = bounds.height * 0.5

        guard let layer = imageView.layer else {
            return
        }

        guard layer.position.x != targetPositionX || layer.position.y != targetPositionY || layer.anchorPoint != FaviconMetrics.imageLayerAnchorPoint else {
            return
        }

        layer.anchorPoint = FaviconMetrics.imageLayerAnchorPoint
        layer.position.x = targetPositionX
        layer.position.y = targetPositionY
    }

    func resizeImageIfNeeded(scaleDown: Bool) {
        let targetRadius = imageCornerRadius(scaleDown: scaleDown)
        let targetTransform = imageTransform(scaleDown: scaleDown)

        guard let layer = imageView.animator().layer else {
            return
        }

        guard layer.cornerRadius != targetRadius || CATransform3DEqualToTransform(layer.transform, targetTransform) == false else {
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.timingFunction = FaviconAnimation.animationTimingFunction
            context.duration = FaviconAnimation.animationDuration
            context.allowsImplicitAnimation = true

            layer.cornerRadius = targetRadius
            layer.transform = targetTransform
        }
    }

    func imageCornerRadius(scaleDown: Bool) -> CGFloat {
        guard scaleDown else {
            return .zero
        }

        return min(imageView.bounds.width, imageView.bounds.height) * 0.5
    }

    func imageTransform(scaleDown: Bool) -> CATransform3D {
        scaleDown ? CATransform3DMakeScale(FaviconAnimation.scaleDownRatio, FaviconAnimation.scaleDownRatio, 1.0) : CATransform3DIdentity
    }

    func shouldDisplayPlaceholderView(favicon: NSImage?, url: URL?) -> Bool {
        favicon == nil && url != nil
    }
}

extension NSView {

    func applyCrossfadeTransition(timingFunction: CAMediaTimingFunction, duration: TimeInterval) {
        let transition = CATransition.buildFadeTransition(timingFunction: timingFunction, duration: duration)
        layer?.add(transition, forKey: nil)
    }
}

private enum FaviconMetrics {
    static let imageSize = NSSize(width: 16, height: 16)
    static let imageLayerAnchorPoint = CGPoint(x: 0.5, y: 0.5)
    static let spinnerPadding = CGFloat(2)
}

private enum FaviconAnimation {
    static let animationDuration = TimeInterval(0.15)
    static let animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
    static let scaleDownRatio: CGFloat = 0.75
}
