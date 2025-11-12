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

final class TabFaviconView: NSView {

    private let imageView = NSImageView()

    var displaysImage: Bool {
        imageView.image != nil
    }

    var image: NSImage? {
        get {
            imageView.image
        }
        set {
            imageView.image = newValue
        }
    }

    var imageTintColor: NSColor? {
        get {
            imageView.contentTintColor
        }
        set {
            imageView.contentTintColor = newValue
        }
    }

    private let spinnerView = SpinnerView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupSubviews()
        setupImageView()
        setupSpinnerView()
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

    func displaySpinnerIfNeeded(url: URL?, isLoading: Bool, error: Error?) {
        let policy = DefaultLoadingIndicatorPolicy()
        guard policy.shouldShowLoadingIndicator(url: url, isLoading: isLoading, error: error) else {
            stopSpinner()
            resizeImageIfNeeded(scaleDown: false)
            return
        }

        spinnerView.startAnimating()
        resizeImageIfNeeded(scaleDown: true)
    }

    func stopSpinner() {
        spinnerView.stopAnimating()
    }
}

private extension TabFaviconView {

    func setupSubviews() {
        addSubview(imageView)
        addSubview(spinnerView)
    }

    func setupImageView() {
        imageView.imageScaling = .scaleProportionallyDown
        imageView.wantsLayer = true
    }

    func setupSpinnerView() {
        spinnerView.setAccessibilityLabel("TabFaviconView.spinner")
        spinnerView.setAccessibilityRole(.progressIndicator)
    }

    func setupConstraints() {
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: TabFaviconMetrics.imageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: TabFaviconMetrics.imageSize.height)
        ])

        spinnerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinnerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinnerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinnerView.widthAnchor.constraint(equalTo: imageView.widthAnchor, constant: TabFaviconMetrics.spinnerPadding * 2),
            spinnerView.heightAnchor.constraint(equalTo: imageView.heightAnchor, constant: TabFaviconMetrics.spinnerPadding * 2)
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

        guard layer.position.x != targetPositionX || layer.position.y != targetPositionY || layer.anchorPoint != TabFaviconMetrics.imageLayerAnchorPoint else {
            return
        }

        layer.anchorPoint = TabFaviconMetrics.imageLayerAnchorPoint
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
}

private enum TabFaviconMetrics {
    static let imageSize = NSSize(width: 16, height: 16)
    static let imageLayerAnchorPoint = CGPoint(x: 0.5, y: 0.5)
    static let spinnerPadding = CGFloat(2)
}

private enum FaviconAnimation {
    static let animationDuration = TimeInterval(0.15)
    static let animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1.0)
    static let scaleDownRatio: CGFloat = 0.75
}
