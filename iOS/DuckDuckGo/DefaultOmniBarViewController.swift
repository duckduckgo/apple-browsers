//
//  DefaultOmniBarViewController.swift
//  DuckDuckGo
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

import UIKit
import BrowserServicesKit
import PrivacyDashboard
import AIChat
import Core
import FeatureFlags_iOS

final class DefaultOmniBarViewController: OmniBarViewController {

    var isSuggestionTrayVisible: Bool {
        omniDelegate?.isSuggestionTrayVisible() == true
    }

    private let isFloatingUIEnabled: Bool
    private lazy var omniBarView = DefaultOmniBarView.create(isFloatingUIEnabled: isFloatingUIEnabled)
    private var isSuppressingKeyboardTransfer = false

    weak var unifiedToggleInputOmnibarActivating: UnifiedToggleInputOmnibarActivating?

    /// Manages shared text state for the iPad duck.ai ↔ search mode toggle.
    private let modeToggleTextModel: IPadModeToggleTextModeling = IPadModeToggleTextModel()
    private let featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery()
    private var modelPickerController: IPadOmnibarModelPickerController?
    private var reasoningPickerController: IPadOmnibarReasoningPickerController?
    private var toolPickerController: IPadOmnibarToolPickerController?
    private var attachmentController: IPadOmnibarAttachmentController?

    override var iPadDuckAIControlValues: IPadDuckAIControlValues {
        IPadDuckAIControlValuesSnapshot(
            selectedModelId: modelPickerController?.currentModelId,
            selectedReasoningEffort: reasoningPickerController?.selectedReasoningEffort,
            selectedTools: toolPickerController?.selectedToolsForSubmission,
            selectedImages: attachmentController?.encodedImages,
            selectedFiles: attachmentController?.encodedFiles
        )
    }

    init(dependencies: OmnibarDependencyProvider, isFloatingUIEnabled: Bool) {
        self.isFloatingUIEnabled = isFloatingUIEnabled
        super.init(dependencies: dependencies)
    }

    override func loadView() {
        view = omniBarView
    }

    // MARK: - Key Commands

