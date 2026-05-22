//
//  AIChatMentionPickerViewController.swift
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

/// Renders the list of open-tab rows for the omnibar `@`-mention picker.
///
/// Responsibilities:
/// - Build the "Recent Tabs" header + a stack of `AIChatMentionPickerRowView`s.
/// - Track the keyboard-driven highlight index (used in M12 by the coordinator's arrow-key
///   handling; in M10 it's only set when the panel first opens).
/// - Vend the rendered content size so the panel can resize itself to fit.
///
/// Filtering / scoring is intentionally NOT here — the coordinator passes a pre-filtered
/// ordered list. Keeps this VC easy to test and the filter rules unit-testable in isolation
/// (M11 will introduce a separate `AIChatMentionPickerFilter` helper).
final class AIChatMentionPickerViewController: NSViewController {

    private enum Layout {
        static let chromeCornerRadius: CGFloat = 8
        static let outerInset: CGFloat = 4
        static let headerHeight: CGFloat = 22
        static let headerLeadingPadding: CGFloat = 12
        /// Padding above the "Recent Tabs" header. Wider than the bottom inset because
        /// the header otherwise reads as glued to the chrome's top edge.
        static let headerTopInset: CGFloat = 8
        /// Padding between the header and the first row.
        static let headerBottomInset: CGFloat = 4
        /// Inset between the chrome's top and the scroll view when the header is hidden
        /// (empty-state mode). Small so the placeholder row doesn't float in a tall void.
        static let noHeaderTopInset: CGFloat = 4
        static let rowHeight: CGFloat = 24
        /// Minimum width even when the longest title is short — keeps the panel from
        /// looking like a sliver. Also the width used by the empty-state placeholder.
        static let minWidth: CGFloat = 200
        /// Cap on width — beyond this, long titles truncate with `…` rather than
        /// stretching the panel beyond the omnibar's reasonable bounds.
        static let maxWidth: CGFloat = 360
        /// Total padding (chrome inset + scroll inset on both sides) added on top of the
        /// row's natural content width. Keeps the panel width = row width + chrome.
        static let totalChromePadding: CGFloat = outerInset * 4
        static let maxVisibleRows: Int = 8
    }

    private let chromeView = NSView()
    private let backgroundView = NSVisualEffectView()
    private let headerLabel = NSTextField(labelWithString: UserText.aiChatAttachMenuRecentTabsHeader)
    private let scrollView = NSScrollView()
    private let rowStack = HoverObservingStackView()
    private var rowViews: [AIChatMentionPickerRowView] = []
    private var emptyRowView: AIChatMentionPickerEmptyRowView?
    private(set) var highlightedIndex: Int?
    /// `scrollView.topAnchor == headerLabel.bottomAnchor + headerBottomInset` — active when
    /// the picker is in normal (non-empty) mode. Toggled off when entering empty state.
    private var scrollViewTopWithHeader: NSLayoutConstraint?
    /// `scrollView.topAnchor == chromeView.topAnchor + noHeaderTopInset` — active when the
    /// picker is showing the "No matching tabs" placeholder.
    private var scrollViewTopWithoutHeader: NSLayoutConstraint?

    /// Called when the user accepts a row (click, or M12's Enter). The coordinator decides
    /// whether to attach or detach based on the omnibar's `activeTabAttachments`.
    var onAccept: ((AIChatTabAttachment) -> Void)?

    /// `true` while the picker is showing the "No matching tabs" placeholder. The Enter
    /// handler falls through to the normal omnibar submit when this is the case.
    var isShowingEmptyState: Bool { emptyRowView != nil }

    /// The tab the keyboard highlight is currently on, if any. `nil` when the picker shows
    /// the empty-state row (M11) or when no rows exist.
    var highlightedTab: AIChatTabAttachment? {
        guard let index = highlightedIndex, rowViews.indices.contains(index) else { return nil }
        return rowViews[index].attachment
    }

    /// Moves the keyboard highlight to the next row, wrapping from the last back to the
    /// first. No-op when there are zero real rows (empty-state mode).
    func moveHighlightDown() {
        guard !rowViews.isEmpty else { return }
        let current = highlightedIndex ?? -1
        let next = (current + 1) % rowViews.count
        setHighlightedIndex(next)
        scrollHighlightedRowIntoView()
    }

