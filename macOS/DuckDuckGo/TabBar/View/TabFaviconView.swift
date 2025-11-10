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
}

extension TabFaviconView {

    func displaySpinnerIfNeeded(url: URL?, isLoading: Bool, error: Error?) {
        let policy = DefaultLoadingIndicatorPolicy()
        guard policy.shouldShowLoadingIndicator(url: url, isLoading: isLoading, error: error) else {
            stopSpinner()
            return
        }

        /// Temporary!! Will be addressed in a follow-up
        imageView.animator().alphaValue = 0
        spinnerView.startAnimating()
    }

    func stopSpinner() {
        /// Temporary: Will be addressed in a follow-up
        imageView.animator().alphaValue = 1
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
            imageView.widthAnchor.constraint(equalToConstant: TabFaviconMetrics.defaultImageSize.width),
            imageView.heightAnchor.constraint(equalToConstant: TabFaviconMetrics.defaultImageSize.height)
        ])

        spinnerView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            spinnerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinnerView.centerYAnchor.constraint(equalTo: centerYAnchor),
            spinnerView.widthAnchor.constraint(equalTo: imageView.widthAnchor, constant: TabFaviconMetrics.defaultSpinnerPadding * 2),
            spinnerView.heightAnchor.constraint(equalTo: imageView.heightAnchor, constant: TabFaviconMetrics.defaultSpinnerPadding * 2)
        ])
    }
}

private enum TabFaviconMetrics {
    static let defaultImageSize = NSSize(width: 16, height: 16)
    static let defaultSpinnerPadding = CGFloat(2)
}