    override var keyCommands: [UIKeyCommand]? {
        guard dependencies.aiChatAddressBarExperience.shouldShowModeToggle,
              omniBarView.textField.isFirstResponder || omniBarView.aiChatTextView.isFirstResponder else {
            return super.keyCommands
        }

        var commands = super.keyCommands ?? []
        let shiftEnter = UIKeyCommand(action: #selector(handleShiftEnter), input: "\r", modifierFlags: .shift)
        shiftEnter.wantsPriorityOverSystemBehavior = true
        commands.append(shiftEnter)

        if omniBarView.aiChatTextView.isFirstResponder {
            let hasHighlight = omniDelegate?.hasAIChatSuggestionsHighlight() ?? false
            let canEnterList = omniDelegate?.isAIChatSuggestionsNavigationAvailable() ?? false
            if hasHighlight || (canEnterList && omniBarView.aiChatTextView.isCaretOnLastLine) {
                commands.append(.prioritizedArrow(input: UIKeyCommand.inputDownArrow, action: #selector(handleAIChatArrowDown)))
            }
            if hasHighlight {
                commands.append(.prioritizedArrow(input: UIKeyCommand.inputUpArrow, action: #selector(handleAIChatArrowUp)))
            }
        }
        return commands
    }

    @objc private func handleAIChatArrowDown() {
        omniDelegate?.onAIChatSuggestionsMoveSelectionDown()
    }

    @objc private func handleAIChatArrowUp() {
        omniDelegate?.onAIChatSuggestionsMoveSelectionUp()
    }

    @objc private func handleShiftEnter() {
        if selectedTextEntryMode == .aiChat {
            omniBarView.aiChatTextView.insertText("\n")
        } else {
            setSelectedTextEntryMode(.aiChat)
        }
    }

    @objc private func aiChatTextViewTapped() {
        omniDelegate?.onAIChatSuggestionsClearHighlight()
    }

    // MARK: - Initialization

    override func viewDidLoad() {
        super.viewDidLoad()

        omniBarView.duckAITextViewDelegate = self

        // A tap in the text view dismisses any keyboard suggestion highlight, even when the caret does not move
        // (so `textViewDidChangeSelection` would not fire) such as tapping an empty field.
        let highlightDismissTap = UITapGestureRecognizer(target: self, action: #selector(aiChatTextViewTapped))
        highlightDismissTap.cancelsTouchesInView = false
        highlightDismissTap.delegate = self
        omniBarView.aiChatTextView.addGestureRecognizer(highlightDismissTap)

        omniBarView.isAIVoiceChatEnabled = DuckAIVoiceShortcutFeature(featureFlagger: dependencies.featureFlagger).isAvailable
        setUpModelPickerIfNeeded()
        omniBarView.onSearchAreaExpandedStateChanged = { [weak self] isExpanded in
            guard let self else { return }
            self.omniDelegate?.onOmniBarExpandedStateChanged(isExpanded: isExpanded)
            self.handleModelPickerExpansionChanged(isExpanded: isExpanded)
        }

        // Handle address bar position changes to set the shadow correctly
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(addressBarPositionChanged),
                                               name: AppUserDefaults.Notifications.addressBarPositionChanged,
                                               object: nil)
    }

    override func onAIChatSendPressed() {
        let text = omniBarView.aiChatTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasAttachments = attachmentController?.hasAttachments ?? false
        // Voice only stands in for an empty prompt; pending attachments are a submittable input.
        if text.isEmpty && !hasAttachments && omniBarView.isAIVoiceChatEnabled {
            omniDelegate?.onDuckAIVoiceModeRequested()
            return
        }
        submitIPadDuckAIText(from: omniBarView.aiChatTextView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateShadowAppearanceByApplyingLayerMask()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        /// Keep the inline duck.ai field first responder across the rotation
        guard omniBarView.aiChatTextView.isFirstResponder else { return }

        omniBarView.aiChatTextView.suppressResignFirstResponder = true
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.omniBarView.aiChatTextView.suppressResignFirstResponder = false
        }
    }

    // MARK: - Text Field Delegate Overrides

    override func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if omniBarView.isSearchAreaExpanded {
            return false
        }

        let activationDecision = unifiedToggleInputOmnibarActivating?.activateFromOmnibarIfNeeded(
            currentText: extractCurrentTextForEditing(textField),
            tapped: textFieldTapped,
            textEntryMode: textEntryMode)

        if activationDecision == .intercept {
            return false
        }

        if modeToggleTextModel.isTransitioning {
            return true
        }

        return super.textFieldShouldBeginEditing(textField)
    }

    override func textFieldDidBeginEditing(_ textField: UITextField) {
        if modeToggleTextModel.isTransitioning {
            handleIPadTextFieldDidBeginEditingDuringTransfer()
        } else {
            super.textFieldDidBeginEditing(textField)
        }

        omniBarView.layoutIfNeeded()
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0.0, options: [.curveEaseOut]) {
            self.omniBarView.isActiveState = true
            self.omniBarView.layoutIfNeeded()
        }
    }

    override func textFieldDidEndEditing(_ textField: UITextField) {
        guard !omniBarView.isSearchAreaExpanded else { return }

        super.textFieldDidEndEditing(textField)

        omniBarView.layoutIfNeeded()
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0.0, options: [.curveEaseOut]) {
            self.omniBarView.isActiveState = false
            self.omniBarView.layoutIfNeeded()
        }
    }

    private func extractCurrentTextForEditing(_ textField: UITextField) -> String? {
        guard let text = textField.text?.trimmingWhitespace(), !text.isEmpty else { return nil }
        if URL(trimmedAddressBarString: text, useUnifiedLogic: isUsingUnifiedPredictor) != nil,
           let url = omniDelegate?.didRequestCurrentURL() {
            return AddressDisplayHelper.addressForDisplay(url: url, showsFullURL: true).string
        }
        return text
    }

    // MARK: - Editing Lifecycle Overrides

    override func setSelectedTextEntryMode(_ mode: TextEntryMode) {
        guard dependencies.aiChatAddressBarExperience.shouldShowModeToggle else {
            super.setSelectedTextEntryMode(mode)
            return
        }

        handleIPadModeToggleTransition(to: mode)
    }

    override func endEditing() {
        if omniBarView.isSearchAreaExpanded {
            omniBarView.aiChatTextView.resignFirstResponder()
        }
        super.endEditing()
    }

    // MARK: - Layout

    override func animateDismissButtonTransition(from oldView: UIView, to newView: UIView) {

        dismissButtonAnimator?.stopAnimation(true)
        let animationDuration: CGFloat = 0.25

        newView.alpha = 0
        newView.isHidden = false
        oldView.isHidden = false

        dismissButtonAnimator = UIViewPropertyAnimator(duration: animationDuration, curve: .easeInOut) {
            oldView.alpha = 0
            newView.alpha = 1.0
        }

        dismissButtonAnimator?.isInterruptible = true

        dismissButtonAnimator?.addCompletion { position in
            if position == .end {
                oldView.isHidden = true
            }
        }
        dismissButtonAnimator?.startAnimation()
    }

    override func showCustomIcon(icon: OmniBarIcon) {
        // This causes constraints to be removed...
        barView.customIconView.removeFromSuperview()

        super.showCustomIcon(icon: icon)

        guard let customIconSuperview = barView.customIconView.superview else { return }

        // ... so we can reapply them here
        barView.customIconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            barView.customIconView.centerYAnchor.constraint(equalTo: customIconSuperview.centerYAnchor),
            barView.customIconView.leadingAnchor.constraint(equalTo: customIconSuperview.leadingAnchor),
        ])
    }

