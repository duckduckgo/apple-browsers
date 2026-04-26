//
//  AIChatOmnibarContainerViewController.swift
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

import Cocoa
import QuartzCore
import Combine
import UniformTypeIdentifiers
import DesignResourcesKitIcons
import AIChat
import BrowserServicesKit
import FeatureFlags
import PixelKit

/// A container view that properly handles hit testing when used with MouseBlockingBackgroundView.
/// Since this view is at origin (0,0) in its superview, point coordinates are equivalent in both systems.
private final class HitTestableContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(point) else { return nil }

        // Iterate subviews in reverse order (front to back)
        for subview in subviews.reversed() where !subview.isHidden {
            if subview.frame.contains(point) {
                if let hitView = subview.hitTest(point) {
                    return hitView
                }
            }
        }

        return self
    }
}

final class AIChatOmnibarContainerViewController: NSViewController {

    private enum Constants {
        static let clipMaskBottomOffset: CGFloat = 14
        static let shadowOverlapHeight: CGFloat = 11
        static let submitButtonSize: CGFloat = 28
        static let submitButtonCornerRadius: CGFloat = 14
        static let submitButtonTrailingInset: CGFloat = 13
        static let submitButtonBottomInset: CGFloat = 8
        static let toolButtonSize: CGFloat = 28
        static let toolButtonLeadingInset: CGFloat = 11
        static let toolButtonSpacing: CGFloat = 3
        static let toolButtonBottomInset: CGFloat = 8
        static let modelPickerTrailingSpacing: CGFloat = 4
        static let modelPickerHeight: CGFloat = 28
        static let attachmentsLeadingInset: CGFloat = 13
        static let attachmentsBottomSpacing: CGFloat = 16
        static let attachmentsRowHeight: CGFloat = AIChatImageAttachmentThumbnailView.totalHeight
        static let attachmentsErrorHeight: CGFloat = 18
        static let attachmentsDisplayCap: Int = AIChatImageAttachmentsContainerView.maxAttachments + 1
        static let suggestionsBottomPadding: CGFloat = 4
    }

    private let backgroundView = MouseBlockingBackgroundView()
    private let shadowView = ShadowView()
    private let innerBorderView = ColorView(frame: .zero)
    private let containerView = HitTestableContainerView()
    private let submitButton = MouseOverButton()
    private let imageUploadButton = AIChatOmnibarToolButton()
    private let toolsButton = AIChatOmnibarToolButton()
    private let imageGenActiveButton = AIChatOmnibarToolButton()
    private let webSearchActiveButton = AIChatOmnibarToolButton()
    private let reasoningPickerButton = AIChatOmnibarToolButton()
    private let modelPickerButton = AIChatModelPickerButton()
    private let attachmentsContainerView = AIChatImageAttachmentsContainerView()

    private let attachmentsErrorLabel: NSTextField = {
        let label = NSTextField(labelWithString: UserText.aiChatAttachmentsLimitError)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemRed
        label.isHidden = true
        return label
    }()

    /// Suggestions view - always in hierarchy, height is 0 when no suggestions
    private let suggestionsView = AIChatSuggestionsView()

    /// Tracks ongoing resize tasks by attachment ID. Used to ensure resizes complete before submission.
    private var resizeTasks: [UUID: Task<Void, Never>] = [:]

    /// Constraint for suggestions view height
    private var suggestionsHeightConstraint: NSLayoutConstraint?

    /// Attachments container height constraint - 0 when empty
    private var attachmentsHeightConstraint: NSLayoutConstraint?

    let themeManager: ThemeManaging
    let omnibarController: AIChatOmnibarController
    var themeUpdateCancellable: AnyCancellable?
    private var appearanceCancellable: AnyCancellable?
    private var textChangeCancellable: AnyCancellable?
    private var toolsVisibilityCancellable: AnyCancellable?
    private var modelsCancellable: AnyCancellable?
    private var windowFrameObserver: AnyCancellable?
    private var viewBoundsObserver: AnyCancellable?
    private var imageGenModeCancellable: AnyCancellable?
    private var toolsLeadingToUploadButton: NSLayoutConstraint?
    private var toolsLeadingToContainer: NSLayoutConstraint?
    private lazy var historyCleaner: HistoryCleaning = HistoryCleaner(
        featureFlagger: NSApp.delegateTyped.featureFlagger,
        privacyConfig: NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager,
        nativeStorageHandler: NSApp.delegateTyped.duckAiNativeStorageHandler,
        featureFlagProvider: AIChatFeatureFlagProvider(featureFlagger: NSApp.delegateTyped.featureFlagger)
    )

    /// Current suggestions height - cached to avoid recalculation
    private(set) var suggestionsHeight: CGFloat = 0

    /// Callback when the suggestions height changes, used for layout updates
    var onSuggestionsHeightChanged: ((CGFloat) -> Void)?

    /// Callback when the passthrough height needs to be recalculated (e.g., when tools visibility changes)
    var onPassthroughHeightNeedsUpdate: (() -> Void)?

    // MARK: - Tab Navigation Callbacks

    /// Called when a tool button receives a Tab key press. Wire this to advance focus to the next visible button.
    var onToolButtonTabPressed: (() -> Void)?

    /// Ordered list of focusable tool buttons. Tab cycles through visible/enabled buttons in this
    /// order, then proceeds to the model picker. Reasoning picker is last so focus flows
    /// left-to-right through the left-side tools, then the reasoning chip (which sits visually
    /// adjacent to the model picker), then the model picker itself.
    private var focusableToolButtons: [AIChatOmnibarToolButton] {
        [imageUploadButton, toolsButton, imageGenActiveButton, webSearchActiveButton, reasoningPickerButton]
    }

    var isImageUploadButtonAvailableForFocus: Bool {
        !imageUploadButton.isHidden && imageUploadButton.isEnabled
    }