    /// Moves the keyboard highlight to the previous row, wrapping from the first to the
    /// last. No-op when there are zero real rows.
    func moveHighlightUp() {
        guard !rowViews.isEmpty else { return }
        let current = highlightedIndex ?? 0
        let previous = (current - 1 + rowViews.count) % rowViews.count
        setHighlightedIndex(previous)
        scrollHighlightedRowIntoView()
    }

    /// Scrolls the document view so the currently highlighted row is fully visible.
    /// Important when keyboard nav moves the highlight past the bottom of the picker's
    /// max visible window.
    private func scrollHighlightedRowIntoView() {
        guard let index = highlightedIndex, rowViews.indices.contains(index) else { return }
        let row = rowViews[index]
        row.scrollToVisible(row.bounds)
    }

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true

        // Chrome — rounded rectangle sitting just inside `outerInset` on each side so the
        // panel's shadow has room to breathe. The fill is a child `NSVisualEffectView` with
        // the `.menu` material instead of a static `controlBackgroundColor` so the picker
        // matches the native `NSMenu` look in both light and dark mode (the previous
        // hardcoded `cgColor` snapshotted the color at `loadView` time and didn't refresh on
        // appearance change, leaving the picker white in dark mode).
        chromeView.translatesAutoresizingMaskIntoConstraints = false
        chromeView.wantsLayer = true
        chromeView.layer?.cornerRadius = Layout.chromeCornerRadius
        // No border. The panel's shadow + the rounded chrome on the contrasting omnibar
        // background give enough visual separation; a stroked border (even at 0.5pt)
        // reads as heavier than AppKit's own context menus.
        // Clip the scroll view + visual effect to the chrome's rounded corners so the
        // highlight doesn't paint past the curve on the first/last rows and the material
        // tracks the rounded shape rather than its square layer bounds.
        chromeView.layer?.masksToBounds = true
        root.addSubview(chromeView)

        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.material = .menu
        backgroundView.blendingMode = .behindWindow
        backgroundView.state = .active
        // `wantsLayer` + matching corner radius here too, otherwise the visual effect view's
        // Metal-backed rendering can leak past the chrome's rounded clip on some macOS
        // releases (especially when the panel is reused after a hide/show).
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = Layout.chromeCornerRadius
        backgroundView.layer?.masksToBounds = true
        chromeView.addSubview(backgroundView)

        // "Recent Tabs" header — secondary text, leading-aligned, fixed height. Mirrors the
        // section header inside the existing "Add Page Content" submenu.
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = NSFont.menuFont(ofSize: 0)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.maximumNumberOfLines = 1
        headerLabel.usesSingleLineMode = true
        chromeView.addSubview(headerLabel)

        // Scroll view + vertical stack hold the rows. NSScrollView so very long open-tab
        // lists scroll instead of stretching the panel beyond the screen.
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // Layer-back the scrolling viewport so AppKit composites the row stack instead
        // of redrawing each row in CoreGraphics on every scroll tick. Major contributor
        // to scroll smoothness on the typical 8-row case.
        scrollView.wantsLayer = true
        scrollView.contentView.wantsLayer = true
        chromeView.addSubview(scrollView)

        rowStack.orientation = .vertical
        rowStack.spacing = 0
        rowStack.alignment = .leading
        rowStack.distribution = .fill
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        rowStack.wantsLayer = true
        scrollView.documentView = rowStack