    override func refreshText(forUrl url: URL?, forceFullURL: Bool) {
        /// Skip while the expanded duck.ai panel is open — otherwise the page title bleeds
        /// through the transparent aiChatTextView. https://app.asana.com/1/137249556945/project/1201011656765697/task/1215084286493408?focus=true
        if omniBarView.isSearchAreaExpanded {
            return
        }
        super.refreshText(forUrl: url, forceFullURL: forceFullURL)
    }

    override func enterAIChatMode() {
        /// Skip while the user is editing — would reveal the favicon over the open panel.
        ///  https://app.asana.com/1/137249556945/project/1201011656765697/task/1215084286493408?focus=true
        if omniBarView.isSearchAreaExpanded || omniBarView.textField.isEditing {
            return
        }
        super.enterAIChatMode()

        if dependencies.aiChatAddressBarExperience.isIPadAIToggleExperienceEnabled,
           state is SmallOmniBarState.AIChatModeState {
            refreshState(SmallOmniBarState.AIChatTabModeState(dependencies: dependencies, isLoading: state.isLoading))
        }
    }

    override func updateInterface(from oldState: any OmniBarState, to state: any OmniBarState) {
        super.updateInterface(from: oldState, to: state)

        let isLandscapeEditing = isExpandedPhone && barView.textField.isEditing
        let newMode: OmniBarLayoutMode
        if isLandscapeEditing || (!state.hasLargeWidth && !isExpandedPhone) {
            newMode = .compact
        } else if isExpandedPhone {
            newMode = .expandedPhone
        } else {
            newMode = .expandedPad
        }

        omniBarView.setLayoutMode(newMode, animated: isExpandedPhone)

        let clearButtonHidden = shouldHideClearButton(for: state)
        omniBarView.isClearButtonHidden = clearButtonHidden

        let hasTrailingAccessory = state.showAIChatButton || state.showAIChatModeToggle
        let hasAdjacentButton = !clearButtonHidden || state.showVoiceSearch || state.showRefresh || state.showAbort || state.showCustomizableButton
        omniBarView.isShowingSeparator = hasTrailingAccessory && hasAdjacentButton

        updateShadowAppearanceByApplyingLayerMask()
    }

    /// Whether the clear button should be hidden for `state`.
    func shouldHideClearButton(for state: any OmniBarState) -> Bool {
        if omniBarView.isSearchAreaExpanded {
            return (omniBarView.aiChatTextView.text ?? "").isEmpty
        }
        return !state.showClear
    }

    override func useSmallTopSpacing() {
        omniBarView.isUsingSmallTopSpacing = true
    }

    override func useRegularTopSpacing() {
        omniBarView.isUsingSmallTopSpacing = false
    }

    var shouldClipShadows: Bool {
        guard !isFloatingUIEnabled else { return false }
        return state.isBrowsing
            && !isSuggestionTrayVisible
    }

    // MARK: Notifications

    @objc private func addressBarPositionChanged() {
        updateShadowAppearanceByApplyingLayerMask()
    }

    // MARK: - Private Helper Methods

    private func updateShadowAppearanceByApplyingLayerMask() {
        omniBarView.updateMaskLayer(maskTop: dependencies.appSettings.currentAddressBarPosition.isBottom,
                                    clip: shouldClipShadows)
    }

