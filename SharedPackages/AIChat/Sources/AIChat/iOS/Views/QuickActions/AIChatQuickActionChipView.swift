//
//  AIChatQuickActionChipView.swift
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
import UIKit

// MARK: - View

/// A pill-shaped chip view displaying a quick action with icon and label.
public final class AIChatQuickActionChipView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let height: CGFloat = 36
        static let cornerRadius: CGFloat = 12
        static let iconLeadingPadding: CGFloat = 8
        static let iconTopPadding: CGFloat = 10
        static let trailingPadding: CGFloat = 12
        static let iconSize: CGFloat = 16
        static let iconLabelSpacing: CGFloat = 6
        static let borderWidth: CGFloat = 1
        static let highlightAlpha: CGFloat = 0.1
    }

    // MARK: - Properties

    var onTap: (() -> Void)?

    // MARK: - UI Components

    private lazy var iconView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.tintColor = UIColor(designSystemColor: .textPrimary)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    private lazy var label: UILabel = {
        let label = UILabel()
        label.font = UIFont.daxButton()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var highlightOverlay: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(Constants.highlightAlpha)
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGesture()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Configuration

    public func configure<Action: AIChatQuickActionType>(with action: Action) {
        label.text = action.title
        iconView.image = action.icon?.withRenderingMode(.alwaysTemplate)
        iconView.isHidden = action.icon == nil
        accessibilityLabel = action.title
    }
}

// MARK: - Private Setup

private extension AIChatQuickActionChipView {

    func setupUI() {
        backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        layer.cornerRadius = Constants.cornerRadius
        layer.borderWidth = Constants.borderWidth
        layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor

        addSubview(iconView)
        addSubview(label)
        addSubview(highlightOverlay)
        highlightOverlay.layer.cornerRadius = Constants.cornerRadius

        setupConstraints()
        setupAccessibility()
    }

    func setupConstraints() {
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: Constants.height),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.iconLeadingPadding),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: Constants.iconTopPadding),
            iconView.widthAnchor.constraint(equalToConstant: Constants.iconSize),
            iconView.heightAnchor.constraint(equalToConstant: Constants.iconSize),

            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: Constants.iconLabelSpacing),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.trailingPadding),

            highlightOverlay.topAnchor.constraint(equalTo: topAnchor),
            highlightOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            highlightOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            highlightOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    func setupAccessibility() {
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    func setupGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tapGesture)
    }

    @objc func handleTap() {
        onTap?()
    }
}

// MARK: - Touch Handling

extension AIChatQuickActionChipView {

    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        highlightOverlay.isHidden = false
    }

    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        highlightOverlay.isHidden = true
    }

    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        highlightOverlay.isHidden = true
    }

    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.borderColor = UIColor(designSystemColor: .decorationQuaternary).cgColor
        }
    }
}
#endif
