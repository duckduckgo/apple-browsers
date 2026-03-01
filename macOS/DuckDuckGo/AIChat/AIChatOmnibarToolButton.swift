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

/// An image view that doesn't intercept mouse events, allowing its superview to handle them.
private final class NonInteractiveImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil  // Pass all hits to superview
    }
}

/// A reusable toolbar button for the AI Chat omnibar with circular hover background effect.
final class AIChatOmnibarToolButton: NSView {

    private enum Constants {
        static let buttonSize: CGFloat = 28
        static let iconSize: CGFloat = 16
    }

    private let iconImageView: NonInteractiveImageView = {
        let imageView = NonInteractiveImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        return imageView
    }()

    private let backgroundLayer = CALayer()

    weak var target: AnyObject?
    var action: Selector?

    var image: NSImage? {
        get { iconImageView.image }
        set { iconImageView.image = newValue }
    }

    var tintColor: NSColor? {
        didSet {
            updateAppearance()
        }
    }

    var hoverBackgroundColor: NSColor = .clear
    var pressedBackgroundColor: NSColor = .clear

    // MARK: - Toggle State Properties

    /// When true, the button automatically toggles `isToggled` on each click
    var togglesOnClick: Bool = false

    /// Whether the button is in a toggled-on state (e.g., for search toggle)
    var isToggled: Bool = false {
        didSet {
            updateAppearance()
        }
    }

    /// Background color when toggled on (uses accent color)
    var toggledBackgroundColor: NSColor = .clear

    /// Tint color for the icon when toggled on (uses accent color)
    var toggledTintColor: NSColor = .clear

    private var isHovered = false {
        didSet {
            updateAppearance()
        }
    }

    private var isMouseDown = false {
        didSet {
            updateAppearance()
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
        wantsLayer = true
        layer?.masksToBounds = true
        setAccessibilityRole(.button)

        // Setup background layer (circular)
        backgroundLayer.cornerRadius = Constants.buttonSize / 2
        backgroundLayer.opacity = 0
        layer?.insertSublayer(backgroundLayer, at: 0)

        // Setup icon image view
        addSubview(iconImageView)

        NSLayoutConstraint.activate([
            iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),
        ])

        updateAppearance()
        setupHoverTracking()
    }

    override func layout() {
        super.layout()
        // Center the background layer
        let layerSize = CGSize(width: Constants.buttonSize, height: Constants.buttonSize)
        backgroundLayer.frame = CGRect(
            x: (bounds.width - layerSize.width) / 2,
            y: (bounds.height - layerSize.height) / 2,
            width: layerSize.width,
            height: layerSize.height
        )
    }

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        NSAppearance.withAppAppearance {
            // For toggle buttons, skip the pressed effect - just show toggled or normal state
            let showPressedEffect = isMouseDown && !togglesOnClick

            if showPressedEffect {
                backgroundLayer.backgroundColor = pressedBackgroundColor.cgColor
                backgroundLayer.opacity = 1
                iconImageView.contentTintColor = isToggled ? toggledTintColor : tintColor
            } else if isToggled {
                backgroundLayer.backgroundColor = toggledBackgroundColor.cgColor
                backgroundLayer.opacity = 1
                iconImageView.contentTintColor = toggledTintColor
            } else if isHovered {
                backgroundLayer.backgroundColor = hoverBackgroundColor.cgColor
                backgroundLayer.opacity = 1
                iconImageView.contentTintColor = tintColor
            } else {
                backgroundLayer.opacity = 0
                iconImageView.contentTintColor = tintColor
            }
        }

        CATransaction.commit()
    }

    private var trackingArea: NSTrackingArea?

    private func setupHoverTracking() {
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseDown(with event: NSEvent) {
        isMouseDown = true
    }

    override func mouseDragged(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        isMouseDown = bounds.contains(locationInView)
    }

    override func mouseUp(with event: NSEvent) {
        let locationInView = convert(event.locationInWindow, from: nil)
        if bounds.contains(locationInView) && isMouseDown {
            if togglesOnClick {
                isToggled.toggle()
            }
            if let action, let target {
                NSApp.sendAction(action, to: target, from: self)
            }
        }
        isMouseDown = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // hitTest receives point in superview's coordinate system
        // Return self for the entire button area to capture all mouse events
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
