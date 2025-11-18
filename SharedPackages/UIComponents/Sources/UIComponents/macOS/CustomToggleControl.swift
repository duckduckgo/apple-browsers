//
//  CustomToggleControl.swift
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

#if os(macOS)

import Cocoa

// MARK: - Custom Toggle Control

public final class CustomToggleControl: NSControl {

    // MARK: - Key Code Constants

    private enum KeyCode {
        static let space: UInt16 = 49
        static let `return`: UInt16 = 36
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
    }

    // MARK: - Properties

    public var leftImage: NSImage? {
        didSet { needsDisplay = true }
    }

    public var rightImage: NSImage? {
        didSet { needsDisplay = true }
    }

    public var isRightSelected: Bool = false {
        didSet {
            if oldValue != isRightSelected {
                animateSelection()
                sendAction(action, to: target)
            }
        }
    }

    public var backgroundColor: NSColor = NSColor(white: 0.9, alpha: 1.0) {
        didSet { needsDisplay = true }
    }

    public var selectedBackgroundColor: NSColor = NSColor.white {
        didSet { needsDisplay = true }
    }

    public var focusedBackgroundColor: NSColor = NSColor(white: 0.85, alpha: 1.0) {
        didSet { needsDisplay = true }
    }

    public var selectionColor: NSColor = NSColor.controlAccentColor {
        didSet { needsDisplay = true }
    }

    public var focusBorderColor: NSColor = NSColor.controlAccentColor {
        didSet { needsDisplay = true }
    }

    public var outerBorderColor: NSColor = NSColor.controlAccentColor {
        didSet { needsDisplay = true }
    }

    public var outerBorderWidth: CGFloat = 2.0 {
        didSet { needsDisplay = true }
    }

    public var selectionInnerBorderColor: NSColor = NSColor.white {
        didSet { needsDisplay = true }
    }

    private var selectionProgress: CGFloat = 0.0
    private var animationTimer: Timer?
    private var animationStartTime: CFTimeInterval = 0
    private var animationStartProgress: CGFloat = 0.0
    private var animationTargetProgress: CGFloat = 0.0
    private let animationDuration: CFTimeInterval = 0.15

    // MARK: - Initialization

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = false

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        NSGraphicsContext.current?.shouldAntialias = true

        let isFocused = window?.firstResponder == self
        let innerBorderWidth: CGFloat = 2.0

        let bgColor = isFocused ? focusedBackgroundColor : backgroundColor
        bgColor.setFill()
        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        backgroundPath.lineJoinStyle = .round
        backgroundPath.fill()

