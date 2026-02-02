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
        static let chipWidth: CGFloat = 240
        static let cornerRadius: CGFloat = 15
        static let borderCornerRadius: CGFloat = 13
        static let borderWidth: CGFloat = 1.5
        static let dashLength: CGFloat = 5
        static let dashSpacing: CGFloat = 5

        static let faviconSize: CGFloat = 24
        static let faviconCornerRadius: CGFloat = 4
        static let faviconLeading: CGFloat = 10
        static let faviconVerticalPadding: CGFloat = 10

        static let removeButtonSize: CGFloat = 24
        static let removeButtonTrailing: CGFloat = 10
        static let removeButtonVerticalPadding: CGFloat = 10

        static let contentSpacing: CGFloat = 8
        static let labelSpacing: CGFloat = 2
    }

    // MARK: - State

    public enum State {
        case placeholder
        case attached(title: String, favicon: UIImage?)
    }

    private var currentState: State = .placeholder

    // MARK: - Properties

    /// Callback invoked when the remove button is tapped.
    public var onRemove: (() -> Void)?

    /// Callback invoked when the chip is tapped in the placeholder state.
    public var onTapToAttach: (() -> Void)?

    private var borderLayer: CAShapeLayer?
    private var isDashedBorder = false
    private var lastBorderBounds: CGRect = .zero
    private var tapGesture: UITapGestureRecognizer?

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

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxSubheadSemibold()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textTertiary)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
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

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    /// Configures the chip with the given state.
    ///
    /// - Parameter state: The state to display (placeholder or attached with title/favicon).
    public func configure(state: State) {
        currentState = state
        updateUI(for: state)
    }

    /// Configures the chip with the given title and optional favicon (attached state).
    ///
    /// - Parameters:
    ///   - title: The page title to display.
    ///   - favicon: The favicon image. If nil, a placeholder is shown.
    public func configure(title: String, favicon: UIImage?) {
        configure(state: .attached(title: title, favicon: favicon))
    }

    /// Updates the chip content, preserving the existing favicon if the new one is nil.
    ///
    /// - Parameters:
    ///   - title: The new page title to display.
    ///   - favicon: The new favicon image. If nil, the existing favicon is preserved.
    public func update(title: String, favicon: UIImage?) {
        guard case .attached = currentState else { return }
        titleLabel.text = title
        if let favicon {
            faviconView.image = favicon
        }
        accessibilityLabel = title
    }
}

// MARK: - Private Setup

private extension AIChatContextChipView {