        let withHeader = scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: Layout.headerBottomInset)
        let withoutHeader = scrollView.topAnchor.constraint(equalTo: chromeView.topAnchor, constant: Layout.noHeaderTopInset)
        // Default state: header visible (we start in "Recent Tabs" mode the moment the
        // picker is shown, before any filter has been applied).
        withHeader.isActive = true
        withoutHeader.isActive = false
        scrollViewTopWithHeader = withHeader
        scrollViewTopWithoutHeader = withoutHeader

        NSLayoutConstraint.activate([
            chromeView.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Layout.outerInset),
            chromeView.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Layout.outerInset),
            chromeView.topAnchor.constraint(equalTo: root.topAnchor, constant: Layout.outerInset),
            chromeView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Layout.outerInset),

            backgroundView.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor),
            backgroundView.topAnchor.constraint(equalTo: chromeView.topAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor),

            headerLabel.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: Layout.headerLeadingPadding),
            headerLabel.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -Layout.headerLeadingPadding),
            headerLabel.topAnchor.constraint(equalTo: chromeView.topAnchor, constant: Layout.headerTopInset),
            headerLabel.heightAnchor.constraint(equalToConstant: Layout.headerHeight),

            scrollView.leadingAnchor.constraint(equalTo: chromeView.leadingAnchor, constant: Layout.outerInset),
            scrollView.trailingAnchor.constraint(equalTo: chromeView.trailingAnchor, constant: -Layout.outerInset),
            scrollView.bottomAnchor.constraint(equalTo: chromeView.bottomAnchor, constant: -Layout.outerInset),

            rowStack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            rowStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])

        view = root
    }

    /// Replaces the picker's rows with the given attachments. `currentTabId` (if any) gets
    /// a trailing "(Current Tab)" badge. Already-attached tabs (any UUID in `attachedTabIds`)
    /// render with a leading checkmark.
    ///
    /// If `tabs` is empty, renders the "No matching tabs" empty-state row instead — the
    /// picker stays on screen so the user can keep typing (the next keystroke that drops
    /// the filter or matches something will repopulate the rows).
    func setTabs(_ tabs: [AIChatTabAttachment], currentTabId: String?, attachedTabIds: Set<String>) {
        currentTabIdForWidthMeasurement = currentTabId

        // Rebuild rows. For now this is a simple "tear down + rebuild" — measured to be fine
        // for typical N (≈ open tabs in a window). If we ever see jank with hundreds of tabs
        // we can move to NSTableView diffing.
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews.removeAll()
        emptyRowView?.removeFromSuperview()
        emptyRowView = nil
        // CRITICAL: reset `highlightedIndex` here so the `setHighlightedIndex(0)` call below
        // isn't no-op'd by the equality guard when the previous filter also ended on index 0.
        // (Without this, filtering from "many rows, row-0 highlighted" → "one row, also row 0"
        // would leave the new row visually unhighlighted.)
        highlightedIndex = nil

        if tabs.isEmpty {
            // Hide the "Recent Tabs" header when showing the empty-state placeholder — the
            // section heading is meaningless without any actual recent-tab rows beneath it.
            headerLabel.isHidden = true
            scrollViewTopWithHeader?.isActive = false
            scrollViewTopWithoutHeader?.isActive = true

            let empty = AIChatMentionPickerEmptyRowView()
            empty.translatesAutoresizingMaskIntoConstraints = false
            rowStack.addArrangedSubview(empty)
            NSLayoutConstraint.activate([
                empty.widthAnchor.constraint(equalTo: rowStack.widthAnchor)
            ])
            emptyRowView = empty
            // Empty state has no highlight target — Enter falls through to normal submit.
            setHighlightedIndex(nil)
            return
        }

        // Non-empty: ensure the "Recent Tabs" header is visible.
        headerLabel.isHidden = false
        scrollViewTopWithoutHeader?.isActive = false
        scrollViewTopWithHeader?.isActive = true

        for tab in tabs {
            let row = AIChatMentionPickerRowView(
                attachment: tab,
                isCurrentTab: tab.id == currentTabId,
                isAttached: attachedTabIds.contains(tab.id)
            )
            row.onAccept = { [weak self, weak row] in
                guard let self, let attachment = row?.attachment else { return }
                self.onAccept?(attachment)
            }
            row.translatesAutoresizingMaskIntoConstraints = false
            rowStack.addArrangedSubview(row)
            NSLayoutConstraint.activate([
                row.heightAnchor.constraint(equalToConstant: Layout.rowHeight),
                row.widthAnchor.constraint(equalTo: rowStack.widthAnchor)
            ])
            rowViews.append(row)
        }
        // Default the highlight to the first row whenever the row set changes.
        setHighlightedIndex(0)
    }

    /// Updates the keyboard-driven (or hover-driven) highlight. `nil` clears the highlight
    /// (used for the empty-state row in M11). Skips the per-row write loop entirely when
    /// the new index matches the old one — important on the scroll hot path, where
    /// `mouseMoved:` fires many times for the same row.
    func setHighlightedIndex(_ newIndex: Int?) {
        guard newIndex != highlightedIndex else { return }
        highlightedIndex = newIndex
        for (index, row) in rowViews.enumerated() {
            row.isHighlighted = (index == newIndex)
        }
    }

    /// The size the panel should adopt for the current set of rows.
    /// - Parameters:
    ///   - rowCount: number of rows (real or empty-state) currently visible.
    ///   - rowHeight: per-row height — `Layout.rowHeight` for regular rows, or
    ///     `AIChatMentionPickerEmptyRowView.Layout.height` for the placeholder. Without
    ///     this the empty-state row (28pt tall) was cropped to the 24pt regular-row
    ///     budget, which shifted its label visually upward.
    ///   - width: panel width to apply.
    ///   - showsHeader: pass `false` to compute the size for the empty-state mode
    ///     (no "Recent Tabs" header).
    func contentSize(forRowCount rowCount: Int, rowHeight: CGFloat, width: CGFloat, showsHeader: Bool) -> NSSize {
        let visibleRows = max(1, min(rowCount, Layout.maxVisibleRows))
        let rowsHeight = CGFloat(visibleRows) * rowHeight
        let headerHeight: CGFloat
        if showsHeader {
            headerHeight = Layout.headerTopInset + Layout.headerHeight + Layout.headerBottomInset
        } else {
            headerHeight = Layout.noHeaderTopInset
        }
        let chromeHeight = headerHeight + rowsHeight + Layout.outerInset
        let totalHeight = chromeHeight + (Layout.outerInset * 2)
        return NSSize(width: width, height: totalHeight)
    }

    /// Convenience: derives the content size from the current row count and a width that
    /// adapts to the longest title currently shown. The empty-state row uses `minWidth`.
    var fittingContentSize: NSSize {
        let isEmpty = rowViews.isEmpty
        let effectiveCount = isShowingEmptyState ? 1 : rowViews.count
        let contentWidth: CGFloat
        if isEmpty {
            contentWidth = Layout.minWidth
        } else {
            let longestRow = rowViews
                .map { row in
                    AIChatMentionPickerRowView.naturalContentWidth(
                        forTitle: row.attachment.title.isEmpty ? (row.attachment.url.host ?? row.attachment.url.absoluteString) : row.attachment.title,
                        isCurrentTab: row.attachment.id == currentTabIdForWidthMeasurement
                    )
                }
                .max() ?? Layout.minWidth
            // Adopt the longest row width + chrome inset, clamped between minWidth and maxWidth.
            let proposed = longestRow + Layout.totalChromePadding
            contentWidth = min(Layout.maxWidth, max(Layout.minWidth, proposed))
        }
        let rowHeight = isEmpty ? AIChatMentionPickerEmptyRowView.Layout.height : Layout.rowHeight
        return contentSize(forRowCount: effectiveCount, rowHeight: rowHeight, width: contentWidth, showsHeader: !isEmpty)
    }

    /// Set by `setTabs(...)` so `fittingContentSize`'s natural-width pass knows which tab
    /// gets the "(Current Tab)" badge (which affects the row's width). Stored separately
    /// from the row views to avoid re-measuring from the live row state.
    private var currentTabIdForWidthMeasurement: String?

    // MARK: - Hover (centralized)

    override func viewDidLoad() {
        super.viewDidLoad()
        rowStack.onMouseMoved = { [weak self] pointInStack in
            self?.updateHighlightFromMousePosition(pointInStack)
        }
        // No `onMouseExited` — keyboard nav may want to keep the current highlight after
        // the cursor leaves the panel. Highlight only resets via `setTabs(...)`.
    }

    private func updateHighlightFromMousePosition(_ pointInStack: NSPoint) {
        guard !rowViews.isEmpty else {
            // Empty-state row isn't a real selection target — keep highlight nil.
            setHighlightedIndex(nil)
            return
        }
        for (index, row) in rowViews.enumerated() where row.frame.contains(pointInStack) {
            setHighlightedIndex(index)
            return
        }
    }
}

/// `NSStackView` subclass that owns one `NSTrackingArea` covering its entire bounds and
/// forwards `mouseMoved:` / `mouseExited:` to the view controller. Centralizing the
/// tracking here (rather than per-row) eliminates the multi-row-highlighted artifact that
/// happens when fast trackpad scroll fires `mouseEntered:` on several rows in succession
/// without the matching `mouseExited:` deliveries.
private final class HoverObservingStackView: NSStackView {

    var onMouseMoved: ((NSPoint) -> Void)?
    var onMouseExited: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        // `.activeAlways` is required because the picker panel never becomes key.
        // `.mouseMoved` (plus `.assumeInside` for the initial mouse position) gives us
        // the per-pixel tracking we need to keep the highlight in sync with the cursor.
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let pointInSelf = convert(event.locationInWindow, from: nil)
        onMouseMoved?(pointInSelf)
    }

    override func mouseExited(with event: NSEvent) {
        onMouseExited?()
    }
}
