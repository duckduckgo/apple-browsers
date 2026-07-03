//
//  AIChatAttachmentsCarouselView.swift
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
import AIChat

/// A horizontally scrollable strip of attachments in the duck.ai omnibar panel. Holds **both**
/// image thumbnails and tab cards in a single ordered stack — the order matches the user's
/// insertion order (driven by `AIChatPanelAttachment` from `AddressBarSharedTextState`), so a
/// sequence of toggles like `tab, tab, image, tab` renders exactly that way.
///
/// The view is intentionally agnostic about how attachments come and go: it just renders the
/// list it's handed. Removal is delegated upward via the `onImageAttachmentRemoveRequested` /
/// `onTabAttachmentRemoveRequested` callbacks; the container VC routes those into the data
/// model (shared state), the publisher fires, and the carousel re-renders. Single source of
/// truth, no in-carousel mutation.
final class AIChatAttachmentsCarouselView: NSView {

    private enum Constants {
        static let cardSpacing: CGFloat = 6
    }

    /// Visible row-content height (the tallest of the attachment view kinds). Items inside the
    /// carousel render in this much vertical space; the carousel itself is taller — see
    /// `expandedHeight` — so card shadows have room to render past the row content edges.
    static let rowHeight: CGFloat = max(
        AIChatTabAttachmentCardView.totalHeight,
        AIChatImageAttachmentThumbnailView.totalHeight,
        AIChatFileAttachmentCardView.totalHeight
    )

    /// Internal padding on every edge of the row content so card shadows aren't clipped at the
    /// carousel's bounds. Sized to comfortably exceed the visible blur tail of the card shadow
    /// (radius 3, offset (0, -1)) on every side, so even the soft edges of the Gaussian blur
    /// fall well inside the carousel.
    static let shadowMargin: CGFloat = 8

    /// Carousel's outer height when expanded — `rowHeight + 2 * shadowMargin`. The container VC
    /// uses this for the height constraint and for sizing the panel.
    static let expandedHeight: CGFloat = rowHeight + 2 * shadowMargin

    private(set) var attachments: [AIChatPanelAttachment] = []

    /// Called whenever the displayed attachment list changes (from `setAttachments`). Lets the
    /// container VC react (e.g. update layout / suggestions visibility).
    var onAttachmentsChanged: (() -> Void)?

    /// Called when the user clicks the close button on an *image* card. The receiver is expected
    /// to remove the attachment from the data model; the carousel will re-render once the
    /// publisher emits.
    var onImageAttachmentRemoveRequested: ((UUID) -> Void)?

    /// Called when the user clicks the close button on a *tab* card. Same flow as the image hook.
    var onTabAttachmentRemoveRequested: ((String) -> Void)?

    /// Called when the user clicks the close button on a *file* card. Same flow as the others.
    var onFileAttachmentRemoveRequested: ((UUID) -> Void)?

    private let scrollView: NSScrollView = {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.drawsBackground = false
        scrollView.scrollerStyle = .overlay
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        return scrollView
    }()

    private let stackView: NSStackView = {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = Constants.cardSpacing
        // `.centerY` so items sit in the middle of the carousel's expanded height, leaving an
        // even shadow-margin band above and below for the card shadows to render in.
        stack.alignment = .centerY
        stack.distribution = .fill
        return stack
    }()

    /// Maps `AIChatPanelAttachment.attachmentId` → its rendered view, so a re-render reuses the
    /// existing instance instead of re-creating it (preventing flicker and preserving in-place
    /// resize-replacement on image thumbnails).
    private var viewsByAttachmentId: [String: NSView] = [:]

    /// The id of the attachment most recently appended in the latest `setAttachments` call.
    /// Stashed here so the caller can scroll it into view after applying its own layout (the
    /// carousel's outer height constraint is owned by the container VC, so the scroll has to
    /// wait until the container has flipped it from 0 to `expandedHeight` and laid out).
    /// Cleared inside `setAttachments` whenever no fresh id was added.
    private var lastAddedAttachmentId: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        translatesAutoresizingMaskIntoConstraints = false

