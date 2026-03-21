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
        static let maxAttachments: Int = 3
        static let horizontalPadding: CGFloat = 12
        static let topPadding: CGFloat = 8
        static let stripHeight: CGFloat = topPadding + UnifiedToggleInputAttachmentThumbnailView.Constants.totalSize
    }

    private(set) var attachments: [AIChatImageAttachment] = []
    var onAttachmentRemoved: ((UUID) -> Void)?
    var onAttachmentsChanged: (() -> Void)?

    var isFull: Bool { attachments.count >= Constants.maxAttachments }

    private let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = Constants.spacing
        stack.alignment = .bottom
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

    func addAttachment(_ attachment: AIChatImageAttachment) {
        guard !isFull else { return }
        attachments.append(attachment)
        let thumbnail = UnifiedToggleInputAttachmentThumbnailView(attachment: attachment)
        thumbnail.onRemove = { [weak self] id in
            self?.removeAttachment(id: id)
        }
        stackView.addArrangedSubview(thumbnail)
        onAttachmentsChanged?()
    }

    func removeAttachment(id: UUID) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        attachments.remove(at: index)
        let thumbnailViews = stackView.arrangedSubviews.compactMap { $0 as? UnifiedToggleInputAttachmentThumbnailView }
        if let view = thumbnailViews.first(where: { $0.attachmentId == id }) {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        onAttachmentRemoved?(id)
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
        addSubview(stackView)
        let bottomConstraint = stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        bottomConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.topPadding),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            stackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -Constants.horizontalPadding),
            bottomConstraint,
        ])
    }
}