    /// Re-applies shadow clipping after floating chrome styling changes (e.g. theme decorate).
    func reconcileShadowClip() {
        updateShadowAppearanceByApplyingLayerMask()
    }

}

// MARK: - iPad Duck.ai Mode Toggle
//
// On iPad, the address bar has a search/duck.ai toggle.
// When the user switches between modes, the text must transfer seamlessly between the UITextField
// (search mode) and the UITextView (duck.ai expanded mode) while keeping the keyboard visible.

extension DefaultOmniBarViewController {

    fileprivate func submitIPadDuckAIText(from textView: UITextView) {
        let query = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasValidAttachment = attachmentController?.hasValidAttachment ?? false
        let hasInvalidAttachment = attachmentController?.hasInvalidAttachment ?? false
        // Mirror the iPhone unified toggle rule: submit needs text or a valid attachment, and is
        // blocked while any attachment is invalid.
        guard !hasInvalidAttachment, !query.isEmpty || hasValidAttachment else { return }

        if selectedTextEntryMode == .aiChat {
            textView.text = ""
            omniBarView.updateTextFieldPlaceholderVisibility(hasText: false)
            omniBarView.updateAIChatSendButton(hasText: false)

            if URL.isValidAddressBarURLInput(query) {
                DailyPixel.fireDailyAndCount(pixel: .aiChatIPadToggleURLSubmitted)
                dismissIPadDuckAIMode()
                omniDelegate?.onOmniQuerySubmitted(query)
            } else {
                let isFirstPromptNewInstall = featureDiscovery.isFirstDuckAIPromptNewInstall
                let firstPromptParameters: [String: String] = isFirstPromptNewInstall ? [PixelParameters.aiChatFirstPromptNewInstall: "true"] : [:]
                DailyPixel.fireDailyAndCount(pixel: .aiChatIPadTogglePromptSubmitted, withAdditionalParameters: firstPromptParameters)
                fireIPadUnifiedPromptSubmittedPixels(hasText: !query.isEmpty, isFirstPromptNewInstall: isFirstPromptNewInstall)
                featureDiscovery.markDuckAIPromptSubmitted()
                /// Collapse and resign instantly so a quick re-tap doesn't race the post-submit
                /// collapse animation.
                /// https://app.asana.com/1/137249556945/project/1201011656765697/task/1215084286493408?focus=true
                omniBarView.setSearchAreaExpanded(false, animated: false)
                omniBarView.aiChatTextView.resignFirstResponder()
                omniDelegate?.onPromptSubmitted(query, tools: nil)
                toolPickerController?.resetSelection()
                attachmentController?.resetSelection()
            }
        } else {
            omniDelegate?.onOmniQuerySubmitted(query)
        }
    }

    /// Dismisses the duck.ai mode without bringing the keyboard back.
    /// Used after prompt submission where we want the bar fully unfocused.
    fileprivate func dismissIPadDuckAIMode() {
        isSuppressingKeyboardTransfer = true
        // Collapse instantly to avoid a visual flash when navigation starts.
        omniBarView.setSearchAreaExpanded(false, animated: false)
        setSelectedTextEntryMode(.search)
        endEditing()
        isSuppressingKeyboardTransfer = false
        attachmentController?.resetSelection()
    }

    /// Handles the duck.ai ↔ search mode transition on iPad, preserving text and keyboard state.
    fileprivate func handleIPadModeToggleTransition(to mode: TextEntryMode) {
        if omniBarView.isSearchAreaExpanded {
            modeToggleTextModel.updateText(omniBarView.aiChatTextView.text ?? "")
        }

        guard let transition = modeToggleTextModel.transition(to: mode) else {
            super.setSelectedTextEntryMode(mode)
            return
        }

        // When switching to duck.ai without editing the auto-selected URL, clear it so
        // the expanded view starts empty — but remember it so search restores it on the way back.
        if mode == .aiChat && shouldClearTextWhenSwitchingToDuckAI() {
            modeToggleTextModel.rememberSearchTextToRestore(omniBarView.textField.text ?? "")
            omniBarView.textField.text = ""
        }

        let isKeyboardActive = omniBarView.aiChatTextView.isFirstResponder || omniBarView.textField.isFirstResponder
        let shouldTransferKeyboard = transition.needsKeyboardTransfer && !isSuppressingKeyboardTransfer && isKeyboardActive

        if shouldTransferKeyboard {
            modeToggleTextModel.beginTransition()

            // The collapse carries the duck.ai field's text into the search field — seed it with the
            // destination text so the search field shows it straight away, never the placeholder.
            omniBarView.aiChatTextView.text = transition.text

            omniBarView.onCollapseAnimationCompleted = { [weak self] in
                guard let self else { return }
                self.beginEditing(animated: false, forTextEntryMode: .search)
                self.updateQuery(transition.text)
                if transition.selectAllText {
                    self.omniBarView.textField?.selectAll(nil)
                }
                self.modeToggleTextModel.endTransition()
            }
        }

        super.setSelectedTextEntryMode(mode)

        if !shouldTransferKeyboard {
            modeToggleTextModel.endTransition()
        }
    }

