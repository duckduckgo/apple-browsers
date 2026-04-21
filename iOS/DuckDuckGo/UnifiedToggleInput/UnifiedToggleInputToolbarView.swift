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

import AIChat
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// Horizontal toolbar with leading action buttons, a trailing model or selected-tool chip, and submit controls.
final class UnifiedToggleInputToolbarView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let verticalPadding: CGFloat = 8
        static let horizontalPadding: CGFloat = 8
        static let toolButtonSize: CGFloat = 40
        static let selectedToolIconSize: CGFloat = 24
        static let selectedToolClearButtonSize: CGFloat = 24
        static let leftGroupSpacing: CGFloat = 4
        static let rightGroupSpacing: CGFloat = 8
        static let chipHeight: CGFloat = 40
        static let chipCornerRadius: CGFloat = 20
        static let chipHorizontalPadding: CGFloat = 16
        static let chipSpacing: CGFloat = 4
    }

    // MARK: - Callbacks

    var onAttachTapped: (() -> Void)?
    var onSelectedToolClearTapped: (() -> Void)?
    var onSubmitTapped: (() -> Void)?
    var onVoiceTapped: (() -> Void)?
    var onStopGeneratingTapped: (() -> Void)?

    // MARK: - State

    var isAIVoiceChatActive: Bool = false {
        didSet { updateSubmitButtonAppearance() }
    }

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

    var selectedTool: AIChatRAGTool? {
        didSet { updateChipVisibility() }
    }

    var modelPickerMenu: UIMenu? {
        get { modelChipButton.menu }
        set {
            modelChipButton.menu = newValue
            modelChipButton.showsMenuAsPrimaryAction = (newValue != nil)
        }
    }

    var toolsMenu: UIMenu? {
        get { toolsButton.menu }
        set {
            toolsButton.menu = newValue
            toolsButton.showsMenuAsPrimaryAction = (newValue != nil)
        }
    }

    var isModelChipHidden: Bool {
        get { modelChipExplicitlyHidden }
        set {
            modelChipExplicitlyHidden = newValue
            updateChipVisibility()
        }
    }

    var isToolsButtonHidden: Bool {
        get { toolsButton.isHidden }
        set { toolsButton.isHidden = newValue }
    }

    var isImageButtonHidden: Bool {
        get { imageButton.isHidden }
        set { imageButton.isHidden = newValue }
    }

    var isImageButtonEnabled: Bool {
        get { imageButton.isEnabled }
        set { imageButton.isEnabled = newValue }
    }

    private var modelChipExplicitlyHidden = false

    // MARK: - UI Components

    private lazy var toolsButton: UIButton = makeToolButton(
        image: DesignSystemImages.Glyphs.Size24.options,
        accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel,
        action: nil
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
        config.titleLineBreakMode = .byTruncatingTail
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 0,
            leading: Constants.chipHorizontalPadding,
            bottom: 0,
            trailing: Constants.chipHorizontalPadding
        )
        config.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .daxSubheadRegular()
            return updated
        }
        config.background.strokeColor = UIColor(designSystemColor: .lines)
        config.background.strokeWidth = 1
        config.cornerStyle = .capsule

        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.heightAnchor.constraint(equalToConstant: Constants.chipHeight).isActive = true

        return button
    }()

    private lazy var selectedToolIconView: UIImageView = {
        let imageView = UIImageView(image: DesignSystemImages.Glyphs.Size24.globe)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.tintColor = UIColor(designSystemColor: .textPrimary)
        imageView.contentMode = .scaleAspectFit
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: Constants.selectedToolIconSize),
            imageView.heightAnchor.constraint(equalToConstant: Constants.selectedToolIconSize),
        ])
        return imageView
    }()

    private lazy var selectedToolClearButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setImage(DesignSystemImages.Glyphs.Size16.close, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textPrimary)
        button.accessibilityLabel = UserText.aiChatToolbarClearSelectedToolAccessibilityLabel
        button.addTarget(self, action: #selector(selectedToolClearTapped), for: .primaryActionTriggered)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Constants.selectedToolClearButtonSize),
            button.heightAnchor.constraint(equalToConstant: Constants.selectedToolClearButtonSize),
        ])
        return button
    }()

    private lazy var selectedToolChipView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        view.layer.cornerRadius = Constants.chipCornerRadius
        view.isHidden = true

        let stackView = UIStackView(arrangedSubviews: [selectedToolIconView, selectedToolClearButton])
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Constants.chipSpacing
        view.addSubview(stackView)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: Constants.chipHeight),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.chipHorizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.chipHorizontalPadding),
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        return view
    }()

    private lazy var submitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.arrowUp, for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor(designSystemColor: .accent)
        button.layer.cornerRadius = Constants.toolButtonSize / 2
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
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
        button.accessibilityLabel = UserText.aiChatToolbarStopGeneratingButtonAccessibilityLabel
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
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
}

