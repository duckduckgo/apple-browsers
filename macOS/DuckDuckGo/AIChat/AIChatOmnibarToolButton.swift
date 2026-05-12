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

    private let textLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.lineBreakMode = .byTruncatingTail
        label.isHidden = true
        return label
    }()

    private let trailingImageView: NonInteractiveImageView = {
        let imageView = NonInteractiveImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyDown
        imageView.isHidden = true
        return imageView
    }()

    private var iconCenterXConstraint: NSLayoutConstraint?
    private var iconLeadingConstraint: NSLayoutConstraint?
    private var trailingImageTrailingConstraint: NSLayoutConstraint?

    private let backgroundLayer = CALayer()

    weak var target: AnyObject?
    var action: Selector?

    var image: NSImage? {
        get { iconImageView.image }
        set { iconImageView.image = newValue }
    }

    var font: NSFont {
        get { textLabel.font ?? .systemFont(ofSize: 12, weight: .medium) }
        set { textLabel.font = newValue }
    }

    var tintColor: NSColor? {
        didSet {
            updateAppearance()
        }
    }

    /// When true, the icon always uses the leading constraint instead of centering.
    /// The leading inset matches the centered position at default button size, so the icon
    /// stays visually centered when icon-only and doesn't shift when the label toggles.
    var keepIconLeadingAligned: Bool = false {
        didSet {
            if keepIconLeadingAligned {
                iconCenterXConstraint?.isActive = false
                iconLeadingConstraint?.isActive = true
            }
        }
    }

    /// Optional text label shown next to the icon. When set, the button expands horizontally.
    var label: String? {
        didSet {
            let hasLabel = label.map { !$0.isEmpty } ?? false
            textLabel.stringValue = label ?? ""
            textLabel.isHidden = !hasLabel
            if !keepIconLeadingAligned {
                iconCenterXConstraint?.isActive = !hasLabel
                iconLeadingConstraint?.isActive = hasLabel
            }
            invalidateIntrinsicContentSize()
        }
    }

    /// Optional trailing image (e.g., close icon). Shown after the label when set.
    var trailingImage: NSImage? {
        didSet {
            let hasTrailing = trailingImage != nil
            trailingImageView.image = trailingImage
            trailingImageView.isHidden = !hasTrailing
            trailingImageTrailingConstraint?.isActive = hasTrailing
            invalidateIntrinsicContentSize()
        }
    }

    var isEnabled: Bool = true {
        didSet {
            updateAppearance()
        }
    }

    /// Persistent background color when set (e.g., for active mode indication). Takes priority over hover.
    var activeBackgroundColor: NSColor? {
        didSet {
            updateAppearance()
            needsLayout = true
        }
    }

    /// Background color on hover while `activeBackgroundColor` is set.
    var activeHoverBackgroundColor: NSColor?

    /// Background color when pressed while `activeBackgroundColor` is set.
    var activePressedBackgroundColor: NSColor?

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

    private static let trailingImageSize: CGFloat = 12

    override var intrinsicContentSize: NSSize {
        if let label, !label.isEmpty {
            let labelWidth = textLabel.intrinsicContentSize.width
            var width = Constants.iconSize + labelWidth + 18
            if trailingImage != nil {
                width += Self.trailingImageSize + 4
            }
            return NSSize(width: width, height: Constants.buttonSize)
        }
        return NSSize(width: Constants.buttonSize, height: Constants.buttonSize)
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
        setNeedsDisplay(bounds.insetBy(dx: -3, dy: -3))
        return super.becomeFirstResponder()
    }

    override func resignFirstResponder() -> Bool {
        setNeedsDisplay(bounds.insetBy(dx: -3, dy: -3))
        return super.resignFirstResponder()
    }

    private func setupView() {
        wantsLayer = true
        setAccessibilityRole(.button)

        // Setup background layer (shape updated in layout())
        backgroundLayer.opacity = 0
        layer?.insertSublayer(backgroundLayer, at: 0)

        // Setup icon image view
        addSubview(iconImageView)
        addSubview(textLabel)
        addSubview(trailingImageView)

        iconCenterXConstraint = iconImageView.centerXAnchor.constraint(equalTo: centerXAnchor)
        iconCenterXConstraint?.isActive = true
        iconLeadingConstraint = iconImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6)
        iconLeadingConstraint?.isActive = false

        trailingImageTrailingConstraint = trailingImageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
        trailingImageTrailingConstraint?.isActive = false

        NSLayoutConstraint.activate([
            iconImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconImageView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            textLabel.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 4),
            textLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            trailingImageView.leadingAnchor.constraint(equalTo: textLabel.trailingAnchor, constant: 4),
            trailingImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            trailingImageView.widthAnchor.constraint(equalToConstant: Self.trailingImageSize),
            trailingImageView.heightAnchor.constraint(equalToConstant: Self.trailingImageSize),
        ])

        updateAppearance()
        setupHoverTracking()
    }

    override func layout() {
        super.layout()
        let hasLabel = label.map { !$0.isEmpty } ?? false
        if hasLabel {
            // Full-width rounded rect when label is shown
            backgroundLayer.frame = bounds
            backgroundLayer.cornerRadius = bounds.height / 2
        } else {
            // Centered circle when icon-only
            let layerSize = CGSize(width: Constants.buttonSize, height: Constants.buttonSize)
            backgroundLayer.frame = CGRect(
                x: (bounds.width - layerSize.width) / 2,
                y: (bounds.height - layerSize.height) / 2,
                width: layerSize.width,
                height: layerSize.height
            )
            backgroundLayer.cornerRadius = Constants.buttonSize / 2
        }
    }

    private func updateAppearance() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        NSAppearance.withAppAppearance {
            guard isEnabled else {
                backgroundLayer.opacity = 0
                iconImageView.contentTintColor = NSColor.secondaryLabelColor
                textLabel.textColor = NSColor.secondaryLabelColor
                trailingImageView.contentTintColor = NSColor.secondaryLabelColor
                CATransaction.commit()
                return
            }

            // For toggle buttons, skip the pressed effect - just show toggled or normal state
            let showPressedEffect = isMouseDown && !togglesOnClick

            let effectiveTint: NSColor?
            if showPressedEffect {
                if activeBackgroundColor != nil, let activePressedBackgroundColor {
                    backgroundLayer.backgroundColor = activePressedBackgroundColor.cgColor
                } else {
                    backgroundLayer.backgroundColor = pressedBackgroundColor.cgColor
                }
                backgroundLayer.opacity = 1
                effectiveTint = isToggled ? toggledTintColor : tintColor
            } else if isToggled {
                backgroundLayer.backgroundColor = toggledBackgroundColor.cgColor
                backgroundLayer.opacity = 1
                effectiveTint = toggledTintColor
            } else if let activeBackgroundColor {
                if isHovered, let activeHoverBackgroundColor {
                    backgroundLayer.backgroundColor = activeHoverBackgroundColor.cgColor
                } else {
                    backgroundLayer.backgroundColor = activeBackgroundColor.cgColor
                }
                backgroundLayer.opacity = 1
                effectiveTint = tintColor
            } else if isHovered {
                backgroundLayer.backgroundColor = hoverBackgroundColor.cgColor
                backgroundLayer.opacity = 1
                effectiveTint = tintColor
            } else {
                backgroundLayer.opacity = 0
                effectiveTint = tintColor
            }
            iconImageView.contentTintColor = effectiveTint
            textLabel.textColor = effectiveTint ?? .labelColor
            trailingImageView.contentTintColor = effectiveTint
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
        if bounds.contains(locationInView) && isMouseDown && isEnabled {
            if togglesOnClick {
                isToggled.toggle()
            }
            if let action, let target {
                NSApp.sendAction(action, to: target, from: self)
            }
        }
        isMouseDown = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard window?.firstResponder == self else { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.resetClip()

        NSColor.controlAccentColor.setStroke()
        let borderRect = bounds.insetBy(dx: -1, dy: -1)
        let focusPath = NSBezierPath(roundedRect: borderRect, xRadius: borderRect.height / 2, yRadius: borderRect.height / 2)
        focusPath.lineWidth = 1.5
        focusPath.lineCapStyle = .round
        focusPath.lineJoinStyle = .round
        focusPath.stroke()

        context.restoreGState()
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
            if isEnabled, let action, let target {
                NSApp.sendAction(action, to: target, from: self)
            }
        default:
            super.keyDown(with: event)
        }
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