    fileprivate func handleIPadTextFieldDidBeginEditingDuringTransfer() {
        _ = omniDelegate?.onTextFieldDidBeginEditing(barView)
        refreshState(state.onEditingStartedState)
        omniDelegate?.onDidBeginEditing()
    }

    private func shouldClearTextWhenSwitchingToDuckAI() -> Bool {
        guard let textField = omniBarView.textField else {
            return false
        }

        // Preserve non-URL user input when switching to duck.ai.
        guard let text = textField.text,
              URL(trimmedAddressBarString: text.trimmingWhitespace(), useUnifiedLogic: isUsingUnifiedPredictor) != nil else {
            return false
        }

        // Clear the auto-displayed page URL, but never once the user has typed — a tap doesn't count as
        // editing, and typing-then-deleting back to the URL still counts (the flag is sticky).
        return !userDidEditText
    }

}

// MARK: - iPad Duck.ai Model Picker

extension DefaultOmniBarViewController {

    private func setUpModelPickerIfNeeded() {
        guard dependencies.aiChatAddressBarExperience.isIPadAIToggleExperienceEnabled,
              dependencies.featureFlagger.isFeatureOn(.iPadDuckAIBarControls) else { return }

        let controller = IPadOmnibarModelPickerController()
        modelPickerController = controller

        // The reasoning and tool pickers share the model picker's store so all chips reflect the
        // same selected model and a single `/models` fetch.
        let reasoningController = IPadOmnibarReasoningPickerController(store: controller.modelStore)
        reasoningPickerController = reasoningController
        reasoningController.onReasoningUpdated = { [weak self] in
            self?.refreshReasoningPicker()
        }

        let toolController = IPadOmnibarToolPickerController(store: controller.modelStore)
        toolPickerController = toolController
        toolController.onToolsUpdated = { [weak self] in
            self?.refreshToolPicker()
            self?.refreshReasoningPicker()
        }
        omniBarView.onSelectedToolClearTapped = { [weak self] in
            self?.toolPickerController?.resetSelection(isUserInitiated: true)
        }

        // The attach button shares the same store so its limits and accepted types track the selected
        // model. The strip view owns the pending attachments; the controller reads and mutates it.
        let attachmentControllerInstance = IPadOmnibarAttachmentController(store: controller.modelStore)
        attachmentController = attachmentControllerInstance
        attachmentControllerInstance.attachmentsStripView = omniBarView.attachmentsStripView
        attachmentControllerInstance.presenterProvider = { [weak self] in
            self?.view.window?.windowScene?.keyWindow?.rootViewController
        }
        attachmentControllerInstance.onExpandRequested = { [weak self] in
            self?.omniBarView.setSearchAreaExpanded(true, animated: false)
        }
        omniBarView.attachmentsStripView.onAttachmentsChanged = { [weak self] in
            self?.handleAttachmentsChanged()
        }

        controller.onModelsUpdated = { [weak self] in
            guard let self else { return }
            // Re-apply any model/reasoning selection unblocked by a subscription refresh, then
            // refresh every chip (a new model changes which reasoning modes, tools, and attachment
            // types apply).
            self.modelPickerController?.handleModelsUpdated()
            self.reasoningPickerController?.handleModelsUpdated()
            self.toolPickerController?.handleModelChanged()
            self.attachmentController?.handleModelChanged()
            self.refreshModelPicker()
            self.refreshReasoningPicker()
            self.refreshToolPicker()
            self.refreshAttachButton()
        }

        omniBarView.isModelPickerEnabled = true
        omniBarView.aiChatModelName = controller.currentModelLabel
        omniBarView.isReasoningPickerEnabled = true
        omniBarView.isToolPickerEnabled = true
        omniBarView.isAttachButtonEnabled = true
        refreshReasoningPicker()
        refreshToolPicker()
        refreshAttachButton()
    }

