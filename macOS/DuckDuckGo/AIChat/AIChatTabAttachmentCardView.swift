//
//  AIChatTabAttachmentCardView.swift
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

/// A horizontal card representing one tab the user has attached to the duck.ai omnibar prompt.
/// Sits in `AIChatAttachmentsCarouselView` alongside the image and file thumbnails.
///
/// Visual structure mirrors how the duck.ai web app renders attached pages: a 36×36 page-thumbnail
/// graphic on the leading edge (favicon plus the stylised "text bars" that suggest page content),
/// the page title in bold next to it, and a circular close button overflowing the top-right
/// corner like the image-attachments thumbnail. Border/background colours come from the design
/// system so the card matches the rest of the omnibar surface.
final class AIChatTabAttachmentCardView: NSView {

    private enum Constants {
        static let cardWidth: CGFloat = 224
        static let cardHeight: CGFloat = 56
        static let cornerRadius: CGFloat = 12
        static let leadingPadding: CGFloat = 10
        static let trailingPadding: CGFloat = 14
        static let thumbnailSize: CGFloat = 36
        static let spacingAfterThumbnail: CGFloat = 12
        static let removeButtonSize: CGFloat = 20
        static let removeButtonOverflow: CGFloat = 6
        static let removeButtonInset: CGFloat = 4
        static let shadowRadius: CGFloat = 3
        static let shadowOpacity: Float = 0.15
        static let shadowOffset = CGSize(width: 0, height: -1)

        static let removeButtonBackgroundColorName = "AIChatRemoveButtonBackgroundColor"
        static let removeButtonIconColorName = "AIChatRemoveButtonIconColor"
    }

    /// Total height of the view including the remove button's vertical overflow.
    static let totalHeight: CGFloat = Constants.cardHeight + Constants.removeButtonOverflow

    let attachmentId: String
    var onRemove: ((String) -> Void)?

