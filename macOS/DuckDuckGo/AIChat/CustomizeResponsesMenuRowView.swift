//
//  CustomizeResponsesMenuRowView.swift
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

import Cocoa

final class CustomizeResponsesMenuRowView: NSView {

    private enum Layout {
        static let width: CGFloat = 300
        static let height: CGFloat = 44
        static let leadingPadding: CGFloat = 16
        static let trailingPadding: CGFloat = 14
        static let iconSize: CGFloat = 16
        static let spacingAfterIcon: CGFloat = 4
        static let switchSpacing: CGFloat = 8
        static let lineGap: CGFloat = 2
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let switchControl = NSSwitch()
    private var trackingArea: NSTrackingArea?

    private let showsToggle: Bool
    private let onOpen: () -> Void
    private let onToggle: (Bool) -> Void

    private var isHovering = false {
        didSet {
            guard oldValue != isHovering else { return }
            updateColors()
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: Layout.width, height: Layout.height) }

    init(title: String,
         subtitle: String,
         icon: NSImage?,
         showsToggle: Bool,
         isActive: Bool,
         onOpen: @escaping () -> Void,
         onToggle: @escaping (Bool) -> Void) {
        self.showsToggle = showsToggle
        self.onOpen = onOpen
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
        autoresizesSubviews = true

        let iconY = (Layout.height - Layout.iconSize) / 2
        iconView.frame = NSRect(x: Layout.leadingPadding, y: iconY, width: Layout.iconSize, height: Layout.iconSize)
        icon?.isTemplate = true
        iconView.image = icon
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.autoresizingMask = []
        addSubview(iconView)

        switchControl.state = isActive ? .on : .off
        switchControl.isHidden = !showsToggle
        let switchSize = switchControl.intrinsicContentSize
        let switchX = Layout.width - Layout.trailingPadding - switchSize.width
        switchControl.frame = NSRect(x: switchX, y: (Layout.height - switchSize.height) / 2, width: switchSize.width, height: switchSize.height)
        switchControl.autoresizingMask = [.minXMargin]
        addSubview(switchControl)

        let titleFont = NSFont.systemFont(ofSize: 13)
        let subtitleFont = NSFont.systemFont(ofSize: 11)
        let titleHeight = ceil(titleFont.ascender - titleFont.descender)
        let subtitleHeight = ceil(subtitleFont.ascender - subtitleFont.descender)
        let block = titleHeight + Layout.lineGap + subtitleHeight
        let blockBottom = (Layout.height - block) / 2

        let textX = Layout.leadingPadding + Layout.iconSize + Layout.spacingAfterIcon
        let textRight = showsToggle ? switchX - Layout.switchSpacing : Layout.width - Layout.trailingPadding
        let textWidth = max(0, textRight - textX)

        titleLabel.font = titleFont
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.usesSingleLineMode = true
        titleLabel.maximumNumberOfLines = 1
        titleLabel.stringValue = title
        titleLabel.frame = NSRect(x: textX, y: blockBottom + subtitleHeight + Layout.lineGap, width: textWidth, height: titleHeight)
        titleLabel.autoresizingMask = [.width]
        addSubview(titleLabel)

        subtitleLabel.font = subtitleFont
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.usesSingleLineMode = true
        subtitleLabel.maximumNumberOfLines = 1
        subtitleLabel.stringValue = subtitle
        subtitleLabel.frame = NSRect(x: textX, y: blockBottom, width: textWidth, height: subtitleHeight)
        subtitleLabel.autoresizingMask = [.width]
        addSubview(subtitleLabel)

        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateColors() {
        let foreground: NSColor = isHovering ? .alternateSelectedControlTextColor : .labelColor
        titleLabel.textColor = foreground
        iconView.contentTintColor = foreground
        subtitleLabel.textColor = isHovering
            ? .alternateSelectedControlTextColor.withAlphaComponent(0.85)
            : .secondaryLabelColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovering {
            let selectionRect = bounds.insetBy(dx: 5, dy: 0)
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: selectionRect, xRadius: 5, yRadius: 5).fill()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point) else { return }

        if showsToggle, switchControl.frame.insetBy(dx: -6, dy: -6).contains(point) {
            let newActive = switchControl.state != .on
            switchControl.state = newActive ? .on : .off
            onToggle(newActive)
            return
        }

        enclosingMenuItem?.menu?.cancelTracking()
        let open = onOpen
        DispatchQueue.main.async { open() }
    }
}