    var isModelPickerButtonAvailableForFocus: Bool {
        !modelPickerButton.isHidden
    }

    /// Returns the first visible and enabled tool button available for focus.
    func firstAvailableToolButtonForFocus() -> AIChatOmnibarToolButton? {
        focusableToolButtons.first { !$0.isHidden && $0.isEnabled }
    }

    func makeFirstAvailableToolButtonFirstResponder() {
        if let button = firstAvailableToolButtonForFocus() {
            view.window?.makeFirstResponder(button)
        }
    }

    func makeModelPickerButtonFirstResponder() {
        view.window?.makeFirstResponder(modelPickerButton)
    }

    /// Advances focus to the next tool button after the given one, or to model picker, or back to text view.
    private func advanceFocusAfter(_ button: AIChatOmnibarToolButton) {
        let buttons = focusableToolButtons
        guard let index = buttons.firstIndex(of: button) else {
            onToolButtonTabPressed?()
            return
        }
        // Find next visible button after current
        for nextButton in buttons[(index + 1)...] where !nextButton.isHidden && nextButton.isEnabled {
            view.window?.makeFirstResponder(nextButton)
            return
        }
        // No more tool buttons — try model picker, then text view
        if isModelPickerButtonAvailableForFocus {
            makeModelPickerButtonFirstResponder()
        } else {
            onToolButtonTabPressed?()
        }
    }

    /// Extra height needed beyond text and suggestions for dynamic content like attachments.
    /// This must be added to the container height calculation by the parent.
    var additionalContentHeight: CGFloat {
        if (omnibarController.isOmnibarToolsEnabled || !imageUploadButton.isHidden) && !attachmentsContainerView.isHidden && !attachmentsContainerView.attachments.isEmpty {
            var height = Constants.attachmentsRowHeight + Constants.attachmentsBottomSpacing
            if attachmentsContainerView.hasExcessAttachments {
                height += Constants.attachmentsErrorHeight
            }
            return height
        }
        return 0
    }

    /// Calculates the total height that should be passthrough for the text container view.
    /// This includes the suggestions area and the tool buttons area (when enabled).
    var totalPassthroughHeight: CGFloat {
        var height = suggestionsHeight
        if suggestionsHeight > 0 {
            // Add bottom padding when there are suggestions
            height += Constants.suggestionsBottomPadding
        }
        if omnibarController.isOmnibarToolsEnabled || !imageUploadButton.isHidden {
            // Add tool buttons area: button size + spacing above suggestions
            height += Constants.toolButtonSize + Constants.toolButtonBottomInset

            // Add attachments area when there are visible attachments
            if !attachmentsContainerView.isHidden && !attachmentsContainerView.attachments.isEmpty {
                height += Constants.attachmentsRowHeight + Constants.attachmentsBottomSpacing
                if attachmentsContainerView.hasExcessAttachments {
                    height += Constants.attachmentsErrorHeight
                }
            }
        }
        return height
    }

    required init?(coder: NSCoder) {
        fatalError("AIChatOmnibarContainerViewController: Bad initializer")
    }

    required init(themeManager: ThemeManaging, omnibarController: AIChatOmnibarController) {
        self.themeManager = themeManager
        self.omnibarController = omnibarController

        super.init(nibName: nil, bundle: nil)
    }

    override func loadView() {
        view = MouseOverView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSuggestionsView()
        subscribeToThemeChanges()
        subscribeToTextChanges()
        subscribeToToolsVisibilityChanges()
        subscribeToImageGenModeChanges()
        setupAttachmentsProvider()
        subscribeToModelUpdates()
        applyThemeStyle()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyTopClipMask()
        layoutShadowView()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        subscribeToViewAppearanceChanges()
    }