    private let cardView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = Constants.cornerRadius
        view.layer?.masksToBounds = true
        return view
    }()

    /// Sibling backing view sitting just behind `cardView` with the same shape and a
    /// `masksToBounds = false` layer. Layer shadows can't render on a view whose layer clips to
    /// bounds (which `cardView` must, to round-clip the page preview), so the shadow lives here.
    private let shadowBackingView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.shadow = NSShadow()
        view.layer?.cornerRadius = Constants.cornerRadius
        view.layer?.shadowColor = NSColor.black.cgColor
        view.layer?.shadowRadius = Constants.shadowRadius
        view.layer?.shadowOpacity = Constants.shadowOpacity
        view.layer?.shadowOffset = Constants.shadowOffset
        view.layer?.masksToBounds = false
        return view
    }()

    private let pagePreviewView: AIChatTabPagePreviewView

    private let titleLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1
        label.usesSingleLineMode = true
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        return label
    }()

    private let removeButton: PointingHandButton = {
        let button = PointingHandButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .shadowlessSquare
        button.isBordered = false
        button.title = ""
        button.imageScaling = .scaleProportionallyDown
        button.setAccessibilityRole(.button)
        button.setAccessibilityLabel(UserText.aiChatRemoveAttachmentButtonAccessibility)
        return button
    }()

    init(attachment: AIChatTabAttachment) {
        self.attachmentId = attachment.id
        self.pagePreviewView = AIChatTabPagePreviewView(favicon: attachment.favicon)
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        addSubview(shadowBackingView)
        addSubview(cardView)
        cardView.addSubview(pagePreviewView)
        cardView.addSubview(titleLabel)
        addSubview(removeButton) // outside the card so its overflow can clip past the corner.

        let displayTitle = attachment.title.isEmpty ? attachment.url.host ?? attachment.url.absoluteString : attachment.title
        titleLabel.stringValue = displayTitle
        // Surface the full title on hover (the most useful thing to disambiguate truncated entries);
        // the URL would be more accurate but is rarely what the user wants to read.
        titleLabel.toolTip = displayTitle

        removeButton.image = DesignSystemImages.Glyphs.Size16.clearSolid
        removeButton.imageScaling = .scaleNone
        removeButton.toolTip = UserText.aiChatRemoveAttachmentButtonTooltip
        removeButton.wantsLayer = true
        removeButton.layer?.cornerRadius = Constants.removeButtonSize / 2
        removeButton.layer?.borderWidth = 1
        removeButton.layer?.masksToBounds = true
        removeButton.target = self
        removeButton.action = #selector(removeButtonClicked)

        NSLayoutConstraint.activate([
            cardView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cardView.bottomAnchor.constraint(equalTo: bottomAnchor),
            cardView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.removeButtonOverflow),
            cardView.widthAnchor.constraint(equalToConstant: Constants.cardWidth),
            cardView.heightAnchor.constraint(equalToConstant: Constants.cardHeight),

            shadowBackingView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            shadowBackingView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            shadowBackingView.topAnchor.constraint(equalTo: cardView.topAnchor),
            shadowBackingView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            pagePreviewView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.leadingPadding),
            pagePreviewView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            pagePreviewView.widthAnchor.constraint(equalToConstant: Constants.thumbnailSize),
            pagePreviewView.heightAnchor.constraint(equalToConstant: Constants.thumbnailSize),

            titleLabel.leadingAnchor.constraint(equalTo: pagePreviewView.trailingAnchor, constant: Constants.spacingAfterThumbnail),
            titleLabel.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Constants.trailingPadding),

            removeButton.centerXAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -Constants.removeButtonInset),
            removeButton.centerYAnchor.constraint(equalTo: cardView.topAnchor, constant: Constants.removeButtonInset),
            removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize),

            heightAnchor.constraint(equalToConstant: Self.totalHeight),
        ])

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func removeButtonClicked() {
        onRemove?(attachmentId)
    }

    // MARK: - Cursor management
    //
    // The carousel lives in the same panel area as the omnibar's `NSTextView`, whose I-beam
    // cursor would otherwise bleed across the card on hover. We register a static `.arrow` cursor
    // rect AND actively set it on `mouseEntered`/`mouseMoved` — the same dual approach used by
    // `AIChatImageAttachmentThumbnailView`. The `PointingHandButton` overrides this for the × icon.

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        setCursorIfNotOverRemoveButton(event: event)
    }

    override func mouseMoved(with event: NSEvent) {
        setCursorIfNotOverRemoveButton(event: event)
    }

    /// Only push `.arrow` when the cursor isn't over the remove button — otherwise the card's
    /// per-tick `mouseMoved` events would race the button's own `.pointingHand` set and produce
    /// a brief flicker as the cursor approaches the ×.
    private func setCursorIfNotOverRemoveButton(event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard !removeButton.frame.contains(location) else { return }
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        // Arrow rect for the card area, then explicitly carve out the remove button's frame
        // with a pointing-hand rect. AppKit picks the most recently added rect for a given
        // point, so the button rect wins inside its bounds even though the parent rect
        // already covers it.
        addCursorRect(bounds, cursor: .arrow)
        addCursorRect(removeButton.frame, cursor: .pointingHand)
    }

    // MARK: - Appearance

    private func updateAppearance() {
        NSAppearance.withAppAppearance {
            let surfaceColor = NSColor(designSystemColor: .surfaceSecondary)
            let removeButtonBackgroundColor = NSColor(named: Constants.removeButtonBackgroundColorName) ?? .white
            let removeButtonIconColor = NSColor(named: Constants.removeButtonIconColorName) ?? .black

            // Surface secondary on the card; the shadow-backing view shares the colour so the
            // soft offset shadow reads on light/dark backgrounds. No border — the shadow alone
            // separates the card from the omnibar surface.
            cardView.layer?.backgroundColor = surfaceColor.cgColor
            shadowBackingView.layer?.backgroundColor = surfaceColor.cgColor
            removeButton.layer?.backgroundColor = removeButtonBackgroundColor.cgColor
            removeButton.layer?.borderColor = removeButtonBackgroundColor.cgColor
            removeButton.contentTintColor = removeButtonIconColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}

// MARK: - Page preview thumbnail

/// A 36×36 stylised "page" thumbnail: favicon at the top-left, three short text bars beside it,
/// and two longer text bars at the bottom — matching the layout the duck.ai web app uses for the
/// same attachment, so native cards and web cards read as the same visual element.
private final class AIChatTabPagePreviewView: NSView {

    private enum Layout {
        static let size: CGFloat = 36
        static let cornerRadius: CGFloat = 6
        static let faviconOrigin = NSPoint(x: 4, y: 4)
        static let faviconSize: CGFloat = 16
    }

    /// Mock-text-bar geometry copied from the web SVG (origin top-left, then converted into
    /// AppKit's bottom-left coordinates by `isFlipped = true`).
    private static let bars: [NSRect] = [
        NSRect(x: 22, y: 4, width: 10, height: 2),
        NSRect(x: 22, y: 10, width: 10, height: 2),
        NSRect(x: 22, y: 16, width: 10, height: 2),
        NSRect(x: 4, y: 22, width: 28, height: 2),
        NSRect(x: 4, y: 28, width: 23, height: 2),
    ]

    private let faviconView: NSImageView = {
        let view = NSImageView()
        view.imageScaling = .scaleProportionallyUpOrDown
        return view
    }()

    override var isFlipped: Bool { true }

    init(favicon: NSImage?) {
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.size, height: Layout.size))

        // The card positions us with Auto Layout (centerY + width/height); the autoresizing-mask
        // constraints AppKit synthesises from our frame would conflict with that, hence the opt-out.
        // Subviews here (the favicon) are still positioned by frame inside `draw` / `init`, which is
        // intentional — page preview internals are deliberately layout-independent.
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = Layout.cornerRadius
        layer?.masksToBounds = true

        faviconView.frame = NSRect(
            origin: Layout.faviconOrigin,
            size: NSSize(width: Layout.faviconSize, height: Layout.faviconSize)
        )
        faviconView.image = favicon ?? DesignSystemImages.Glyphs.Size16.pageContentAttach
        addSubview(faviconView)

        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let barColor = NSColor(designSystemColor: .lines)
        barColor.setFill()
        for bar in Self.bars {
            NSBezierPath(roundedRect: bar, xRadius: 1, yRadius: 1).fill()
        }
    }

    private func updateAppearance() {
        NSAppearance.withAppAppearance {
            // A subtler tint than the surrounding card surface so the thumbnail reads as a nested
            // page preview rather than a flat solid block.
            let backgroundColor = NSColor(designSystemColor: .surfaceTertiary)
            layer?.backgroundColor = backgroundColor.cgColor
        }
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}
