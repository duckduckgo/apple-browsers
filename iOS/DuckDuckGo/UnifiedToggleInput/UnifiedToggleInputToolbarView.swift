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

/// Horizontal toolbar with AI tool buttons: image, [spacer], model picker chip, submit/stop.
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

    var onAttachTapped: (() -> Void)?
    var onSubmitTapped: (() -> Void)?
    var onStopGeneratingTapped: (() -> Void)?

    // MARK: - State

    var isSubmitEnabled: Bool = false {
        didSet { updateSubmitButtonState() }
    }

    var isSubmitButtonHidden: Bool = false {
        didSet { submitButton.isHidden = isSubmitButtonHidden }
    }

    var isImageButtonHidden: Bool = false {
        didSet { imageButton.isHidden = isImageButtonHidden }
    }

    var isStopMode: Bool = false {
        didSet {
            guard isStopMode != oldValue else { return }
            submitButton.isHidden = isStopMode || isSubmitButtonHidden
            stopButton.isHidden = !isStopMode
        }
    }

    var modelName: String = "" {
        didSet { modelChipLabel.text = modelName }
    }

    func setModelMenu(_ menu: UIMenu) {
        modelChipButton.menu = menu
    }

    // MARK: - UI Components

    private lazy var imageButton: UIButton = makeToolButton(
        image: DesignSystemImages.Glyphs.Size16.image,
        accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel,
        action: #selector(attachTapped)
    )

    private lazy var modelChipButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.showsMenuAsPrimaryAction = true

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
        button.setImage(DesignSystemImages.Glyphs.Size24.arrowRight, for: .normal)
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
        button.setImage(UIImage(systemName: "stop.fill"), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(singleUseColor: .aiChatStopGenerating)
        button.layer.cornerRadius = Constants.toolButtonSize / 2
        button.clipsToBounds = true
        button.isHidden = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = UserText.aiChatToolbarStopGeneratingButtonAccessibilityLabel
        button.addTarget(self, action: #selector(stopGeneratingTapped), for: .touchUpInside)
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
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let rightGroup = UIStackView(arrangedSubviews: [modelChipButton, submitButton, stopButton])
        rightGroup.axis = .horizontal
        rightGroup.spacing = Constants.rightGroupSpacing
        rightGroup.alignment = .center
        rightGroup.translatesAutoresizingMaskIntoConstraints = false

        let outerStack = UIStackView(arrangedSubviews: [imageButton, spacer, rightGroup])
        outerStack.axis = .horizontal
        outerStack.alignment = .center
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)

        NSLayoutConstraint.activate([
            outerStack.topAnchor.constraint(equalTo: topAnchor, constant: Constants.verticalPadding),
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.verticalPadding),
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

    @objc private func attachTapped() { onAttachTapped?() }
    @objc private func submitTapped() { onSubmitTapped?() }
    @objc private func stopGeneratingTapped() { onStopGeneratingTapped?() }
}
