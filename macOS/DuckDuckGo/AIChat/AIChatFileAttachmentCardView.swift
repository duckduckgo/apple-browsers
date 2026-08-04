//
//  AIChatFileAttachmentCardView.swift
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

import AIChat
import AppKit
import DesignResourcesKit
import DesignResourcesKitIcons

/// A horizontal card representing a file attachment (PDF etc.) in the duck.ai omnibar carousel.
/// Deliberately shares `AIChatTabAttachmentCardView`'s geometry — same card size, same 36×36
/// thumbnail slot, same bold title beside it — so a mixed carousel of tabs and files reads as one
/// row of like elements. Only the thumbnail's contents differ: a stylised page with a red file-kind
/// badge instead of a favicon.
final class AIChatFileAttachmentCardView: NSView {

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

    /// Total height of the view including the remove button's vertical overflow — kept identical
    /// to `AIChatTabAttachmentCardView.totalHeight` so files / images / tabs share the same row
    /// baseline in the carousel.
    static let totalHeight: CGFloat = Constants.cardHeight + Constants.removeButtonOverflow

    let attachmentId: UUID
    var onRemove: ((UUID) -> Void)?

    private let cardView: NSView = {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.cornerRadius = Constants.cornerRadius
        view.layer?.masksToBounds = true
        return view
    }()

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

    private let filePreviewView = AIChatFilePagePreviewView()

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

    init(attachment: AIChatFileAttachment) {
        self.attachmentId = attachment.id
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        addSubview(shadowBackingView)
        addSubview(cardView)
        cardView.addSubview(filePreviewView)
        cardView.addSubview(titleLabel)
        addSubview(removeButton) // outside the card so its overflow can clip past the corner.

        titleLabel.stringValue = attachment.fileName
        // The label truncates on narrow cards; the tooltip carries the full filename.
        toolTip = attachment.fileName
        setAccessibilityLabel(String(format: UserText.aiChatFileAttachmentAccessibilityFormat, attachment.fileName))

        filePreviewView.kindLabel = Self.kindLabel(for: attachment.mimeType)

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

            filePreviewView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: Constants.leadingPadding),
            filePreviewView.centerYAnchor.constraint(equalTo: cardView.centerYAnchor),
            filePreviewView.widthAnchor.constraint(equalToConstant: Constants.thumbnailSize),
            filePreviewView.heightAnchor.constraint(equalToConstant: Constants.thumbnailSize),

            titleLabel.leadingAnchor.constraint(equalTo: filePreviewView.trailingAnchor, constant: Constants.spacingAfterThumbnail),
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
    // Mirrors the tab and image card behaviour: register `.arrow` as a static cursor rect AND
    // actively set it on hover so the omnibar text view's I-beam doesn't bleed through. The
    // `PointingHandButton` overrides this on the × icon itself.

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

    /// Badge text for the thumbnail. Only PDFs are called out by name; every other accepted type
    /// gets the generic label (mime subtypes like `vnd.openxmlformats-…` are unreadable at badge
    /// size, and the filename in the title already carries the extension).
    private static func kindLabel(for mimeType: String) -> String {
        mimeType.lowercased().contains("pdf") ? "PDF" : "FILE"
    }

    // MARK: - Appearance

    private func updateAppearance() {
        NSAppearance.withAppAppearance {
            let surfaceColor = NSColor(designSystemColor: .surfaceSecondary)
            let removeButtonBackgroundColor = NSColor(named: Constants.removeButtonBackgroundColorName) ?? .white
            let removeButtonIconColor = NSColor(named: Constants.removeButtonIconColorName) ?? .black

            cardView.layer?.backgroundColor = surfaceColor.cgColor
            shadowBackingView.layer?.backgroundColor = surfaceColor.cgColor
            removeButton.layer?.backgroundColor = removeButtonBackgroundColor.cgColor
            removeButton.layer?.borderColor = removeButtonBackgroundColor.cgColor
            removeButton.contentTintColor = removeButtonIconColor
        }
        filePreviewView.refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}

// MARK: - File preview thumbnail

/// A 36×36 stylised "document" thumbnail matching `AIChatTabAttachmentCardView`'s page preview in
/// size, corner radius and background: two short "text" lines at the top, and a filled red badge
/// with the file kind below. Geometry is in flipped (top-left origin) coordinates so it reads the
/// way a designer would describe it.
private final class AIChatFilePagePreviewView: NSView {

    private enum Layout {
        static let size: CGFloat = 36
        static let cornerRadius: CGFloat = 6
        static let bar1Rect = NSRect(x: 6, y: 7, width: 18, height: 2)
        static let bar2Rect = NSRect(x: 6, y: 12, width: 12, height: 2)
        static let badgeRect = NSRect(x: 4, y: 18, width: 28, height: 13)
        static let badgeCornerRadius: CGFloat = 3.5
        static let barCornerRadius: CGFloat = 1
    }

    var kindLabel: String = "PDF" {
        didSet {
            guard kindLabel != oldValue else { return }
            label.stringValue = kindLabel
        }
    }

    private let label: NSTextField = {
        let label = NSTextField(labelWithString: "PDF")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 8, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        return label
    }()

    override var isFlipped: Bool { true }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.size, height: Layout.size))

        // The card positions us with Auto Layout (centerY + width/height), so opt out of the
        // autoresizing-mask constraints AppKit would otherwise synthesise from this frame.
        translatesAutoresizingMaskIntoConstraints = false

        wantsLayer = true
        layer?.cornerRadius = Layout.cornerRadius
        layer?.masksToBounds = true

        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: leadingAnchor, constant: Layout.badgeRect.midX),
            label.centerYAnchor.constraint(equalTo: topAnchor, constant: Layout.badgeRect.midY),
        ])

        refreshAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSAppearance.withAppAppearance {
            NSColor(designSystemColor: .lines).setFill()
            NSBezierPath(roundedRect: Layout.bar1Rect, xRadius: Layout.barCornerRadius, yRadius: Layout.barCornerRadius).fill()
            NSBezierPath(roundedRect: Layout.bar2Rect, xRadius: Layout.barCornerRadius, yRadius: Layout.barCornerRadius).fill()

            // Brand-red kind badge (the duck.ai web app uses the same hue).
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: Layout.badgeRect, xRadius: Layout.badgeCornerRadius, yRadius: Layout.badgeCornerRadius).fill()
        }
    }

    func refreshAppearance() {
        NSAppearance.withAppAppearance {
            // Subtler tint than the card surface so the thumbnail reads as a nested page preview
            // rather than a flat block — same treatment as the tab card's page preview.
            layer?.backgroundColor = NSColor(designSystemColor: .surfaceTertiary).cgColor
        }
        needsDisplay = true
    }
}