    private func subscribeToViewAppearanceChanges() {
        appearanceCancellable = view.publisher(for: \.effectiveAppearance)
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.applyThemeStyle()
            }
    }

    private func subscribeToTextChanges() {
        textChangeCancellable = omnibarController.$currentText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                self?.updateSubmitButtonState(for: text)
            }
    }

    private func subscribeToToolsVisibilityChanges() {
        toolsVisibilityCancellable = omnibarController.isOmnibarToolsEnabledPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEnabled in
                self?.updateToolButtonsVisibility(isEnabled: isEnabled)
            }
    }

    private func subscribeToImageGenModeChanges() {
        imageGenModeCancellable = omnibarController.$activeToolMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateToolButtonsVisibility(isEnabled: self.omnibarController.isOmnibarToolsEnabled)
                self.updateImageUploadVisibility(supportsImageUpload: self.omnibarController.selectedModelSupportsImageUpload)
            }
    }

    private func updateSubmitButtonState(for text: String) {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canSendImages = omnibarController.isImageGenerationMode || omnibarController.selectedModelSupportsImageUpload
        let hasBlockingExcess = canSendImages && attachmentsContainerView.hasExcessAttachments
        applySubmitButtonAppearance(enabled: hasText && !hasBlockingExcess)
    }

    private func applySubmitButtonAppearance(enabled: Bool) {
        submitButton.isEnabled = enabled

        NSAppearance.withAppAppearance {
            if enabled {
                submitButton.layer?.backgroundColor = NSColor(designSystemColor: .accentPrimary).cgColor
                submitButton.normalTintColor = .white
                submitButton.mouseOverTintColor = NSColor(designSystemColor: .buttonsPrimaryText).withAlphaComponent(0.8)
            } else {
                submitButton.layer?.backgroundColor = NSColor.clear.cgColor
                submitButton.normalTintColor = NSColor.secondaryLabelColor
                submitButton.mouseOverTintColor = NSColor.secondaryLabelColor
            }
        }
    }

    // MARK: - Tool Button Visibility

    private var shouldShowToolsButton: Bool {
        omnibarController.isOmnibarToolsEnabled
            && (omnibarController.isImageGenerationEnabled || omnibarController.isWebSearchEnabled)
    }

    private var shouldShowImageUpload: Bool {
        omnibarController.isImageGenerationMode || omnibarController.selectedModelSupportsImageUpload
    }

    private var shouldShowAttachments: Bool {
        shouldShowImageUpload
    }

    private var shouldShowModelPicker: Bool {
        guard !omnibarController.isImageGenerationMode else { return false }
        let hasContent = !omnibarController.models.isEmpty || omnibarController.cachedModelShortName != nil
        return omnibarController.isOmnibarToolsEnabled && hasContent
    }

    private func updateToolButtonsVisibility(isEnabled: Bool) {
        toolsButton.isHidden = !shouldShowToolsButton
        imageGenActiveButton.isHidden = !shouldShowToolsButton || !omnibarController.isImageGenerationMode
        webSearchActiveButton.isHidden = !shouldShowToolsButton || !omnibarController.isWebSearchMode
        imageUploadButton.isHidden = !shouldShowAttachments || !shouldShowImageUpload
        imageUploadButton.isEnabled = !attachmentsContainerView.isFull
        modelPickerButton.isHidden = !shouldShowModelPicker
        toolsButton.label = omnibarController.activeToolMode != nil ? nil : UserText.aiChatToolsButtonLabel

        attachmentsContainerView.isHidden = !shouldShowAttachments
        if !shouldShowAttachments {
            attachmentsHeightConstraint?.constant = 0
        }

        updateToolsLeadingConstraint()
        updateToolModeUI()
        updateReasoningPickerVisibility()
        onPassthroughHeightNeedsUpdate?()
    }

    /// Switches the tools button's leading constraint between chaining after the upload button
    /// and pinning to the container edge. Deactivates first to avoid conflicts.
    private func updateToolsLeadingConstraint() {
        let uploadVisible = !imageUploadButton.isHidden
        if uploadVisible {
            toolsLeadingToContainer?.isActive = false
            toolsLeadingToUploadButton?.isActive = true
        } else {
            toolsLeadingToUploadButton?.isActive = false
            toolsLeadingToContainer?.isActive = true
        }
    }

    private func updateToolModeUI() {
        let isImageGenMode = omnibarController.isImageGenerationMode
        let isWebSearchMode = omnibarController.isWebSearchMode

        // Active pill styling for image gen
        imageGenActiveButton.activeBackgroundColor = isImageGenMode
            ? NSColor(designSystemColor: .controlsFillPrimary)
            : nil
        imageGenActiveButton.activeHoverBackgroundColor = isImageGenMode
            ? NSColor(designSystemColor: .controlsFillSecondary)
            : nil
        imageGenActiveButton.activePressedBackgroundColor = isImageGenMode
            ? NSColor(designSystemColor: .controlsFillTertiary)
            : nil

        // Active pill styling for web search
        webSearchActiveButton.activeBackgroundColor = isWebSearchMode
            ? NSColor(designSystemColor: .controlsFillPrimary)
            : nil
        webSearchActiveButton.activeHoverBackgroundColor = isWebSearchMode
            ? NSColor(designSystemColor: .controlsFillSecondary)
            : nil
        webSearchActiveButton.activePressedBackgroundColor = isWebSearchMode
            ? NSColor(designSystemColor: .controlsFillTertiary)
            : nil

        // Hide suggestions in image gen mode or when attachments are present
        let suppress = shouldSuppressSuggestions
        suggestionsView.isHidden = suppress
        suggestionsHeight = -1
        updateSuggestionsHeight(suppress ? 0 : lastKnownSuggestionsHeight)
    }

    private func applyTopClipMask() {
        view.wantsLayer = true
        guard view.bounds.height > 10 else {
            view.layer?.mask = nil
            return
        }
        let mask = CAShapeLayer()
        mask.frame = view.bounds
        let visibleRect = CGRect(x: 0, y: 0, width: view.bounds.width, height: view.bounds.height - Constants.clipMaskBottomOffset)
        mask.path = CGPath(rect: visibleRect, transform: nil)
        view.layer?.mask = mask
    }

    private func setupUI() {
        backgroundView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.borderWidth = 1
        backgroundView.borderColor = NSColor.black.withAlphaComponent(0.2)
        view.addSubview(backgroundView)

        innerBorderView.translatesAutoresizingMaskIntoConstraints = false
        innerBorderView.borderWidth = 1
        backgroundView.addSubview(innerBorderView)

        shadowView.shadowColor = .suggestionsShadow
        shadowView.shadowOpacity = 1
        shadowView.shadowOffset = CGSize(width: 0, height: 0)
        shadowView.shadowRadius = 20
        shadowView.shadowSides = [.left, .right, .bottom]

        containerView.translatesAutoresizingMaskIntoConstraints = false
        backgroundView.addSubview(containerView)

        submitButton.translatesAutoresizingMaskIntoConstraints = false
        submitButton.title = ""
        submitButton.bezelStyle = .shadowlessSquare
        submitButton.isBordered = false
        submitButton.wantsLayer = true
        submitButton.target = self
        submitButton.action = #selector(submitButtonClicked)

        submitButton.image = DesignSystemImages.Glyphs.Size12.arrowRight
        submitButton.imagePosition = .imageOnly
        submitButton.toolTip = UserText.aiChatSendButtonTooltip
        containerView.addSubview(submitButton)

        imageUploadButton.translatesAutoresizingMaskIntoConstraints = false
        imageUploadButton.target = self
        imageUploadButton.action = #selector(imageUploadButtonClicked)
        imageUploadButton.image = DesignSystemImages.Glyphs.Size16.attach
        imageUploadButton.toolTip = UserText.aiChatImageUploadButtonTooltip
        imageUploadButton.setAccessibilityLabel(UserText.aiChatImageUploadButtonTooltip)
        imageUploadButton.onTabPressed = { [weak self] in guard let self else { return }; self.advanceFocusAfter(self.imageUploadButton) }
        containerView.addSubview(imageUploadButton)

        toolsButton.translatesAutoresizingMaskIntoConstraints = false
        toolsButton.target = self
        toolsButton.action = #selector(toolsButtonClicked)
        toolsButton.image = DesignSystemImages.Glyphs.Size16.options
        toolsButton.keepIconLeadingAligned = true
        toolsButton.label = UserText.aiChatToolsButtonLabel
        toolsButton.toolTip = UserText.aiChatToolsButtonLabel
        toolsButton.setAccessibilityLabel(UserText.aiChatToolsButtonLabel)
        toolsButton.onTabPressed = { [weak self] in guard let self else { return }; self.advanceFocusAfter(self.toolsButton) }
        containerView.addSubview(toolsButton)

        imageGenActiveButton.translatesAutoresizingMaskIntoConstraints = false
        imageGenActiveButton.target = self
        imageGenActiveButton.action = #selector(imageGenActiveButtonClicked)
        imageGenActiveButton.image = DesignSystemImages.Glyphs.Size16.image
        imageGenActiveButton.label = UserText.aiChatImageGenButtonLabel
        imageGenActiveButton.trailingImage = DesignSystemImages.Glyphs.Size12.closeSmall
        imageGenActiveButton.toolTip = UserText.aiChatImageGenDeactivateTooltip
        imageGenActiveButton.setAccessibilityLabel(UserText.aiChatImageGenDeactivateTooltip)
        imageGenActiveButton.onTabPressed = { [weak self] in guard let self else { return }; self.advanceFocusAfter(self.imageGenActiveButton) }
        imageGenActiveButton.isHidden = true
        containerView.addSubview(imageGenActiveButton)

        webSearchActiveButton.translatesAutoresizingMaskIntoConstraints = false
        webSearchActiveButton.target = self
        webSearchActiveButton.action = #selector(webSearchActiveButtonClicked)
        webSearchActiveButton.image = DesignSystemImages.Glyphs.Size16.globe
        webSearchActiveButton.label = UserText.aiChatWebSearchButtonLabel
        webSearchActiveButton.trailingImage = DesignSystemImages.Glyphs.Size12.closeSmall
        webSearchActiveButton.toolTip = UserText.aiChatWebSearchDeactivateTooltip
        webSearchActiveButton.setAccessibilityLabel(UserText.aiChatWebSearchDeactivateTooltip)
        webSearchActiveButton.onTabPressed = { [weak self] in guard let self else { return }; self.advanceFocusAfter(self.webSearchActiveButton) }
        webSearchActiveButton.isHidden = true
        containerView.addSubview(webSearchActiveButton)

        reasoningPickerButton.translatesAutoresizingMaskIntoConstraints = false
        reasoningPickerButton.target = self
        reasoningPickerButton.action = #selector(reasoningPickerButtonClicked)
        reasoningPickerButton.font = .systemFont(ofSize: 12, weight: .regular)
        reasoningPickerButton.toolTip = UserText.aiChatReasoningEffortPickerButtonTooltip
        reasoningPickerButton.setAccessibilityLabel(UserText.aiChatReasoningEffortPickerButtonTooltip)
        reasoningPickerButton.onTabPressed = { [weak self] in guard let self else { return }; self.advanceFocusAfter(self.reasoningPickerButton) }
        reasoningPickerButton.isHidden = true
        containerView.addSubview(reasoningPickerButton)

        modelPickerButton.translatesAutoresizingMaskIntoConstraints = false
        modelPickerButton.target = self
        modelPickerButton.action = #selector(modelPickerButtonClicked)
        modelPickerButton.modelName = persistedModelShortName
        modelPickerButton.toolTip = UserText.aiChatModelPickerButtonTooltip
        modelPickerButton.setAccessibilityLabel(UserText.aiChatModelPickerButtonTooltip)
        modelPickerButton.onTabPressed = { [weak self] in self?.onToolButtonTabPressed?() }
        containerView.addSubview(modelPickerButton)

        attachmentsContainerView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsContainerView.onAttachmentsChanged = { [weak self] in
            self?.updateAttachmentsLayout()
        }
        attachmentsContainerView.onAttachmentWillRemove = { [weak self] id in
            PixelKit.fire(AIChatPixel.aiChatAddressBarImageRemoved, frequency: .dailyAndCount, includeAppVersionParameter: true)
            // Cancel and remove resize task if still pending
            self?.resizeTasks[id]?.cancel()
            self?.resizeTasks.removeValue(forKey: id)
        }
        containerView.addSubview(attachmentsContainerView)
        containerView.addSubview(attachmentsErrorLabel)

        NSLayoutConstraint.activate([
            backgroundView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            innerBorderView.topAnchor.constraint(equalTo: backgroundView.topAnchor, constant: 1),
            innerBorderView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor, constant: 1),
            innerBorderView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor, constant: -1),
            innerBorderView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor, constant: -1),

            containerView.topAnchor.constraint(equalTo: backgroundView.topAnchor),
            containerView.leadingAnchor.constraint(equalTo: backgroundView.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: backgroundView.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: backgroundView.bottomAnchor),

            submitButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.submitButtonTrailingInset),
            // Bottom constraint is set in setupSuggestionsView() to be above suggestions
            submitButton.widthAnchor.constraint(equalToConstant: Constants.submitButtonSize),
            submitButton.heightAnchor.constraint(equalToConstant: Constants.submitButtonSize),

            modelPickerButton.heightAnchor.constraint(equalToConstant: Constants.modelPickerHeight),

            reasoningPickerButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.toolButtonSize),
            reasoningPickerButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),
            reasoningPickerButton.trailingAnchor.constraint(equalTo: modelPickerButton.leadingAnchor, constant: -Constants.toolButtonSpacing),

            imageUploadButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.toolButtonLeadingInset),
            imageUploadButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.toolButtonSize),
            imageUploadButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),

            toolsButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.toolButtonSize),
            toolsButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),

            imageGenActiveButton.leadingAnchor.constraint(equalTo: toolsButton.trailingAnchor, constant: Constants.toolButtonSpacing),
            imageGenActiveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.toolButtonSize),
            imageGenActiveButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),

            webSearchActiveButton.leadingAnchor.constraint(equalTo: toolsButton.trailingAnchor, constant: Constants.toolButtonSpacing),
            webSearchActiveButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.toolButtonSize),
            webSearchActiveButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),

            attachmentsContainerView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.attachmentsLeadingInset),
            attachmentsContainerView.bottomAnchor.constraint(equalTo: imageUploadButton.topAnchor),

            attachmentsErrorLabel.leadingAnchor.constraint(equalTo: attachmentsContainerView.leadingAnchor),
            attachmentsErrorLabel.bottomAnchor.constraint(equalTo: attachmentsContainerView.topAnchor, constant: -2),
        ])

        // Attachments container height: 0 when empty, expands when attachments are added
        attachmentsHeightConstraint = attachmentsContainerView.heightAnchor.constraint(equalToConstant: 0)
        attachmentsHeightConstraint?.isActive = true

        // Model picker trailing: next to submit button when visible, or near container edge when hidden
        // Submit button is always visible, so model picker always sits to its left
        modelPickerButton.trailingAnchor.constraint(equalTo: submitButton.leadingAnchor, constant: -Constants.modelPickerTrailingSpacing).isActive = true

        applyTheme(theme: themeManager.theme)
    }

    // MARK: - Suggestions Setup

    private func setupSuggestionsView() {
        suggestionsView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(suggestionsView)

        // Height constraint controls visibility - 0 when no suggestions
        let heightConstraint = suggestionsView.heightAnchor.constraint(equalToConstant: 0)
        suggestionsHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            suggestionsView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            suggestionsView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            suggestionsView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -Constants.suggestionsBottomPadding),
            heightConstraint,

            // Submit button sits above suggestions
            submitButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.submitButtonBottomInset),

            // Tool buttons sit above suggestions
            toolsButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            imageGenActiveButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            webSearchActiveButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            imageUploadButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            reasoningPickerButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            modelPickerButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset)
        ])

        // Tools button chains after image upload button, or aligns to container when upload is hidden
        toolsLeadingToUploadButton = toolsButton.leadingAnchor.constraint(equalTo: imageUploadButton.trailingAnchor, constant: Constants.toolButtonSpacing)
        toolsLeadingToContainer = toolsButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.toolButtonLeadingInset)
        toolsLeadingToUploadButton?.isActive = true
        toolsLeadingToContainer?.isActive = false

        // Handle suggestion clicks
        suggestionsView.onSuggestionClicked = { [weak self] suggestion in
            guard let self else { return }
            let pixel: AIChatPixel = suggestion.isPinned ? .aiChatRecentChatSelectedPinnedMouse : .aiChatRecentChatSelectedMouse
            PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
            self.omnibarController.delegate?.aiChatOmnibarController(
                self.omnibarController,
                didSelectSuggestion: suggestion
            )
        }

        // Handle suggestion deletions (gated by feature flag)
        let canRemoveSuggestions = NSApp.delegateTyped.featureFlagger.isFeatureOn(.aiChatRemoveSuggestion)
        suggestionsView.canDeleteSuggestions = canRemoveSuggestions
        if canRemoveSuggestions {
            suggestionsView.onSuggestionDeleted = { [weak self] suggestion in
                guard let self, let window = self.view.window else { return }

                PixelKit.fire(AIChatPixel.aiChatRecentChatDeleteButtonClicked, frequency: .dailyAndCount, includeAppVersionParameter: true)

                let alert = NSAlert()
                alert.messageText = UserText.removeRecentChatConfirmationTitle
                alert.informativeText = String(format: UserText.removeRecentChatConfirmationMessage, suggestion.title)
                alert.addButton(withTitle: UserText.removeRecentChatConfirmationButton, response: .OK)
                alert.buttons.first?.hasDestructiveAction = true
                alert.addButton(withTitle: UserText.cancel, response: .cancel, keyEquivalent: .escape)

                alert.beginSheetModal(for: window) { [weak self] response in
                    guard let self else { return }
                    guard response == .OK else {
                        PixelKit.fire(AIChatPixel.aiChatRecentChatDeleteCancelled, frequency: .dailyAndCount, includeAppVersionParameter: true)
                        return
                    }
                    PixelKit.fire(AIChatPixel.aiChatRecentChatDeleteConfirmed, frequency: .dailyAndCount, includeAppVersionParameter: true)
                    self.omnibarController.suggestionsViewModel.removeSuggestion(suggestion)
                    Task { @MainActor in
                        _ = await self.historyCleaner.deleteAIChat(chatID: suggestion.chatId)
                        self.omnibarController.refreshSuggestions()
                    }
                }
            }
        }

        suggestionsView.onViewAllChatsClicked = { [weak self] in
            self?.omnibarController.viewAllChats()
        }

        // Bind to view model with height change callback
        suggestionsView.bind(to: omnibarController.suggestionsViewModel) { [weak self] newHeight in
            self?.updateSuggestionsHeight(newHeight)
        }
    }

    /// The last known suggestions height before image gen mode suppressed it.
    private var lastKnownSuggestionsHeight: CGFloat = 0

    private var shouldSuppressSuggestions: Bool {
        omnibarController.isImageGenerationMode || !attachmentsContainerView.attachments.isEmpty
    }

    private func updateSuggestionsHeight(_ newHeight: CGFloat) {
        // Track the real height even when suppressed
        if !shouldSuppressSuggestions {
            lastKnownSuggestionsHeight = newHeight
        }

        // Suppress suggestions height when image generation mode is active or attachments present
        let effectiveHeight = shouldSuppressSuggestions ? 0 : newHeight

        // Skip if height hasn't changed
        guard effectiveHeight != suggestionsHeight else { return }

        suggestionsHeight = effectiveHeight
        suggestionsHeightConstraint?.constant = effectiveHeight

        // Notify about height change for container resize
        onSuggestionsHeightChanged?(effectiveHeight)
    }

    /// Starts event monitoring. Call this when the view controller becomes visible.
    func startEventMonitoring() {
        backgroundView.startListening()
        addShadowToWindow()
        observeWindowFrameChanges()
    }

    /// Stops event monitoring. Call this when the view controller is about to be dismissed.
    func cleanup() {
        backgroundView.stopListening()
        shadowView.removeFromSuperview()
        windowFrameObserver?.cancel()
        windowFrameObserver = nil
        viewBoundsObserver?.cancel()
        viewBoundsObserver = nil

        // Clear attachments and cancel pending resize tasks
        clearAttachments()

        // Restore model picker to persisted value
        modelPickerButton.modelName = persistedModelShortName

        omnibarController.cleanup()
    }

    private func addShadowToWindow() {
        guard shadowView.superview == nil else { return }
        view.window?.contentView?.addSubview(shadowView)
        layoutShadowView()
    }

    private func observeWindowFrameChanges() {
        guard let window = view.window else { return }

        windowFrameObserver = window.publisher(for: \.frame)
            .sink { [weak self] _ in
                self?.layoutShadowView()
            }

        viewBoundsObserver = view.publisher(for: \.bounds)
            .sink { [weak self] _ in
                self?.layoutShadowView()
            }
    }

    private func layoutShadowView() {
        guard let superview = shadowView.superview else { return }

        let winFrame = view.convert(view.bounds, to: nil)
        var frame = superview.convert(winFrame, from: nil)

        /// Do not overlap shadow of main address bar
        frame.size.height -= Constants.shadowOverlapHeight

        shadowView.frame = frame
    }

    @objc private func submitButtonClicked() {
        omnibarController.submit()
    }

    @objc private func toolsButtonClicked() {
        let menu = buildToolsMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -5), in: toolsButton)
    }

    @objc private func imageGenActiveButtonClicked() {
        PixelKit.fire(AIChatPixel.aiChatAddressBarImageGenerationDeactivated, frequency: .dailyAndCount, includeAppVersionParameter: true)
        omnibarController.toggleImageGenerationMode()
    }

    @objc private func webSearchActiveButtonClicked() {
        PixelKit.fire(AIChatPixel.aiChatAddressBarWebSearchDeactivated, frequency: .dailyAndCount, includeAppVersionParameter: true)
        omnibarController.toggleWebSearchMode()
    }

    private func buildToolsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if omnibarController.isImageGenerationEnabled {
            let createImageItem = NSMenuItem()
            createImageItem.attributedTitle = toolsMenuItemAttributedTitle(
                title: UserText.aiChatImageGenButtonLabel,
                subtitle: UserText.aiChatImageGenToolSubtitle
            )
            createImageItem.image = DesignSystemImages.Glyphs.Size16.image
            createImageItem.target = self
            createImageItem.action = #selector(toolsMenuCreateImageClicked)
            if omnibarController.isImageGenerationMode {
                createImageItem.state = .on
            }
            menu.addItem(createImageItem)
        }

        if omnibarController.isWebSearchEnabled {
            let webSearchItem = NSMenuItem()
            webSearchItem.attributedTitle = toolsMenuItemAttributedTitle(
                title: UserText.aiChatWebSearchButtonLabel,
                subtitle: UserText.aiChatWebSearchToolSubtitle
            )
            webSearchItem.image = DesignSystemImages.Glyphs.Size16.globe
            webSearchItem.target = self
            webSearchItem.action = #selector(toolsMenuWebSearchClicked)
            if omnibarController.isWebSearchMode {
                webSearchItem.state = .on
            }
            menu.addItem(webSearchItem)
        }

        return menu
    }

    private func toolsMenuItemAttributedTitle(title: String, subtitle: String) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular)
        ]))
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 4)
        ]))
        result.append(NSAttributedString(string: subtitle, attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor
        ]))
        return result
    }

    @objc private func toolsMenuCreateImageClicked() {
        if !omnibarController.isImageGenerationMode {
            PixelKit.fire(AIChatPixel.aiChatAddressBarImageGenerationActivated, frequency: .dailyAndCount, includeAppVersionParameter: true)
        }
        omnibarController.toggleImageGenerationMode()
    }

    @objc private func toolsMenuWebSearchClicked() {
        if !omnibarController.isWebSearchMode {
            PixelKit.fire(AIChatPixel.aiChatAddressBarWebSearchActivated, frequency: .dailyAndCount, includeAppVersionParameter: true)
        }
        omnibarController.toggleWebSearchMode()
    }

    @objc private func imageUploadButtonClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = allowedContentTypes(for: omnibarController.selectedModelImageFormats)

        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            let remaining = Constants.attachmentsDisplayCap - self.attachmentsContainerView.attachments.count
            for url in panel.urls.prefix(max(remaining, 0)) {
                self.addImageAttachment(from: url)
            }
        }
    }

    private func allowedContentTypes(for formats: [String]) -> [UTType] {
        let types = formats.compactMap { UTType(filenameExtension: $0.lowercased()) }
        return types.isEmpty ? [.jpeg, .png, .webP] : types
    }

    /// Attempts to add an image attachment from a drag-and-drop operation.
    /// - Returns: `true` if the image was accepted, `false` if attachments are full.
    func addImageAttachmentFromDrop(_ url: URL) -> Bool {
        guard attachmentsContainerView.attachments.count < Constants.attachmentsDisplayCap else { return false }
        addImageAttachment(from: url)
        return true
    }

    private func addImageAttachment(from url: URL) {
        guard let originalImage = NSImage(contentsOf: url) else { return }

        let placeholderId = UUID()
        let placeholder = AIChatImageAttachment(
            id: placeholderId,
            image: originalImage,
            fileName: url.lastPathComponent,
            fileURL: url,
            skipResize: true
        )
        attachmentsContainerView.addAttachment(placeholder)
        PixelKit.fire(AIChatPixel.aiChatAddressBarImageAttached, frequency: .dailyAndCount, includeAppVersionParameter: true)

        resizeTasks[placeholderId] = makeResizeTask(for: url, placeholderId: placeholderId)
    }

    /// Resizes the image on a background thread and replaces the placeholder when done.
    /// Loads a separate NSImage from disk — NSImage is not thread-safe,
    /// so sharing the same instance across threads would cause a data race.
    private func makeResizeTask(for fileURL: URL, placeholderId: UUID) -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard !Task.isCancelled else { return }

            guard let backgroundImage = NSImage(contentsOf: fileURL) else { return }
            let resized = AIChatImageAttachment(
                id: placeholderId,
                image: backgroundImage,
                fileName: fileURL.lastPathComponent,
                fileURL: fileURL,
                skipResize: false
            )

            guard !Task.isCancelled else { return }

            await MainActor.run { [weak self] in
                self?.attachmentsContainerView.replaceAttachment(id: placeholderId, with: resized)
                self?.resizeTasks.removeValue(forKey: placeholderId)
            }
        }
    }

    private func setupAttachmentsProvider() {
        omnibarController.attachmentsProvider = { [weak self] in
            self?.attachmentsContainerView.attachments ?? []
        }
        omnibarController.onAttachmentsClearRequested = { [weak self] in
            self?.clearAttachments()
        }
        omnibarController.waitForAttachmentsReady = { [weak self] in
            guard let self else { return }
            let tasks = Array(self.resizeTasks.values)
            for task in tasks {
                await task.value
            }
        }
    }

    private func clearAttachments() {
        // Cancel any pending resize tasks
        for task in resizeTasks.values {
            task.cancel()
        }
        resizeTasks.removeAll()

        attachmentsContainerView.removeAllAttachments()
        updateAttachmentsLayout()
    }

    private func updateAttachmentsLayout() {
        let hasAttachments = !attachmentsContainerView.attachments.isEmpty
        let hasExcess = attachmentsContainerView.hasExcessAttachments
        let isFull = attachmentsContainerView.isFull

        omnibarController.hasImageAttachments = hasAttachments

        attachmentsHeightConstraint?.constant = hasAttachments
            ? Constants.attachmentsRowHeight + Constants.attachmentsBottomSpacing
            : 0

        attachmentsErrorLabel.isHidden = !hasExcess

        // Disable the upload button when at max attachments and update tooltip
        if omnibarController.isOmnibarToolsEnabled {
            imageUploadButton.isEnabled = !isFull
            imageUploadButton.toolTip = isFull
                ? UserText.aiChatAttachmentsLimitError
                : UserText.aiChatImageUploadButtonTooltip
        }

        // Disable submit when too many images
        updateSubmitButtonState(for: omnibarController.currentText)

        // Suppress or restore suggestions based on attachments presence
        let suppress = shouldSuppressSuggestions
        suggestionsView.isHidden = suppress
        suggestionsHeight = -1
        updateSuggestionsHeight(suppress ? 0 : lastKnownSuggestionsHeight)

        onPassthroughHeightNeedsUpdate?()
    }

    @objc private func modelPickerButtonClicked() {
        let menu = buildModelPickerMenu()
        // Align menu's trailing edge with button's trailing edge, with a small gap below
        let x = modelPickerButton.bounds.width - menu.size.width
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: -5), in: modelPickerButton)
    }

    private var selectedModelId: String {
        omnibarController.persistedModelId
    }

    /// Short display name for the currently persisted model.
    /// Falls back to the cached short name when models haven't been fetched yet.
    private var persistedModelShortName: String {
        omnibarController.models.first(where: { $0.id == omnibarController.persistedModelId })?.shortName
            ?? omnibarController.cachedModelShortName
            ?? ""
    }

    private func subscribeToModelUpdates() {
        modelsCancellable = omnibarController.$models
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                modelPickerButton.isHidden = !shouldShowModelPicker
                // Refresh button label once models arrive
                modelPickerButton.modelName = persistedModelShortName
                // Refresh image upload visibility with updated supportsImageUpload
                updateImageUploadVisibility(supportsImageUpload: omnibarController.selectedModelSupportsImageUpload)
                updateReasoningPickerVisibility()
            }
    }

    private func buildModelPickerMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let sections = AIChatModelSectionBuilder.buildSections(
            models: omnibarController.models,
            hasActiveSubscription: omnibarController.hasActiveSubscription,
            advancedSectionHeader: UserText.aiChatModelPickerAdvancedSectionHeader,
            basicSectionHeader: UserText.aiChatModelPickerBasicModelsSectionHeader
        )

        for (index, section) in sections.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            if let header = section.header {
                let headerItem = NSMenuItem(title: header, action: nil, keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
            }
            for model in section.items {
                menu.addItem(menuItem(for: model))
            }
        }

        return menu
    }

    private func menuItem(for model: AIChatModel) -> NSMenuItem {
        let item = NSMenuItem(title: model.name, action: #selector(modelSelected(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = model
        item.image = model.menuIcon
        item.isEnabled = model.entityHasAccess
        if model.id == selectedModelId {
            item.state = .on
        }
        return item
    }

    @objc private func modelSelected(_ sender: NSMenuItem) {
        guard let model = sender.representedObject as? AIChatModel else { return }
        omnibarController.updateSelectedModel(model.id)
        modelPickerButton.modelName = model.shortName
        updateImageUploadVisibility(supportsImageUpload: model.supportsImageUpload)
        updateReasoningPickerVisibility()
        PixelKit.fire(AIChatPixel.aiChatAddressBarModelSelected, frequency: .dailyAndCount, includeAppVersionParameter: true)
    }

    // MARK: - Reasoning Picker

    @objc private func reasoningPickerButtonClicked() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let currentEffort = omnibarController.displayedReasoningEffort
        for effort in omnibarController.pickerReasoningEfforts {
            let item = NSMenuItem(title: "", action: #selector(reasoningEffortSelected(_:)), keyEquivalent: "")
            item.attributedTitle = toolsMenuItemAttributedTitle(title: effort.title, subtitle: effort.subtitle)
            item.target = self
            item.representedObject = effort
            item.image = effort.icon
            if effort == currentEffort {
                item.state = .on
            }
            menu.addItem(item)
        }

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -5), in: reasoningPickerButton)
    }

    @objc private func reasoningEffortSelected(_ sender: NSMenuItem) {
        guard let effort = sender.representedObject as? AIChatReasoningEffort else { return }
        omnibarController.updateSelectedReasoningEffort(effort)
        updateReasoningPickerAppearance(effort)
        PixelKit.fire(AIChatPixel.aiChatAddressBarReasoningEffortSelected, frequency: .dailyAndCount, includeAppVersionParameter: true)
    }

    private func updateReasoningPickerVisibility() {
        guard omnibarController.isReasoningEffortEnabled else {
            reasoningPickerButton.isHidden = true
            return
        }
        let efforts = omnibarController.pickerReasoningEfforts
        reasoningPickerButton.isHidden = efforts.count <= 1 || omnibarController.isImageGenerationMode
        guard let fallback = efforts.first else { return }
        // Display only. The controller owns stale-effort cleanup (on model switch and on models
        // refetch) so we never write to persistence from here — a saved value that isn't supported
        // by the current model is ignored for display and not attached to submissions.
        // `displayedReasoningEffort` maps stored bucket-equivalents (e.g. `.medium` → `.high`)
        // to the picker's representation so the chip label/icon stay in sync with what's
        // actually submitted.
        updateReasoningPickerAppearance(omnibarController.displayedReasoningEffort ?? fallback)
    }

    private func updateReasoningPickerAppearance(_ effort: AIChatReasoningEffort) {
        reasoningPickerButton.label = effort.title
        reasoningPickerButton.image = effort.icon
    }

    private func updateImageUploadVisibility(supportsImageUpload: Bool) {
        guard omnibarController.isOmnibarToolsEnabled else { return }

        let showUpload = supportsImageUpload || omnibarController.isImageGenerationMode
        imageUploadButton.isHidden = !showUpload
        attachmentsContainerView.isHidden = !showUpload
        if !showUpload {
            attachmentsHeightConstraint?.constant = 0
            attachmentsErrorLabel.isHidden = true
        } else {
            updateAttachmentsLayout()
        }

        updateSubmitButtonState(for: omnibarController.currentText)
        updateToolsLeadingConstraint()
        onPassthroughHeightNeedsUpdate?()
    }

    private func applyTheme(theme: ThemeStyleProviding) {
        let barStyleProvider = theme.addressBarStyleProvider
        let colorsProvider = theme.colorsProvider

        backgroundView.backgroundColor = colorsProvider.activeAddressBarBackgroundColor
        backgroundView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadius
        backgroundView.layer?.masksToBounds = false  // Don't clip subviews - important for hit testing

        if let borderColor = NSColor(named: "AddressBarBorderColor") {
            backgroundView.borderColor = borderColor
        }

        submitButton.layer?.cornerRadius = Constants.submitButtonCornerRadius
        // Colour is set dynamically by applySubmitButtonAppearance based on enabled state
        applySubmitButtonAppearance(enabled: !omnibarController.currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let toolButtonTintColor = NSColor(designSystemColor: .textPrimary)
        toolsButton.tintColor = toolButtonTintColor
        toolsButton.hoverBackgroundColor = .buttonMouseOver
        toolsButton.pressedBackgroundColor = .buttonMouseDown
        imageGenActiveButton.tintColor = toolButtonTintColor
        imageGenActiveButton.hoverBackgroundColor = .buttonMouseOver
        imageGenActiveButton.pressedBackgroundColor = .buttonMouseDown
        webSearchActiveButton.tintColor = toolButtonTintColor
        webSearchActiveButton.hoverBackgroundColor = .buttonMouseOver
        webSearchActiveButton.pressedBackgroundColor = .buttonMouseDown
        imageUploadButton.tintColor = toolButtonTintColor
        imageUploadButton.hoverBackgroundColor = .buttonMouseOver
        imageUploadButton.pressedBackgroundColor = .buttonMouseDown
        reasoningPickerButton.tintColor = toolButtonTintColor
        reasoningPickerButton.hoverBackgroundColor = .buttonMouseOver
        reasoningPickerButton.pressedBackgroundColor = .buttonMouseDown
        modelPickerButton.tintColor = toolButtonTintColor

        innerBorderView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadius
        innerBorderView.borderColor = NSColor(named: "AddressBarInnerBorderColor")
        innerBorderView.backgroundColor = NSColor.clear
        innerBorderView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadius

        shadowView.shadowRadius = barStyleProvider.suggestionShadowRadius
        shadowView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadius

        NSAppearance.withAppAppearance {
            imageUploadButton.hoverBackgroundColor = .buttonMouseOver
            imageUploadButton.pressedBackgroundColor = .buttonMouseDown
            modelPickerButton.hoverBackgroundColor = .buttonMouseOver
            modelPickerButton.pressedBackgroundColor = .buttonMouseDown
        }
    }
}

extension AIChatOmnibarContainerViewController: ThemeUpdateListening {

    func applyThemeStyle(theme: ThemeStyleProviding) {
        applyTheme(theme: theme)
    }
}
