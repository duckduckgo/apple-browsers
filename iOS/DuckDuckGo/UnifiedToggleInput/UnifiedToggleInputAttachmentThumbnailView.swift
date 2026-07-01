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

    /// How an image attachment is laid out inside its chip.
    /// - `inline`: the thumbnail sits beside the remove button on a single row (iPhone).
    /// - `filled`: the image fills a square chip and the remove button overhangs the top-right
    ///   corner as a circular badge (iPad, matching macOS).
    enum ImageLayout {
        case inline
        case filled
    }

    /// The metrics driving the chip's layout. Callers inject a `Sizing` so the same view can render
    /// the compact iPhone chips and the larger square iPad thumbnails; the default matches iPhone so
    /// existing call sites are unaffected.
    struct Sizing {
        var chipHeight: CGFloat
        var imageChipWidth: CGFloat
        var fileChipWidth: CGFloat
        var chipCornerRadius: CGFloat
        var thumbnailSize: CGFloat
        var thumbnailCornerRadius: CGFloat
        var documentIconSize: CGFloat
        var removeButtonSize: CGFloat
        var horizontalPadding: CGFloat
        var iconTextSpacing: CGFloat
        var textRemoveSpacing: CGFloat
        var borderWidth: CGFloat
        var imageLayout: ImageLayout
        /// Side length of the square image chip when `imageLayout == .filled`.
        var imageChipSide: CGFloat

        /// Margin reserved around a `.filled` image chip so the corner remove button stays inside the
        /// view's bounds (keeping its tap target hittable). Derived from the remove button size.
        var removeButtonCornerOverflow: CGFloat {
            (removeButtonSize / 2).rounded(.up)
        }

        /// The height a single row of thumbnails occupies for this sizing — the taller of the file
        /// chip and the (possibly overhanging) image chip.
        var thumbnailRowHeight: CGFloat {
            let imageHeight = imageLayout == .filled ? imageChipSide + removeButtonCornerOverflow : chipHeight
            return max(imageHeight, chipHeight)
        }

        static let iPhone = Sizing(
            chipHeight: Constants.chipHeight,
            imageChipWidth: Constants.imageChipWidth,
            fileChipWidth: Constants.fileChipWidth,
            chipCornerRadius: Constants.chipCornerRadius,
            thumbnailSize: Constants.thumbnailSize,
            thumbnailCornerRadius: Constants.thumbnailCornerRadius,
            documentIconSize: Constants.documentIconSize,
            removeButtonSize: Constants.removeButtonSize,
            horizontalPadding: Constants.horizontalPadding,
            iconTextSpacing: Constants.iconTextSpacing,
            textRemoveSpacing: Constants.textRemoveSpacing,
            borderWidth: Constants.borderWidth,
            imageLayout: .inline,
            imageChipSide: Constants.imageChipWidth
        )

        /// The iPad expanded-omnibar chips: square 42×42 image thumbnails with an overhanging remove
        /// badge (matching macOS), and compact file chips.
        static let iPadOmnibar = Sizing(
            chipHeight: 42,
            imageChipWidth: 82,
            fileChipWidth: 196,
            chipCornerRadius: 10,
            thumbnailSize: 28,
            thumbnailCornerRadius: 6,
            documentIconSize: 24,
            removeButtonSize: 20,
            horizontalPadding: 10,
            iconTextSpacing: 8,
            textRemoveSpacing: 6,
            borderWidth: 1,
            imageLayout: .filled,
            imageChipSide: 42
        )
    }

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
    private let sizing: Sizing

    /// True when this chip renders an image using the square, overhanging-badge layout.
    private var usesFilledImageLayout: Bool {
        attachment.isImage && sizing.imageLayout == .filled
    }

    private lazy var chipView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = sizing.chipCornerRadius
        view.layer.borderWidth = sizing.borderWidth
        return view
    }()

    private lazy var imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = usesFilledImageLayout ? 0 : sizing.thumbnailCornerRadius
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

    init(attachment: UnifiedToggleInputAttachment, sizing: Sizing = .iPhone) {
        self.attachment = attachment
        self.attachmentId = attachment.id
        self.sizing = sizing
        super.init(frame: .zero)
        setupUI()
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        if usesFilledImageLayout {
            let side = sizing.imageChipSide + sizing.removeButtonCornerOverflow
            return CGSize(width: side, height: side)
        }
        let width = attachment.isImage ? sizing.imageChipWidth : sizing.fileChipWidth
        return CGSize(width: width, height: sizing.chipHeight)
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
        if usesFilledImageLayout {
            setupFilledImageLayout()
        } else {
            setupInlineLayout()
        }
    }

    /// iPhone chip: thumbnail (or file icon + name) on a single row beside the remove button.
    func setupInlineLayout() {
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

            imageView.leadingAnchor.constraint(equalTo: chipView.leadingAnchor, constant: sizing.horizontalPadding),
            imageView.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: sizing.thumbnailSize),
            imageView.heightAnchor.constraint(equalToConstant: sizing.thumbnailSize),

            fileIconView.leadingAnchor.constraint(equalTo: chipView.leadingAnchor, constant: sizing.horizontalPadding),
            fileIconView.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),
            fileIconView.widthAnchor.constraint(equalToConstant: sizing.documentIconSize),
            fileIconView.heightAnchor.constraint(equalToConstant: sizing.documentIconSize),

            fileNameLabel.leadingAnchor.constraint(equalTo: fileIconView.trailingAnchor, constant: sizing.iconTextSpacing),
            fileNameLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -sizing.textRemoveSpacing),
            fileNameLabel.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),

            removeButton.widthAnchor.constraint(equalToConstant: sizing.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: sizing.removeButtonSize),
            removeButton.trailingAnchor.constraint(equalTo: chipView.trailingAnchor, constant: -sizing.horizontalPadding),
            removeButton.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),

            widthAnchor.constraint(equalToConstant: intrinsicContentSize.width),
            heightAnchor.constraint(equalToConstant: sizing.chipHeight),
        ])
    }

    /// iPad image chip: a square image with the circular remove button overhanging the top-right
    /// corner. The chip is pinned to the bottom-leading so the overhang stays inside the view's
    /// bounds (keeping the remove button hittable).
    func setupFilledImageLayout() {
        addSubview(chipView)
        chipView.addSubview(imageView)
        addSubview(removeButton)

        let overhang = sizing.removeButtonCornerOverflow

        removeButton.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        removeButton.layer.cornerRadius = sizing.removeButtonSize / 2
        removeButton.layer.borderWidth = 1
        removeButton.layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        removeButton.tintColor = UIColor(designSystemColor: .textPrimary)
        removeButton.clipsToBounds = true

        NSLayoutConstraint.activate([
            chipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chipView.bottomAnchor.constraint(equalTo: bottomAnchor),
            chipView.widthAnchor.constraint(equalToConstant: sizing.imageChipSide),
            chipView.heightAnchor.constraint(equalToConstant: sizing.imageChipSide),

            imageView.topAnchor.constraint(equalTo: chipView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: chipView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: chipView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: chipView.bottomAnchor),

            removeButton.widthAnchor.constraint(equalToConstant: sizing.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: sizing.removeButtonSize),
            removeButton.centerXAnchor.constraint(equalTo: chipView.trailingAnchor),
            removeButton.centerYAnchor.constraint(equalTo: chipView.topAnchor),

            widthAnchor.constraint(equalToConstant: sizing.imageChipSide + overhang),
            heightAnchor.constraint(equalToConstant: sizing.imageChipSide + overhang),
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
        if usesFilledImageLayout {
            removeButton.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
            removeButton.layer.borderColor = UIColor(designSystemColor: .lines).cgColor
            removeButton.tintColor = UIColor(designSystemColor: .textPrimary)
        } else {
            removeButton.tintColor = UIColor(designSystemColor: .textPrimary)
        }
    }

    @objc func removeTapped() {
        onRemove?(attachmentId)
    }
}