        let leftRect = NSRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
        let rightRect = NSRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height)

        let indicatorGap: CGFloat = 2.0
        let availableWidth = bounds.width - (indicatorGap * 2)
        let availableHeight = bounds.height - (indicatorGap * 2)

        let indicatorWidth = availableWidth / 2
        let indicatorHeight = availableHeight

        let indicatorMaxX = availableWidth - indicatorWidth
        let indicatorX = indicatorGap + (indicatorMaxX * selectionProgress)
        let indicatorY = indicatorGap
        let indicatorRect = NSRect(x: indicatorX, y: indicatorY, width: indicatorWidth, height: indicatorHeight)

        context.saveGState()
        selectionColor.setFill()
        let cornerRadius = indicatorHeight / 2
        let selectionPath = NSBezierPath(roundedRect: indicatorRect, xRadius: cornerRadius, yRadius: cornerRadius)
        selectionPath.lineJoinStyle = .round
        selectionPath.fill()

        selectionInnerBorderColor.setStroke()
        let innerBorderRect = indicatorRect.insetBy(dx: 0.5, dy: 0.5)
        let innerBorderPath = NSBezierPath(roundedRect: innerBorderRect, xRadius: cornerRadius - 0.5, yRadius: cornerRadius - 0.5)
        innerBorderPath.lineWidth = 1.0
        innerBorderPath.lineJoinStyle = .round
        innerBorderPath.lineCapStyle = .round
        innerBorderPath.stroke()
        context.restoreGState()

        if let leftImage = leftImage {
            drawImage(leftImage, in: leftRect, alpha: isRightSelected ? 0.5 : 1.0)
        }

        if let rightImage = rightImage {
            drawImage(rightImage, in: rightRect, alpha: isRightSelected ? 1.0 : 0.5)
        }

        if isFocused {
            context.saveGState()

            context.resetClip()

            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setShouldSmoothFonts(true)

            focusBorderColor.setStroke()
            let innerBorderRect = bounds.insetBy(dx: -innerBorderWidth / 2, dy: -innerBorderWidth / 2)
            let focusPath = NSBezierPath(roundedRect: innerBorderRect, xRadius: innerBorderRect.height / 2, yRadius: innerBorderRect.height / 2)
            focusPath.lineWidth = innerBorderWidth
            focusPath.lineCapStyle = .round
            focusPath.lineJoinStyle = .round
            focusPath.stroke()

            outerBorderColor.setStroke()
            let outerBorderInset = -(innerBorderWidth + outerBorderWidth / 2)
            let outerBorderRect = bounds.insetBy(dx: outerBorderInset, dy: outerBorderInset)
            let outerBorderPath = NSBezierPath(roundedRect: outerBorderRect, xRadius: outerBorderRect.height / 2, yRadius: outerBorderRect.height / 2)
            outerBorderPath.lineWidth = outerBorderWidth
            outerBorderPath.lineCapStyle = .round
            outerBorderPath.lineJoinStyle = .round
            outerBorderPath.stroke()

            context.restoreGState()
        }
    }

    private func drawImage(_ image: NSImage, in rect: NSRect, alpha: CGFloat) {
        let imageSize = NSSize(width: bounds.height * 0.5, height: bounds.height * 0.5)
        let imageRect = NSRect(
            x: rect.midX - imageSize.width / 2,
            y: rect.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )

        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: alpha)
    }

    // MARK: - Animation

    private func animateSelection() {
        animationTargetProgress = isRightSelected ? 1.0 : 0.0
        animationStartProgress = selectionProgress
        animationStartTime = CACurrentMediaTime()

        animationTimer?.invalidate()
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateAnimation()
        }
    }

    @objc private func updateAnimation() {
        let elapsed = CACurrentMediaTime() - animationStartTime
        let progress = min(elapsed / animationDuration, 1.0)

        // Ease in-out animation
        let easedProgress = (1 - cos(progress * .pi)) / 2
        selectionProgress = animationStartProgress + (animationTargetProgress - animationStartProgress) * easedProgress

        needsDisplay = true

        if progress >= 1.0 {
            selectionProgress = animationTargetProgress
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    // MARK: - Mouse Handling

    public override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        isRightSelected = location.x > bounds.width / 2
    }

    // MARK: - Keyboard Handling

    public override var acceptsFirstResponder: Bool { true }
    public override var canBecomeKeyView: Bool { true }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.space:
            isRightSelected.toggle()
        case KeyCode.return:
            isRightSelected.toggle()
            // Move to previous key view
            if let previousKeyView = self.previousKeyView {
                window?.makeFirstResponder(previousKeyView)
            }
        case KeyCode.leftArrow:
            isRightSelected = false
        case KeyCode.rightArrow:
            isRightSelected = true
        default:
            super.keyDown(with: event)
        }
    }

    public override func becomeFirstResponder() -> Bool {
        let innerBorderWidth: CGFloat = 2.0
        let totalBorderWidth = innerBorderWidth + outerBorderWidth
        let expandedRect = bounds.insetBy(dx: -totalBorderWidth, dy: -totalBorderWidth)
        setNeedsDisplay(expandedRect)
        return super.becomeFirstResponder()
    }

    public override func resignFirstResponder() -> Bool {
        let innerBorderWidth: CGFloat = 2.0
        let totalBorderWidth = innerBorderWidth + outerBorderWidth
        let expandedRect = bounds.insetBy(dx: -totalBorderWidth, dy: -totalBorderWidth)
        setNeedsDisplay(expandedRect)
        return super.resignFirstResponder()
    }

    // MARK: - Layout

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    deinit {
        animationTimer?.invalidate()
    }
}

#endif
