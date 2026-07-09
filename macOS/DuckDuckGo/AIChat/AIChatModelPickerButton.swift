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
import DesignResourcesKit
import DesignResourcesKitIcons

/// A pill-shaped button that displays the current AI model name with a dropdown chevron.
/// Used in the AI Chat omnibar to allow model selection via a context menu.
final class AIChatModelPickerButton: NSView {

    private enum Constants {
        static let height: CGFloat = 28
        static let horizontalPadding: CGFloat = 13
        static let legacyHorizontalPadding: CGFloat = 10
        static let iconTextSpacing: CGFloat = 3
        static let chevronSize: CGFloat = 16
        static let fontSize: CGFloat = 12
        static let cornerRadius: CGFloat = 14
    }

    private let themeManager: ThemeManaging = NSApp.delegateTyped.themeManager

    private var horizontalPadding: CGFloat {
        themeManager.isAppRebranded ? Constants.horizontalPadding : Constants.legacyHorizontalPadding
    }

    private let nameLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: Constants.fontSize, weight: .regular)
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
        imageView.image = DesignSystemImages.Glyphs.Size16.chevronDownMedium
        return imageView
    }()

    private let backgroundLayer = CALayer()
    private let focusRingLayer: CAShapeLayer = {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.lineWidth = 1.5
        layer.lineCap = .round
        layer.lineJoin = .round
        layer.isHidden = true
        return layer
    }()

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

    /// Stroke colour for the keyboard-focus ring. Defaults to the design-system primary
    /// accent; the container VC re-assigns this from `theme.colorsProvider.accentPrimaryColor`
    /// via `applyTheme(theme:)` so the ring follows in-app theme switches (Pink, Blue, etc.).
    var focusRingColor: NSColor = NSColor(designSystemColor: .accentPrimary) {
        didSet { updateFocusRingStrokeColor() }
    }

    private func updateFocusRingStrokeColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        effectiveAppearance.performAsCurrentDrawingAppearance {
            focusRingLayer.strokeColor = focusRingColor.cgColor
        }
        CATransaction.commit()
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
        let totalWidth = horizontalPadding + labelWidth + Constants.iconTextSpacing + Constants.chevronSize + horizontalPadding
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

    var onTabPressed: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { setFocusRingHidden(false) }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { setFocusRingHidden(true) }
        return didResign
    }

    private func setFocusRingHidden(_ hidden: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        focusRingLayer.isHidden = hidden
        CATransaction.commit()
    }

    private func setupView() {
        wantsLayer = true
        // The focus ring sublayer extends 1pt past the view's bounds. On macOS Monterey
        // the hosting layer clips its sublayers to bounds by default, which would hide
        // the ring; explicitly disable masking so the ring renders on every supported OS.
        layer?.masksToBounds = false
        setAccessibilityRole(.popUpButton)

        // Setup background layer (pill shape)
        backgroundLayer.cornerRadius = Constants.cornerRadius
        backgroundLayer.opacity = 0
        layer?.insertSublayer(backgroundLayer, at: 0)

        // Focus ring sublayer sits above the background so it stays visible while hovered.
        // Stroke colour follows `focusRingColor` and re-resolves against the view's effective
        // appearance — see `updateFocusRingStrokeColor()`.
        layer?.addSublayer(focusRingLayer)
        updateFocusRingStrokeColor()

        // Add subviews
        addSubview(nameLabel)
        addSubview(chevronImageView)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: horizontalPadding),
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

        // Focus ring sits 1pt outside the pill. Rendered as a sublayer rather than
        // in `draw(_:)` so the 1pt overflow is not clipped by the view's backing layer
        // (which was the cause of the broken ring on macOS Monterey).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let ringRect = bounds.insetBy(dx: -1, dy: -1)
        focusRingLayer.frame = ringRect
        focusRingLayer.path = CGPath(
            roundedRect: focusRingLayer.bounds,
            cornerWidth: ringRect.height / 2,
            cornerHeight: ringRect.height / 2,
            transform: nil
        )
        CATransaction.commit()
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

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48: // Tab
            if let onTabPressed {
                onTabPressed()
            } else {
                super.keyDown(with: event)
            }
        case 49, 36: // Space, Return - trigger action
            if let action, let target {
                NSApp.sendAction(action, to: target, from: self)
            }
        default:
            super.keyDown(with: event)
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
        updateFocusRingStrokeColor()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }
}
