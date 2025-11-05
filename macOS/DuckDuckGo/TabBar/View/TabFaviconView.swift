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

import Foundation
import AppKit

final class TabFaviconView: NSView {

    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private let imageView = {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyDown
        return imageView
    }()

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
        setupConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateImage(_ image: NSImage?) {
        imageView.image = image
    }
}

private extension TabFaviconView {

    func setupSubviews() {
        addSubview(imageView)
    }

    func setupConstraints() {
        let imageWidthConstraint = imageView.widthAnchor.constraint(equalTo: widthAnchor)
        let imageHeightConstraint = imageView.heightAnchor.constraint(equalTo: heightAnchor)
        let imageCenterXConstraint = imageView.centerXAnchor.constraint(equalTo: centerXAnchor)
        let imageCenterYConstraint = imageView.centerYAnchor.constraint(equalTo: centerYAnchor)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageCenterXConstraint, imageCenterYConstraint, imageWidthConstraint, imageHeightConstraint
        ])

        self.imageWidthConstraint = imageWidthConstraint
        self.imageHeightConstraint = imageHeightConstraint
    }
}
