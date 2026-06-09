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
        static let topPadding: CGFloat = 4
        static let bottomPadding: CGFloat = 8
        static let horizontalPadding: CGFloat = 8
        static let toolButtonSize: CGFloat = 40
        static let selectedToolIconSize: CGFloat = 24
        static let selectedToolClearButtonSize: CGFloat = 24
        static let leftGroupSpacing: CGFloat = 4
        static let rightGroupSpacing: CGFloat = 4
        static let chipHeight: CGFloat = 40
        static let chipCornerRadius: CGFloat = 20
        static let chipHorizontalPadding: CGFloat = 16
        static let chipSpacing: CGFloat = 4
    }

    // MARK: - Callbacks

    var onSelectedToolClearTapped: (() -> Void)?
    var onSubmitTapped: (() -> Void)?
    var onVoiceTapped: (() -> Void)?
    var onStopGeneratingTapped: (() -> Void)?
    var onReturnKeyTapped: (() -> Void)?

    // MARK: - State

    var isAIVoiceChatActive: Bool = false {
        didSet { updateSubmitButtonAppearance() }
    }

    var isSubmitEnabled: Bool = false {
        didSet { updateSubmitButtonState() }
    }

    var isSubmitBlockedByRecoveryCard: Bool = false {
        didSet { updateSubmitButtonAppearance() }
    }

    var usesNewPromptSubmitStyle: Bool = false {
        didSet { updateSubmitButtonAppearance() }
    }

    private var isFireTab: Bool = false
    private var preservesSubmitStyleDuringDismissal = false
    private var isImageButtonAvailable = true

    func refreshFireMode(fireMode: Bool) {
        isFireTab = fireMode
        overrideUserInterfaceStyle = fireMode ? .dark : .unspecified
        updateSubmitButtonAppearance()
    }

    var isGenerating: Bool = false {
        didSet {
            updateGeneratingVisibility()
            updateToolbarControlsEnabledState()
        }
    }

    func prepareForToolbarVisibilityChange(showToolbar: Bool) {
        if showToolbar {
            preservesSubmitStyleDuringDismissal = false
        } else {
            preservesSubmitStyleDuringDismissal = preservesSubmitStyleDuringDismissal || usesNewPromptSubmitStyle
        }
        updateSubmitButtonAppearance()
    }

    func finalizeToolbarShown() {
        guard preservesSubmitStyleDuringDismissal else { return }
        preservesSubmitStyleDuringDismissal = false
        updateSubmitButtonAppearance()
    }

    var modelName: String = "4o-mini" {
        didSet { updateModelChipConfiguration() }
    }

    var selectedTool: AIChatRAGTool? {
        didSet { updateChipVisibility() }
    }

    var selectedReasoningMode: AIChatReasoningMode? {
        didSet { updateReasoningButtonAppearance() }
    }

    var modelPickerMenu: UIMenu? {
        get { modelChipButton.menu }
        set {
            modelChipButton.menu = newValue
            modelChipButton.showsMenuAsPrimaryAction = (newValue != nil)
        }
    }

    /// Programmatically opens the model chip's pull-down menu. Returns `true` when the OS
    /// exposes an API to trigger it (iOS 17.4+, where `performPrimaryAction()` lands), `false`
    /// otherwise.
    @discardableResult
    func presentModelPickerMenu() -> Bool {
        if #available(iOS 17.4, *) {
            modelChipButton.performPrimaryAction()
            return true
        }
        return false
    }

    var reasoningPickerMenu: UIMenu? {
        get { reasoningButton.menu }
        set {
            reasoningButton.menu = newValue
            reasoningButton.showsMenuAsPrimaryAction = (newValue != nil)
        }
    }

    var toolsMenu: UIMenu? {
        get { toolsButton.menu }
        set {
            toolsButton.menu = newValue
            toolsButton.showsMenuAsPrimaryAction = (newValue != nil)
        }
    }

    var attachmentMenu: UIMenu? {
        get { imageButton.menu }
        set {
            imageButton.menu = newValue
            imageButton.showsMenuAsPrimaryAction = (newValue != nil)
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

    var isReasoningButtonHidden: Bool {
        get { reasoningButton.isHidden }
        set { reasoningButton.isHidden = newValue }
    }

    var isImageButtonHidden: Bool {
        get { imageButton.isHidden }
        set { imageButton.isHidden = newValue }
    }

    var isImageButtonEnabled: Bool {
        get { imageButton.isEnabled }
        set {
            isImageButtonAvailable = newValue
            updateToolbarControlsEnabledState()
        }
    }

    var isReturnKeyHidden: Bool {
        get { returnKeyButton.isHidden }
        set { returnKeyButton.isHidden = newValue }
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
        action: nil
    )

    private lazy var reasoningButton: UIButton = {
        let button = makeToolButton(
            image: DesignSystemImages.Glyphs.Size24.lightning,
            accessibilityLabel: UserText.aiChatToolbarReasoningButtonAccessibilityLabel,
            action: nil
        )
        button.isHidden = true
        button.accessibilityIdentifier = "AIChat.Toolbar.Button.Reasoning"
        if #available(iOS 16.0, *) {
            button.preferredMenuElementOrder = .fixed
        }
        return button
    }()

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
        button.accessibilityIdentifier = "AIChat.Toolbar.Button.ModelChip"
        if #available(iOS 16.0, *) {
            button.preferredMenuElementOrder = .fixed
        }
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.heightAnchor.constraint(equalToConstant: Constants.chipHeight).isActive = true

        return button
    }()

    private lazy var selectedToolIconView: UIImageView = {
        let imageView = UIImageView()
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

    private lazy var returnKeyButton: CircularButton = {
        let button = CircularButton()
        button.isShadowHidden = true
        button.setImage(DesignSystemImages.Glyphs.Size24.enter, for: .normal)
        button.applyReturnKeyStyle()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isHidden = true
        // Priorities collapse(required) > width > hugging so the button is 40pt when shown yet
        // collapses to zero when hidden, instead of keeping a frame that overlaps submit.
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        button.accessibilityLabel = UserText.aiChatToolbarReturnKeyButtonAccessibilityLabel
        button.addTarget(self, action: #selector(returnKeyTapped), for: .touchUpInside)
        let width = button.widthAnchor.constraint(equalToConstant: Constants.toolButtonSize)
        width.priority = .required - 1
        NSLayoutConstraint.activate([
            width,
            button.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),
        ])
        return button
    }()

    private lazy var submitButton: CircularButton = {
        let button = CircularButton()
        button.isShadowHidden = true
        button.setImage(DesignSystemImages.Glyphs.Size24.arrowUp, for: .normal)
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

    private lazy var stopButton: CircularButton = {
        let button = CircularButton()
        button.isShadowHidden = true
        button.setImage(DesignSystemImages.Glyphs.Size24.stopSquare, for: .normal)
        button.setColors(
            foreground: UIColor(designSystemColor: .textPrimary),
            background: UIColor(singleUseColor: .unifiedToggleInputStopButtonBackground)
        )
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

        let rightGroup = UIStackView(arrangedSubviews: [reasoningButton, modelChipButton, returnKeyButton, submitButton, stopButton])
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
            outerStack.topAnchor.constraint(equalTo: topAnchor, constant: Constants.topPadding),
            outerStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Constants.bottomPadding),
            modelChipButton.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, multiplier: 0.45)
        ])

        updateChipVisibility()
        updateSubmitButtonState()
        updateToolbarControlsEnabledState()
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

    private func updateReasoningButtonAppearance() {
        guard let mode = selectedReasoningMode else {
            reasoningButton.setImage(nil, for: .normal)
            return
        }

        reasoningButton.setImage(mode.unifiedToggleInputButtonImage, for: .normal)
        reasoningButton.tintColor = mode.unifiedToggleInputButtonTintColor
    }

    private func updateChipVisibility() {
        modelChipButton.isHidden = modelChipExplicitlyHidden
        selectedToolChipView.isHidden = (selectedTool == nil)
        selectedToolIconView.image = selectedTool?.toolbarChipIcon
        selectedToolChipView.accessibilityLabel = selectedTool?.toolbarChipAccessibilityLabel
    }

    func updateSubmitButtonState() {
        updateSubmitButtonAppearance()
    }

    func updateSubmitButtonAppearance() {
        let showVoice = isAIVoiceChatActive && !isSubmitEnabled
        let usesReturnKeyStyle = usesNewPromptSubmitStyle || preservesSubmitStyleDuringDismissal
        let icon: UIImage? = {
            if showVoice {
                return DesignSystemImages.Glyphs.Size24.voice
            } else if usesReturnKeyStyle {
                return DesignSystemImages.Glyphs.Size24.arrowRight
            } else {
                return DesignSystemImages.Glyphs.Size24.arrowUp
            }
        }()
        submitButton.setImage(icon, for: .normal)
        let submitAllowed = isSubmitEnabled && !isSubmitBlockedByRecoveryCard
        let isActive = submitAllowed || showVoice
        submitButton.isEnabled = isActive
        if showVoice {
            submitButton.applyAIVoiceChatStyle()
        } else if usesReturnKeyStyle {
            submitButton.applyReturnKeyStyle()
        } else {
            submitButton.applySubmitStyle(isActive: isActive, isFireTab: isFireTab, activeForeground: .white)
        }
    }

    func updateGeneratingVisibility() {
        if isGenerating {
            submitButton.isHidden = true
            stopButton.isHidden = false
        } else {
            stopButton.isHidden = true
            submitButton.isHidden = false
        }
    }

    func updateToolbarControlsEnabledState() {
        let controlsAreEnabled = !isGenerating
        imageButton.isEnabled = controlsAreEnabled && isImageButtonAvailable
        toolsButton.isEnabled = controlsAreEnabled
        reasoningButton.isEnabled = controlsAreEnabled
        modelChipButton.isEnabled = controlsAreEnabled
        selectedToolClearButton.isEnabled = controlsAreEnabled
    }

    @objc private func selectedToolClearTapped() { onSelectedToolClearTapped?() }
    @objc private func returnKeyTapped() { onReturnKeyTapped?() }
    @objc private func submitTapped() {
        if isAIVoiceChatActive && !isSubmitEnabled {
            onVoiceTapped?()
        } else {
            onSubmitTapped?()
        }
    }
    @objc private func stopGeneratingTapped() { onStopGeneratingTapped?() }
}

private extension AIChatRAGTool {

    var toolbarChipIcon: DesignSystemImage? {
        switch self {
        case .webSearch:
            return DesignSystemImages.Glyphs.Size24.globe
        case .imageGeneration:
            return DesignSystemImages.Glyphs.Size24.images
        case .newsSearch, .videosSearch, .localSearch, .relatedSearchTerms, .weatherForecast:
            // Not surfaced in the unified-input tools menu — defensive fallback only.
            return nil
        }
    }

    var toolbarChipAccessibilityLabel: String? {
        switch self {
        case .webSearch:
            return UserText.aiChatToolbarWebSearchToolTitle
        case .imageGeneration:
            return UserText.aiChatToolbarImageGenerationToolTitle
        case .newsSearch, .videosSearch, .localSearch, .relatedSearchTerms, .weatherForecast:
            // Not surfaced in the unified-input tools menu — defensive fallback only.
            return nil
        }
    }
}
