//
//  LetterView.swift
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
import Combine
import SwiftUIExtensions

final class LetterView: NSView {

    private var applicationStatePublisher: AnyCancellable?

    enum BackgroundShape {
        case rectangle
        case circle
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        startListeningToNotifications()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        startListeningToNotifications()
    }

    func displayURL(_ url: URL?) {
        guard let domain = url?.host,
           let eTLDplus1 = NSApp.delegateTyped.tld.eTLDplus1(domain),
           let firstLetter = eTLDplus1.capitalized.first.flatMap(String.init)
        else {
            placeholderView.isHidden = false
            return
        }

        placeholderView.isHidden = true
        label.stringValue = firstLetter
        backgroundView.layer?.backgroundColor = Color.forString(eTLDplus1).cgColor
    }

    private let backgroundView: NSView = {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.layer?.cornerRadius = 4.0
        return view
    }()

    private let label: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .white
        label.alignment = .center
        return label
    }()

    private let placeholderView: NSImageView = {
        let imageView = NSImageView()
        imageView.image = .web
        imageView.imageScaling = .scaleProportionallyUpOrDown
        return imageView
    }()

    var backgroundShape: BackgroundShape = .rectangle {
        didSet {
            refreshBackgroundCornerRadius()
        }
    }

    var labelFont: NSFont? {
        get {
            label.font
        }
        set {
            label.font = newValue
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    override func layout() {
        super.layout()
        refreshBackgroundCornerRadius()
    }

    private func setup() {
        wantsLayer = true
        addSubview(backgroundView)
        addSubview(label)
        addSubview(placeholderView)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            backgroundView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: bottomAnchor),

            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),

            placeholderView.leadingAnchor.constraint(equalTo: leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    private func refreshBackgroundCornerRadius() {
        let backgroundCornerRadius = backgroundShape == .circle ? bounds.width * 0.5 : 4
        guard let backgroundLayer = backgroundView.layer, backgroundLayer.cornerRadius != backgroundCornerRadius else {
            return
        }

        backgroundLayer.cornerRadius = backgroundCornerRadius
    }
}

private extension LetterView {

    private func startListeningToNotifications() {
        applicationStatePublisher = NSApp.isActivePublisher()
            .dropFirst()
            .sink { [weak self] isActive in
                self?.refreshActivationAlpha(isActive: isActive)
            }
    }

    func refreshActivationAlpha(isActive: Bool) {
        backgroundView.alphaValue = isActive ? .activeViewAlpha : .inactiveViewAlpha
    }
}
