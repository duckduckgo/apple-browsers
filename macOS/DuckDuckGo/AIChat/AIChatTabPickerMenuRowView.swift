//
//  AIChatTabPickerMenuRowView.swift
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

/// A custom row hosted as `NSMenuItem.view` inside the omnibar's "Attach Page Content" submenu.
///
/// Why a custom view: a normal `NSMenuItem` action dismisses the menu the moment the user clicks.
/// We need the submenu to **stay open** while the user toggles tabs on and off, so the row owns
/// its own `mouseDown:` / `mouseUp:` and never triggers an item action — `NSMenu` doesn't see an
/// activation, so the submenu remains open. Same idiom AppKit uses to host sliders and switches
/// inside menus.
///
/// Layout is intentionally frame-based with an `intrinsicContentSize`: `NSMenuItem.view` items
/// behave more predictably when the row sizes itself directly than when they fight `NSMenu`'s
/// own measurement pass through AutoLayout. The leading checkmark slot is always reserved (even
/// when the row isn't attached) so all rows in the submenu align consistently.
final class AIChatTabPickerMenuRowView: NSView {

    private enum Layout {
        static let height: CGFloat = 22
        static let width: CGFloat = 280
        static let leadingPadding: CGFloat = 4
        static let trailingPadding: CGFloat = 14
        static let checkmarkSize: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let spacingAfterCheckmark: CGFloat = 6
        static let spacingAfterIcon: CGFloat = 4
    }

    private let checkmarkView = NSImageView()
    private let faviconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private var trackingArea: NSTrackingArea?

    private(set) var isAttached: Bool {
        didSet { checkmarkView.isHidden = !isAttached }
    }

    private var isHovering: Bool = false {
        didSet {
            guard oldValue != isHovering else { return }
            updateColors()
            needsDisplay = true
        }
    }

    private let onToggle: () -> Void

    override var intrinsicContentSize: NSSize {
        NSSize(width: Layout.width, height: Layout.height)
    }

    init(attachment: AIChatTabAttachment, isAttached: Bool, onToggle: @escaping () -> Void) {
        self.isAttached = isAttached
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))

        autoresizesSubviews = true

        // Checkmark slot (leading) — its space is reserved unconditionally so favicon and title
        // line up across attached / unattached rows. Rendered in `labelColor` to match the
        // native menu checkmark style instead of the accent-coloured variant.
        let checkmarkY = (Layout.height - Layout.checkmarkSize) / 2
        checkmarkView.frame = NSRect(
            x: Layout.leadingPadding,
            y: checkmarkY,
            width: Layout.checkmarkSize,
            height: Layout.checkmarkSize
        )
        let checkmarkImage = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        checkmarkImage?.isTemplate = true // ensures `contentTintColor` is honored.
        checkmarkView.image = checkmarkImage
        checkmarkView.imageScaling = .scaleProportionallyUpOrDown
        checkmarkView.isHidden = !isAttached
        checkmarkView.autoresizingMask = []
        addSubview(checkmarkView)

        // Favicon (after the reserved checkmark slot)
        let faviconX = Layout.leadingPadding + Layout.checkmarkSize + Layout.spacingAfterCheckmark
        let faviconY = (Layout.height - Layout.iconSize) / 2
        faviconView.frame = NSRect(
            x: faviconX,
            y: faviconY,
            width: Layout.iconSize,
            height: Layout.iconSize
        )
        faviconView.imageScaling = .scaleProportionallyUpOrDown
        faviconView.image = attachment.favicon ?? NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        faviconView.autoresizingMask = []
        addSubview(faviconView)

        // Title — sized to its natural height and vertically centered. Filling the row's full
        // height would leave the text top-aligned (NSTextField's default) which makes the title
        // sit higher than the favicon; computing the height from the font's line metrics and
        // recentering matches AppKit's standard menu-item baseline.
        let titleX = faviconX + Layout.iconSize + Layout.spacingAfterIcon
        let titleWidth = Layout.width - titleX - Layout.trailingPadding
        let menuFont = NSFont.menuFont(ofSize: 0)
        titleLabel.font = menuFont
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.usesSingleLineMode = true
        titleLabel.stringValue = attachment.title.isEmpty ? attachment.url.host ?? attachment.url.absoluteString : attachment.title
        titleLabel.toolTip = attachment.url.absoluteString
        let titleHeight = ceil(menuFont.ascender - menuFont.descender)
        titleLabel.frame = NSRect(
            x: titleX,
            y: (Layout.height - titleHeight) / 2,
            width: titleWidth,
            height: titleHeight
        )
        titleLabel.autoresizingMask = [.width]
        addSubview(titleLabel)

        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateColors() {
        // Mirror native menu rendering: foreground in `labelColor` normally, and switching to
        // `alternateSelectedControlTextColor` (white) over the accent-coloured hover background
        // so the checkmark and title stay readable.
        let foreground: NSColor = isHovering ? .alternateSelectedControlTextColor : .labelColor
        titleLabel.textColor = foreground
        checkmarkView.contentTintColor = foreground
    }

    // MARK: - Hover highlight

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if isHovering {
            // System-wide selection background, accent-aware in macOS 11+. Replaces the deprecated
            // `selectedMenuItemColor` and matches what AppKit menus and source lists use.
            NSColor.selectedContentBackgroundColor.setFill()
            dirtyRect.fill()
        }
    }

    // MARK: - Click handling (the keep-menu-open trick)

    /// `NSMenu` would normally close on `mouseUp:` if we let the click bubble back as an item
    /// activation. Toggling locally here without chaining to `super` keeps the submenu open.
    override func mouseUp(with event: NSEvent) {
        let pointInView = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pointInView) else { return }
        isAttached.toggle()
        onToggle()
    }

    /// We override `mouseDown:` solely to consume the press half of the click. Without this,
    /// `NSMenu`'s tracking session may treat the press as a normal item activation and dismiss
    /// the menu before our `mouseUp:` runs.
    override func mouseDown(with event: NSEvent) {
        // Intentionally empty: swallow the press, wait for `mouseUp:`.
    }
}
