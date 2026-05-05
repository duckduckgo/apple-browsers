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
import DesignResourcesKit
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
    private let submitButton = AIChatSubmitButton()
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
    /// When true, the attachments view is being reinstalled from the current tab's shared state (on tab switch).
    /// Used to suppress the `onAttachmentsChanged` → `persistAttachmentsToActiveTab` writeback during that window.
    private var isRestoringAttachmentsFromSharedState = false
    /// True while `cleanup()` is tearing down the panel. The clear-attachments call inside cleanup must not
    /// persist an empty list back to shared state — on a tab-switch dismissal, cleanup runs before the controller's
    /// `$selectedTabViewModel` sink has swapped `sharedTextState` to the incoming tab, so any persist at this point
    /// would zero out the *outgoing* tab's attachments.
    private var isCleaningUp = false

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
    /// KVO on the submit button's hover/press state — drives the layer fill through the
    /// accent / accent-alt three-state palette. Direct-layer fill (rather than the
    /// `MouseOverButton.backgroundColor` sub-layer) keeps the icon visible.
    private var submitButtonMouseOverObservation: NSKeyValueObservation?
    private var submitButtonMouseDownObservation: NSKeyValueObservation?
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

    /// Advances focus to the next tool button after the given one, or to model picker, then to the
    /// voice-mode submit button (when active), and finally back to the text view.
    private func advanceFocusAfter(_ button: AIChatOmnibarToolButton) {
        let buttons = focusableToolButtons
        guard let index = buttons.firstIndex(of: button) else {
            advanceFocusToVoiceSubmitOrText()
            return
        }
        // Find next visible button after current
        for nextButton in buttons[(index + 1)...] where !nextButton.isHidden && nextButton.isEnabled {
            view.window?.makeFirstResponder(nextButton)
            return
        }
        // No more tool buttons — try model picker, then voice-mode submit button, then text view
        if isModelPickerButtonAvailableForFocus {
            makeModelPickerButtonFirstResponder()
        } else {
            advanceFocusToVoiceSubmitOrText()
        }
    }

    /// Used as the final hop in the tab cycle. The voice-mode submit button is the only state in
    /// which the submit button participates in keyboard navigation — submit mode skips it because
    /// Enter on the textarea already handles submission.
    private func advanceFocusToVoiceSubmitOrText() {
        if submitButtonMode == .voice && submitButton.isEnabled {
            view.window?.makeFirstResponder(submitButton)
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
        observeSubmitButtonHoverState()
        applyThemeStyle()
    }

    /// Observe `MouseOverButton.isMouseOver` / `isMouseDown` so the submit button's fill
    /// animates through `accent{,Alt}{Primary,Secondary,Tertiary}` on hover/press without
    /// using the sub-layer-based `backgroundColor` property (which would obscure the icon).
    private func observeSubmitButtonHoverState() {
        submitButtonMouseOverObservation = submitButton.observe(\.isMouseOver, options: [.new]) { [weak self] _, _ in
            self?.applySubmitButtonFill()
        }
        submitButtonMouseDownObservation = submitButton.observe(\.isMouseDown, options: [.new]) { [weak self] _, _ in
            self?.applySubmitButtonFill()
        }
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
                // Re-evaluate the submit button so voice mode is suppressed/restored when
                // image-generation toggles (voice mode is hidden while image-gen is active).
                self.updateSubmitButtonState(for: self.omnibarController.currentText)
            }
    }

    /// What the submit button does on click. Driven by whether the input has text — empty
    /// triggers a voice-chat tab open, otherwise the existing submit flow runs.
    private enum SubmitButtonMode {
        case submit
        case voice
    }

    private var submitButtonMode: SubmitButtonMode = .submit

    private func updateSubmitButtonState(for text: String) {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let canSendImages = omnibarController.isImageGenerationMode || omnibarController.selectedModelSupportsImageUpload
        let hasBlockingExcess = canSendImages && attachmentsContainerView.hasExcessAttachments

        // Voice-chat mode only kicks in when the input is empty, the feature flag is on, and we
        // aren't in image-generation mode (where the button must keep its image-flow semantics).
        // Otherwise the button keeps its original arrow/disabled-when-empty behavior.
        if !hasText && omnibarController.isVoiceChatAccessEnabled && !omnibarController.isImageGenerationMode {
            submitButtonMode = .voice
            submitButton.image = DesignSystemImages.Glyphs.Size16.voice
            submitButton.toolTip = UserText.aiChatVoiceChatButtonTooltip
            submitButton.setAccessibilityLabel(UserText.aiChatVoiceChatButtonTooltip)
            // Voice has no Enter-on-empty shortcut, so the button must be tab-reachable.
            submitButton.refusesFirstResponder = false
            applySubmitButtonAppearance(enabled: true)
        } else {
            submitButtonMode = .submit
            submitButton.image = DesignSystemImages.Glyphs.Size12.arrowRight
            submitButton.toolTip = UserText.aiChatSendButtonTooltip
            submitButton.setAccessibilityLabel(UserText.aiChatSendButtonTooltip)
            // Enter on the textarea handles submit; skip the button in tab order.
            submitButton.refusesFirstResponder = true
            applySubmitButtonAppearance(enabled: hasText && !hasBlockingExcess)
        }
    }

    private func applySubmitButtonAppearance(enabled: Bool) {
        submitButton.isEnabled = enabled
        // Tints. Both modes keep the icon constant across hover/press; only the fill animates,
        // so `mouseOverTintColor` / `mouseDownTintColor` stay nil.
        NSAppearance.withAppAppearance {
            if enabled {
                if submitButtonMode == .voice {
                    submitButton.normalTintColor = NSColor(designSystemColor: .accentAltContentPrimary)
                } else {
                    submitButton.normalTintColor = NSColor(designSystemColor: .accentContentPrimary)
                }
            } else {
                submitButton.normalTintColor = NSColor.secondaryLabelColor
            }
            submitButton.mouseOverTintColor = nil
            submitButton.mouseDownTintColor = nil
        }
        // Fill. Driven via the view's main `layer.backgroundColor` directly so it renders BEHIND
        // the NSButton image content. We deliberately do NOT use `MouseOverButton`'s
        // `backgroundColor` property — that property drives a sub-layer added on top of the view's
        // main layer, and CALayer sub-layers always render above the parent layer's contents,
        // which would obscure the icon. The hover/press transitions are handled by KVO on
        // `isMouseOver` / `isMouseDown` (see `observeSubmitButtonHoverState`).
        applySubmitButtonFill()
    }

    /// Sets `submitButton.layer.backgroundColor` to the appropriate state-aware color. Called
    /// from `applySubmitButtonAppearance(enabled:)` and from the KVO observers on the hover/press
    /// dynamic properties. Disabled state and "submit mode while empty" both render no fill.
    private func applySubmitButtonFill() {
        let designSystemColor: DesignSystemColor?
        if !submitButton.isEnabled {
            designSystemColor = nil
        } else if submitButtonMode == .voice {
            if submitButton.isMouseDown {
                designSystemColor = .accentAltTertiary
            } else if submitButton.isMouseOver {
                designSystemColor = .accentAltSecondary
            } else {
                designSystemColor = .accentAltPrimary
            }
        } else {
            if submitButton.isMouseDown {
                designSystemColor = .accentTertiary
            } else if submitButton.isMouseOver {
                designSystemColor = .accentSecondary
            } else {
                designSystemColor = .accentPrimary
            }
        }
        NSAppearance.withAppAppearance {
            submitButton.layer?.backgroundColor = designSystemColor.map { NSColor(designSystemColor: $0).cgColor } ?? NSColor.clear.cgColor
        }
    }

    // MARK: - Tool Button Visibility

    private var shouldShowToolsButton: Bool {
        omnibarController.isOmnibarToolsEnabled && (isImageGenerationItemVisible || isWebSearchItemVisible)
    }

    private var isImageGenerationItemVisible: Bool {
        omnibarController.isImageGenerationEnabled
    }

    private var isWebSearchItemVisible: Bool {
        omnibarController.isWebSearchEnabled && omnibarController.selectedModelSupportsWebSearch
    }

    private var shouldShowWebSearchChip: Bool {
        shouldShowToolsButton && omnibarController.isWebSearchMode && omnibarController.selectedModelSupportsWebSearch
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
        webSearchActiveButton.isHidden = !shouldShowWebSearchChip
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
        // The `MouseOverButton`-managed hover/press sub-layer reads `cornerRadius` from this property
        // when rendering its background — needed so the voice-chat fill renders rounded.
        submitButton.cornerRadius = Constants.submitButtonCornerRadius
        submitButton.target = self
        submitButton.action = #selector(submitButtonClicked)
        // Tab from the (voice-mode) submit button hands focus back to the textarea — same callback
        // the model picker uses, so the loop closes consistently regardless of which button is last.
        submitButton.onTabPressed = { [weak self] in self?.onToolButtonTabPressed?() }

        // Conservative initial state — arrow icon. `updateSubmitButtonState(for:)` fires
        // immediately on subscribe and swaps to voice mode if the flag is on and input is empty.
        submitButton.image = DesignSystemImages.Glyphs.Size12.arrowRight
        submitButton.imagePosition = .imageOnly
        submitButton.toolTip = UserText.aiChatSendButtonTooltip
        submitButton.setAccessibilityLabel(UserText.aiChatSendButtonTooltip)
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
        // Tab from the model picker advances to the voice-mode submit button (when active), or
        // falls back to the textarea if voice mode is off.
        modelPickerButton.onTabPressed = { [weak self] in self?.advanceFocusToVoiceSubmitOrText() }
        containerView.addSubview(modelPickerButton)

        attachmentsContainerView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsContainerView.onAttachmentsChanged = { [weak self] in
            guard let self else { return }
            self.updateAttachmentsLayout()
            /// Skip the persist write during restore (tab switch reinstall — would echo back the list we just read)
            /// and during cleanup (panel teardown — at that moment the controller's `sharedTextState` may still be
            /// pointing at the outgoing tab, and persisting an empty list would wipe that tab's saved attachments).
            if !self.isRestoringAttachmentsFromSharedState && !self.isCleaningUp {
                self.omnibarController.persistAttachmentsToActiveTab(self.attachmentsContainerView.attachments)
            }
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

    /// Whether suggestions are collapsed due to the address bar being unfocused while in duck.ai mode.
    private var isSuggestionsCollapsedByUnfocus: Bool = false

    private var shouldSuppressSuggestions: Bool {
        omnibarController.isImageGenerationMode || !attachmentsContainerView.attachments.isEmpty || isSuggestionsCollapsedByUnfocus
    }

    /// Collapses/expands the suggestions row without affecting tools, submit button, or model picker.
    /// Used to reflect unfocused duck.ai mode, where the panel stays on screen but suggestions are hidden.
    func setSuggestionsCollapsedByUnfocus(_ collapsed: Bool) {
        guard isSuggestionsCollapsedByUnfocus != collapsed else { return }
        isSuggestionsCollapsedByUnfocus = collapsed
        suggestionsView.isHidden = shouldSuppressSuggestions
        suggestionsHeight = -1
        updateSuggestionsHeight(shouldSuppressSuggestions ? 0 : lastKnownSuggestionsHeight)
        onPassthroughHeightNeedsUpdate?()
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

    /// Shows or hides the drop shadow that extends below the panel. The panel itself stays visible.
    /// Used to mirror the address-bar shadow behaviour: on focus the shadow is drawn, on unfocus it's removed.
    func setShadowVisible(_ visible: Bool) {
        if visible {
            addShadowToWindow()
        } else {
            shadowView.removeFromSuperview()
        }
    }

    /// Stops event monitoring. Call this when the view controller is about to be dismissed.
    func cleanup() {
        isCleaningUp = true
        defer { isCleaningUp = false }
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

        // Reset cached height state so the next open doesn't reuse stale values from the previous session.
        // Without this, switching tabs after suggestions loaded leaves `lastKnownSuggestionsHeight` > 0,
        // and the next activation sizes the panel as if suggestions were still present.
        isSuggestionsCollapsedByUnfocus = false
        lastKnownSuggestionsHeight = 0
        suggestionsHeight = 0
        suggestionsHeightConstraint?.constant = 0
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
        switch submitButtonMode {
        case .submit:
            omnibarController.submit()
        case .voice:
            omnibarController.openNewVoiceChat()
        }
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

        if isWebSearchItemVisible {
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
        omnibarController.onActiveTabAttachmentsRestoreRequested = { [weak self] attachments in
            self?.restoreAttachmentsFromSharedState(attachments)
        }
    }

    /// Reinstalls the attachments view from the incoming tab's persisted list on tab switch.
    /// Any in-flight resize tasks are cancelled because they were associated with the outgoing tab's
    /// view instances; the persisted attachments already hold the best-available image we had for them.
    private func restoreAttachmentsFromSharedState(_ attachments: [AIChatImageAttachment]) {
        isRestoringAttachmentsFromSharedState = true
        defer { isRestoringAttachmentsFromSharedState = false }

        for task in resizeTasks.values {
            task.cancel()
        }
        resizeTasks.removeAll()

        attachmentsContainerView.removeAllAttachments()
        for attachment in attachments {
            attachmentsContainerView.addAttachment(attachment)
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
                // Refresh tool button visibility so the Web Search chip reflects the loaded
                // model's `supportedTools` (belt-and-braces — the controller also clears
                // `activeToolMode` when the persisted model doesn't support web search).
                updateToolButtonsVisibility(isEnabled: omnibarController.isOmnibarToolsEnabled)
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
        // Refresh tool button visibility so the tools button disappears / reappears when the
        // new model changes what the menu would show (e.g. only Web Search is flag-enabled and
        // the newly selected model doesn't support it — the button would otherwise pop an empty menu).
        updateToolButtonsVisibility(isEnabled: omnibarController.isOmnibarToolsEnabled)
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
        // Colour is set dynamically by applySubmitButtonAppearance based on enabled state.
        // Route through `updateSubmitButtonState(for:)` so voice mode is preserved on theme
        // changes — calling `applySubmitButtonAppearance` directly with the legacy
        // hasText-only enabled flag would re-disable the voice button on every theme refresh.
        updateSubmitButtonState(for: omnibarController.currentText)

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

// MARK: - AIChatSubmitButton

/// Specialised submit button that participates in the omnibar's tab cycle when in voice
/// mode. In submit mode the textarea's Enter handles submission, so the button is skipped
/// in keyboard navigation; in voice mode there is no Enter shortcut on empty input, so users
/// need to be able to Tab onto this button and press Enter/Space to start the voice session.
///
/// Mirrors the keyboard handling in `AIChatOmnibarToolButton`: Tab calls a callback (so the
/// container VC can route focus back to the textarea), Enter/Space triggers the button's
/// action via `NSButton`'s built-in behavior.
final class AIChatSubmitButton: MouseOverButton {

    /// Set by the container VC. When non-nil, `Tab` advances focus via this callback instead
    /// of the default first-responder chain.
    var onTabPressed: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48: // Tab
            if let onTabPressed {
                onTabPressed()
            } else {
                super.keyDown(with: event)
            }
        case 49, 36: // Space, Return — trigger the button's action manually.
            // NSButton's default keyDown doesn't reliably fire the action when the button
            // uses a custom layer-drawn appearance (`bezelStyle = .shadowlessSquare`, no border).
            if isEnabled, let action, let target {
                NSApp.sendAction(action, to: target, from: self)
            }
        default:
            super.keyDown(with: event)
        }
    }

    // The visible button is a rounded layer drawn by `MouseOverButton`'s hover tracking area.
    // AppKit's default focus ring fits the image content, which makes it hug the icon instead
    // of the rounded button frame. Overriding the mask + bounds makes the focus ring match the
    // button's actual shape.
    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }
}