    func setupUI() {
        backgroundColor = .clear
        layer.cornerRadius = Constants.cornerRadius
        clipsToBounds = true

        addSubview(mainStackView)

        chipContentView.addSubview(faviconView)
        chipContentView.addSubview(titleLabel)
        chipContentView.addSubview(removeButton)
        mainStackView.addArrangedSubview(chipContentView)

        let gesture = UITapGestureRecognizer(target: self, action: #selector(chipTapped))
        tapGesture = gesture
        addGestureRecognizer(gesture)

        setupConstraints()
        setupAccessibility()
    }

    func updateUI(for state: State) {
        switch state {
        case .placeholder:
            titleLabel.text = UserText.attachPageContent
            titleLabel.textColor = UIColor(designSystemColor: .textPlaceholder)
            faviconView.image = DesignSystemImages.Glyphs.Size24.pageContentAttach.withRenderingMode(.alwaysTemplate)
            faviconView.tintColor = UIColor(designSystemColor: .textTertiary)
            faviconView.backgroundColor = .clear
            faviconView.layer.borderWidth = 0
            faviconView.layer.borderColor = nil
            backgroundColor = .clear
            removeButton.isHidden = true
            accessibilityLabel = UserText.attachPageContent
            updateBorder(dashed: true)
            isUserInteractionEnabled = true
            tapGesture?.isEnabled = true

        case .attached(let title, let favicon):
            titleLabel.text = title
            titleLabel.textColor = UIColor(designSystemColor: .textPrimary)
            removeButton.isHidden = false
            faviconView.image = favicon ?? placeholderFavicon()
            faviconView.backgroundColor = .clear
            faviconView.layer.borderWidth = 0
            faviconView.layer.borderColor = nil
            backgroundColor = .clear
            accessibilityLabel = title
            updateBorder(dashed: false)
            tapGesture?.isEnabled = false
        }
    }

    func updateBorder(dashed: Bool) {
        isDashedBorder = dashed
        layer.borderWidth = 0
        layer.borderColor = nil
        clipsToBounds = true

        let borderLayer = makeOrReuseBorderLayer()
        borderLayer.strokeColor = UIColor(designSystemColor: dashed ? .decorationPrimary : .decorationQuaternary).cgColor
        borderLayer.lineWidth = Constants.borderWidth
        borderLayer.lineDashPattern = dashed ? [NSNumber(value: Constants.dashLength), NSNumber(value: Constants.dashSpacing)] : nil
        borderLayer.fillColor = dashed ? nil : UIColor(designSystemColor: .controlsFillPrimary).cgColor

        setNeedsLayout()
    }

    func makeOrReuseBorderLayer() -> CAShapeLayer {
        if let borderLayer = borderLayer {
            return borderLayer
        }

        let newLayer = CAShapeLayer()
        newLayer.contentsScale = UIScreen.main.scale
        layer.insertSublayer(newLayer, at: 0)
        borderLayer = newLayer
        return newLayer
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Constants.chipWidth),

            mainStackView.topAnchor.constraint(equalTo: topAnchor),
            mainStackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStackView.bottomAnchor.constraint(equalTo: bottomAnchor),

            faviconView.leadingAnchor.constraint(equalTo: chipContentView.leadingAnchor, constant: Constants.faviconLeading),
            faviconView.topAnchor.constraint(equalTo: chipContentView.topAnchor, constant: Constants.faviconVerticalPadding),
            faviconView.bottomAnchor.constraint(equalTo: chipContentView.bottomAnchor, constant: -Constants.faviconVerticalPadding),
            faviconView.widthAnchor.constraint(equalToConstant: Constants.faviconSize),
            faviconView.heightAnchor.constraint(equalToConstant: Constants.faviconSize),

            titleLabel.leadingAnchor.constraint(equalTo: faviconView.trailingAnchor, constant: Constants.contentSpacing),
            titleLabel.centerYAnchor.constraint(equalTo: chipContentView.centerYAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -Constants.contentSpacing),

            removeButton.trailingAnchor.constraint(equalTo: chipContentView.trailingAnchor, constant: -Constants.removeButtonTrailing),
            removeButton.topAnchor.constraint(equalTo: chipContentView.topAnchor, constant: Constants.removeButtonVerticalPadding),
            removeButton.bottomAnchor.constraint(equalTo: chipContentView.bottomAnchor, constant: -Constants.removeButtonVerticalPadding),
            removeButton.widthAnchor.constraint(equalToConstant: Constants.removeButtonSize),
            removeButton.heightAnchor.constraint(equalToConstant: Constants.removeButtonSize),
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

    @objc func chipTapped() {
        if case .placeholder = currentState {
            onTapToAttach?()
        }
    }
}

// MARK: - Layout

extension AIChatContextChipView {

    public override func layoutSubviews() {
        super.layoutSubviews()

        guard !bounds.isEmpty else { return }
        guard let borderLayer = borderLayer else { return }

        if lastBorderBounds != bounds {
            let inset = Constants.borderWidth / 2
            let insetBounds = CGRect(origin: .zero, size: bounds.size).insetBy(dx: inset, dy: inset)

            borderLayer.frame = bounds
            borderLayer.path = UIBezierPath(roundedRect: insetBounds, cornerRadius: Constants.borderCornerRadius).cgPath
            lastBorderBounds = bounds
        }
    }
}

// MARK: - Trait Changes

extension AIChatContextChipView {

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            if let borderLayer = borderLayer {
                borderLayer.strokeColor = UIColor(designSystemColor: isDashedBorder ? .decorationPrimary : .decorationQuaternary).cgColor
                borderLayer.fillColor = isDashedBorder ? nil : UIColor(designSystemColor: .controlsFillPrimary).cgColor
            }
            // Update favicon border color for dark mode (placeholder state only)
            if faviconView.layer.borderWidth > 0 {
                faviconView.layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor
            }
        }
    }
}
#endif
