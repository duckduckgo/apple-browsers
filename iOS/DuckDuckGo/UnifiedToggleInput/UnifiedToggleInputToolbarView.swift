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
        static let bottomPadding: CGFloat = 4
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
        static let minimumGroupGap: CGFloat = 8
    }

    // MARK: - Callbacks

    var onSelectedToolClearTapped: (() -> Void)?
    var onSubmitTapped: (() -> Void)?
    var onVoiceTapped: (() -> Void)?
    var onStopGeneratingTapped: (() -> Void)?
    var onReturnKeyTapped: (() -> Void)?
    var onModelPickerShown: (() -> Void)?
    var onReasoningPickerShown: (() -> Void)?

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

    /// A spent allowance blocks the voice button too: it opens a chat the allowance can't pay for.
    var isInputBlockedByUsageLimit: Bool = false {
        didSet {
            guard oldValue != isInputBlockedByUsageLimit else { return }
            updateSubmitButtonAppearance()
            updateToolbarControlsEnabledState()
        }
    }

    var usesNewPromptSubmitStyle: Bool = false {
        didSet { updateSubmitButtonAppearance() }
    }

    /// Swaps the arrow for the label the Terms of Service disclaimer names ("Ask" or "Create") while it shows.
    var termsOfServiceSendButton: DuckAiTermsOfServiceSendButton? {
        didSet {
            guard oldValue != termsOfServiceSendButton else { return }
            updateSubmitButtonAppearance()
        }
    }

    /// The terms are unaccepted, so the submit button may read "Ask" or "Create" at any time. The row
    /// reserves that width even before anything is typed, so typing never changes the layout.
    var reservesTermsOfServiceSendButton: Bool = false {
        didSet {
            guard oldValue != reservesTermsOfServiceSendButton else { return }
            setNeedsLayout()
        }
    }

    private var isFireTab: Bool = false
    private var preservesSubmitStyleDuringDismissal = false
    private var preservedTermsOfServiceSendButton: DuckAiTermsOfServiceSendButton?
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
            preservedTermsOfServiceSendButton = nil
        } else {
            preservesSubmitStyleDuringDismissal = preservesSubmitStyleDuringDismissal || usesNewPromptSubmitStyle
            preservedTermsOfServiceSendButton = preservedTermsOfServiceSendButton ?? termsOfServiceSendButton
        }
        updateSubmitButtonAppearance()
    }

    func finalizeToolbarShown() {
        guard preservesSubmitStyleDuringDismissal || preservedTermsOfServiceSendButton != nil else { return }
        preservesSubmitStyleDuringDismissal = false
        preservedTermsOfServiceSendButton = nil
        updateSubmitButtonAppearance()
    }

    var modelName: String = "4o-mini" {
        didSet {
            updateModelChipConfiguration()
            guard oldValue != modelName else { return }
            fullModelChipWidthCache = nil
            setNeedsLayout()
        }
    }

    /// The selected model's provider icon, which the pill shows alone when the row is too narrow for its name.
    var modelIcon: UIImage? {
        didSet { updateModelChipConfiguration() }
    }

    /// How far the row has shrunk its controls to fit.
    private(set) var compactLevel: UTIToolbarCompactLevel = .full

    var isModelChipMenuIndicatorHidden: Bool = false {
        didSet {
            guard oldValue != isModelChipMenuIndicatorHidden else { return }
            updateModelChipConfiguration()
            modelChipButton.isUserInteractionEnabled = !isModelChipMenuIndicatorHidden
            fullModelChipWidthCache = nil
            setNeedsLayout()
        }
    }

    var selectedTool: AIChatRAGTool? {
        didSet {
            updateChipVisibility()
            setNeedsLayout()
        }
    }

    var selectedReasoningMode: AIChatReasoningMode? {
        didSet { updateReasoningButtonAppearance() }
    }

    private var storedModelPickerMenu: UIMenu?

    var modelPickerMenu: UIMenu? {
        get { storedModelPickerMenu }
        set {
            storedModelPickerMenu = newValue
            updateModelPickerPrimaryAction()
        }
    }

    /// Programmatically opens the model chip's pull-down menu. Returns `true` when the OS
    /// exposes an API to trigger it (iOS 17.4+, where `performPrimaryAction()` lands), `false`
    /// otherwise.
    @discardableResult
    func presentModelPickerMenu() -> Bool {
        guard modelPickerMenu != nil else { return false }

        if #available(iOS 17.4, *) {
            modelChipButton.performPrimaryAction()
            return true
        }
        return false
    }
    
    @discardableResult
    func presentReasoningPickerMenu() -> Bool {
        guard reasoningPickerMenu != nil else { return false }

        if #available(iOS 17.4, *) {
            reasoningButton.performPrimaryAction()
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
            selectedToolMenuButton.menu = newValue
            selectedToolMenuButton.showsMenuAsPrimaryAction = (newValue != nil)
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
            setNeedsLayout()
        }
    }

    var isToolsButtonHidden: Bool {
        get { toolsButtonExplicitlyHidden }
        set {
            toolsButtonExplicitlyHidden = newValue
            updateChipVisibility()
            setNeedsLayout()
        }
    }

    var isReasoningButtonHidden: Bool {
        get { reasoningButton.isHidden }
        set {
            reasoningButton.isHidden = newValue
            setNeedsLayout()
        }
    }

    var isImageButtonHidden: Bool {
        get { imageButton.isHidden }
        set {
            imageButton.isHidden = newValue
            setNeedsLayout()
        }
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
        set {
            returnKeyButton.isHidden = newValue
            setNeedsLayout()
        }
    }

    var isEditing: Bool = false {
        didSet {
            guard oldValue != isEditing else { return }
            leftControlsGroup.isHidden = isEditing
            secondaryTrailingGroup.isHidden = isEditing
            updateSubmitButtonAppearance()
        }
    }

    private var modelChipExplicitlyHidden = false
    private var toolsButtonExplicitlyHidden = false
    private var fullModelChipWidthCache: CGFloat?

    // MARK: - UI Components

    private lazy var toolsButton: UIButton = makeToolButton(
        image: DesignSystemImages.Glyphs.Size24.options,
        accessibilityLabel: UserText.aiChatToolbarToolsButtonAccessibilityLabel,
        action: nil
    )

    private(set) lazy var imageButton: UIButton = {
        let button = makeToolButton(
            image: DesignSystemImages.Glyphs.Size24.attach,
            accessibilityLabel: UserText.aiChatToolbarAttachButtonAccessibilityLabel,
            action: nil
        )
        if #available(iOS 16.0, *) {
            button.preferredMenuElementOrder = .fixed
        }
        return button
    }()

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
        button.addTarget(self, action: #selector(reasoningPickerShown), for: .touchDown)
        return button
    }()

    private lazy var modelChipButton: UIButton = {
        let config = Self.modelChipConfiguration(title: modelName, showsMenuIndicator: !isModelChipMenuIndicatorHidden)
        let button = UIButton(configuration: config)
        button.accessibilityIdentifier = "AIChat.Toolbar.Button.ModelChip"
        if #available(iOS 16.0, *) {
            button.preferredMenuElementOrder = .fixed
        }
        button.addTarget(self, action: #selector(modelPickerShown), for: .touchDown)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.heightAnchor.constraint(equalToConstant: Constants.chipHeight).isActive = true

        return button
    }()

    /// Collapsed to its provider icon, the pill is a square the size of the other buttons.
    private lazy var modelChipIconWidthConstraint: NSLayoutConstraint = {
        let constraint = modelChipButton.widthAnchor.constraint(equalToConstant: Constants.toolButtonSize)
        constraint.priority = .required - 1
        return constraint
    }()

    /// Never on screen: measures the pill with its name while it shows only its icon.
    private lazy var modelChipSizingButton = UIButton(configuration: .plain())

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

        view.addSubview(selectedToolMenuButton)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: Constants.chipHeight),
            stackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Constants.chipHorizontalPadding),
            stackView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Constants.chipHorizontalPadding),
            stackView.topAnchor.constraint(equalTo: view.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            selectedToolMenuButton.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectedToolMenuButton.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            selectedToolMenuButton.topAnchor.constraint(equalTo: view.topAnchor),
            selectedToolMenuButton.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        return view
    }()

    /// Covers the chip while it stands in for the tools button, so tapping it opens the tools menu.
    private lazy var selectedToolMenuButton: UIButton = {
        let button = UIButton(type: .custom)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.accessibilityLabel = UserText.aiChatToolbarToolsButtonAccessibilityLabel
        button.accessibilityIdentifier = "AIChat.Toolbar.Button.SelectedToolMenu"
        button.isHidden = true
        return button
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
        button.accessibilityIdentifier = "AIChat.Toolbar.Button.Submit"
        button.titleLabel?.font = AIChatSubmitButtonTitle.font
        button.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        button.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize).isActive = true
        return button
    }()

    private lazy var submitButtonWidthConstraint: NSLayoutConstraint = {
        let constraint = submitButton.widthAnchor.constraint(equalToConstant: Constants.toolButtonSize)
        constraint.isActive = true
        return constraint
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

    private lazy var leftControlsGroup: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [imageButton, toolsButton, selectedToolChipView])
        stack.axis = .horizontal
        stack.spacing = Constants.leftGroupSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    private lazy var secondaryTrailingGroup: UIStackView = {
        let stack = UIStackView(arrangedSubviews: [reasoningButton, modelChipButton])
        stack.axis = .horizontal
        stack.spacing = Constants.rightGroupSpacing
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Fitting the row

    /// The row as it stands, with each control at its full look whatever level is applied now.
    var rowFit: RowFit {
        RowFit(showsAttachButton: !imageButton.isHidden,
               showsToolsButton: !toolsButtonExplicitlyHidden,
               showsModeChip: selectedTool != nil,
               showsReasoningButton: !reasoningButton.isHidden,
               modelChipWidth: modelChipExplicitlyHidden ? nil : fullModelChipWidth,
               showsReturnKey: !returnKeyButton.isHidden,
               submitButtonWidth: reservedSubmitButtonWidth)
    }

    override func layoutSubviews() {
        // Editing hides every control that shrinks.
        if isEditing {
            applyCompactLevel(.full)
        } else if bounds.width > 0 {
            applyCompactLevel(rowFit.level(forToolbarWidth: bounds.width))
        }
        super.layoutSubviews()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.preferredContentSizeCategory != previousTraitCollection?.preferredContentSizeCategory else { return }
        fullModelChipWidthCache = nil
        setNeedsLayout()
    }
}

