//
//  UnifiedToggleInputAttachmentsStripView.swift
//  DuckDuckGo
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
import UIKit

final class UnifiedToggleInputAttachmentsStripView: UIView {

    enum Constants {
        static let spacing: CGFloat = 4
        static let standardSpacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 12
        static let topPadding: CGFloat = 8
        static let stripHeight: CGFloat = topPadding + UnifiedToggleInputAttachmentThumbnailView.Constants.chipHeight
    }

    private(set) var attachments: [UnifiedToggleInputAttachment] = []
    var onAttachmentRemoved: ((UUID, UnifiedToggleInputAttachment, Bool) -> Void)?
    var onAttachmentsChanged: (() -> Void)?
    var onPageContextRemove: (() -> Void)?
    /// Tapping the chip in its placeholder state asks for the page to be attached again.
    var onPageContextTap: (() -> Void)?
    var onSelectionContextRemove: ((String) -> Void)?

    private(set) var hasVisiblePageContext = false
    private(set) var hasVisibleSelectionContext = false

    private let usesCompactLayout: Bool

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = !usesCompactLayout
        scrollView.clipsToBounds = true
        return scrollView
    }()

    private lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = usesCompactLayout ? Constants.spacing : Constants.standardSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private var contextChipStyle: AIChatContextChipView.Style {
        usesCompactLayout ? .attachmentStrip : .standalone
    }

    private lazy var pageContextChip = AIChatContextChipView(style: contextChipStyle)

    /// Page context keeps its own separate slot — selections augment the page rather than replace it.
    private var selectionContextChips: [(id: String, view: AIChatContextChipView)] = []

    init(usesCompactLayout: Bool = false) {
        self.usesCompactLayout = usesCompactLayout
        super.init(frame: .zero)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    struct ChipWidthLimits {
        let maximumWidth: CGFloat
        let minimumContentWidth: CGFloat
    }

    static func chipWidths(visibleWidth: CGFloat, chips: [ChipWidthLimits]) -> [CGFloat] {
        guard !chips.isEmpty, visibleWidth.isFinite, visibleWidth > 0 else { return [] }
        let availableWidth = visibleWidth - 2 * Constants.horizontalPadding - CGFloat(chips.count - 1) * Constants.spacing
        let fourSlotWidth = max(0, (visibleWidth - 2 * Constants.horizontalPadding - 3 * Constants.spacing) / 4)
        let minimumWidths = chips.map { max($0.minimumContentWidth, min($0.maximumWidth, fourSlotWidth)) }
        var widths = chips.map { max($0.maximumWidth, $0.minimumContentWidth) }
        var excessWidth = widths.reduce(0, +) - availableWidth

        // Lower the widest group until it reaches another chip's width or a content minimum.
        while excessWidth > 0 {
            let shrinkable = widths.indices.filter { widths[$0] > minimumWidths[$0] }
            guard let widest = shrinkable.map({ widths[$0] }).max() else { break }
            let widestIndices = shrinkable.filter { widths[$0] == widest }
            let nextWidth = shrinkable.map { widths[$0] }.filter { $0 < widest }.max() ?? 0
            let groupMinimum = widestIndices.map { minimumWidths[$0] }.max() ?? 0
            let targetWidth = max(nextWidth, groupMinimum)
            let availableReduction = (widest - targetWidth) * CGFloat(widestIndices.count)

            if excessWidth <= availableReduction {
                let finalWidth = widest - excessWidth / CGFloat(widestIndices.count)
                for index in widestIndices {
                    widths[index] = finalWidth
                }
                break
            }

            for index in widestIndices {
                widths[index] = targetWidth
            }
            excessWidth -= availableReduction
        }
        return widths
    }

    override func layoutSubviews() {
        guard usesCompactLayout else {
            super.layoutSubviews()
            return
        }
        let chips = stackView.arrangedSubviews
        let limits = chips.map { view -> ChipWidthLimits in
            if let chip = view as? AIChatContextChipView {
                return ChipWidthLimits(maximumWidth: 240, minimumContentWidth: chip.minimumContentWidth)
            }
            let thumbnail = view as? UnifiedToggleInputAttachmentThumbnailView
            return ChipWidthLimits(maximumWidth: thumbnail?.intrinsicContentSize.width ?? 0,
                                   minimumContentWidth: thumbnail?.minimumContentWidth ?? 0)
        }
        let widths = Self.chipWidths(visibleWidth: bounds.width, chips: limits)
        for (view, width) in zip(chips, widths) {
            if let chip = view as? AIChatContextChipView {
                chip.preferredWidth = width
            } else if let chip = view as? UnifiedToggleInputAttachmentThumbnailView {
                chip.setWidth(width)
            }
        }
        super.layoutSubviews()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            setNeedsLayout()
        }
    }

    func addAttachment(_ attachment: UnifiedToggleInputAttachment) {
        let shouldAutoScroll = shouldAutoScrollAfterAddingAttachment()
        attachments.append(attachment)
        stackView.addArrangedSubview(makeThumbnail(for: attachment))
        setNeedsLayout()
        onAttachmentsChanged?()
        if shouldAutoScroll {
            scheduleScrollToTrailingEdge()
        }
    }

    func replaceAttachment(id: UUID, with attachment: UnifiedToggleInputAttachment) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments[index] = attachment
        let thumbnailViews = stackView.arrangedSubviews.compactMap { $0 as? UnifiedToggleInputAttachmentThumbnailView }
        guard let view = thumbnailViews.first(where: { $0.attachmentId == id }),
              let arrangedIndex = stackView.arrangedSubviews.firstIndex(of: view) else { return }
        stackView.removeArrangedSubview(view)
        view.removeFromSuperview()
        stackView.insertArrangedSubview(makeThumbnail(for: attachment), at: arrangedIndex)
        setNeedsLayout()
        onAttachmentsChanged?()
    }

    func removeAttachment(id: UUID, isUserInitiated: Bool = false) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        let removedAttachment = attachments[index]
        attachments.remove(at: index)
        let thumbnailViews = stackView.arrangedSubviews.compactMap { $0 as? UnifiedToggleInputAttachmentThumbnailView }
        if let view = thumbnailViews.first(where: { $0.attachmentId == id }) {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        onAttachmentRemoved?(id, removedAttachment, isUserInitiated)
        setNeedsLayout()
        onAttachmentsChanged?()
    }

    func removeAllAttachments() {
        attachments.removeAll()
        stackView.arrangedSubviews
            .compactMap { $0 as? UnifiedToggleInputAttachmentThumbnailView }
            .forEach {
                stackView.removeArrangedSubview($0)
                $0.removeFromSuperview()
            }
        setNeedsLayout()
        onAttachmentsChanged?()
    }

    func setPageContextChipState(_ state: AIChatContextChipView.State) {
        pageContextChip.configure(state: state)
        setNeedsLayout()
    }

    func setPageContextChipVisible(_ isVisible: Bool) {
        guard hasVisiblePageContext != isVisible else { return }
        let shouldAutoScroll = shouldAutoScrollAfterAddingAttachment()
        hasVisiblePageContext = isVisible

        if isVisible {
            stackView.addArrangedSubview(pageContextChip)
            if shouldAutoScroll {
                scheduleScrollToTrailingEdge()
            }
        } else {
            stackView.removeArrangedSubview(pageContextChip)
            pageContextChip.removeFromSuperview()
        }

        setNeedsLayout()
        onAttachmentsChanged?()
    }

    /// Reuses existing chips so attaching one more doesn't re-animate the ones already on screen.
    func setSelectionContextChips(_ items: [(id: String, title: String, favicon: UIImage?)]) {
        let incomingIDs = Set(items.map(\.id))
        let didChange = incomingIDs != Set(selectionContextChips.map(\.id))
        let shouldAutoScroll = didChange && !items.isEmpty && shouldAutoScrollAfterAddingAttachment()

        for chip in selectionContextChips where !incomingIDs.contains(chip.id) {
            stackView.removeArrangedSubview(chip.view)
            chip.view.removeFromSuperview()
        }

        var reconciled: [(id: String, view: AIChatContextChipView)] = []
        for item in items {
            if let existing = selectionContextChips.first(where: { $0.id == item.id }) {
                existing.view.configure(state: .attached(title: item.title, favicon: item.favicon))
                reconciled.append(existing)
            } else {
                let view = AIChatContextChipView(style: contextChipStyle)
                view.configure(state: .attached(title: item.title, favicon: item.favicon))
                view.onRemove = { [weak self] in
                    self?.onSelectionContextRemove?(item.id)
                }
                stackView.addArrangedSubview(view)
                reconciled.append((id: item.id, view: view))
            }
        }

        selectionContextChips = reconciled
        hasVisibleSelectionContext = !items.isEmpty
        setNeedsLayout()

        guard didChange else { return }
        if shouldAutoScroll {
            scheduleScrollToTrailingEdge()
        }
        onAttachmentsChanged?()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
        pageContextChip.onRemove = { [weak self] in
            self?.onPageContextRemove?()
        }
        pageContextChip.onTap = { [weak self] in
            self?.onPageContextTap?()
        }
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        let bottomConstraint = scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottomConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.topPadding),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: UnifiedToggleInputAttachmentThumbnailView.Constants.chipHeight),
            bottomConstraint,

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Constants.horizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Constants.horizontalPadding),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    private func makeThumbnail(for attachment: UnifiedToggleInputAttachment) -> UnifiedToggleInputAttachmentThumbnailView {
        let thumbnail = UnifiedToggleInputAttachmentThumbnailView(attachment: attachment, usesCompactLayout: usesCompactLayout)
        thumbnail.onRemove = { [weak self] id in
            self?.removeAttachment(id: id, isUserInitiated: true)
        }
        return thumbnail
    }

    private func scrollToTrailingEdge() {
        layoutIfNeeded()
        let maximumOffset = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        scrollView.setContentOffset(CGPoint(x: maximumOffset, y: 0), animated: false)
    }

    private func shouldAutoScrollAfterAddingAttachment() -> Bool {
        guard !scrollView.isTracking, !scrollView.isDragging, !scrollView.isDecelerating else { return false }
        let maximumOffset = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
        return maximumOffset == 0 || scrollView.contentOffset.x >= maximumOffset - 1
    }

    private func scheduleScrollToTrailingEdge() {
        setNeedsLayout()
        DispatchQueue.main.async { [weak self] in
            self?.superview?.layoutIfNeeded()
            self?.layoutIfNeeded()
            self?.scrollToTrailingEdge()
        }
    }
}
