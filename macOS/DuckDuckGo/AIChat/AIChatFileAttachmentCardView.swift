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

/// A square card representing a file attachment (PDF etc.) in the duck.ai omnibar carousel.
/// Matches the duck.ai web app's attachment style: a 56×56 surface-secondary tile with two
/// short "text" lines at the top and a red filled "PDF" pill below — no inline filename
/// (the filename surfaces via tooltip and accessibility label so the visual stays compact and
/// reads as a kind-of-thing, not a labelled item).
final class AIChatFileAttachmentCardView: NSView {

    private enum Constants {
        static let cardSize: CGFloat = 56
        static let cornerRadius: CGFloat = 12
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
    static let totalHeight: CGFloat = Constants.cardSize + Constants.removeButtonOverflow

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

    private let pagePreviewView = AIChatFilePagePreviewView()

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
        cardView.addSubview(pagePreviewView)
        addSubview(removeButton) // outside the card so its overflow can clip past the corner.

        // Filename only surfaces via tooltip + accessibility — the visual is filename-agnostic
        // to match the duck.ai web app's compact tile style.
        toolTip = attachment.fileName
        setAccessibilityLabel(String(format: UserText.aiChatFileAttachmentAccessibilityFormat, attachment.fileName))

        pagePreviewView.translatesAutoresizingMaskIntoConstraints = false
        pagePreviewView.kindLabel = Self.kindLabel(for: attachment.mimeType)

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
            cardView.widthAnchor.constraint(equalToConstant: Constants.cardSize),
            cardView.heightAnchor.constraint(equalToConstant: Constants.cardSize),

            shadowBackingView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            shadowBackingView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            shadowBackingView.topAnchor.constraint(equalTo: cardView.topAnchor),
            shadowBackingView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

            pagePreviewView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            pagePreviewView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            pagePreviewView.topAnchor.constraint(equalTo: cardView.topAnchor),
            pagePreviewView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),

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

    /// Short uppercased label shown on the file pill — derived from the mime type.
    private static func kindLabel(for mimeType: String) -> String {
        let lower = mimeType.lowercased()
        if lower.contains("pdf") {
            return "PDF"
        }
        // Trim "application/" or similar prefixes and uppercase whatever remains. Falls back to
        // a generic "FILE" label so the pill always reads as something.
        if let slashIndex = lower.firstIndex(of: "/") {
            let suffix = lower[lower.index(after: slashIndex)...]
            let trimmed = suffix.split(separator: "+").first.map(String.init) ?? String(suffix)
            if !trimmed.isEmpty {
                return trimmed.uppercased()
            }
        }
        return "FILE"
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
        pagePreviewView.refreshAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }
}

// MARK: - File preview

/// Draws the inside of the file card: two short "text" lines at the top and a filled red pill
/// with the file kind label centred below. Geometry is in flipped (top-left origin) coordinates
/// so it matches how a designer would describe the layout.
private final class AIChatFilePagePreviewView: NSView {

    private enum Layout {
        // All in flipped-Y coordinates (origin at top-left of the 56×56 card).
        static let bar1Rect = NSRect(x: 10, y: 10, width: 22, height: 3)
        static let bar2Rect = NSRect(x: 10, y: 16, width: 14, height: 3)
        static let pillRect = NSRect(x: 8, y: 24, width: 40, height: 22)
        static let pillCornerRadius: CGFloat = 5
        static let barCornerRadius: CGFloat = 1.5
    }

    var kindLabel: String = "PDF" {
        didSet {
            guard kindLabel != oldValue else { return }
            label.stringValue = kindLabel
            needsDisplay = true
        }
    }

    private let label: NSTextField = {
        let label = NSTextField(labelWithString: "PDF")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 10, weight: .bold)
        label.textColor = .white
        label.alignment = .center
        return label
    }()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(label)
        // Centre the label inside the pill area; using AppKit constraints keeps the text
        // pixel-aligned regardless of the parent's frame.
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: leadingAnchor, constant: Layout.pillRect.midX),
            label.centerYAnchor.constraint(equalTo: topAnchor, constant: Layout.pillRect.midY),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSAppearance.withAppAppearance {
            let barColor = NSColor(designSystemColor: .lines)
            barColor.setFill()
            NSBezierPath(roundedRect: Layout.bar1Rect, xRadius: Layout.barCornerRadius, yRadius: Layout.barCornerRadius).fill()
            NSBezierPath(roundedRect: Layout.bar2Rect, xRadius: Layout.barCornerRadius, yRadius: Layout.barCornerRadius).fill()

            // Brand-red PDF pill (the duck.ai web app uses the same hue).
            NSColor.systemRed.setFill()
            NSBezierPath(roundedRect: Layout.pillRect, xRadius: Layout.pillCornerRadius, yRadius: Layout.pillCornerRadius).fill()
        }
    }

    func refreshAppearance() {
        needsDisplay = true
    }
}
