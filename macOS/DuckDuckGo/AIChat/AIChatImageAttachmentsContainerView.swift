//
//  AIChatImageAttachmentsContainerView.swift
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

/// A horizontal container view that displays up to 3 image attachment thumbnails.
final class AIChatImageAttachmentsContainerView: NSView {

    private enum Constants {
        static let spacing: CGFloat = 4
        static let maxAttachments = 3
    }

    private let stackView: NSStackView = {
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .horizontal
        stack.spacing = Constants.spacing
        stack.alignment = .bottom
        return stack
    }()

    private(set) var attachments: [AIChatImageAttachment] = []

    /// Called when attachments are added or removed.
    var onAttachmentsChanged: (() -> Void)?

    /// Called when an attachment is about to be removed. Allows parent to cleanup (e.g., cancel resize tasks).
    var onAttachmentWillRemove: ((UUID) -> Void)?

    var isFull: Bool {
        attachments.count >= Constants.maxAttachments
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        addSubview(stackView)

        let bottomConstraint = stackView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        bottomConstraint.priority = .defaultHigh

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            bottomConstraint,
        ])
    }

    func addAttachment(_ attachment: AIChatImageAttachment) {
        guard !isFull else { return }

        attachments.append(attachment)

        let thumbnailView = AIChatImageAttachmentThumbnailView(attachment: attachment)
        thumbnailView.onRemove = { [weak self] id in
            self?.removeAttachment(id: id)
        }
        stackView.addArrangedSubview(thumbnailView)

        onAttachmentsChanged?()
    }

    func removeAttachment(id: UUID) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }

        onAttachmentWillRemove?(id)

        attachments.remove(at: index)
        let thumbnailView = stackView.arrangedSubviews[index]
        stackView.removeArrangedSubview(thumbnailView)
        thumbnailView.removeFromSuperview()

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

    /// Replaces an attachment's image in place. Used for updating from placeholder to loaded image.
    func replaceAttachment(id: UUID, with newAttachment: AIChatImageAttachment) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        guard let thumbnailView = stackView.arrangedSubviews[index] as? AIChatImageAttachmentThumbnailView else { return }

        attachments[index] = newAttachment
        thumbnailView.updateImage(newAttachment.image)
    }
}