// MARK: - Compact levels

/// How far the toolbar row shrinks its controls to fit, in the order they collapse.
enum UTIToolbarCompactLevel: Int, CaseIterable, Comparable {
    case full
    /// The model pill shows only the selected model's provider icon.
    case modelIcon
    /// The active mode's chip stands in for the tools button: it loses its ✕ and opens the tools menu.
    case mergedTools

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension UnifiedToggleInputToolbarView {

    /// Picks the first compact level at which the controls on screen fit, so the row only collapses when it has to.
    struct RowFit {
        var showsAttachButton = true
        var showsToolsButton = true
        var showsModeChip = false
        var showsReasoningButton = true
        /// The pill showing its name, or nil while it is hidden.
        var modelChipWidth: CGFloat?
        var showsReturnKey = false
        var submitButtonWidth = Constants.toolButtonSize

        func level(forToolbarWidth width: CGFloat) -> UTIToolbarCompactLevel {
            UTIToolbarCompactLevel.allCases.first { minimumToolbarWidth(at: $0) <= width } ?? .mergedTools
        }

        /// The narrowest toolbar that holds the row at `level`.
        func minimumToolbarWidth(at level: UTIToolbarCompactLevel) -> CGFloat {
            let button = Constants.toolButtonSize
            let mergesTools = level >= .mergedTools && showsModeChip
            var leadingWidths: [CGFloat] = showsAttachButton ? [button] : []
            if showsToolsButton && !mergesTools { leadingWidths.append(button) }
            if showsModeChip { leadingWidths.append(mergesTools ? Self.mergedToolChipWidth : Self.toolChipWidth) }
            var pickerWidths: [CGFloat] = showsReasoningButton ? [button] : []
            if let modelChipWidth { pickerWidths.append(level >= .modelIcon ? button : modelChipWidth) }
            let pickers = Self.stackWidth(pickerWidths, spacing: Constants.rightGroupSpacing)
            let trailingWidths = [pickers] + (showsReturnKey ? [button] : []) + [submitButtonWidth]
            return 2 * Constants.horizontalPadding
                + Self.stackWidth(leadingWidths, spacing: Constants.leftGroupSpacing)
                + Constants.minimumGroupGap
                + Self.stackWidth(trailingWidths, spacing: Constants.rightGroupSpacing)
        }

        static let toolChipWidth = 2 * Constants.chipHorizontalPadding + Constants.selectedToolIconSize
            + Constants.chipSpacing + Constants.selectedToolClearButtonSize
        static let mergedToolChipWidth = 2 * Constants.chipHorizontalPadding + Constants.selectedToolIconSize

        private static func stackWidth(_ widths: [CGFloat], spacing: CGFloat) -> CGFloat {
            widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0))
        }
    }
}

