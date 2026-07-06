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
        static let horizontalPadding: CGFloat = 12
        static let topPadding: CGFloat = 8
        static let stripHeight: CGFloat = topPadding + UnifiedToggleInputAttachmentThumbnailView.Constants.chipHeight
    }

    private(set) var attachments: [UnifiedToggleInputAttachment] = []
    var onAttachmentRemoved: ((UUID, UnifiedToggleInputAttachment, Bool) -> Void)?
    var onAttachmentsChanged: (() -> Void)?

    private let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.clipsToBounds = true
        return scrollView
    }()

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Constants.spacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addAttachment(_ attachment: UnifiedToggleInputAttachment) {
        let shouldAutoScroll = shouldAutoScrollAfterAddingAttachment()
        attachments.append(attachment)
        stackView.addArrangedSubview(makeThumbnail(for: attachment))
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
        onAttachmentsChanged?()
    }

    func removeAllAttachments() {
        attachments.removeAll()
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        onAttachmentsChanged?()
    }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        clipsToBounds = false
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
        let thumbnail = UnifiedToggleInputAttachmentThumbnailView(attachment: attachment)
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
