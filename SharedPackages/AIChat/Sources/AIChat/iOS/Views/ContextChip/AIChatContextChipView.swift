//
//  AIChatContextChipView.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

#if os(iOS)
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

// MARK: - View

/// A chip view displaying page context information with favicon, title, subtitle, remove button,
/// and an info row with separator.
public final class AIChatContextChipView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let cornerRadius: CGFloat = 8
        static let borderWidth: CGFloat = 1
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 8
        static let faviconSize: CGFloat = 24
        static let faviconCornerRadius: CGFloat = 4
        static let contentSpacing: CGFloat = 8
        static let labelSpacing: CGFloat = 2
        static let removeButtonSize: CGFloat = 24
        static let separatorHeight: CGFloat = 1
        static let infoIconSize: CGFloat = 16
        static let infoRowSpacing: CGFloat = 6
        static let infoRowTopPadding: CGFloat = 8
        static let infoFontSize: CGFloat = 13
    }

    // MARK: - Properties

    /// Callback invoked when the remove button is tapped.
    public var onRemove: (() -> Void)?

    /// The subtitle text displayed below the title.
    public var subtitle: String = "" {
        didSet { subtitleLabel.text = subtitle }
    }

    /// The info text displayed in the footer row.
    public var infoText: String = "" {
        didSet { infoLabel.text = infoText }
    }

    // MARK: - UI Components

    private lazy var mainStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.alignment = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var chipContentView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var faviconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor(designSystemColor: .textSecondary)
        imageView.backgroundColor = UIColor(designSystemColor: .surface)
        imageView.layer.cornerRadius = Constants.faviconCornerRadius
        imageView.layer.masksToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var labelsStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        stackView.axis = .vertical
        stackView.spacing = Constants.labelSpacing
        stackView.alignment = .leading
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxSubheadSemibold()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var subtitleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxFootnoteRegular()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textSecondary)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var removeButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size16.close.withRenderingMode(.alwaysTemplate), for: .normal)
        button.tintColor = UIColor(designSystemColor: .textSecondary)
        button.addTarget(self, action: #selector(removeButtonTapped), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var separatorLine: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .decorationQuaternary)
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var infoRowContainer: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var infoRowStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Constants.infoRowSpacing
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var infoIcon: UIImageView = {
        let imageView = UIImageView()
        imageView.image = DesignSystemImages.Glyphs.Size12.info
        imageView.tintColor = UIColor(designSystemColor: .textSecondary)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var infoLabel: UILabel = {
        let label = UILabel()
        let fontMetrics = UIFontMetrics(forTextStyle: .footnote)
        label.font = fontMetrics.scaledFont(for: UIFont.italicSystemFont(ofSize: Constants.infoFontSize))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textSecondary)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    /// Configures the chip with the given title and optional favicon.
    ///
    /// - Parameters:
    ///   - title: The page title to display.
    ///   - favicon: The favicon image. If nil, a placeholder is shown.
    public func configure(title: String, favicon: UIImage?) {
        titleLabel.text = title
        faviconView.image = favicon ?? placeholderFavicon()
        accessibilityLabel = title
    }
}

// MARK: - Private Setup

private extension AIChatContextChipView {

    func setupUI() {
        backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        layer.cornerRadius = Constants.cornerRadius
        layer.borderWidth = Constants.borderWidth
        layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor

        addSubview(mainStackView)

        chipContentView.addSubview(faviconView)
        chipContentView.addSubview(labelsStackView)
        chipContentView.addSubview(removeButton)
        mainStackView.addArrangedSubview(chipContentView)

        mainStackView.addArrangedSubview(separatorLine)

        infoRowStackView.addArrangedSubview(infoIcon)
        infoRowStackView.addArrangedSubview(infoLabel)
        infoRowContainer.addSubview(infoRowStackView)
        mainStackView.addArrangedSubview(infoRowContainer)

        setupConstraints()
        setupAccessibility()
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            mainStackView.topAnchor.constraint(equalTo: topAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            faviconView.leadingAnchor.constraint(equalTo: chipContentView.leadingAnchor, constant: Constants.horizontalPadding),
            faviconView.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor),
            faviconView.widthAnchor.constraint(equalToConstant: Constants.faviconSize),
            faviconView.heightAnchor.constraint(equalToConstant: Constants.faviconSize),

            labelsStackView.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: Constants.contentSpacing),
            labelsStackView.topAnchor.constraint(equalTo: chipContentView.topAnchor, constant: Constants.verticalPadding),
            labelsStackView.bottomAnchor.constraint(equalTo: chipContentView.bottomAnchor, constant: -Constants.verticalPadding),
            labelsStackView.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -Constants.contentSpacing),

            removeButton.trailingAnchor.constraint(equalTo: chipContentView.trailingAnchor, constant: -Constants.horizontalPadding),
            removeButton.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize),

            separatorLine.heightAnchor.constraint(equalToConstant: Constants.separatorHeight),

            infoRowStackView.topAnchor.constraint(equalTo: infoRowContainer.topAnchor, constant: Constants.infoRowTopPadding),
            infoRowStackView.leadingAnchor.constraint(equalTo: infoRowContainer.leadingAnchor, constant: Constants.horizontalPadding),
            infoRowStackView.trailingAnchor.constraint(lessThanOrEqualTo: infoRowContainer.trailingAnchor, constant: -Constants.horizontalPadding),
            infoRowStackView.bottomAnchor.constraint(equalTo: infoRowContainer.bottomAnchor, constant: -Constants.verticalPadding),

            infoIcon.widthAnchor.constraint(equalToConstant: Constants.infoIconSize),
            infoIcon.heightAnchor.constraint(equalToConstant: Constants.infoIconSize),
        ])
    }

    func setupAccessibility() {
        isAccessibilityElement = false
        removeButton.accessibilityLabel = "Remove"
        removeButton.accessibilityTraits = .button
    }

    func placeholderFavicon() -> UIImage? {
        return DesignSystemImages.Glyphs.Size24.globe.withRenderingMode(.alwaysTemplate)
    }

    @objc func removeButtonTapped() {
        onRemove?()
    }
}

// MARK: - Trait Changes

extension AIChatContextChipView {

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor
        }
    }
}
#endif
