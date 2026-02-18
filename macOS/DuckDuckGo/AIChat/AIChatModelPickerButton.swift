//
//  AIChatModelPickerButton.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import DesignResourcesKitIcons

/// A pill-shaped button that displays the current AI model name with a dropdown chevron.
/// Used in the AI Chat omnibar to allow model selection via a context menu.
final class AIChatModelPickerButton: NSView {

    private enum Constants {
        static let height: CGFloat = 28
        static let horizontalPadding: CGFloat = 10
        static let iconTextSpacing: CGFloat = 3
        static let chevronSize: CGFloat = 12
        static let fontSize: CGFloat = 12
        static let cornerRadius: CGFloat = 14
    }

    private let nameLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Constants.fontSize, weight: .medium)
        label.isEditable = false
        label.isSelectable = false
        label.isBezeled = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        return label
    }()

    private let chevronImageView: NSImageView = {
        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.image = DesignSystemImages.Glyphs.Size12.arrowDown
        return imageView
    }()

    private let backgroundLayer = CALayer()

    weak var target: AnyObject?
    var action: Selector?

    var modelName: String = "" {
        didSet {
            nameLabel.stringValue = modelName
            invalidateIntrinsicContentSize()
        }
    }

    var tintColor: NSColor? {
        didSet {
            updateAppearance()
        }
    }

    var hoverBackgroundColor: NSColor = .clear
    var pressedBackgroundColor: NSColor = .clear

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
        let labelWidth = nameLabel.intrinsicContentSize.width
        let totalWidth = Constants.horizontalPadding + labelWidth + Constants.iconTextSpacing + Constants.chevronSize + Constants.horizontalPadding
        return NSSize(width: totalWidth, height: Constants.height)
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
        setAccessibilityRole(.popUpButton)

        // Setup background layer (pill shape)
        backgroundLayer.cornerRadius = Constants.cornerRadius
        backgroundLayer.opacity = 0
        layer?.insertSublayer(backgroundLayer, at: 0)

        // Add subviews
        addSubview(nameLabel)
        addSubview(chevronImageView)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            chevronImageView.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: Constants.iconTextSpacing),
            chevronImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronImageView.widthAnchor.constraint(equalToConstant: Constants.chevronSize),
            chevronImageView.heightAnchor.constraint(equalToConstant: Constants.chevronSize),
        ])

        updateAppearance()
        setupHoverTracking()
    }

    override func layout() {
        super.layout()
        backgroundLayer.frame = bounds
    }

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        NSAppearance.withAppAppearance {
            if isMouseDown {
                backgroundLayer.backgroundColor = pressedBackgroundColor.cgColor
                backgroundLayer.opacity = 1
            } else if isHovered {
                backgroundLayer.backgroundColor = hoverBackgroundColor.cgColor
                backgroundLayer.opacity = 1
            } else {
                backgroundLayer.opacity = 0
            }

            nameLabel.textColor = tintColor
            chevronImageView.contentTintColor = tintColor
        }

        CATransaction.commit()
    }

    // MARK: - Hover Tracking

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
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
