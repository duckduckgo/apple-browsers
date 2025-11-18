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

enum FaviconPlaceholderStyle {
    case dot
    case domainPrefix(URL?)
}

final class TabFaviconView: NSView {

    private let imageView = NSImageView()
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

    func startSpinnerIfNeeded(url: URL?, isLoading: Bool, error: Error?) {
        let policy = DefaultLoadingIndicatorPolicy()
        guard policy.shouldShowLoadingIndicator(url: url, isLoading: isLoading, error: error) else {
            stopSpinner()
            resizeImageIfNeeded(scaleDown: false)
            return
        }

        startSpinner()
        resizeImageIfNeeded(scaleDown: true)
    }

    /// Renders a given Favicon, with a crossfade animation.
    ///
    /// - Important:
    ///     In order to avoid flickering triggered during CollectionView reload (ie. Pinning / Unpinning a tab), we'll skip Crossfading whenever the View was effectively reset.
    ///
    func displayFavicon(favicon: NSImage?, placeholderStyle: FaviconPlaceholderStyle) {
        let targetImage = favicon ?? placeholderStyle.placeholderImage
        if shouldApplyCrossfade(targetImage: targetImage) {
            imageView.applyCrossfadeTransition(timingFunction: FaviconAnimation.animationTimingFunction, duration: FaviconAnimation.animationDuration)
        }

        imageView.image = targetImage

        placeholderView.isShown = shouldDisplayPlaceholderView(favicon: favicon, placeholderStyle: placeholderStyle)
        placeholderView.displayURL(placeholderStyle.url)
    }

    func reset() {
        stopSpinner(animated: false)
        imageView.image = nil
        placeholderView.isShown = false
    }
}

private extension TabFaviconView {

    func startSpinner() {
        spinnerView.startAnimating()
    }

    func stopSpinner(animated: Bool = true) {
        spinnerView.stopAnimating(animated: animated)
    }

    func shouldApplyCrossfade(targetImage: NSImage?) -> Bool {
        placeholderView.isShown && targetImage != nil || imageView.image != nil && imageView.image != targetImage
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

    func shouldDisplayPlaceholderView(favicon: NSImage?, placeholderStyle: FaviconPlaceholderStyle) -> Bool {
        favicon == nil && placeholderStyle.url != nil
    }
}

private extension FaviconPlaceholderStyle {

    var url: URL? {
        guard case .domainPrefix(let url) = self else {
            return nil
        }

        return url
    }

    var placeholderImage: NSImage? {
        guard case .dot = self else {
            return nil
        }

        // Note: We're not using the `circle.fill` symbol since it's just impossible to get it to render in 16x16.
        return NSImage.drawFilledCircle(size: FaviconPlaceholder.imageSize, foregroundColorName: FaviconPlaceholder.foregroundColorName)
    }
}

private extension NSImage {

    static func drawFilledCircle(size: NSSize, foregroundColorName: DesignSystemColor) -> NSImage {
        let targetFrame = NSRect(origin: .zero, size: size)
        let image = NSImage(size: size)

        image.lockFocus()

        NSColor(designSystemColor: foregroundColorName).setFill()
        NSBezierPath(ovalIn: targetFrame).fill()

        image.unlockFocus()

        return image
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

private enum FaviconPlaceholder {
    static let imageSize = FaviconMetrics.imageSize
    static let foregroundColorName: DesignSystemColor = .placeholderShade12
}
