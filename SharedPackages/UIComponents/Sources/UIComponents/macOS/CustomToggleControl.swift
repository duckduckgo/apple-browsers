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
        static let tab: UInt16 = 48
        static let space: UInt16 = 49
        static let `return`: UInt16 = 36
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
    }

    // MARK: - Properties

    /// The number of segments in the control (always 2 for this toggle)
    public var segmentCount: Int { 2 }

    /// The index of the selected segment (0 = left, 1 = right)
    public var selectedSegment: Int {
        get {
            return _selectedSegment
        }
        set {
            guard newValue >= 0 && newValue < segmentCount else { return }
            if _selectedSegment != newValue {
                _selectedSegment = newValue
                animateSelection()
                sendAction(action, to: target)
            }
        }
    }

    private var _selectedSegment: Int = 0

    public var leftImage: NSImage? {
        didSet { needsDisplay = true }
    }

    public var rightImage: NSImage? {
        didSet { needsDisplay = true }
    }

    public var leftSelectedImage: NSImage? {
        didSet { needsDisplay = true }
    }

    public var rightSelectedImage: NSImage? {
        didSet { needsDisplay = true }
    }

    public var iconTintColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
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

    private var leftSegmentToolTip: String?
    private var rightSegmentToolTip: String?

    // MARK: - Label Properties

    private var leftLabel: String?
    private var rightLabel: String?

    public var labelFont: NSFont = NSFont.systemFont(ofSize: 13, weight: .regular) {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    public var labelColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }

    public var selectedLabelColor: NSColor = .labelColor {
        didSet { needsDisplay = true }
    }

    public private(set) var isExpanded: Bool = false
    private var expansionProgress: CGFloat = 0.0

    private var expansionAnimationTimer: Timer?
    private var expansionAnimationStartTime: CFTimeInterval = 0
    private var expansionAnimationStartProgress: CGFloat = 0.0
    private var expansionAnimationTargetProgress: CGFloat = 0.0
    private let expansionAnimationDuration: CFTimeInterval = 0.2

    public var onWidthChange: ((CGFloat) -> Void)?
    public var collapsedWidth: CGFloat = 70
    private let iconLabelSpacing: CGFloat = 4
    private let segmentPadding: CGFloat = 8
    private let labelTrailingPadding: CGFloat = 8

    // MARK: - Width Calculation

    public var expandedWidth: CGFloat {
        let leftLabelWidth = labelWidth(for: leftLabel)
        let rightLabelWidth = labelWidth(for: rightLabel)

        // Each segment needs: padding + icon + spacing + label + labelTrailingPadding + padding
        let iconWidth: CGFloat = 16
        let leftSegmentWidth = segmentPadding + iconWidth + (leftLabel != nil ? iconLabelSpacing + leftLabelWidth + labelTrailingPadding : 0) + segmentPadding
        let rightSegmentWidth = segmentPadding + iconWidth + (rightLabel != nil ? iconLabelSpacing + rightLabelWidth + labelTrailingPadding : 0) + segmentPadding

        return leftSegmentWidth + rightSegmentWidth + 4 // 4 for indicator gaps
    }

    public var currentWidth: CGFloat {
        let collapsed = collapsedWidth
        let expanded = expandedWidth
        return collapsed + (expanded - collapsed) * expansionProgress
    }

    private func labelWidth(for label: String?) -> CGFloat {
        guard let label = label else { return 0 }
        let attributes: [NSAttributedString.Key: Any] = [.font: labelFont]
        let size = (label as NSString).size(withAttributes: attributes)
        return ceil(size.width)
    }

    // MARK: - Public API Methods

    /// Sets the label for the specified segment
    /// - Parameters:
    ///   - label: The label text to display
    ///   - segment: The index of the segment (0 = left, 1 = right)
    public func setLabel(_ label: String?, forSegment segment: Int) {
        guard segment >= 0 && segment < segmentCount else { return }
        if segment == 0 {
            leftLabel = label
        } else {
            rightLabel = label
        }
        invalidateIntrinsicContentSize()
        needsDisplay = true
    }

    /// Returns the label for the specified segment
    /// - Parameter segment: The index of the segment (0 = left, 1 = right)
    /// - Returns: The label text for the segment, or nil if none is set
    public func label(forSegment segment: Int) -> String? {
        guard segment >= 0 && segment < segmentCount else { return nil }
        return segment == 0 ? leftLabel : rightLabel
    }

    /// Sets the expanded state of the control
    /// - Parameters:
    ///   - expanded: Whether to show labels (expanded) or hide them (collapsed)
    ///   - animated: Whether to animate the transition
    public func setExpanded(_ expanded: Bool, animated: Bool) {
        guard isExpanded != expanded else { return }
        isExpanded = expanded

        if animated {
            animateExpansion(to: expanded)
        } else {
            expansionProgress = expanded ? 1.0 : 0.0
            expansionAnimationTimer?.invalidate()
            expansionAnimationTimer = nil
            onWidthChange?(currentWidth)
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// Sets the tooltip for the specified segment
    /// - Parameters:
    ///   - toolTip: The tooltip text to display
    ///   - segment: The index of the segment (0 = left, 1 = right)
    public func setToolTip(_ toolTip: String?, forSegment segment: Int) {
        guard segment >= 0 && segment < segmentCount else { return }
        if segment == 0 {
            leftSegmentToolTip = toolTip
        } else {
            rightSegmentToolTip = toolTip
        }
    }

    /// Returns the tooltip for the specified segment
    /// - Parameter segment: The index of the segment (0 = left, 1 = right)
    /// - Returns: The tooltip text for the segment, or nil if none is set
    public func toolTip(forSegment segment: Int) -> String? {
        guard segment >= 0 && segment < segmentCount else { return nil }
        return segment == 0 ? leftSegmentToolTip : rightSegmentToolTip
    }

    /// Sets the selection state for the specified segment
    /// - Parameters:
    ///   - selected: Whether the segment should be selected
    ///   - segment: The index of the segment (0 = left, 1 = right)
    public func setSelected(_ selected: Bool, forSegment segment: Int) {
        guard segment >= 0 && segment < segmentCount else { return }
        if selected {
            selectedSegment = segment
        }
    }

    /// Returns whether the specified segment is selected
    /// - Parameter segment: The index of the segment (0 = left, 1 = right)
    /// - Returns: true if the segment is selected, false otherwise
    public func isSelected(forSegment segment: Int) -> Bool {
        guard segment >= 0 && segment < segmentCount else { return false }
        return selectedSegment == segment
    }

    /// Sets the image for the specified segment
    /// - Parameters:
    ///   - image: The image to display
    ///   - segment: The index of the segment (0 = left, 1 = right)
    public func setImage(_ image: NSImage?, forSegment segment: Int) {
        guard segment >= 0 && segment < segmentCount else { return }
        if segment == 0 {
            leftImage = image
        } else {
            rightImage = image
        }
    }

    /// Returns the image for the specified segment
    /// - Parameter segment: The index of the segment (0 = left, 1 = right)
    /// - Returns: The image for the segment, or nil if none is set
    public func image(forSegment segment: Int) -> NSImage? {
        guard segment >= 0 && segment < segmentCount else { return nil }
        return segment == 0 ? leftImage : rightImage
    }

    /// Sets the selected image for the specified segment
    /// - Parameters:
    ///   - image: The image to display when selected
    ///   - segment: The index of the segment (0 = left, 1 = right)
    public func setSelectedImage(_ image: NSImage?, forSegment segment: Int) {
        guard segment >= 0 && segment < segmentCount else { return }
        if segment == 0 {
            leftSelectedImage = image
        } else {
            rightSelectedImage = image
        }
    }

    /// Returns the selected image for the specified segment
    /// - Parameter segment: The index of the segment (0 = left, 1 = right)
    /// - Returns: The selected image for the segment, or nil if none is set
    public func selectedImage(forSegment segment: Int) -> NSImage? {
        guard segment >= 0 && segment < segmentCount else { return nil }
        return segment == 0 ? leftSelectedImage : rightSelectedImage
    }

    /// Resets the control to segment 0 without triggering the action
    public func reset() {
        guard _selectedSegment != 0 else { return }
        _selectedSegment = 0
        animateSelection()
    }

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

        let isLeftSelected = selectedSegment == 0
        let isRightSelected = selectedSegment == 1

        if let leftImg = (isLeftSelected && leftSelectedImage != nil) ? leftSelectedImage : leftImage {
            drawSegmentContent(image: leftImg, label: leftLabel, in: leftRect, isSelected: isLeftSelected)
        }

        if let rightImg = (isRightSelected && rightSelectedImage != nil) ? rightSelectedImage : rightImage {
            drawSegmentContent(image: rightImg, label: rightLabel, in: rightRect, isSelected: isRightSelected)
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

    private func drawSegmentContent(image: NSImage, label: String?, in rect: NSRect, isSelected: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.clip(to: rect)

        let imageSize = image.size

        let currentLabelWidth = labelWidth(for: label) * expansionProgress

        let hasVisibleLabel = label != nil && expansionProgress > 0
        let spacing = hasVisibleLabel ? iconLabelSpacing : 0
        let totalContentWidth = imageSize.width + spacing + currentLabelWidth

        let contentStartX = rect.midX - totalContentWidth / 2

        let imageRect = NSRect(
            x: contentStartX,
            y: rect.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        )
        drawImage(image, in: imageRect, alpha: 1.0)

        if let label = label, expansionProgress > 0 {
            let textColor = isSelected ? selectedLabelColor : labelColor
            let attributes: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: textColor.withAlphaComponent(expansionProgress)
            ]

            let labelX = imageRect.maxX + iconLabelSpacing
            let labelSize = (label as NSString).size(withAttributes: attributes)
            let labelY = rect.midY - labelSize.height / 2

            let labelRect = NSRect(x: labelX, y: labelY, width: labelSize.width, height: labelSize.height)
            (label as NSString).draw(in: labelRect, withAttributes: attributes)
        }

        context.restoreGState()
    }

    private func drawImage(_ image: NSImage, in rect: NSRect, alpha: CGFloat) {
        NSGraphicsContext.current?.imageInterpolation = .high

        // For template images, we need to manually tint them for proper color rendering
        if image.isTemplate {
            let tintedImage = NSImage(size: image.size, flipped: false) { bounds in
                self.iconTintColor.set()
                bounds.fill()

                image.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1.0)
                return true
            }

            tintedImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
        } else {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
        }
    }

    // MARK: - Animation

    private func animateSelection() {
        animationTargetProgress = selectedSegment == 1 ? 1.0 : 0.0
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

        let easedProgress = (1 - cos(progress * .pi)) / 2
        selectionProgress = animationStartProgress + (animationTargetProgress - animationStartProgress) * easedProgress

        needsDisplay = true

        if progress >= 1.0 {
            selectionProgress = animationTargetProgress
            animationTimer?.invalidate()
            animationTimer = nil
        }
    }

    private func animateExpansion(to expanded: Bool) {
        expansionAnimationTargetProgress = expanded ? 1.0 : 0.0
        expansionAnimationStartProgress = expansionProgress
        expansionAnimationStartTime = CACurrentMediaTime()

        expansionAnimationTimer?.invalidate()
        expansionAnimationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateExpansionAnimation()
        }
    }

    @objc private func updateExpansionAnimation() {
        let elapsed = CACurrentMediaTime() - expansionAnimationStartTime
        let progress = min(elapsed / expansionAnimationDuration, 1.0)

        let easedProgress = (1 - cos(progress * .pi)) / 2
        expansionProgress = expansionAnimationStartProgress + (expansionAnimationTargetProgress - expansionAnimationStartProgress) * easedProgress

        onWidthChange?(currentWidth)
        invalidateIntrinsicContentSize()
        needsDisplay = true

        if progress >= 1.0 {
            expansionProgress = expansionAnimationTargetProgress
            expansionAnimationTimer?.invalidate()
            expansionAnimationTimer = nil
        }
    }

    public override var intrinsicContentSize: NSSize {
        return NSSize(width: currentWidth, height: NSView.noIntrinsicMetric)
    }

    // MARK: - Mouse Handling

    public override func mouseDown(with event: NSEvent) {
        if event.buttonNumber == 1 || (event.modifierFlags.contains(.control) && event.buttonNumber == 0) {
            rightMouseDown(with: event)
            return
        }

        let location = convert(event.locationInWindow, from: nil)
        selectedSegment = location.x > bounds.width / 2 ? 1 : 0

        if isExpanded {
            setExpanded(false, animated: true)
        }
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let menu = menu {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        } else {
            super.rightMouseDown(with: event)
        }
    }

    public override func menu(for event: NSEvent) -> NSMenu? {
        return menu
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateToolTipForMouseLocation(event.locationInWindow)
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateToolTipForMouseLocation(event.locationInWindow)
    }

    private func updateToolTipForMouseLocation(_ locationInWindow: NSPoint) {
        let location = convert(locationInWindow, from: nil)
        let segment = location.x > bounds.width / 2 ? 1 : 0
        let newToolTip = segment == 0 ? leftSegmentToolTip : rightSegmentToolTip

        if super.toolTip != newToolTip {
            super.toolTip = newToolTip
        }
    }

    // MARK: - Keyboard Handling

    public override var acceptsFirstResponder: Bool { true }
    public override var canBecomeKeyView: Bool { true }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyCode.space, KeyCode.return:
            selectedSegment = selectedSegment == 0 ? 1 : 0
        case KeyCode.leftArrow:
            selectedSegment = 0
        case KeyCode.rightArrow:
            selectedSegment = 1
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
            options: [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        updateTrackingAreas()
        super.toolTip = nil
    }

    public override func viewDidHide() {
        super.viewDidHide()
        super.toolTip = nil
    }

    public override var isHidden: Bool {
        didSet {
            if !isHidden {
                updateTrackingAreas()
                super.toolTip = nil

                if let window = window {
                    let mouseLocationInWindow = window.mouseLocationOutsideOfEventStream
                    let mouseLocationInView = convert(mouseLocationInWindow, from: nil)
                    if bounds.contains(mouseLocationInView) {
                        updateToolTipForMouseLocation(mouseLocationInWindow)
                    }
                }
            }
        }
    }

    deinit {
        animationTimer?.invalidate()
        expansionAnimationTimer?.invalidate()
    }
}

#endif
