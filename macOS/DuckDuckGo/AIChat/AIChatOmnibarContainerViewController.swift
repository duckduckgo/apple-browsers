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
        static let maxAttachments: Int = 3
        static let suggestionsBottomPadding: CGFloat = 4
    }

    private let backgroundView = MouseBlockingBackgroundView()
    private let shadowView = ShadowView()
    private let innerBorderView = ColorView(frame: .zero)
    private let containerView = HitTestableContainerView()
    private let submitButton = MouseOverButton()
    private let imageGenButton = AIChatOmnibarToolButton()
    private let imageUploadButton = AIChatOmnibarToolButton()
    private let modelPickerButton = AIChatModelPickerButton()
    private let attachmentsContainerView = AIChatImageAttachmentsContainerView()

    private let attachmentsErrorLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
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
    private var imageGenLeadingToUploadButton: NSLayoutConstraint?
    private var imageGenLeadingToContainer: NSLayoutConstraint?
    private lazy var historyCleaner: HistoryCleaning = HistoryCleaner(
        featureFlagger: NSApp.delegateTyped.featureFlagger,
        privacyConfig: NSApp.delegateTyped.privacyFeatures.contentBlocking.privacyConfigurationManager
    )

    /// Current suggestions height - cached to avoid recalculation
    private(set) var suggestionsHeight: CGFloat = 0

    /// Callback when the suggestions height changes, used for layout updates
    var onSuggestionsHeightChanged: ((CGFloat) -> Void)?

    /// Callback when the passthrough height needs to be recalculated (e.g., when tools visibility changes)
    var onPassthroughHeightNeedsUpdate: (() -> Void)?

    // MARK: - Tab Navigation Callbacks

    /// Called when the image upload button receives a Tab key press. Wire this to advance focus.
    var onImageUploadButtonTabPressed: (() -> Void)?

    /// Called when the model picker button receives a Tab key press. Wire this to advance focus.
    var onModelPickerButtonTabPressed: (() -> Void)?

    var isImageUploadButtonAvailableForFocus: Bool {
        !imageUploadButton.isHidden && imageUploadButton.isEnabled
    }

    var isModelPickerButtonAvailableForFocus: Bool {
        !modelPickerButton.isHidden
    }

    func makeImageUploadButtonFirstResponder() {
        view.window?.makeFirstResponder(imageUploadButton)
    }

    func makeModelPickerButtonFirstResponder() {
        view.window?.makeFirstResponder(modelPickerButton)
    }

    /// Extra height needed beyond text and suggestions for dynamic content like attachments.
    /// This must be added to the container height calculation by the parent.
    var additionalContentHeight: CGFloat {
        if omnibarController.isOmnibarToolsEnabled && !attachmentsContainerView.attachments.isEmpty {
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
        if omnibarController.isOmnibarToolsEnabled {
            // Add tool buttons area: button size + spacing above suggestions
            height += Constants.toolButtonSize + Constants.toolButtonBottomInset

            // Add attachments area when there are attachments
            if !attachmentsContainerView.attachments.isEmpty {
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
        imageGenModeCancellable = omnibarController.$isImageGenerationMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateToolButtonsVisibility(isEnabled: self.omnibarController.isOmnibarToolsEnabled)
            }
    }

    private func updateSubmitButtonState(for text: String) {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasExcess = attachmentsContainerView.hasExcessAttachments
        applySubmitButtonAppearance(enabled: hasText && !hasExcess)
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

    private func updateToolButtonsVisibility(isEnabled: Bool) {
        let isImageGenMode = omnibarController.isImageGenerationMode

        imageGenButton.isHidden = !isEnabled || !omnibarController.isImageGenerationEnabled
        imageUploadButton.isHidden = !isEnabled
        if isEnabled {
            imageUploadButton.isHidden = !isImageGenMode && !omnibarController.selectedModelSupportsImageUpload
            imageUploadButton.isEnabled = !attachmentsContainerView.isFull
            let hasContent = !omnibarController.models.isEmpty || omnibarController.cachedModelShortName != nil
            modelPickerButton.isHidden = isImageGenMode || !hasContent
        } else {
            modelPickerButton.isHidden = true
        }
        attachmentsContainerView.isHidden = !isEnabled
        if !isEnabled {
            attachmentsHeightConstraint?.constant = 0
        }

        updateImageGenLeadingConstraint()

        updateImageGenModeUI(isImageGenMode)

        // Notify that passthrough height needs recalculation since tools area changed
        onPassthroughHeightNeedsUpdate?()
    }

    /// Switches the image gen button's leading constraint between chaining after the upload button
    /// and pinning to the container edge. Deactivates first to avoid conflicts.
    private func updateImageGenLeadingConstraint() {
        let uploadVisible = !imageUploadButton.isHidden
        if uploadVisible {
            imageGenLeadingToContainer?.isActive = false
            imageGenLeadingToUploadButton?.isActive = true
        } else {
            imageGenLeadingToUploadButton?.isActive = false
            imageGenLeadingToContainer?.isActive = true
        }
    }

    private func updateImageGenModeUI(_ isImageGenMode: Bool) {
        // Toggle background color and tooltip on image gen button
        imageGenButton.activeBackgroundColor = isImageGenMode
            ? NSColor(designSystemColor: .accentAltPrimary)
            : nil
        imageGenButton.activePressedBackgroundColor = isImageGenMode
            ? NSColor(designSystemColor: .accentAltSecondary)
            : nil
        imageGenButton.toolTip = isImageGenMode
            ? UserText.aiChatImageGenDeactivateTooltip
            : UserText.aiChatImageGenButtonLabel

        // Hide suggestions in image gen mode or when attachments are present
        let suppress = shouldSuppressSuggestions
        suggestionsView.isHidden = suppress
        // Force height recalculation — collapses to 0 when suppressed, restores when leaving
        suggestionsHeight = -1 // invalidate cache to allow update
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
        imageUploadButton.onTabPressed = { [weak self] in self?.onImageUploadButtonTabPressed?() }
        containerView.addSubview(imageUploadButton)

        imageGenButton.translatesAutoresizingMaskIntoConstraints = false
        imageGenButton.target = self
        imageGenButton.action = #selector(imageGenButtonClicked)
        imageGenButton.image = DesignSystemImages.Glyphs.Size16.image
        imageGenButton.label = UserText.aiChatImageGenButtonLabel
        imageGenButton.toolTip = UserText.aiChatImageGenButtonLabel
        imageGenButton.setAccessibilityLabel(UserText.aiChatImageGenButtonLabel)
        containerView.addSubview(imageGenButton)

        modelPickerButton.translatesAutoresizingMaskIntoConstraints = false
        modelPickerButton.target = self
        modelPickerButton.action = #selector(modelPickerButtonClicked)
        modelPickerButton.modelName = persistedModelShortName
        modelPickerButton.toolTip = UserText.aiChatModelPickerButtonTooltip
        modelPickerButton.setAccessibilityLabel(UserText.aiChatModelPickerButtonTooltip)
        modelPickerButton.onTabPressed = { [weak self] in self?.onModelPickerButtonTabPressed?() }
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

            imageUploadButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.toolButtonLeadingInset),
            imageUploadButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.toolButtonSize),
            imageUploadButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),

            imageGenButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.toolButtonSize),
            imageGenButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),

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
            imageGenButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            imageUploadButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset),
            modelPickerButton.bottomAnchor.constraint(equalTo: suggestionsView.topAnchor, constant: -Constants.toolButtonBottomInset)
        ])

        // Image gen button chains after image upload button, or aligns to container when upload is hidden
        imageGenLeadingToUploadButton = imageGenButton.leadingAnchor.constraint(equalTo: imageUploadButton.trailingAnchor, constant: Constants.toolButtonSpacing)
        imageGenLeadingToContainer = imageGenButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.toolButtonLeadingInset)
        imageGenLeadingToUploadButton?.isActive = true
        imageGenLeadingToContainer?.isActive = false

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

    @objc private func imageGenButtonClicked() {
        omnibarController.toggleImageGenerationMode()
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
            let displayCap = Constants.maxAttachments + 1
            let remaining = displayCap - self.attachmentsContainerView.attachments.count
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
        let displayCap = Constants.maxAttachments + 1
        guard attachmentsContainerView.attachments.count < displayCap else { return false }
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

        // Show error when too many images are attached
        attachmentsErrorLabel.stringValue = UserText.aiChatAttachmentsLimitError
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
            .sink { [weak self] models in
                guard let self else { return }
                // Show or hide the picker depending on whether models are available
                if omnibarController.isOmnibarToolsEnabled {
                    let hasContent = !models.isEmpty || omnibarController.cachedModelShortName != nil
                    modelPickerButton.isHidden = !hasContent
                }
                // Refresh button label once models arrive
                modelPickerButton.modelName = persistedModelShortName
                // Refresh image upload visibility with updated supportsImageUpload
                updateImageUploadVisibility(supportsImageUpload: omnibarController.selectedModelSupportsImageUpload)
            }
    }

    private func buildModelPickerMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if omnibarController.hasActiveSubscription {
            populateSubscribedModelPickerMenu(menu)
        } else {
            populateFreeModelPickerMenu(menu)
        }

        return menu
    }

    /// Free user layout: accessible models first, then "Advanced Models" section with disabled premium models.
    private func populateFreeModelPickerMenu(_ menu: NSMenu) {
        let accessible = omnibarController.models.filter { $0.entityHasAccess }
        let premium = omnibarController.models.filter { !$0.entityHasAccess }

        for model in accessible {
            menu.addItem(menuItem(for: model))
        }

        if !premium.isEmpty {
            menu.addItem(.separator())

            let header = NSMenuItem(title: UserText.aiChatModelPickerAdvancedSectionHeader, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for model in premium {
                menu.addItem(menuItem(for: model))
            }
        }
    }

    /// Subscribed user layout: "Advanced Models" section first, then "Basic Models" section with free-tier models.
    private func populateSubscribedModelPickerMenu(_ menu: NSMenu) {
        let basic = omnibarController.models.filter { $0.accessTier.contains(AIChatUserTier.free.rawValue) }
        let advanced = omnibarController.models.filter { !$0.accessTier.contains(AIChatUserTier.free.rawValue) }

        if !advanced.isEmpty {
            let header = NSMenuItem(title: UserText.aiChatModelPickerAdvancedModelsSectionHeader, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for model in advanced {
                menu.addItem(menuItem(for: model))
            }
        }

        if !basic.isEmpty {
            menu.addItem(.separator())

            let header = NSMenuItem(title: UserText.aiChatModelPickerBasicModelsSectionHeader, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for model in basic {
                menu.addItem(menuItem(for: model))
            }
        }
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
        PixelKit.fire(AIChatPixel.aiChatAddressBarModelSelected, frequency: .dailyAndCount, includeAppVersionParameter: true)
    }

    private func updateImageUploadVisibility(supportsImageUpload: Bool) {
        guard omnibarController.isOmnibarToolsEnabled else { return }

        let showUpload = supportsImageUpload || omnibarController.isImageGenerationMode
        imageUploadButton.isHidden = !showUpload
        attachmentsContainerView.isHidden = !showUpload
        if !showUpload {
            attachmentsHeightConstraint?.constant = 0
        } else {
            updateAttachmentsLayout()
        }

        updateImageGenLeadingConstraint()
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
        imageGenButton.tintColor = toolButtonTintColor
        imageGenButton.hoverBackgroundColor = .buttonMouseOver
        imageGenButton.pressedBackgroundColor = .buttonMouseDown
        imageUploadButton.tintColor = toolButtonTintColor
        imageUploadButton.hoverBackgroundColor = .buttonMouseOver
        imageUploadButton.pressedBackgroundColor = .buttonMouseDown
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
