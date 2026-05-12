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
        static let chipHeight: CGFloat = 44
        static let imageChipWidth: CGFloat = 82
        static let fileChipWidth: CGFloat = 196
        static let chipCornerRadius: CGFloat = 18
        static let thumbnailSize: CGFloat = 32
        static let thumbnailCornerRadius: CGFloat = 6
        static let documentIconSize: CGFloat = 32
        static let removeButtonSize: CGFloat = 32
        static let horizontalPadding: CGFloat = 10
        static let iconTextSpacing: CGFloat = 8
        static let textRemoveSpacing: CGFloat = 6
        static let borderWidth: CGFloat = 1
    }

    let attachmentId: UUID
    var onRemove: ((UUID) -> Void)?
    private let attachment: UnifiedToggleInputAttachment

    private let chipView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = Constants.chipCornerRadius
        view.layer.borderWidth = Constants.borderWidth
        return view
    }()

    private let imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = Constants.thumbnailCornerRadius
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

    private let fileNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxSubheadSemibold()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size16.close, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textPrimary)
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
        let width = attachment.isImage ? Constants.imageChipWidth : Constants.fileChipWidth
        return CGSize(width: width, height: Constants.chipHeight)
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyAppearance()
        }
    }
}

private extension UnifiedToggleInputAttachmentThumbnailView {

    var borderColor: UIColor {
        attachment.isInvalid
            ? UIColor(designSystemColor: .destructivePrimary).withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.60 : 0.34)
            : UIColor(designSystemColor: .lines)
    }

    var chipBackgroundColor: UIColor {
        attachment.isInvalid
            ? UIColor(designSystemColor: .destructivePrimary).withAlphaComponent(traitCollection.userInterfaceStyle == .dark ? 0.24 : 0.18)
            : UIColor(designSystemColor: .controlsFillPrimary)
    }

    func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(chipView)
        chipView.addSubview(imageView)
        chipView.addSubview(fileIconView)
        chipView.addSubview(fileNameLabel)
        chipView.addSubview(removeButton)

        fileNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        removeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            chipView.topAnchor.constraint(equalTo: topAnchor),
            chipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            chipView.bottomAnchor.constraint(equalTo: bottomAnchor),

            imageView.leadingAnchor.constraint(equalTo: chipView.leadingAnchor, constant: Constants.horizontalPadding),
            imageView.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: Constants.thumbnailSize),
            imageView.heightAnchor.constraint(equalToConstant: Constants.thumbnailSize),

            fileIconView.leadingAnchor.constraint(equalTo: chipView.leadingAnchor, constant: Constants.horizontalPadding),
            fileIconView.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),
            fileIconView.widthAnchor.constraint(equalToConstant: Constants.documentIconSize),
            fileIconView.heightAnchor.constraint(equalToConstant: Constants.documentIconSize),

            fileNameLabel.leadingAnchor.constraint(equalTo: fileIconView.trailingAnchor, constant: Constants.iconTextSpacing),
            fileNameLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -Constants.textRemoveSpacing),
            fileNameLabel.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),

            removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.trailingAnchor.constraint(equalTo: chipView.trailingAnchor, constant: -Constants.horizontalPadding),
            removeButton.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),

            widthAnchor.constraint(equalToConstant: intrinsicContentSize.width),
            heightAnchor.constraint(equalToConstant: Constants.chipHeight),
        ])
    }

    func configure() {
        switch attachment {
        case .image(let imageAttachment):
            imageView.image = imageAttachment.image
            imageView.isHidden = false
            fileIconView.isHidden = true
            fileNameLabel.isHidden = true
            accessibilityLabel = imageAttachment.fileName
        case .file(let fileAttachment):
            configureFile(fileName: fileAttachment.fileName, validationMessage: nil)
        case .invalidFile(let fileAttachment):
            configureFile(fileName: fileAttachment.fileName, validationMessage: fileAttachment.validationMessage)
        }
        applyAppearance()
    }

    func configureFile(fileName: String, validationMessage: String?) {
        imageView.image = nil
        imageView.isHidden = true
        fileIconView.image = DesignSystemImages.Color.Size24.document
        fileIconView.tintColor = nil
        fileNameLabel.text = fileName
        fileIconView.isHidden = false
        fileNameLabel.isHidden = false
        accessibilityLabel = fileName
        accessibilityValue = validationMessage
    }

    func applyAppearance() {
        chipView.backgroundColor = chipBackgroundColor
        chipView.layer.borderColor = borderColor.cgColor
        fileNameLabel.textColor = UIColor(designSystemColor: .textPrimary)
        removeButton.tintColor = UIColor(designSystemColor: .textPrimary)
    }

    @objc func removeTapped() {
        onRemove?(attachmentId)
    }
}