    private func handleModelPickerExpansionChanged(isExpanded: Bool) {
        guard isExpanded, let controller = modelPickerController else { return }
        controller.activate()
        refreshModelPicker()
        refreshReasoningPicker()
        refreshToolPicker()
        refreshAttachButton()
    }

    private func refreshModelPicker() {
        guard let controller = modelPickerController else { return }

        if let shortName = controller.currentModelLabel {
            omniBarView.aiChatModelName = shortName
        }
        let menu = controller.makeMenu { [weak self] modelId in
            guard let self else { return }
            self.modelPickerController?.handleModelSelection(modelId)
            self.toolPickerController?.handleModelChanged()
            self.attachmentController?.handleModelChanged()
            self.refreshModelPicker()
            self.refreshReasoningPicker()
            self.refreshToolPicker()
            self.refreshAttachButton()
        }
        omniBarView.aiChatModelPickerMenu = menuFiringShownPixel(menu) {
            UnifiedToggleInputCoordinatorPixelHelper.fireModelPickerShownPixel(isAITabState: false)
        }
    }

    private func refreshReasoningPicker() {
        guard let controller = reasoningPickerController else { return }

        let hiddenByTool = toolPickerController?.selectedToolHidesReasoningPicker ?? false
        if controller.isReasoningPickerAvailable, !hiddenByTool {
            omniBarView.aiChatReasoningIcon = controller.currentReasoningMode?.unifiedToggleInputButtonImage
            omniBarView.aiChatReasoningPickerMenu = menuFiringShownPixel(controller.makeMenu()) {
                UnifiedToggleInputCoordinatorPixelHelper.fireReasoningPickerShownPixel(isAITabState: false)
            }
        } else {
            omniBarView.aiChatReasoningIcon = nil
            omniBarView.aiChatReasoningPickerMenu = nil
        }
    }

    private func menuFiringShownPixel(_ menu: UIMenu?, onShow: @escaping () -> Void) -> UIMenu? {
        guard let menu else { return nil }
        let deferred = UIDeferredMenuElement.uncached { completion in
            onShow()
            completion(menu.children)
        }
        return UIMenu(title: menu.title, options: menu.options, children: [deferred])
    }

    private func refreshToolPicker() {
        guard let controller = toolPickerController else { return }

        if controller.isToolPickerAvailable {
            omniBarView.aiChatToolPickerMenu = controller.makeMenu()
            omniBarView.selectedTool = controller.selectedTool
        } else {
            omniBarView.aiChatToolPickerMenu = nil
            omniBarView.selectedTool = nil
        }
    }

    private func refreshAttachButton() {
        // A nil menu hides the button — i.e. when the selected model accepts no attachments.
        omniBarView.aiChatAttachmentMenu = attachmentController?.makeMenu()
    }

    private func fireIPadUnifiedPromptSubmittedPixels(hasText: Bool, isFirstPromptNewInstall: Bool) {
        guard modelPickerController != nil else { return }
        let attachments = attachmentController?.pendingAttachments ?? []
        let selectedTool = toolPickerController?.selectedTool
        UnifiedToggleInputCoordinatorPixelHelper.fireUnifiedPromptSubmittedPixel(
            hasText: hasText,
            selectedTool: selectedTool,
            attachments: attachments,
            reasoningMode: iPadReasoningModeForSubmitPixel,
            modelId: modelPickerController?.currentModelId,
            surface: .addressBar,
            pageType: omniDelegate?.currentPromptPageType() ?? .unknown,
            origin: .ipadTogglePrompt,
            isFirstPromptNewInstall: isFirstPromptNewInstall
        )
        UnifiedToggleInputCoordinatorPixelHelper.fireToolSubmittedPixelIfNeeded(
            selectedTool: selectedTool,
            attachments: attachments,
            surface: .addressBar
        )
    }

    private var iPadReasoningModeForSubmitPixel: AIChatReasoningMode? {
        if toolPickerController?.selectedToolHidesReasoningPicker == true { return nil }
        guard reasoningPickerController?.isReasoningPickerAvailable == true else { return nil }
        return reasoningPickerController?.currentReasoningMode
    }

