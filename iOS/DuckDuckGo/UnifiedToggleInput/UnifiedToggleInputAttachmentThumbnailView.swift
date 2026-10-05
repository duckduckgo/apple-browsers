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
        static let chipCornerRadius: CGFloat = chipHeight / 2
        static let standardIconSize: CGFloat = 28
        static let standardThumbnailCornerRadius: CGFloat = 6
        static let standardRemoveButtonSize: CGFloat = 32
        static let faviconCornerRadius: CGFloat = 4
        static let faviconSize: CGFloat = 20
        static let iconFrameSize: CGFloat = 24
        static let removeButtonSize: CGFloat = 28
        static let removeButtonTrailing: CGFloat = 8
        static let horizontalPadding: CGFloat = 10
        static let iconTextSpacing: CGFloat = 8
        static let textRemoveSpacing: CGFloat = 6
        static let borderWidth: CGFloat = 1
        static let compactHorizontalPadding: CGFloat = 6
        static let compactContentSpacing: CGFloat = 4
        static let removeButtonHitTarget: CGFloat = 44
    }

    let attachmentId: UUID
    var onRemove: ((UUID) -> Void)?
    private let attachment: UnifiedToggleInputAttachment
    private let usesCompactLayout: Bool
    private var widthConstraint: NSLayoutConstraint!
    private var iconLeadingConstraint: NSLayoutConstraint!
    private var titleLeadingConstraint: NSLayoutConstraint!
    private var titleTrailingConstraint: NSLayoutConstraint!
    private var removeTrailingConstraint: NSLayoutConstraint!
    private let iconLayoutGuide = UILayoutGuide()

    private var iconFrameSize: CGFloat {
        usesCompactLayout ? Constants.iconFrameSize : Constants.standardIconSize
    }

    private var removeButtonSize: CGFloat {
        usesCompactLayout ? Constants.removeButtonSize : Constants.standardRemoveButtonSize
    }

    private var iconSize: CGFloat {
        if usesCompactLayout, case .tab = attachment {
            return Constants.faviconSize
        }
        return iconFrameSize
    }

    var minimumContentWidth: CGFloat {
        guard !attachment.isImage else {
            return Constants.removeButtonHitTarget
        }
        let title = attachment.fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let compactTitle = String(title.prefix(1)) + "…"
        let font = fileNameLabel.font ?? .daxSubheadSemibold()
        let titleWidth = ceil((compactTitle as NSString).size(withAttributes: [.font: font]).width) + 1
        return Constants.compactHorizontalPadding + Constants.removeButtonTrailing + Constants.iconFrameSize + titleWidth
            + 2 * Constants.compactContentSpacing + Constants.removeButtonSize
    }

    private let chipView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        view.layer.cornerRadius = Constants.chipCornerRadius
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = Constants.borderWidth
        return view
    }()

    private lazy var imageView: UIImageView = {
        let iv = UIImageView()
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = usesCompactLayout ? 0 : Constants.standardThumbnailCornerRadius
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

    private lazy var fileNameLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxSubheadSemibold()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.lineBreakMode = usesCompactLayout ? .byTruncatingTail : .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var removeButton: UIButton = {
        let button = usesCompactLayout ? AttachmentRemoveButton(type: .system) : UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size16.close, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textSecondary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(removeTapped), for: .touchUpInside)
        button.layer.cornerRadius = usesCompactLayout ? removeButtonSize / 2 : 0
        return button
    }()

    init(attachment: UnifiedToggleInputAttachment, usesCompactLayout: Bool = false) {
        self.usesCompactLayout = usesCompactLayout
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

    func setWidth(_ width: CGFloat) {
        guard usesCompactLayout else { return }
        widthConstraint.constant = width
        let paddingExpansion = Constants.horizontalPadding - Constants.compactHorizontalPadding
        let leadingSpacingExpansion = Constants.iconTextSpacing - Constants.compactContentSpacing
        let trailingSpacingExpansion = Constants.textRemoveSpacing - Constants.compactContentSpacing
        let textSpacing = attachment.isImage ? 0 : leadingSpacingExpansion + trailingSpacingExpansion
        let totalExpansion = paddingExpansion + textSpacing
        let fraction = min(1, max(0, (width - minimumContentWidth) / totalExpansion))
        iconLeadingConstraint.constant = Constants.compactHorizontalPadding + paddingExpansion * fraction
        titleLeadingConstraint.constant = Constants.compactContentSpacing + leadingSpacingExpansion * fraction
        titleTrailingConstraint.constant = -(Constants.compactContentSpacing + trailingSpacingExpansion * fraction)
    }

    override func layoutSubviews() {
        setWidth(widthConstraint.constant)
        super.layoutSubviews()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            applyAppearance()
        }
        if traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory {
            setNeedsLayout()
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
        chipView.addLayoutGuide(iconLayoutGuide)
        chipView.addSubview(fileIconView)
        chipView.addSubview(fileNameLabel)
        chipView.addSubview(removeButton)

        fileNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        removeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        widthConstraint = widthAnchor.constraint(equalToConstant: intrinsicContentSize.width)
        iconLeadingConstraint = iconLayoutGuide.leadingAnchor.constraint(equalTo: chipView.leadingAnchor, constant: Constants.horizontalPadding)
        titleLeadingConstraint = fileNameLabel.leadingAnchor.constraint(equalTo: iconLayoutGuide.trailingAnchor, constant: Constants.iconTextSpacing)
        titleTrailingConstraint = fileNameLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -Constants.textRemoveSpacing)
        let removeTrailing = usesCompactLayout ? Constants.removeButtonTrailing : Constants.horizontalPadding
        removeTrailingConstraint = removeButton.trailingAnchor.constraint(equalTo: chipView.trailingAnchor, constant: -removeTrailing)

        if !attachment.isImage {
            NSLayoutConstraint.activate([titleLeadingConstraint, titleTrailingConstraint])
        } else {
            fileNameLabel.leadingAnchor.constraint(equalTo: chipView.leadingAnchor).isActive = true
        }

        if usesCompactLayout {
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: chipView.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: chipView.trailingAnchor),
                imageView.topAnchor.constraint(equalTo: chipView.topAnchor),
                imageView.bottomAnchor.constraint(equalTo: chipView.bottomAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: chipView.leadingAnchor, constant: Constants.horizontalPadding),
                imageView.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: Constants.standardIconSize),
                imageView.heightAnchor.constraint(equalToConstant: Constants.standardIconSize),
            ])
        }

        NSLayoutConstraint.activate([
            chipView.topAnchor.constraint(equalTo: topAnchor),
            chipView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chipView.trailingAnchor.constraint(equalTo: trailingAnchor),
            chipView.bottomAnchor.constraint(equalTo: bottomAnchor),

            iconLeadingConstraint,
            iconLayoutGuide.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),
            iconLayoutGuide.widthAnchor.constraint(equalToConstant: iconFrameSize),
            iconLayoutGuide.heightAnchor.constraint(equalToConstant: iconFrameSize),
            fileIconView.centerXAnchor.constraint(equalTo: iconLayoutGuide.centerXAnchor),
            fileIconView.centerYAnchor.constraint(equalTo: iconLayoutGuide.centerYAnchor),
            fileIconView.widthAnchor.constraint(equalToConstant: iconSize),
            fileIconView.heightAnchor.constraint(equalToConstant: iconSize),

            fileNameLabel.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),

            removeButton.widthAnchor.constraint(equalToConstant: removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: removeButtonSize),
            removeTrailingConstraint,
            removeButton.centerYAnchor.constraint(equalTo: chipView.centerYAnchor),

            widthConstraint,
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
        case .tab(let tabAttachment):
            configureTab(title: tabAttachment.title, favicon: tabAttachment.favicon)
        }
        applyAppearance()
    }

    func configureTab(title: String, favicon: UIImage?) {
        imageView.image = nil
        imageView.isHidden = true
        let fallbackIcon = usesCompactLayout ? DesignSystemImages.Glyphs.Size16.globe : DesignSystemImages.Glyphs.Size24.globe
        fileIconView.image = favicon?.withRenderingMode(.alwaysOriginal) ?? fallbackIcon.withRenderingMode(.alwaysTemplate)
        fileIconView.tintColor = UIColor(designSystemColor: .textSecondary)
        fileIconView.layer.cornerRadius = usesCompactLayout ? Constants.faviconCornerRadius : Constants.standardThumbnailCornerRadius
        fileIconView.clipsToBounds = true
        fileNameLabel.text = title
        fileIconView.isHidden = false
        fileNameLabel.isHidden = false
        accessibilityLabel = title
        accessibilityValue = nil
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
        removeButton.tintColor = UIColor(designSystemColor: .textSecondary)
        if usesCompactLayout {
            let isDarkMode = traitCollection.userInterfaceStyle == .dark
            removeButton.backgroundColor = UIColor(designSystemColor: isDarkMode ? .surfaceTertiary : .controlsRaisedFillPrimary)
        } else {
            removeButton.backgroundColor = .clear
        }
    }

    @objc func removeTapped() {
        onRemove?(attachmentId)
    }
}

private final class AttachmentRemoveButton: UIButton {

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let minimumSize = UnifiedToggleInputAttachmentThumbnailView.Constants.removeButtonHitTarget
        let dx = min(0, (bounds.width - minimumSize) / 2)
        let dy = min(0, (bounds.height - minimumSize) / 2)
        return bounds.insetBy(dx: dx, dy: dy).contains(point)
    }
}