        let documentView = NSView()
        documentView.translatesAutoresizingMaskIntoConstraints = false
        documentView.addSubview(stackView)
        scrollView.documentView = documentView

        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            documentView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            documentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            documentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            documentView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),

            // Inset the stack horizontally by the same shadow margin so the first / last cards'
            // horizontal shadow blur doesn't clip at the carousel's leading / trailing edges.
            stackView.leadingAnchor.constraint(equalTo: documentView.leadingAnchor, constant: Self.shadowMargin),
            stackView.trailingAnchor.constraint(equalTo: documentView.trailingAnchor, constant: -Self.shadowMargin),
            stackView.topAnchor.constraint(equalTo: documentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: documentView.bottomAnchor),
        ])
    }

    // MARK: - Rendering

    /// Replaces the displayed cards/thumbnails to match `newAttachments`. View instances are
    /// keyed by `AIChatPanelAttachment.attachmentId` and reused across re-renders; on an image
    /// resize replacement (same id, fresh `NSImage`) the existing thumbnail is updated in place.
    ///
    /// Stashes the last newly-added attachment id in `lastAddedAttachmentId`; the caller is
    /// expected to call `scrollLastAddedAttachmentIntoView()` after applying any layout that
    /// would affect the carousel's own frame (the container VC owns the carousel's outer
    /// height constraint and flips it from 0 → `expandedHeight`).
    func setAttachments(_ newAttachments: [AIChatPanelAttachment]) {
        guard newAttachments != attachments else { return }
        let previousIds = Set(attachments.map(\.attachmentId))
        attachments = newAttachments

        let newIds = Set(newAttachments.map(\.attachmentId))

        // Remove views for ids that aren't in the new list.
        for (id, view) in viewsByAttachmentId where !newIds.contains(id) {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
            viewsByAttachmentId.removeValue(forKey: id)
        }

        // Walk the new list in order, reuse or create per entry, and ensure the stack order
        // matches the requested order.
        for (index, entry) in newAttachments.enumerated() {
            let id = entry.attachmentId
            if let existing = viewsByAttachmentId[id] {
                if stackView.arrangedSubviews[safe: index] !== existing {
                    stackView.removeArrangedSubview(existing)
                    stackView.insertArrangedSubview(existing, at: index)
                }
                // Resize-replacement path: the same image attachment id can carry a freshly
                // resized `NSImage`. Update the rendered thumbnail in place.
                if case .image(let image) = entry, let thumbnail = existing as? AIChatImageAttachmentThumbnailView {
                    thumbnail.updateImage(image.image)
                }
                continue
            }
            let view = makeView(for: entry)
            viewsByAttachmentId[id] = view
            stackView.insertArrangedSubview(view, at: index)
        }

        let addedIds = newIds.subtracting(previousIds)
        lastAddedAttachmentId = newAttachments.last(where: { addedIds.contains($0.attachmentId) })?.attachmentId

        onAttachmentsChanged?()
    }

    /// Scrolls the carousel so the attachment most recently added in the previous
    /// `setAttachments` call is visible. No-op when nothing was newly added (e.g. the user
    /// removed a card or an image resize replaced an existing one in place).
    ///
    /// Caller must invoke this after any layout pass that updates the carousel's outer
    /// frame — typically `layoutSubtreeIfNeeded()` on the carousel — so `scrollToVisible`
    /// reads accurate frames.
    func scrollLastAddedAttachmentIntoView() {
        guard let id = lastAddedAttachmentId, let view = viewsByAttachmentId[id] else { return }
        view.scrollToVisible(view.bounds)
    }

    // MARK: - Cursor management
    //
    // The carousel sits in the same panel area as the omnibar's `NSTextView`. Without explicit
    // cursor handling here, hovering over the empty space *between* cards (or on the carousel
    // before any cards render) can show the text view's I-beam cursor flickering through. The
    // individual cards each register their own `.arrow` rect, but the carousel-level fallback
    // covers the gaps and the rounded-corner regions outside any card's bounds.

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
        setCursorIfInGapRegion(event: event)
    }

    override func mouseMoved(with event: NSEvent) {
        setCursorIfInGapRegion(event: event)
    }

    /// Only push `.arrow` when the cursor is in a true gap region (not over any rendered card).
    /// If a card subview is under the cursor, it will set its own cursor (arrow on the card body,
    /// pointing-hand on its × button) — the carousel must not race those.
    private func setCursorIfInGapRegion(event: NSEvent) {
        let pointInWindow = event.locationInWindow
        let pointInSelf = convert(pointInWindow, from: nil)
        // `hitTest` returns the deepest subview at the point, or self if no subview was hit.
        // Inside the scroll view's documentView/cards we'll get a non-self hit; in the gap or
        // shadow-margin band we get self (or the scrollView itself, which has no cursor logic).
        if let hit = hitTest(pointInSelf), hit !== self, hit !== scrollView {
            return
        }
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    private func makeView(for entry: AIChatPanelAttachment) -> NSView {
        switch entry {
        case .image(let imageAttachment):
            let view = AIChatImageAttachmentThumbnailView(attachment: imageAttachment)
            view.onRemove = { [weak self] id in
                self?.onImageAttachmentRemoveRequested?(id)
            }
            return view
        case .tab(let tabAttachment):
            let view = AIChatTabAttachmentCardView(attachment: tabAttachment)
            view.onRemove = { [weak self] id in
                self?.onTabAttachmentRemoveRequested?(id)
            }
            return view
        case .file(let fileAttachment):
            let view = AIChatFileAttachmentCardView(attachment: fileAttachment)
            view.onRemove = { [weak self] id in
                self?.onFileAttachmentRemoveRequested?(id)
            }
            return view
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