    /// Called when the strip's attachments change (add / remove / clear): rebuilds the attach menu
    /// (limits change with the pending set), grows or collapses the expanded area to fit, and nudges
    /// any anchored suggestions popover to follow the new height.
    private func handleAttachmentsChanged() {
        refreshAttachButton()
        omniBarView.updateAttachmentsLayout(animated: true)
        let hasText = !(omniBarView.aiChatTextView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        omniBarView.updateAIChatSendButton(hasText: hasText)
        omniDelegate?.onOmniBarExpandedContentSizeChanged()
    }
}

// MARK: - UITextViewDelegate (iPad Duck.ai Expanded Text View)
//
// Handles text input in the expanded duckAITextView when the iPad duck.ai mode toggle is active.
// The textField's placeholder is used as a shared placeholder — its alpha is toggled based on
// whether the duckAITextView has content, so the placeholder shows through when empty.

extension DefaultOmniBarViewController: UITextViewDelegate {

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            // A highlighted chat-history row claims Return instead of submitting the typed prompt.
            if omniDelegate?.onAIChatSuggestionsActivateHighlight() == true {
                return false
            }
            submitIPadDuckAIText(from: textView)
            return false
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        let newQuery = textView.text ?? ""

        modeToggleTextModel.updateText(newQuery)
        userDidEditText = true
        // The user is editing the duck.ai field — their text now governs, so don't resurrect the
        // page URL we cleared on the way in when toggling back to search.
        modeToggleTextModel.invalidateSearchTextToRestore()

        if modeToggleTextModel.isTransitioning, !omniBarView.isSearchAreaExpanded {
            omniBarView.textField.text = newQuery
        }

        if selectedTextEntryMode != .aiChat {
            omniDelegate?.onOmniQueryUpdated(newQuery)
        } else {
            omniDelegate?.onAIChatQueryUpdated(newQuery)
        }
        if newQuery.isEmpty {
            refreshState(state.onTextClearedState)
        } else {
            refreshState(state.onTextEnteredState)
        }

        omniBarView.updateTextFieldPlaceholderVisibility(hasText: !modeToggleTextModel.showPlaceholder)
        omniBarView.updateAIChatSendButton(hasText: modeToggleTextModel.hasSubmittableText)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        // Moving the caret in the text (e.g. tapping back into the field) dismisses the keyboard suggestion highlight.
        omniDelegate?.onAIChatSuggestionsClearHighlight()
    }

    func textViewDidEndEditing(_ textView: UITextView) {
        guard !modeToggleTextModel.isTransitioning else { return }

        omniBarView.setSearchAreaExpanded(false, animated: true)

        switch omniDelegate?.onEditingEnd() {
        case .dismissed, .none:
            refreshState(state.onEditingStoppedState)
        case .suspended:
            refreshState(state.onEditingSuspendedState)
        }
        omniDelegate?.onDidEndEditing()

        omniBarView.layoutIfNeeded()
        UIViewPropertyAnimator.runningPropertyAnimator(withDuration: 0.2, delay: 0.0, options: [.curveEaseOut]) {
            self.omniBarView.isActiveState = false
            self.omniBarView.layoutIfNeeded()
        }
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        _ = omniDelegate?.onTextFieldDidBeginEditing(barView)
        refreshState(state.onEditingStartedState)
        omniDelegate?.onDidBeginEditing()

        omniBarView.layoutIfNeeded()
    }
}

extension DefaultOmniBarViewController: UIGestureRecognizerDelegate {

    // Observe taps without consuming them, so the text view's own caret/selection gestures still run.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

}

private extension UITextView {

    var isCaretOnLastLine: Bool {
        // Subpixel tolerance absorbing rounding between the caret position and the end of the document.
        let lastLineTolerance: CGFloat = 1
        guard let selectedTextRange else { return true }
        let caretMaxY = caretRect(for: selectedTextRange.end).maxY
        let documentEndMaxY = caretRect(for: endOfDocument).maxY
        return caretMaxY >= documentEndMaxY - lastLineTolerance
    }

}

private extension UIKeyCommand {

    static func prioritizedArrow(input: String, action: Selector) -> UIKeyCommand {
        let command = UIKeyCommand(action: action, input: input, modifierFlags: [])
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

}
