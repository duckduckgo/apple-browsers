//
//  UnifiedToggleInputToolbarView.swift
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

import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// Horizontal toolbar with AI tool buttons: globe, image, [spacer], model picker chip, submit.
/// All buttons except submit are non-functional stubs for Part 1.
final class UnifiedToggleInputToolbarView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let verticalPadding: CGFloat = 8
        static let horizontalPadding: CGFloat = 8
        static let toolButtonSize: CGFloat = 40
        static let leftGroupSpacing: CGFloat = 4
        static let rightGroupSpacing: CGFloat = 8
        static let chipHeight: CGFloat = 32
        static let chipCornerRadius: CGFloat = 16
        static let chipHorizontalPadding: CGFloat = 12
        static let chipSpacing: CGFloat = 4
        static let chipFontSize: CGFloat = 13
    }

    // MARK: - Callbacks

    var onSearchTapped: (() -> Void)?
    var onAttachTapped: (() -> Void)?
    var onModelPickerTapped: (() -> Void)?
    var onSubmitTapped: (() -> Void)?
    var onStopGeneratingTapped: (() -> Void)?

    // MARK: - State

    var isSubmitEnabled: Bool = false {
        didSet { updateSubmitButtonState() }
    }

    var isSubmitButtonHidden: Bool = false {
        didSet { updateGeneratingVisibility() }
    }

    var isGenerating: Bool = false {
        didSet { updateGeneratingVisibility() }
    }

    var modelName: String = "4o-mini" {
        didSet { modelChipLabel.text = modelName }
    }

    // MARK: - UI Components

    private lazy var globeButton: UIButton = makeToolButton(
        image: DesignSystemImages.Glyphs.Size16.globe,
        accessibilityLabel: UserText.aiChatToolbarSearchButtonAccessibilityLabel,
        action: #selector(searchTapped)
    )

    private lazy var imageButton: UIButton = makeToolButton(
        image: DesignSystemImages.Glyphs.Size16.image,
        accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel,
        action: #selector(attachTapped)
    )

    private lazy var modelChipButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(modelPickerTapped), for: .touchUpInside)

        button.addSubview(modelChipLabel)
        button.addSubview(modelChipChevron)

        button.layer.cornerRadius = Constants.chipCornerRadius
        button.layer.borderWidth = 1
        button.layer.borderColor = UIColor(designSystemColor: .lines).cgColor
        button.clipsToBounds = true

        NSLayoutConstraint.activate([
            button.heightAnchor.constraint(equalToConstant: Constants.chipHeight),
            modelChipLabel.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: Constants.chipHorizontalPadding),
            modelChipLabel.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            modelChipChevron.leadingAnchor.constraint(equalTo: modelChipLabel.trailingAnchor, constant: Constants.chipSpacing),
            modelChipChevron.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -Constants.chipHorizontalPadding),
            modelChipChevron.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            modelChipChevron.widthAnchor.constraint(equalToConstant: 12),
            modelChipChevron.heightAnchor.constraint(equalToConstant: 12),
        ])

        return button
    }()

    private lazy var modelChipLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = modelName
        label.font = .systemFont(ofSize: Constants.chipFontSize, weight: .regular)
        label.textColor = UIColor(designSystemColor: .textPrimary)
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }()

    private lazy var modelChipChevron: UIImageView = {
        let imageView = UIImageView(image: UIImage(systemName: "chevron.down")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        ))
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = UIColor(designSystemColor: .textPrimary)
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private lazy var submitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.arrowUp, for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(designSystemColor: .accent)
        button.layer.cornerRadius = Constants.toolButtonSize / 2
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = UserText.aiChatToolbarSubmitButtonAccessibilityLabel
        button.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Constants.toolButtonSize),
            button.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),
        ])
        return button
    }()

    private lazy var stopButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size16.stopSquare, for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(designSystemColor: .destructivePrimary)
        button.layer.cornerRadius = 14
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = "Stop generating"
        button.accessibilityIdentifier = "AIChat.Toolbar.Button.StopGenerating"
        button.addTarget(self, action: #selector(stopGeneratingTapped), for: .touchUpInside)
        button.isHidden = true
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Constants.toolButtonSize),
            button.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),
        ])
        return button
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        modelChipButton.layer.borderColor = UIColor(designSystemColor: .lines).cgColor
    }

    // MARK: - Setup

    private func setupUI() {
        let leftGroup = UIStackView(arrangedSubviews: [globeButton, imageButton])
        leftGroup.axis = .horizontal
        leftGroup.spacing = Constants.leftGroupSpacing
        leftGroup.alignment = .center
        leftGroup.translatesAutoresizingMaskIntoConstraints = false
        leftGroup.backgroundColor = UIColor(singleUseColor: .unifiedToggleInputCardBackground)
        leftGroup.layer.cornerRadius = 20
        leftGroup.clipsToBounds = true

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rightGroup = UIStackView(arrangedSubviews: [modelChipButton, submitButton, stopButton])
        rightGroup.axis = .horizontal
        rightGroup.spacing = Constants.rightGroupSpacing
        rightGroup.alignment = .center
        rightGroup.translatesAutoresizingMaskIntoConstraints = false

        let outerStack = UIStackView(arrangedSubviews: [leftGroup, spacer, rightGroup])
        outerStack.axis = .horizontal
        outerStack.alignment = .center
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)

        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            outerStack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateSubmitButtonState()
    }

    private func makeToolButton(image: DesignSystemImage, accessibilityLabel: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.tintColor = UIColor(designSystemColor: .iconsSecondary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel
        button.addTarget(self, action: action, for: .touchUpInside)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Constants.toolButtonSize),
            button.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),
        ])
        return button
    }

    private func updateSubmitButtonState() {
        submitButton.isEnabled = isSubmitEnabled
        submitButton.backgroundColor = isSubmitEnabled
            ? UIColor(designSystemColor: .accent)
            : UIColor(designSystemColor: .controlsFillPrimary)
        submitButton.tintColor = isSubmitEnabled
            ? .white
            : UIColor(designSystemColor: .iconsSecondary)
    }

    // MARK: - Actions

    private func updateGeneratingVisibility() {
        if isGenerating {
            submitButton.isHidden = true
            stopButton.isHidden = false
        } else {
            stopButton.isHidden = true
            submitButton.isHidden = isSubmitButtonHidden
        }
    }

    @objc private func searchTapped() { onSearchTapped?() }
    @objc private func attachTapped() { onAttachTapped?() }
    @objc private func modelPickerTapped() { onModelPickerTapped?() }
    @objc private func submitTapped() { onSubmitTapped?() }
    @objc private func stopGeneratingTapped() { onStopGeneratingTapped?() }
}
