//
//  UnifiedToggleInputAttachmentThumbnailView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

final class UnifiedToggleInputAttachmentThumbnailView: UIView {

    enum Constants {
        static let thumbnailSize: CGFloat = 50
        static let cornerRadius: CGFloat = 12
        static let borderWidth: CGFloat = 2
        static let removeButtonSize: CGFloat = 20
        static let removeButtonInset: CGFloat = 4
        static let removeButtonOverflow: CGFloat = 8
        static let totalSize: CGFloat = thumbnailSize + removeButtonOverflow
    }

    let attachmentId: UUID
    var onRemove: ((UUID) -> Void)?
    private let attachment: UnifiedToggleInputAttachment

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = Constants.cornerRadius
        iv.layer.borderWidth = Constants.borderWidth
        iv.layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        iv.translatesAutoresizingMaskIntoConstraints = false
        return iv
    }()

    private let fileIconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor(designSystemColor: .iconsSecondary)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private let fileExtensionLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxCaptionBold()
        label.adjustsFontForContentSizeCategory = true
        label.textAlignment = .center
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var removeButton: UIButton = {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        button.setImage(UIImage(systemName: "xmark", withConfiguration: config), for: .normal)
        button.tintColor = UIColor(designSystemColor: .iconsSecondary)
        button.backgroundColor = UIColor(designSystemColor: .panel)
        button.layer.cornerRadius = Constants.removeButtonSize / 2
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        return button
    }()

    init(attachment: UnifiedToggleInputAttachment) {
        self.attachment = attachment
        self.attachmentId = attachment.id
        super.init(frame: .zero)
        setupUI()
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: Constants.totalSize, height: Constants.totalSize)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            imageView.layer.borderColor = UIColor(designSystemColor: .lines).cgColor
            removeButton.layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        }
    }
}

private extension UnifiedToggleInputAttachmentThumbnailView {

    func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        addSubview(fileIconView)
        addSubview(fileExtensionLabel)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Constants.thumbnailSize),
            imageView.heightAnchor.constraint(equalToConstant: Constants.thumbnailSize),

            fileIconView.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            fileIconView.centerYAnchor.constraint(equalTo: imageView.centerYAnchor, constant: -6),
            fileIconView.widthAnchor.constraint(equalToConstant: 24),
            fileIconView.heightAnchor.constraint(equalToConstant: 24),

            fileExtensionLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 4),
            fileExtensionLabel.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -4),
            fileExtensionLabel.bottomAnchor.constraint(equalTo: imageView.bottomAnchor, constant: -6),

            removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.centerXAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -Constants.removeButtonInset),
            removeButton.centerYAnchor.constraint(equalTo: imageView.topAnchor, constant: Constants.removeButtonInset),

            widthAnchor.constraint(equalToConstant: Constants.totalSize),
            heightAnchor.constraint(equalToConstant: Constants.totalSize),
        ])
    }

    func configure() {
        switch attachment {
        case .image(let imageAttachment):
            imageView.image = imageAttachment.image
            imageView.backgroundColor = .clear
            imageView.isHidden = false
            fileIconView.isHidden = true
            fileExtensionLabel.isHidden = true
            accessibilityLabel = imageAttachment.fileName
        case .file(let fileAttachment):
            imageView.image = nil
            imageView.backgroundColor = UIColor(designSystemColor: .surface)
            imageView.isHidden = false
            fileIconView.image = DesignSystemImages.Glyphs.Size24.folder.withRenderingMode(.alwaysTemplate)
            fileExtensionLabel.text = attachment.fileExtensionDisplayName
            fileIconView.isHidden = false
            fileExtensionLabel.isHidden = false
            accessibilityLabel = fileAttachment.fileName
        }
    }

    @objc func removeTapped() {
        onRemove?(attachmentId)
    }
}
