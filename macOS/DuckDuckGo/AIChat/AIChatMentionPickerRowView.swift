//
//  AIChatMentionPickerRowView.swift
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

/// A single row inside the omnibar's `@`-mention picker panel.
///
/// Visually a sibling of `AIChatTabPickerMenuRowView` (same favicon / title / leading
/// checkmark layout) but tuned for the non-activating `NSPanel` context rather than for
/// hosting inside an `NSMenuItem.view`:
///
/// 1. Hover state is owned by `AIChatMentionPickerViewController` (one centralized
///    `NSTrackingArea` on the scroll view's document) rather than by each row individually.
///    Per-row tracking areas were flaky during fast scroll: rapid `mouseEntered:` events
///    fired without paired `mouseExited:` callbacks, leaving multiple rows visually
///    "highlighted" at once. Centralizing the tracking is the standard AppKit fix.
/// 2. `isHighlighted` is set by the VC for both keyboard nav (M12 arrows / Enter) and
///    mouse hover — there's only one highlighted row at a time, period. The visual
///    feedback is identical for either source.
/// 3. The click handler ACCEPTS the row (calls `onAccept`); it doesn't locally toggle an
///    `isAttached` state the way the menu row does. The accept handler in the coordinator
///    decides whether to add or remove the attachment based on the current state.
/// 4. Optional trailing accessory text (e.g. "(Current Tab)") rendered in secondary color.
final class AIChatMentionPickerRowView: NSView {

    enum Layout {
        static let height: CGFloat = 24
        static let leadingPadding: CGFloat = 6
        static let trailingPadding: CGFloat = 10
        static let checkmarkSize: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let spacingAfterCheckmark: CGFloat = 6
        static let spacingAfterIcon: CGFloat = 6
        static let spacingBeforeAccessory: CGFloat = 8
        /// Tightened from 4 → 2: the selection fill should track the row's edges closely
        /// instead of leaving a visible band of "row but not selected" pixels.
        static let selectionInset: CGFloat = 2
        static let selectionCornerRadius: CGFloat = 5
    }

    private let checkmarkView = NSImageView()
    private let faviconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let accessoryLabel = NSTextField(labelWithString: "")
    /// Cached width of the trailing "(Current Tab)" badge. Computed once at init time so
    /// scrolling — which can trigger many `layout()` passes — doesn't pay for `sizeToFit()`
    /// per row per tick.
    private let accessoryWidth: CGFloat

    /// The tab this row represents. Surfaced so the coordinator can route an accept event
    /// back to the right attachment without keeping a parallel index array.
    let attachment: AIChatTabAttachment

    /// Called when the user clicks this row. The picker coordinator decides whether to
    /// attach or detach based on the current `activeTabAttachments` state.
    var onAccept: (() -> Void)?

    var isAttached: Bool = false {
        didSet { checkmarkView.isHidden = !isAttached }
    }

    /// Single highlight flag, driven by the VC for both keyboard nav and mouse hover. The
    /// row never sets this itself — there's no per-row tracking area to compete with the
    /// VC's centralized hit-testing.
    var isHighlighted: Bool = false {
        didSet {
            guard oldValue != isHighlighted else { return }
            needsDisplay = true
            updateColors()
        }
    }

    init(attachment: AIChatTabAttachment, isCurrentTab: Bool, isAttached: Bool) {
        self.attachment = attachment
        let menuFont = NSFont.menuFont(ofSize: 0)
        // Measure the accessory once — text is fixed at init time and never changes.
        if isCurrentTab {
            let attributed = NSAttributedString(
                string: UserText.aiChatTabPickerCurrentTabSuffix,
                attributes: [.font: menuFont]
            )
            self.accessoryWidth = ceil(attributed.size().width)
        } else {
            self.accessoryWidth = 0
        }
        super.init(frame: .zero)
        self.isAttached = isAttached
        autoresizesSubviews = true
        // Layer-backing lets AppKit composite the scrolling stack instead of redrawing
        // via CoreGraphics on every tick, which makes the picker feel a lot smoother
        // under fast trackpad scroll.
        wantsLayer = true

        // Checkmark slot — its space is always reserved, so the column of favicons and
        // titles aligns across attached / unattached rows.
        let checkmarkImage = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
        checkmarkImage?.isTemplate = true
        checkmarkView.image = checkmarkImage
        checkmarkView.imageScaling = .scaleProportionallyUpOrDown
        checkmarkView.isHidden = !isAttached
        addSubview(checkmarkView)

        faviconView.imageScaling = .scaleProportionallyUpOrDown
        faviconView.image = attachment.favicon ?? NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        addSubview(faviconView)

        titleLabel.font = menuFont
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.usesSingleLineMode = true
        titleLabel.stringValue = attachment.title.isEmpty ? (attachment.url.host ?? attachment.url.absoluteString) : attachment.title
        titleLabel.toolTip = attachment.url.absoluteString
        addSubview(titleLabel)

        accessoryLabel.font = menuFont
        accessoryLabel.textColor = .secondaryLabelColor
        accessoryLabel.lineBreakMode = .byClipping
        accessoryLabel.maximumNumberOfLines = 1
        accessoryLabel.usesSingleLineMode = true
        accessoryLabel.stringValue = isCurrentTab ? UserText.aiChatTabPickerCurrentTabSuffix : ""
        accessoryLabel.isHidden = !isCurrentTab
        addSubview(accessoryLabel)

        updateColors()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        // Width is determined by the picker controller via the row's frame; we report a
        // height-only intrinsic size.
        NSSize(width: NSView.noIntrinsicMetric, height: Layout.height)
    }

