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
import PrivacyConfig

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
        static let shadowOverlapHeight: CGFloat = 21
        static let legacyShadowOverlapHeight: CGFloat = 12
        static let submitButtonSize: CGFloat = 28
        static let submitButtonCornerRadius: CGFloat = 14
        static let submitButtonTrailingInset: CGFloat = 8
        static let legacySubmitButtonTrailingInset: CGFloat = 13
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
        /// Carousel's outer height when populated — includes the row content height plus an
        /// internal shadow-margin band on top and bottom, so card shadows render without clipping.
        static let attachmentsCarouselRowHeight: CGFloat = AIChatAttachmentsCarouselView.expandedHeight
        /// Visible vertical spacing between the cards' bottom edge and the tools row.
        static let attachmentsCarouselBottomSpacing: CGFloat = 8
        /// Anchor offset for the carousel's bottom: the carousel's lower shadow-margin band
        /// already provides part of the visual spacing, so the actual constraint constant is the
        /// remaining gap = `bottomSpacing - shadowMargin`. Negated for the layout API.
        static let attachmentsCarouselBottomAnchorOffset: CGFloat = -(attachmentsCarouselBottomSpacing - AIChatAttachmentsCarouselView.shadowMargin)
        /// Total panel height the carousel + below-spacing reserves when populated.
        static let attachmentsCarouselTotalPanelReservation: CGFloat = AIChatAttachmentsCarouselView.expandedHeight + (attachmentsCarouselBottomSpacing - AIChatAttachmentsCarouselView.shadowMargin)
        static let suggestionsBottomPadding: CGFloat = 4
        static let containerTopPadding: CGFloat = 5
        static let legacyContainerTopPadding: CGFloat = 0
        static let contentLeadingInset: CGFloat = 2
        static let legacyContentLeadingInset: CGFloat = 0
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
    // No image-attachments container view: image / file / tab attachment data all lives on
    // `AddressBarSharedTextState`, and the unified `AIChatAttachmentsCarouselView` is the
    // sole rendering surface.
    private let attachmentsCarouselView = AIChatAttachmentsCarouselView()

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

    /// Holds ongoing resize tasks keyed by attachment ID, so we can await them before submission.
    private var resizeTasks: [UUID: Task<Void, Never>] = [:]

    /// Constraint for suggestions view height
    private var suggestionsHeightConstraint: NSLayoutConstraint?

    /// Unified attachments carousel height constraint — 0 when both image and tab attachment
    /// lists are empty, `attachmentsCarouselRowHeight + attachmentsCarouselBottomSpacing` otherwise.
    /// (Named `attachmentsCarouselHeightConstraint` for the property's introduction history; it now
    /// drives the combined image + tab row.)
    private var attachmentsCarouselHeightConstraint: NSLayoutConstraint?

    /// True while the attach menu is open. We defer the carousel's panel-reflow (height
    /// constraint update + `onPassthroughHeightNeedsUpdate`) until the menu closes — otherwise
    /// each toggle would push the panel down by a card-row's worth, and the menu (popped at the
    /// button's pre-toggle position) would visually drift over the new card. The carousel's
    /// data still updates immediately so the menu's checkmarks stay in sync; only the panel
    /// growth is held back.
    private var isDeferringCarouselLayout = false

    /// Sticky error from the most recent file pick that was rejected at pick-time (too large, too
    /// many pages, encrypted/unreadable, unsupported, or over the count limit). Shown in the
    /// attachments error label and cleared when the user next changes attachments or the model.
    private var lastAttachmentError: String?

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

    /// Combined "carousel + error label" reservation. Single source of truth so
    /// `additionalContentHeight` and `totalPassthroughHeight` can't drift apart on the
    /// gating rule (the carousel is populated only via tools UI today, but each method
    /// previously open-coded the same arithmetic with subtly different gates).
    private var attachmentRowReservation: CGFloat {
        var height: CGFloat = 0
        // The carousel filters out attachments the model can't accept, so its `attachments`
        // count reflects what the user actually sees.
        if !attachmentsCarouselView.attachments.isEmpty {
            height += Constants.attachmentsCarouselTotalPanelReservation
        }
        if shouldShowAttachmentError {
            height += Constants.attachmentsErrorHeight
        }
        return height
    }

    /// Whether the attachments error label should be visible — either a sticky pick-time rejection
    /// or a live count-excess cue (one over the cap).
    private var shouldShowAttachmentError: Bool {
        lastAttachmentError != nil || hasVisibleImageExcess || hasVisibleFileExcess
    }

    /// Extra height needed beyond text and suggestions for dynamic content like attachments.
    /// This must be added to the container height calculation by the parent.
    var additionalContentHeight: CGFloat {
        let containerTopPadding = themeManager.isAppRebranded ? Constants.containerTopPadding : Constants.legacyContainerTopPadding
        return attachmentRowReservation + containerTopPadding
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
            height += attachmentRowReservation
        }
        return height
    }

    /// True when the user has more image attachments than the cap AND the model can render them
    /// in the carousel — i.e. the error label has visible cards to anchor against.
    private var hasVisibleImageExcess: Bool {
        (omnibarController.selectedModelSupportsImageUpload || omnibarController.isImageGenerationMode)
            && omnibarController.hasExcessActiveTabImageAttachments
    }

    /// File-side analogue of `hasVisibleImageExcess`.
    private var hasVisibleFileExcess: Bool {
        omnibarController.selectedModelSupportsFileUpload && hasExcessFileAttachments
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
        let imageBlockingExcess = canSendImages && omnibarController.hasExcessActiveTabImageAttachments
        let fileBlockingExcess = omnibarController.selectedModelSupportsFileUpload && hasExcessFileAttachments
        let hasBlockingExcess = imageBlockingExcess || fileBlockingExcess

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
                    submitButton.normalTintColor = NSColor(designSystemColor: .iconsPrimary)
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
                designSystemColor = .controlsFillTertiary
            } else if submitButton.isMouseOver {
                designSystemColor = .controlsFillSecondary
            } else {
                designSystemColor = .controlsFillPrimary
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

    /// Image picker has room for at least one more attachment.
    private var canPickAdditionalImages: Bool {
        shouldShowImageUpload && !omnibarController.isActiveTabImageAttachmentsFull
    }

    /// File picker has room for at least one more attachment (and the model supports files).
    private var canPickAdditionalFiles: Bool {
        omnibarController.selectedModelSupportsFileUpload && !isFileAttachmentsFull
    }

    /// File-side analogue of `omnibarController.isActiveTabImageAttachmentsFull` — at or above the per-conversation cap.
    private var isFileAttachmentsFull: Bool {
        omnibarController.activeFileAttachments.count >= omnibarController.maxFileAttachments
    }

    /// File-side analogue of `omnibarController.hasExcessActiveTabImageAttachments` — strictly over cap.
    private var hasExcessFileAttachments: Bool {
        omnibarController.activeFileAttachments.count > omnibarController.maxFileAttachments
    }

    /// The attach button is now multi-purpose: it triggers either the legacy image-and-file
    /// picker (when only image upload is available) or a menu with both options (when the tab
    /// picker is also enabled). It needs to be visible when *any* attach mode is available
    /// — image upload, file upload (PDFs etc.), or the omnibar tab picker.
    private var shouldShowAttachButton: Bool {
        shouldShowImageUpload
            || omnibarController.isOmnibarTabPickerEnabled
            || omnibarController.selectedModelSupportsFileUpload
    }

    /// "Attach Image or File" is shown when *either* path can still accept one more attachment —
    /// images (within cap) or files (within cap). When both are full, hiding the item avoids the
    /// dead click that would otherwise just open a picker the user can't pick into.
    private var shouldShowImageOrFileMenuItem: Bool {
        canPickAdditionalImages || canPickAdditionalFiles
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
        imageUploadButton.isHidden = !shouldShowAttachButton
        // Disable only when we'd be entering the legacy direct-file-picker path AND images are at
        // cap. With the tab picker enabled the button always opens the menu (which conditionally
        // omits the image item itself when full), so the outer button stays interactive.
        imageUploadButton.isEnabled = omnibarController.isOmnibarTabPickerEnabled || !omnibarController.isActiveTabImageAttachmentsFull
        modelPickerButton.isHidden = !shouldShowModelPicker
        toolsButton.label = omnibarController.activeToolMode != nil ? nil : UserText.aiChatToolsButtonLabel

        // The carousel row's height is recomputed centrally via `updateAttachmentsCarouselLayout()`.
        if !shouldShowAttachments {
            updateAttachmentsCarouselLayout()
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

        shadowView.shadowColor = themeManager.theme.colorsProvider.addressBarShadowColor
        shadowView.shadowOpacity = 1
        shadowView.shadowOffset = CGSize(width: 0, height: 0)
        shadowView.shadowRadius = themeManager.theme.addressBarStyleProvider.suggestionShadowRadius
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
        imageUploadButton.action = #selector(attachButtonClicked)
        imageUploadButton.image = DesignSystemImages.Glyphs.Size16.attach
        updateAttachButtonTooltip()
        imageUploadButton.onTabPressed = { [weak self] in guard let self else { return }; self.advanceFocusAfter(self.imageUploadButton) }
        containerView.addSubview(imageUploadButton)

        toolsButton.translatesAutoresizingMaskIntoConstraints = false
        toolsButton.target = self
        toolsButton.action = #selector(toolsButtonClicked)
        toolsButton.image = DesignSystemImages.Glyphs.Size16.options
        toolsButton.keepIconLeadingAligned = !themeManager.isAppRebranded
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

        containerView.addSubview(attachmentsErrorLabel)

        attachmentsCarouselView.translatesAutoresizingMaskIntoConstraints = false
        attachmentsCarouselView.onAttachmentsChanged = { [weak self] in
            self?.updateAttachmentsCarouselLayout()
        }
        // X clicks on a card route through the controller, which writes to shared state; the
        // `$aiChatPanelAttachments` publisher then drives the carousel re-render. Single source
        // of truth for the order; the carousel itself never mutates its own state.
        attachmentsCarouselView.onImageAttachmentRemoveRequested = { [weak self] id in
            guard let self else { return }
            PixelKit.fire(AIChatPixel.aiChatAddressBarImageRemoved, frequency: .dailyAndCount, includeAppVersionParameter: true)
            self.lastAttachmentError = nil
            self.resizeTasks[id]?.cancel()
            self.resizeTasks.removeValue(forKey: id)
            self.omnibarController.removeImageAttachmentFromActiveTab(id: id)
        }
        attachmentsCarouselView.onTabAttachmentRemoveRequested = { [weak self] id in
            // × on a tab card is the primary tab-removal action. The carousel doesn't
            // remember whether the tab was attached via the "Add Page Content" submenu or
            // the @-mention picker, so we fire `attach_tab_removed` here uniformly (the
            // mention-specific `mention_tab_removed` continues to fire only when the user
            // deselects through the @-picker UI, which keeps it as a clean signal of
            // @-picker engagement).
            PixelKit.fire(AIChatPixel.aiChatAddressBarAttachTabRemoved, frequency: .dailyAndCount, includeAppVersionParameter: true)
            self?.omnibarController.removeTabAttachmentFromActiveTab(id: id)
        }
        attachmentsCarouselView.onFileAttachmentRemoveRequested = { [weak self] id in
            PixelKit.fire(AIChatPixel.aiChatAddressBarFileRemoved, frequency: .dailyAndCount, includeAppVersionParameter: true)
            self?.lastAttachmentError = nil
            self?.omnibarController.removeFileAttachmentFromActiveTab(id: id)
        }
        containerView.addSubview(attachmentsCarouselView)

        // Single subscription drives the carousel for both restore-on-tab-switch and live
        // mutations. `@Published.sink` delivers the current value on subscribe so the initial
        // render is automatic.
        omnibarController.onActiveTabPanelAttachmentsChanged = { [weak self] panelAttachments in
            self?.applyPanelAttachmentsFromSharedState(panelAttachments)
        }
        // Initial render — the controller's `$selectedTabViewModel` sink hasn't fired yet at
        // this point, so seed manually from whatever the active tab already has.
        applyPanelAttachmentsFromSharedState(omnibarController.activePanelAttachments)

        let isAppRebranded = themeManager.isAppRebranded
        let contentLeadingInset = isAppRebranded ? Constants.contentLeadingInset : Constants.legacyContentLeadingInset
        let submitButtonTrailingInset = isAppRebranded ? Constants.submitButtonTrailingInset : Constants.legacySubmitButtonTrailingInset

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

            submitButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -submitButtonTrailingInset),
            // Bottom constraint is set in setupSuggestionsView() to be above suggestions
            submitButton.widthAnchor.constraint(equalToConstant: Constants.submitButtonSize),
            submitButton.heightAnchor.constraint(equalToConstant: Constants.submitButtonSize),

            modelPickerButton.heightAnchor.constraint(equalToConstant: Constants.modelPickerHeight),

            reasoningPickerButton.widthAnchor.constraint(greaterThanOrEqualToConstant: Constants.toolButtonSize),
            reasoningPickerButton.heightAnchor.constraint(equalToConstant: Constants.toolButtonSize),
            reasoningPickerButton.trailingAnchor.constraint(equalTo: modelPickerButton.leadingAnchor, constant: -Constants.toolButtonSpacing),

            imageUploadButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.toolButtonLeadingInset + contentLeadingInset),
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

            // The unified attachments carousel sits directly above the tools row. It contains the
            // image attachments view (leading) and the tab cards (trailing) — both flow into one
            // horizontally-scrollable strip.
            attachmentsCarouselView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.attachmentsLeadingInset + contentLeadingInset),
            attachmentsCarouselView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -Constants.attachmentsLeadingInset),
            // The carousel's bottom shadow-margin band already accounts for part of the visual
            // gap to the tools row; the constraint adds the remainder so the visible card-to-tools
            // distance is `attachmentsCarouselBottomSpacing`.
            attachmentsCarouselView.bottomAnchor.constraint(equalTo: imageUploadButton.topAnchor, constant: Constants.attachmentsCarouselBottomAnchorOffset),

            attachmentsErrorLabel.leadingAnchor.constraint(equalTo: attachmentsCarouselView.leadingAnchor),
            attachmentsErrorLabel.bottomAnchor.constraint(equalTo: attachmentsCarouselView.topAnchor, constant: -2),
        ])

        // Carousel height: 0 when empty, `attachmentsCarouselRowHeight` when there's at least one
        // image thumbnail or tab card. The row collapses to nothing when both kinds are empty.
        attachmentsCarouselHeightConstraint = attachmentsCarouselView.heightAnchor.constraint(equalToConstant: 0)
        attachmentsCarouselHeightConstraint?.isActive = true

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

        // Tools button chains after image upload button, or aligns to container when upload is hidden.
        // The container is edge to edge, so re-apply the leading inset here to match imageUploadButton.
        let contentLeadingInset = themeManager.isAppRebranded ? Constants.contentLeadingInset : Constants.legacyContentLeadingInset
        toolsLeadingToUploadButton = toolsButton.leadingAnchor.constraint(equalTo: imageUploadButton.trailingAnchor, constant: Constants.toolButtonSpacing)
        toolsLeadingToContainer = toolsButton.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: Constants.toolButtonLeadingInset + contentLeadingInset)
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
        omnibarController.isImageGenerationMode
            || !omnibarController.activeImageAttachments.isEmpty
            || !attachmentsCarouselView.attachments.isEmpty
            || isSuggestionsCollapsedByUnfocus
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
        // Record the real height even when suppressed
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
        backgroundView.stopListening()
        shadowView.removeFromSuperview()
        windowFrameObserver?.cancel()
        windowFrameObserver = nil
        viewBoundsObserver?.cancel()
        viewBoundsObserver = nil

        // Cancel pending resize tasks. Attachment data on shared state is intentionally left
        // intact — cleanup is panel teardown, not a user-driven clear.
        cancelAllImageResizeTasks()

        // The pick-time rejection error is transient panel UI, so drop it on teardown rather than
        // letting it resurface when the panel is reopened.
        lastAttachmentError = nil

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
        frame.size.height -= themeManager.isAppRebranded ? Constants.shadowOverlapHeight : Constants.legacyShadowOverlapHeight

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

    /// Routes the attach-button click. When the omnibar tab picker is enabled, opens a menu
    /// (Attach Image or File / Attach Page Content). Otherwise behaves as before — opens the
    /// image-and-file picker directly. Keeps the legacy file-picker path 1-to-1 for users with
    /// the new flag off.
    @objc private func attachButtonClicked() {
        if omnibarController.isOmnibarTabPickerEnabled {
            let menu = buildAttachMenu()
            menu.delegate = self
            // Hold the panel layout still while the menu is up — see `isDeferringCarouselLayout`
            // for the rationale. Carousel data still updates so the menu's checkmarks stay in sync.
            isDeferringCarouselLayout = true
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -5), in: imageUploadButton)
        } else {
            presentImageFilePicker()
        }
    }

    /// Opens the image-and-file picker. Pulled out of the legacy `imageUploadButtonClicked` so
    /// both the legacy direct-click path and the new "Attach Image or File" menu item can share it.
    private func presentImageFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = pickerAllowedContentTypes()

        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK else { return }
            self.addPickedAttachments(from: panel.urls)
        }
    }

    /// Adds picked images / files, enforcing the API-driven limits at pick-time. A file that
    /// violates a limit (unsupported type, too large, over the total-size budget, too many pages,
    /// encrypted / unreadable, or over the count limit) is not attached — the first such reason is
    /// surfaced in the error label. Limits are evaluated cumulatively so a multi-select batch can't
    /// collectively overshoot. Images keep the `displayCap` (one-over) cue since they have no
    /// size / page dimension and a single submission is bounded to the per-turn image count.
    private func addPickedAttachments(from urls: [URL]) {
        // Reading bytes off disk and parsing PDFs (page count / encryption) is offloaded to a
        // background task per file — a large PDF would otherwise block the main thread. Validation,
        // attachment, and label updates stay on the main actor; files are processed in order so the
        // cumulative count / total-size checks remain correct.
        Task { @MainActor [weak self] in
            guard let self else { return }
            var imagesAdded = self.omnibarController.activeImageAttachments.count
            let imageCap = self.omnibarController.imageAttachmentsDisplayCap
            var pendingFiles = self.omnibarController.activeFileAttachments.map(AIChatAttachmentValidator.FileDescriptor.init)
            var firstFileError: String?

            for url in urls {
                let utType = UTType(filenameExtension: url.pathExtension.lowercased())
                if let utType, utType.conforms(to: .image) {
                    guard imagesAdded < imageCap else { continue }
                    self.addImageAttachment(from: url)
                    imagesAdded += 1
                } else {
                    guard let attachment = await Task.detached(priority: .userInitiated, operation: {
                        Self.makeFileAttachment(from: url)
                    }).value else { continue }
                    let descriptor = AIChatAttachmentValidator.FileDescriptor(attachment)

                    // Size / total-size / page / type / encryption reject the file outright. Count is
                    // handled separately by the `displayCap` (one-over) cue below, so we pass
                    // `enforceCount: false` here — otherwise an over-count file would be rejected with a
                    // count message instead of getting the "+1" visual cue that images also use.
                    if self.omnibarController.attachmentLimits != nil {
                        let validator = self.omnibarController.makeAttachmentValidator(
                            pendingImageCount: imagesAdded,
                            pendingFiles: pendingFiles
                        )
                        if let error = validator.fileValidationError(for: descriptor, enforceCount: false) {
                            PixelKit.fire(
                                AIChatPixel.aiChatAddressBarFileValidationFailed(reason: error.reason.rawValue),
                                frequency: .dailyAndCount,
                                includeAppVersionParameter: true
                            )
                            if firstFileError == nil { firstFileError = error.message }
                            continue
                        }
                    }

                    // Count cue: allow up to `displayCap` (one over the limit) so the carousel renders
                    // the over-limit state and the error label calls it out; submit stays blocked while over.
                    guard pendingFiles.count < self.omnibarController.fileAttachmentsDisplayCap else { continue }

                    self.omnibarController.addFileAttachmentToActiveTab(attachment)
                    PixelKit.fire(AIChatPixel.aiChatAddressBarFileAttached, frequency: .dailyAndCount, includeAppVersionParameter: true)
                    pendingFiles.append(descriptor)
                }
            }

            self.lastAttachmentError = firstFileError
            self.updateAttachmentsLayout()
        }
    }

    /// Union of the UTTypes the picker should allow:
    /// - image formats from the model (extensions like `"png"`)
    /// - file MIME types from the model (`"application/pdf"` etc.)
    /// Defaults to image-only when both lists are empty so the picker never opens with no
    /// allowed types (which would let the user pick anything).
    private func pickerAllowedContentTypes() -> [UTType] {
        var types: [UTType] = []
        if canPickAdditionalImages {
            let imageTypes = omnibarController.selectedModelImageFormats
                .compactMap { UTType(filenameExtension: $0.lowercased()) }
            types.append(contentsOf: imageTypes.isEmpty ? [.jpeg, .png, .webP] : imageTypes)
        }
        if omnibarController.selectedModelSupportsFileUpload {
            let fileTypes = omnibarController.selectedModelSupportedFileTypes
                .compactMap { UTType(mimeType: $0) }
            types.append(contentsOf: fileTypes)
        }
        return types
    }

    /// Top-level attach menu: "Attach Image or File" (when image upload is supported by the
    /// current model) and "Attach Page Content" (with the tabs submenu). The image item is
    /// omitted when the model doesn't support image upload, because the omnibar attach button is
    /// also visible in that case (purely for tab attachment), and showing a non-functional item
    /// would be confusing.
    /// Label for the image/file picker menu item, adapted to what the selected model supports:
    /// "Add Images" (image-only), "Add PDFs" (file-only), or "Add Images or PDFs" (both). When the
    /// model advertises a non-PDF file type, the file noun is generalized from the accepted types.
    private func attachMenuItemTitle() -> String {
        let supportsImages = omnibarController.selectedModelSupportsImageUpload
        let supportsFiles = omnibarController.selectedModelSupportsFileUpload
        let fileTypes = omnibarController.selectedModelSupportedFileTypes
        let isPDFOnly = fileTypes == ["application/pdf"]

        switch (supportsImages, supportsFiles) {
        case (true, true):
            return isPDFOnly
                ? UserText.aiChatAttachMenuImageOrFile
                : UserText.aiChatAttachMenuImagesOrFilesTyped(fileTypesNoun(fileTypes))
        case (true, false):
            return UserText.aiChatAttachMenuImages
        case (false, true):
            return isPDFOnly
                ? UserText.aiChatAttachMenuFiles
                : UserText.aiChatAttachMenuFilesTyped(fileTypesNoun(fileTypes))
        case (false, false):
            return UserText.aiChatAttachMenuImageOrFile
        }
    }

    private func fileTypesNoun(_ mimeTypes: [String]) -> String {
        let names = mimeTypes.map(AIChatAttachmentValidator.fileTypeName(for:))
        return names.isEmpty ? "PDFs" : names.joined(separator: ", ")
    }

    /// Tooltip / accessibility label for the attach button. Uses the same adaptive copy as the
    /// attach-menu item ("Add Images" / "Add PDFs" / "Add Images or PDFs") so the wording always
    /// matches what the selected model accepts — never a misleading singular "Add image". When the
    /// model accepts neither images nor files (only the tab picker is available), it falls back to
    /// the page-content label.
    private func attachButtonTooltip() -> String {
        // Reflect what the button can actually do *now*. When image/file picking is unavailable —
        // unsupported by the model or both kinds at capacity — `shouldShowImageOrFileMenuItem` is
        // false and the menu only offers page content, so the tooltip must match rather than read
        // "Add Images or PDFs".
        guard shouldShowImageOrFileMenuItem else {
            return UserText.aiChatAttachMenuPageContent
        }
        return attachMenuItemTitle()
    }

    private func updateAttachButtonTooltip() {
        let tooltip = attachButtonTooltip()
        imageUploadButton.toolTip = tooltip
        imageUploadButton.setAccessibilityLabel(tooltip)
    }

    private func buildAttachMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if shouldShowImageOrFileMenuItem {
            let imageItem = NSMenuItem(
                title: attachMenuItemTitle(),
                action: #selector(attachMenuImageOrFileClicked),
                keyEquivalent: ""
            )
            imageItem.target = self
            imageItem.image = DesignSystemImages.Glyphs.Size16.folder
            menu.addItem(imageItem)
            menu.addItem(NSMenuItem.separator())
        }

        let pageItem = NSMenuItem(
            title: UserText.aiChatAttachMenuPageContent,
            action: nil,
            keyEquivalent: ""
        )
        pageItem.image = DesignSystemImages.Glyphs.Size16.pageContentAttach
        pageItem.submenu = buildAttachTabsSubmenu()
        menu.addItem(pageItem)

        return menu
    }

    /// Observer installed as the `NSMenuDelegate` of the "Add Page Content" submenu so we can
    /// fire the picker-shown / picker-canceled pixels exactly once per open/close cycle. The
    /// row's `onToggle` callback below flips the observer's `didMutateDuringSession` flag so
    /// the canceled pixel is only fired when nothing was toggled during the session.
    /// Retained on the VC because `NSMenu.delegate` is weak.
    private var attachTabsSubmenuObserver: AttachTabsSubmenuObserver?

    /// Builds the "Attach Page Content" submenu. When the user has open URL tabs, the submenu
    /// starts with a "Recent Tabs" section header followed by a custom-view row per tab — each
    /// row stays-open-on-click via `AIChatTabPickerMenuRowView` so the user can multi-toggle
    /// without dismissing the menu. When there are no tabs to show, the submenu drops the header
    /// and shows only a disabled "No open tabs" placeholder.
    private func buildAttachTabsSubmenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Observer fires the picker-shown pixel on willOpen and the picker-canceled pixel on
        // didClose when no row was toggled in between. Stored on the VC so its lifetime
        // covers the menu's lifetime (NSMenu's delegate ref is weak).
        let observer = AttachTabsSubmenuObserver()
        attachTabsSubmenuObserver = observer
        menu.delegate = observer

        let attachedIds = Set(omnibarController.activeTabAttachments.map(\.id))
        let candidates = omnibarController.openTabsForOmnibarPicker()
        let currentTabId = omnibarController.currentTabUUID

        guard !candidates.isEmpty else {
            let empty = NSMenuItem(title: UserText.aiChatAttachMenuNoOpenTabs, action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return menu
        }

        let header = NSMenuItem(title: UserText.aiChatAttachMenuRecentTabsHeader, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        // `openTabsForOmnibarPicker()` returns the current tab first, so the menu shows
        // "(Current Tab)" pinned on top.
        for candidate in candidates {
            let item = NSMenuItem()
            let row = AIChatTabPickerMenuRowView(
                attachment: candidate,
                isAttached: attachedIds.contains(candidate.id),
                isCurrentTab: candidate.id == currentTabId,
                onToggle: { [weak omnibarController, weak observer] in
                    guard let omnibarController else { return }
                    // Read state BEFORE toggle so we know which pixel to fire — the toggle
                    // flips it, so post-toggle we'd see the opposite of "what just happened".
                    let wasAttached = omnibarController.activeTabAttachments.contains(where: { $0.id == candidate.id })
                    omnibarController.toggleTabAttachment(candidate)
                    let pixel: AIChatPixel = wasAttached
                        ? .aiChatAddressBarAttachTabRemoved
                        : .aiChatAddressBarAttachTabChosen
                    PixelKit.fire(pixel, frequency: .dailyAndCount, includeAppVersionParameter: true)
                    observer?.markDidMutate()
                }
            )
            item.view = row
            menu.addItem(item)
        }

        return menu
    }

    @objc private func attachMenuImageOrFileClicked() {
        presentImageFilePicker()
    }

    /// Attempts to add an image attachment from a drag-and-drop operation.
    /// - Returns: `true` if the image was accepted, `false` if attachments are full.
    func addImageAttachmentFromDrop(_ url: URL) -> Bool {
        guard omnibarController.activeImageAttachments.count < omnibarController.imageAttachmentsDisplayCap else { return false }
        // A successful drop is a pick action from the user's perspective, so clear any stale
        // pick-time rejection error (matching the file/image picker path).
        lastAttachmentError = nil
        addImageAttachment(from: url)
        updateAttachmentsLayout()
        return true
    }

    /// Reads file bytes off disk and builds a file attachment (PDFs etc.), inspecting PDFs for page
    /// count / encryption so the validator can enforce the page-count limit and reject encrypted or
    /// unreadable files. MIME type comes from the URL's UTType so it matches the model's
    /// `supportedFileTypes` (which are MIME types). Returns `nil` if the bytes can't be read.
    private nonisolated static func makeFileAttachment(from url: URL) -> AIChatFileAttachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let mimeType = UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType
            ?? "application/octet-stream"
        let inspection = AIChatPDFInspector.inspect(data: data, mimeType: mimeType)
        return AIChatFileAttachment(
            data: data,
            fileName: url.lastPathComponent,
            mimeType: mimeType,
            pageCount: inspection.pageCount,
            isEncrypted: inspection.isEncrypted
        )
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
        omnibarController.addImageAttachmentToActiveTab(placeholder)
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
                self?.omnibarController.replaceImageAttachmentInActiveTab(id: placeholderId, with: resized)
                self?.resizeTasks.removeValue(forKey: placeholderId)
            }
        }
    }

    private func setupAttachmentsProvider() {
        // Submit-time clear callback: cancel any in-flight image-resize tasks. Data clearing
        // is handled by the controller calling `persistAttachmentsToActiveTab([])` directly.
        omnibarController.onAttachmentsClearRequested = { [weak self] in
            self?.cancelAllImageResizeTasks()
            // Submit clears all attachments, so a leftover pick-time rejection no longer applies.
            self?.lastAttachmentError = nil
            self?.updateAttachmentsLayout()
        }
        // Block submit until in-flight resize tasks finish so the prompt carries the resized
        // image, not the placeholder.
        omnibarController.waitForAttachmentsReady = { [weak self] in
            guard let self else { return }
            let tasks = Array(self.resizeTasks.values)
            for task in tasks {
                await task.value
            }
        }
    }

    private func cancelAllImageResizeTasks() {
        for task in resizeTasks.values {
            task.cancel()
        }
        resizeTasks.removeAll()
    }

    private func updateAttachmentsLayout() {
        let hasAttachments = !omnibarController.activeImageAttachments.isEmpty
        let isFull = omnibarController.isActiveTabImageAttachmentsFull

        omnibarController.hasImageAttachments = hasAttachments

        // Image thumbnails and tab cards share the carousel's row, so the row's height is driven
        // jointly through `updateAttachmentsCarouselLayout()` (single source of truth for the row).
        updateAttachmentsCarouselLayout()

        // Gate the error label on model support — same `hasVisibleImageExcess` /
        // `hasVisibleFileExcess` predicates that `attachmentRowReservation` already uses for
        // the height reservation. Using the raw `hasExcess*` checks here would leave the label
        // shown when the current model doesn't accept the kind of attachment in excess (cards
        // get filtered out of the carousel but the excess persists in shared state from a
        // prior model), and because no row height is reserved in that case the label would
        // overlap the tools row below. Keeping the two decisions in sync prevents that.
        let visibleImageExcess = hasVisibleImageExcess
        let visibleFileExcess = hasVisibleFileExcess
        // A sticky pick-time rejection (size / pages / unsupported / count) takes priority — it
        // names the precise reason the file the user just chose wasn't added. Otherwise fall back
        // to the live count-excess copy; file excess wins over image excess as it's the more
        // recently introduced and likely thing the user has just done.
        attachmentsErrorLabel.isHidden = !shouldShowAttachmentError
        if let lastAttachmentError {
            attachmentsErrorLabel.stringValue = lastAttachmentError
        } else if visibleFileExcess {
            // API-driven so the copy names the real per-conversation cap (3 free / 5 paid) rather
            // than a hardcoded "3 files".
            attachmentsErrorLabel.stringValue = UserText.aiChatAttachmentFileCountLimit(
                maxFilesPerConversation: omnibarController.maxFileAttachments
            )
        } else {
            attachmentsErrorLabel.stringValue = UserText.aiChatAttachmentImageTurnLimit(
                maxImagesPerTurn: omnibarController.maxImageAttachments
            )
        }

        // Disable the upload button only when *no* attach path can accept one more attachment.
        // The button stays enabled if image room remains, file room remains, OR the tab picker
        // is on (the menu always has the Attach Page Content option).
        if omnibarController.isOmnibarToolsEnabled {
            imageUploadButton.isEnabled = omnibarController.isOmnibarTabPickerEnabled
                || !isFull
                || canPickAdditionalFiles
            // "Limit reached" tooltip only when the picker is the only path AND it's exhausted
            // for both kinds — otherwise the default tooltip stays so the user knows they can
            // still attach the other kind.
            let allPickerPathsFull = isFull && (!omnibarController.selectedModelSupportsFileUpload || isFileAttachmentsFull)
            if allPickerPathsFull && !omnibarController.isOmnibarTabPickerEnabled {
                imageUploadButton.toolTip = UserText.aiChatAttachmentsLimitError
                imageUploadButton.setAccessibilityLabel(UserText.aiChatAttachmentsLimitError)
            } else {
                updateAttachButtonTooltip()
            }
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

    /// Pushes the unified attachments list (from `AddressBarSharedTextState.aiChatPanelAttachments`)
    /// into the carousel, filtering out attachment kinds the current model can't accept so the
    /// user doesn't see cards that would be silently stripped at submit time. The data itself
    /// survives in shared state — switching back to a supporting model brings the cards back.
    /// While the attach menu is open we skip the panel-reflow step; it runs once when the menu
    /// closes. Otherwise we run the full `updateAttachmentsLayout()` so the error label,
    /// attach-button enabled state, and submit-button state all refresh — this is the path that
    /// fires when a file is added/removed via the picker (or a tab via X click).
    private func applyPanelAttachmentsFromSharedState(_ attachments: [AIChatPanelAttachment]) {
        let filtered = attachments.filter { entry in
            switch entry {
            case .image:
                return omnibarController.selectedModelSupportsImageUpload || omnibarController.isImageGenerationMode
            case .file:
                return omnibarController.selectedModelSupportsFileUpload
            case .tab:
                // Tab attachments are page content, not model-typed payloads — always renderable.
                return true
            }
        }
        attachmentsCarouselView.setAttachments(filtered)
        guard !isDeferringCarouselLayout else { return }
        updateAttachmentsLayout()
        // The height constraint just flipped to `expandedHeight` (when the carousel went
        // from zero → some attachments). Force layout to settle on the new frame before
        // scrolling, otherwise `scrollToVisible` reads the still-zero carousel height.
        attachmentsCarouselView.superview?.layoutSubtreeIfNeeded()
        attachmentsCarouselView.scrollLastAddedAttachmentIntoView()
    }

    /// Re-applies the active tab's saved panel attachments through the carousel filter — used
    /// by code paths that change *what the current model supports* without changing the
    /// attachments themselves (model picker change, image-gen mode toggle), so cards for newly
    /// unsupported kinds disappear and cards for newly supported kinds reappear.
    private func refreshCarouselForCurrentModelSupport() {
        applyPanelAttachmentsFromSharedState(omnibarController.activePanelAttachments)
    }

    private func updateAttachmentsCarouselLayout() {
        // Row collapses when there are no rendered cards in the carousel; expanded row otherwise.
        // The carousel's own attachment list is the post-filter view of shared state (e.g.
        // `applyPanelAttachmentsFromSharedState` drops image attachments when the selected
        // model doesn't support image upload), so reading from it is the right "what will the
        // user actually see" signal — checking `activeImageAttachments` here as well would
        // reserve the expanded height for zero visible cards in that filtered-out scenario.
        let hasAnyVisibleAttachment = !attachmentsCarouselView.attachments.isEmpty
        attachmentsCarouselHeightConstraint?.constant = hasAnyVisibleAttachment
            ? Constants.attachmentsCarouselRowHeight
            : 0
        // Adding/removing a tab attachment changes whether suggestions should be visible —
        // mirroring the behavior of the image attachments path. (`shouldSuppressSuggestions`
        // already factors both lists in.)
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

        // A model switch changes what's acceptable, so a stale pick-time error no longer applies.
        lastAttachmentError = nil

        let showImageSide = supportsImageUpload || omnibarController.isImageGenerationMode
        // The attach BUTTON should remain visible when *any* attach mode is available — image,
        // file (PDFs etc.), or tab picker.
        imageUploadButton.isHidden = !shouldShowAttachButton
        if !showImageSide {
            // Image side disappearing — recompute the shared row height; if tabs/files are
            // present the carousel stays at row height, otherwise it collapses.
            updateAttachmentsCarouselLayout()
            // No explicit `attachmentsErrorLabel.isHidden = true` here — the call to
            // `refreshCarouselForCurrentModelSupport()` below routes through
            // `applyPanelAttachmentsFromSharedState` → `updateAttachmentsLayout`, which now
            // evaluates the label visibility against `hasVisibleImageExcess` /
            // `hasVisibleFileExcess` and will correctly hide the label when the new model
            // doesn't support the kind of attachment in excess. Setting `isHidden = true`
            // here would just be undone by that re-invocation a few lines down.
        } else {
            updateAttachmentsLayout()
        }

        // Cards for kinds the new model can't accept disappear from the carousel here; the
        // underlying shared-state list is left untouched so a switch back restores them.
        refreshCarouselForCurrentModelSupport()

        updateSubmitButtonState(for: omnibarController.currentText)
        updateToolsLeadingConstraint()
        onPassthroughHeightNeedsUpdate?()
    }

    private func applyTheme(theme: ThemeStyleProviding) {
        let barStyleProvider = theme.addressBarStyleProvider
        let colorsProvider = theme.colorsProvider
        let isAppRebranding = themeManager.isAppRebranded

        backgroundView.backgroundColor = colorsProvider.activeAddressBarBackgroundColor
        backgroundView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadiusWithSuggestions

        if isAppRebranding {
            backgroundView.roundedCorners = [.bottomLeft, .bottomRight]
        } else {
            backgroundView.layer?.masksToBounds = false  // Don't clip subviews - important for hit testing
        }

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
        // Focus-ring colour follows the active theme's primary accent, the same source the
        // search/AI toggle uses, so all controls in the duck.ai address bar agree on the glow.
        // (The submit button is excluded — it uses AppKit's native focus ring, which can't
        // be themed without a deeper rewrite.)
        let focusRingColor = colorsProvider.accentPrimaryColor
        toolsButton.tintColor = toolButtonTintColor
        toolsButton.hoverBackgroundColor = .buttonMouseOver
        toolsButton.pressedBackgroundColor = .buttonMouseDown
        toolsButton.focusRingColor = focusRingColor
        imageGenActiveButton.tintColor = toolButtonTintColor
        imageGenActiveButton.hoverBackgroundColor = .buttonMouseOver
        imageGenActiveButton.pressedBackgroundColor = .buttonMouseDown
        imageGenActiveButton.focusRingColor = focusRingColor
        webSearchActiveButton.tintColor = toolButtonTintColor
        webSearchActiveButton.hoverBackgroundColor = .buttonMouseOver
        webSearchActiveButton.pressedBackgroundColor = .buttonMouseDown
        webSearchActiveButton.focusRingColor = focusRingColor
        imageUploadButton.tintColor = toolButtonTintColor
        imageUploadButton.hoverBackgroundColor = .buttonMouseOver
        imageUploadButton.pressedBackgroundColor = .buttonMouseDown
        imageUploadButton.focusRingColor = focusRingColor
        reasoningPickerButton.tintColor = toolButtonTintColor
        reasoningPickerButton.hoverBackgroundColor = .buttonMouseOver
        reasoningPickerButton.pressedBackgroundColor = .buttonMouseDown
        reasoningPickerButton.focusRingColor = focusRingColor
        modelPickerButton.tintColor = toolButtonTintColor
        modelPickerButton.focusRingColor = focusRingColor

        innerBorderView.borderColor = NSColor(named: "AddressBarInnerBorderColor")
        innerBorderView.backgroundColor = NSColor.clear
        innerBorderView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadiusWithSuggestions

        if isAppRebranding {
            innerBorderView.roundedCorners = [.bottomLeft, .bottomRight]
        }

        shadowView.shadowRadius = barStyleProvider.suggestionShadowRadius
        shadowView.cornerRadius = barStyleProvider.addressBarActiveBackgroundViewRadiusWithSuggestions

        NSAppearance.withAppAppearance {
            shadowView.shadowColor = colorsProvider.addressBarShadowColor
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
    //
    // Note: the ring colour is the system `controlAccentColor`, so it does *not* follow the
    // in-app theme switcher (Pink etc.) the way the other AIChat controls do. AppKit's focus
    // ring colour can't be overridden without taking ownership of the entire focus-ring render
    // path on an NSButton subclass — left as a known limitation for a separate PR.
    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: cornerRadius, yRadius: cornerRadius).fill()
    }
}

// MARK: - Attach menu delegate

extension AIChatOmnibarContainerViewController: NSMenuDelegate {

    /// `NSMenu` calls this when the entire menu chain (top-level menu + any open submenu) closes.
    /// Used to release the carousel-layout deferral that was started in `attachButtonClicked` —
    /// once unset, the panel reflows once with whatever toggles the user accumulated. Full
    /// `updateAttachmentsLayout()` (vs. just the row layout) so error label / attach-button
    /// state stay in sync with whatever the user attached while the menu was open.
    func menuDidClose(_ menu: NSMenu) {
        guard isDeferringCarouselLayout else { return }
        isDeferringCarouselLayout = false
        updateAttachmentsLayout()
        attachmentsCarouselView.superview?.layoutSubtreeIfNeeded()
        attachmentsCarouselView.scrollLastAddedAttachmentIntoView()
    }
}

// MARK: - "Add Page Content" submenu observer

/// Observes one open/close cycle of the "Add Page Content" submenu so the picker-shown and
/// picker-canceled pixels fire exactly once per session. Sits as the submenu's
/// `NSMenuDelegate` (the VC's own conformance already handles the top-level attach menu's
/// `menuDidClose`, so we keep this submenu-only logic separate to avoid mixing concerns).
private final class AttachTabsSubmenuObserver: NSObject, NSMenuDelegate {

    /// `true` once any row's `onToggle` fired during the current open session. Reset on the
    /// next `menuWillOpen` so each open/close pair is evaluated independently.
    private var didMutateDuringSession = false

    func menuWillOpen(_ menu: NSMenu) {
        didMutateDuringSession = false
        PixelKit.fire(
            AIChatPixel.aiChatAddressBarAttachTabsPickerShown,
            frequency: .dailyAndCount,
            includeAppVersionParameter: true
        )
    }

    func menuDidClose(_ menu: NSMenu) {
        guard !didMutateDuringSession else { return }
        PixelKit.fire(
            AIChatPixel.aiChatAddressBarAttachPickerCanceled,
            frequency: .dailyAndCount,
            includeAppVersionParameter: true
        )
    }

    /// Called from the row's `onToggle` closure so the cancel pixel is suppressed when the
    /// user actually picked or removed something during this session.
    func markDidMutate() {
        didMutateDuringSession = true
    }
}
