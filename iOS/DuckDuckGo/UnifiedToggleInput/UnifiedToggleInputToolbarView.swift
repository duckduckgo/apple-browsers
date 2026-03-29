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

/// Horizontal toolbar with AI tool buttons: image, [spacer], model picker chip, submit.
final class UnifiedToggleInputToolbarView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let verticalPadding: CGFloat = 8
        static let horizontalPadding: CGFloat = 8
        static let toolButtonSize: CGFloat = 40
        static let rightGroupSpacing: CGFloat = 8
        static let chipHeight: CGFloat = 32
        static let chipCornerRadius: CGFloat = 16
        static let chipHorizontalPadding: CGFloat = 12
        static let chipSpacing: CGFloat = 4
        static let chipFontSize: CGFloat = 13
    }

    // MARK: - Callbacks

    var onCustomizeResponsesTapped: (() -> Void)?
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
        didSet { updateModelChipConfiguration() }
    }

    var modelPickerMenu: UIMenu? {
        get { modelChipButton.menu }
        set {
            modelChipButton.menu = newValue
            modelChipButton.showsMenuAsPrimaryAction = (newValue != nil)
        }
    }

    var isModelChipHidden: Bool {
        get { modelChipButton.isHidden }
        set { modelChipButton.isHidden = newValue }
    }

    var isImageButtonHidden: Bool {
        get { imageButton.isHidden }
        set { imageButton.isHidden = newValue }
    }

    var isCustomizeResponsesButtonHidden: Bool {
        get { customizeResponsesButton.isHidden }
        set { customizeResponsesButton.isHidden = newValue }
    }

    // MARK: - UI Components

    private lazy var customizeResponsesButton: UIButton = makeToolButton(
        image: DesignSystemImages.Glyphs.Size24.options,
        accessibilityLabel: UserText.aiChatToolbarCustomizeResponsesButtonAccessibilityLabel,
        action: #selector(customizeResponsesTapped)
    )

    private(set) lazy var imageButton: UIButton = makeToolButton(
        image: DesignSystemImages.Glyphs.Size24.attach,
        accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel,
        action: #selector(attachTapped)
    )

    private lazy var modelChipButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = modelName
        config.image = UIImage(systemName: "chevron.down")?.withConfiguration(
            UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
        )
        config.imagePlacement = .trailing
        config.imagePadding = Constants.chipSpacing
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: Constants.chipHorizontalPadding,
            bottom: 0,
            trailing: Constants.chipHorizontalPadding
        )
        config.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .systemFont(ofSize: Constants.chipFontSize, weight: .regular)
            return updated
        }
        config.background.strokeColor = UIColor(designSystemColor: .lines)
        config.background.strokeWidth = 1
        config.cornerStyle = .capsule

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.heightAnchor.constraint(equalToConstant: Constants.chipHeight).isActive = true

        return button
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

    // MARK: - Setup

    private func setupUI() {
        let leftGroup = UIStackView(arrangedSubviews: [customizeResponsesButton, imageButton])
        leftGroup.axis = .horizontal
        leftGroup.spacing = 0
        leftGroup.alignment = .center
        leftGroup.translatesAutoresizingMaskIntoConstraints = false

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

    private func updateModelChipConfiguration() {
        modelChipButton.configuration?.title = modelName
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

    @objc private func customizeResponsesTapped() { onCustomizeResponsesTapped?() }
    @objc private func attachTapped() { onAttachTapped?() }
    @objc private func modelPickerTapped() { onModelPickerTapped?() }
    @objc private func submitTapped() { onSubmitTapped?() }
    @objc private func stopGeneratingTapped() { onStopGeneratingTapped?() }
}