    override func layout() {
        super.layout()
        let height = bounds.height

        let checkmarkX = Layout.leadingPadding
        checkmarkView.frame = NSRect(
            x: checkmarkX,
            y: (height - Layout.checkmarkSize) / 2,
            width: Layout.checkmarkSize,
            height: Layout.checkmarkSize
        )

        let faviconX = checkmarkX + Layout.checkmarkSize + Layout.spacingAfterCheckmark
        faviconView.frame = NSRect(
            x: faviconX,
            y: (height - Layout.iconSize) / 2,
            width: Layout.iconSize,
            height: Layout.iconSize
        )

        let menuFont = NSFont.menuFont(ofSize: 0)
        let textHeight = ceil(menuFont.ascender - menuFont.descender)
        let textY = (height - textHeight) / 2

        // Accessory ("(Current Tab)") sits at the trailing edge with a width measured once
        // at init time; title gets whatever remains and truncates with `…`.
        let titleX = faviconX + Layout.iconSize + Layout.spacingAfterIcon
        let availableForTitleAndAccessory = bounds.width - titleX - Layout.trailingPadding
        let titleWidth: CGFloat
        if accessoryWidth > 0 {
            titleWidth = max(0, availableForTitleAndAccessory - Layout.spacingBeforeAccessory - accessoryWidth)
        } else {
            titleWidth = max(0, availableForTitleAndAccessory)
        }
        titleLabel.frame = NSRect(x: titleX, y: textY, width: titleWidth, height: textHeight)

        if accessoryWidth > 0 {
            let accessoryX = bounds.width - Layout.trailingPadding - accessoryWidth
            accessoryLabel.frame = NSRect(x: accessoryX, y: textY, width: accessoryWidth, height: textHeight)
        }
    }

    /// Width this row would need to fit its content without truncation. Used by the
    /// picker view controller to pick a panel width that matches the longest title in
    /// the current filter (capped at `AIChatMentionPickerViewController`'s max width).
    static func naturalContentWidth(forTitle title: String, isCurrentTab: Bool) -> CGFloat {
        let menuFont = NSFont.menuFont(ofSize: 0)
        let titleAttributed = NSAttributedString(string: title, attributes: [.font: menuFont])
        let titleWidth = ceil(titleAttributed.size().width)
        let accessoryWidth: CGFloat
        if isCurrentTab {
            let accessoryAttributed = NSAttributedString(
                string: UserText.aiChatTabPickerCurrentTabSuffix,
                attributes: [.font: menuFont]
            )
            accessoryWidth = ceil(accessoryAttributed.size().width) + Layout.spacingBeforeAccessory
        } else {
            accessoryWidth = 0
        }
        return Layout.leadingPadding
            + Layout.checkmarkSize
            + Layout.spacingAfterCheckmark
            + Layout.iconSize
            + Layout.spacingAfterIcon
            + titleWidth
            + accessoryWidth
            + Layout.trailingPadding
    }

    // MARK: - Highlight rendering

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isHighlighted else { return }
        let selectionRect = bounds.insetBy(dx: Layout.selectionInset, dy: 0)
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(roundedRect: selectionRect, xRadius: Layout.selectionCornerRadius, yRadius: Layout.selectionCornerRadius).fill()
    }

    private func updateColors() {
        let foreground: NSColor = isHighlighted ? .alternateSelectedControlTextColor : .labelColor
        titleLabel.textColor = foreground
        checkmarkView.contentTintColor = foreground
        // Keep the accessory in the muted color when unselected; flip to the selection's
        // foreground (slightly de-emphasized) when the row is highlighted.
        accessoryLabel.textColor = isHighlighted ? .alternateSelectedControlTextColor.withAlphaComponent(0.85) : .secondaryLabelColor
    }

    // MARK: - Click handling

    override func mouseDown(with event: NSEvent) {
        // Swallow the press half; we accept on mouseUp inside the row's bounds so a drag-out
        // doesn't fire the action (standard AppKit list semantics).
    }

    override func mouseUp(with event: NSEvent) {
        let pointInView = convert(event.locationInWindow, from: nil)
        guard bounds.contains(pointInView) else { return }
        onAccept?()
    }
}
