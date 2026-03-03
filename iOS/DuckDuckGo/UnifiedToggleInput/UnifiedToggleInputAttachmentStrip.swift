//
//  UnifiedToggleInputAttachmentStrip.swift
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

/// Horizontal scrollable strip of image attachment thumbnails with remove buttons.
/// Each thumbnail is 56×56pt with an X button in the top-right corner.
final class UnifiedToggleInputAttachmentStrip: UIView {

    // MARK: - Constants

    private enum Constants {
        static let thumbnailSize: CGFloat = 56
        static let thumbnailCornerRadius: CGFloat = 8
        static let removeButtonSize: CGFloat = 20
        static let stripPadding: CGFloat = 8
        static let thumbnailSpacing: CGFloat = 8
    }

    // MARK: - Callbacks

    var onRemove: ((UUID) -> Void)?

    // MARK: - UI

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsHorizontalScrollIndicator = false
        sv.showsVerticalScrollIndicator = false
        return sv
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.axis = .horizontal
        sv.spacing = Constants.thumbnailSpacing
        sv.alignment = .center
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public API

    func setAttachments(_ attachments: [AIChatImageAttachment]) {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for attachment in attachments {
            stackView.addArrangedSubview(makeThumbnail(for: attachment))
        }
    }

    // MARK: - Private

    private func setupUI() {
        addSubview(scrollView)
        scrollView.addSubview(stackView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: Constants.stripPadding),
            stackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: Constants.stripPadding),
            stackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -Constants.stripPadding),
            stackView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -Constants.stripPadding),
            stackView.heightAnchor.constraint(equalToConstant: Constants.thumbnailSize),
        ])
    }

    private func makeThumbnail(for attachment: AIChatImageAttachment) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let imageView = UIImageView(image: attachment.image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = Constants.thumbnailCornerRadius
        container.addSubview(imageView)

        let removeButton = UIButton(type: .system)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        removeButton.tintColor = .white
        let attachmentId = attachment.id
        removeButton.addAction(UIAction { [weak self] _ in
            self?.onRemove?(attachmentId)
        }, for: .touchUpInside)
        container.addSubview(removeButton)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Constants.thumbnailSize),
            container.heightAnchor.constraint(equalToConstant: Constants.thumbnailSize),

            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            removeButton.topAnchor.constraint(equalTo: container.topAnchor),
            removeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize),
        ])

        return container
    }
}