private extension UnifiedToggleInputToolbarView {

    private func setupUI() {
        let spacer = UIView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let rightGroup = UIStackView(arrangedSubviews: [secondaryTrailingGroup, returnKeyButton, submitButton, stopButton])
        rightGroup.axis = .horizontal
        rightGroup.spacing = Constants.rightGroupSpacing
        rightGroup.alignment = .center
        rightGroup.translatesAutoresizingMaskIntoConstraints = false
        rightGroup.setContentHuggingPriority(.required, for: .horizontal)
        rightGroup.setContentCompressionResistancePriority(.required, for: .horizontal)

        let outerStack = UIStackView(arrangedSubviews: [leftControlsGroup, spacer, rightGroup])
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

    static let modelChipMenuIndicatorImage = UIImage(systemName: "chevron.down")?.withConfiguration(
        UIImage.SymbolConfiguration(pointSize: 10, weight: .medium)
    )

    static let modelChipContentInsets = NSDirectionalEdgeInsets(
        top: 0,
        leading: Constants.chipHorizontalPadding,
        bottom: 0,
        trailing: Constants.chipHorizontalPadding
    )

    static func modelChipConfiguration(title: String, showsMenuIndicator: Bool) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = showsMenuIndicator ? modelChipMenuIndicatorImage : nil
        config.imagePlacement = .trailing
        config.imagePadding = Constants.chipSpacing
        config.titleLineBreakMode = .byTruncatingTail
        config.contentInsets = modelChipContentInsets
        config.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var updated = attributes
            updated.font = .daxSubheadRegular()
            return updated
        }
        config.background.strokeColor = UIColor(designSystemColor: .lines)
        config.background.strokeWidth = 1
        config.cornerStyle = .capsule
        return config
    }

    private func updateModelChipConfiguration() {
        let showsProviderIcon = compactLevel >= .modelIcon
        guard var config = modelChipButton.configuration else { return }
        config.title = showsProviderIcon ? nil : modelName
        if showsProviderIcon {
            config.image = modelIcon ?? DesignSystemImages.Glyphs.Size16.aiModelOSS
        } else {
            config.image = isModelChipMenuIndicatorHidden ? nil : Self.modelChipMenuIndicatorImage
        }
        config.imagePadding = showsProviderIcon ? 0 : Constants.chipSpacing
        config.contentInsets = showsProviderIcon ? .zero : Self.modelChipContentInsets
        modelChipButton.configuration = config
        modelChipButton.accessibilityLabel = showsProviderIcon ? modelName : nil
        modelChipIconWidthConstraint.isActive = showsProviderIcon
    }

    private func applyCompactLevel(_ level: UTIToolbarCompactLevel) {
        guard level != compactLevel else { return }
        compactLevel = level
        updateModelChipConfiguration()
        updateChipVisibility()
    }

    /// The pill showing its name, measured even while it shows only its icon.
    private var fullModelChipWidth: CGFloat {
        if let fullModelChipWidthCache { return fullModelChipWidthCache }
        modelChipSizingButton.configuration = Self.modelChipConfiguration(title: modelName,
                                                                         showsMenuIndicator: !isModelChipMenuIndicatorHidden)
        let width = ceil(modelChipSizingButton.intrinsicContentSize.width)
        fullModelChipWidthCache = width
        return width
    }

    /// Counts the "Ask" or "Create" label while the terms are unaccepted, even before anything is typed,
    /// so the first keystroke never collapses the row.
    private var reservedSubmitButtonWidth: CGFloat {
        let pendingLabel = reservesTermsOfServiceSendButton ? DuckAiTermsOfServiceSendButton(selectedTool: selectedTool) : nil
        guard let label = preservedTermsOfServiceSendButton ?? termsOfServiceSendButton ?? pendingLabel else {
            return Constants.toolButtonSize
        }
        return AIChatSubmitButtonTitle.buttonWidth(for: label.title, minimumWidth: Constants.toolButtonSize)
    }

    private func updateModelPickerPrimaryAction() {
        modelChipButton.menu = storedModelPickerMenu
        modelChipButton.showsMenuAsPrimaryAction = modelChipButton.menu != nil
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
        let mergesTools = compactLevel >= .mergedTools && selectedTool != nil
        modelChipButton.isHidden = modelChipExplicitlyHidden
        toolsButton.isHidden = toolsButtonExplicitlyHidden || mergesTools
        selectedToolChipView.isHidden = (selectedTool == nil)
        selectedToolClearButton.isHidden = mergesTools
        selectedToolMenuButton.isHidden = !mergesTools
        selectedToolIconView.image = selectedTool?.toolbarChipIcon
        selectedToolChipView.accessibilityLabel = selectedTool?.toolbarChipAccessibilityLabel
        selectedToolMenuButton.accessibilityValue = selectedTool?.toolbarChipAccessibilityLabel
    }

    func updateSubmitButtonState() {
        updateSubmitButtonAppearance()
    }

    /// The "Ask" or "Create" label replaces the voice button too, disabled until the user types.
    private var showsVoiceButton: Bool {
        isAIVoiceChatActive && !isSubmitEnabled && !isEditing
            && (preservedTermsOfServiceSendButton ?? termsOfServiceSendButton) == nil
    }

    func updateSubmitButtonAppearance() {
        let showVoice = showsVoiceButton
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
        // Kept through the dismissal: the submit that starts it also clears the tool the label names.
        let labelTitle = showVoice ? nil : (preservedTermsOfServiceSendButton ?? termsOfServiceSendButton)?.title
        submitButton.setImage(labelTitle == nil ? icon : nil, for: .normal)
        submitButton.setTitle(labelTitle, for: .normal)
        submitButton.accessibilityLabel = labelTitle ?? UserText.aiChatToolbarSubmitButtonAccessibilityLabel
        submitButtonWidthConstraint.constant = labelTitle.map {
            AIChatSubmitButtonTitle.buttonWidth(for: $0, minimumWidth: Constants.toolButtonSize)
        } ?? Constants.toolButtonSize
        let submitAllowed = isSubmitEnabled && !isSubmitBlockedByRecoveryCard
        let isActive = (submitAllowed || showVoice) && !isInputBlockedByUsageLimit
        submitButton.isEnabled = isActive
        // The blocked button and a disabled "Ask" take the inactive submit fill: the voice and
        // return-key styles have no disabled state of their own.
        if isInputBlockedByUsageLimit || (labelTitle != nil && !isActive) {
            submitButton.applySubmitStyle(isActive: false, isFireTab: isFireTab, activeForeground: .white)
        } else if labelTitle != nil {
            // An enabled "Ask" is the disclaimer's call to action, so it keeps the primary fill in every style.
            submitButton.applyPrimaryButtonStyle()
        } else if showVoice {
            submitButton.applyAIVoiceChatStyle()
        } else if usesReturnKeyStyle {
            submitButton.applyReturnKeyStyle()
        } else {
            submitButton.applySubmitStyle(isActive: isActive, isFireTab: isFireTab, activeForeground: .white)
        }
        // The labels the row reserves come and go with the terms state, not with what the button shows.
        setNeedsLayout()
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
        let controlsAreEnabled = !isGenerating && !isInputBlockedByUsageLimit
        imageButton.isEnabled = controlsAreEnabled && isImageButtonAvailable
        toolsButton.isEnabled = controlsAreEnabled
        reasoningButton.isEnabled = controlsAreEnabled
        modelChipButton.isEnabled = controlsAreEnabled
        selectedToolClearButton.isEnabled = controlsAreEnabled
        selectedToolMenuButton.isEnabled = controlsAreEnabled
    }

    @objc private func selectedToolClearTapped() { onSelectedToolClearTapped?() }
    @objc private func returnKeyTapped() { onReturnKeyTapped?() }
    @objc private func modelPickerShown() {
        guard modelPickerMenu != nil else { return }
        onModelPickerShown?()
    }
    @objc private func reasoningPickerShown() {
        guard reasoningPickerMenu != nil else { return }
        onReasoningPickerShown?()
    }
    @objc private func submitTapped() {
        if showsVoiceButton {
            onVoiceTapped?()
        } else {
            onSubmitTapped?()
        }
    }
    @objc private func stopGeneratingTapped() { onStopGeneratingTapped?() }
}