private extension UnifiedToggleInputToolbarView {

    private func setupUI() {
        let leftGroup = UIStackView(arrangedSubviews: [imageButton, toolsButton, selectedToolChipView])
        leftGroup.axis = .horizontal
        leftGroup.spacing = Constants.leftGroupSpacing
        leftGroup.alignment = .center
        leftGroup.translatesAutoresizingMaskIntoConstraints = false

        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let rightGroup = UIStackView(arrangedSubviews: [modelChipButton, submitButton, stopButton])
        rightGroup.axis = .horizontal
        rightGroup.spacing = Constants.rightGroupSpacing
        rightGroup.alignment = .center
        rightGroup.translatesAutoresizingMaskIntoConstraints = false
        rightGroup.setContentHuggingPriority(.required, for: .horizontal)
        rightGroup.setContentCompressionResistancePriority(.required, for: .horizontal)

        let outerStack = UIStackView(arrangedSubviews: [leftGroup, spacer, rightGroup])
        outerStack.axis = .horizontal
        outerStack.alignment = .center
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(outerStack)

        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            outerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            outerStack.topAnchor.constraint(equalTo: topAnchor, constant: Constants.verticalPadding),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.verticalPadding),
            modelChipButton.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.45)
        ])

        updateChipVisibility()
        updateSubmitButtonState()
    }

    func makeToolButton(image: DesignSystemImage, accessibilityLabel: String, action: Selector?) -> UIButton {
        let button: UIButton
        if #available(iOS 26, *) {
            var configuration = UIButton.Configuration.plain()
            configuration.image = image
            configuration.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
            configuration.contentInsets = .zero
            button = UIButton(configuration: configuration)
        } else {
            let legacyButton = UIButton(type: .system)
            legacyButton.setImage(image, for: .normal)
            legacyButton.tintColor = UIColor(designSystemColor: .textPrimary)
            legacyButton.backgroundColor = .clear
            button = legacyButton
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = accessibilityLabel
        if let action {
            button.addTarget(self, action: action, for: .primaryActionTriggered)
        }
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Constants.toolButtonSize),
            button.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),
        ])
        return button
    }

    private func updateModelChipConfiguration() {
        modelChipButton.configuration?.title = modelName
    }

    private func updateChipVisibility() {
        modelChipButton.isHidden = modelChipExplicitlyHidden
        selectedToolChipView.isHidden = (selectedTool == nil)
        selectedToolChipView.accessibilityLabel = selectedTool == .webSearch ? UserText.aiChatToolbarWebSearchToolTitle : nil
    }

    func updateSubmitButtonState() {
        updateSubmitButtonAppearance()
    }

    func updateSubmitButtonAppearance() {
        let showVoice = isAIVoiceChatActive && !isSubmitEnabled
        let icon = showVoice ? DesignSystemImages.Glyphs.Size24.voice : DesignSystemImages.Glyphs.Size24.arrowUp
        submitButton.setImage(icon, for: .normal)
        submitButton.isEnabled = isSubmitEnabled || showVoice
        submitButton.backgroundColor = (isSubmitEnabled || showVoice)
            ? UIColor(designSystemColor: .accent)
            : UIColor(designSystemColor: .controlsFillPrimary)
        submitButton.tintColor = (isSubmitEnabled || showVoice)
            ? .white
            : UIColor(designSystemColor: .iconsSecondary)
    }

    func updateGeneratingVisibility() {
        if isGenerating {
            submitButton.isHidden = true
            stopButton.isHidden = false
        } else {
            stopButton.isHidden = true
            submitButton.isHidden = isSubmitButtonHidden
        }
    }

    @objc private func attachTapped() { onAttachTapped?() }
    @objc private func selectedToolClearTapped() { onSelectedToolClearTapped?() }
    @objc private func submitTapped() {
        if isAIVoiceChatActive && !isSubmitEnabled {
            onVoiceTapped?()
        } else {
            onSubmitTapped?()
        }
    }
    @objc private func stopGeneratingTapped() { onStopGeneratingTapped?() }
}
