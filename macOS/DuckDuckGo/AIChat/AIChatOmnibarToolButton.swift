//
//  AIChatOmnibarToolButton.swift
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

/// A reusable toolbar button for the AI Chat omnibar with circular hover background effect.
final class AIChatOmnibarToolButton: NSView {

    private enum Constants {
        static let buttonSize: CGFloat = 28
        static let iconSize: CGFloat = 16
    }

    private let button = MouseOverButton()
    private let hoverBackgroundView = NSView()

    var target: AnyObject? {
        get { button.target }
        set { button.target = newValue }
    }

    var action: Selector? {
        get { button.action }
        set { button.action = newValue }
    }

    var image: NSImage? {
        get { button.image }
        set { button.image = newValue }
    }

    override var toolTip: String? {
        get { button.toolTip }
        set { button.toolTip = newValue }
    }

    var tintColor: NSColor? {
        get { button.normalTintColor }
        set { button.normalTintColor = newValue }
    }

    var hoverBackgroundColor: NSColor = NSColor(designSystemColor: .surfacePrimary) {
        didSet {
            updateHoverBackground()
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: Constants.buttonSize, height: Constants.buttonSize)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        // Setup hover background view (circular)
        hoverBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        hoverBackgroundView.wantsLayer = true
        hoverBackgroundView.layer?.cornerRadius = Constants.buttonSize / 2
        hoverBackgroundView.alphaValue = 0
        addSubview(hoverBackgroundView)

        // Setup button
        button.translatesAutoresizingMaskIntoConstraints = false
        button.title = ""
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.wantsLayer = true
        button.imagePosition = .imageOnly
        addSubview(button)

        NSLayoutConstraint.activate([
            hoverBackgroundView.centerXAnchor.constraint(equalTo: centerXAnchor),
            hoverBackgroundView.centerYAnchor.constraint(equalTo: centerYAnchor),
            hoverBackgroundView.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            hoverBackgroundView.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            button.centerXAnchor.constraint(equalTo: centerXAnchor),
            button.centerYAnchor.constraint(equalTo: centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            button.heightAnchor.constraint(equalToConstant: Constants.iconSize),
        ])

        updateHoverBackground()
        setupHoverTracking()
    }

    private func updateHoverBackground() {
        hoverBackgroundView.layer?.backgroundColor = hoverBackgroundColor.cgColor
    }

    private func setupHoverTracking() {
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            hoverBackgroundView.animator().alphaValue = 1
        }
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            hoverBackgroundView.animator().alphaValue = 0
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateHoverBackground()
    }
}
