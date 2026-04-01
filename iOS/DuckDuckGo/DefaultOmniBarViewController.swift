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
import Combine
import PrivacyDashboard
import Suggestions
import Bookmarks
import AIChat
import Core

final class DefaultOmniBarViewController: OmniBarViewController {

    var isSuggestionTrayVisible: Bool {
        omniDelegate?.isSuggestionTrayVisible() == true
    }

    private lazy var omniBarView = DefaultOmniBarView.create()
    private weak var editingStateViewController: OmniBarEditingStateViewController?
    private var cancellables = Set<AnyCancellable>()
    private let sessionStateMetrics = SessionStateMetrics(storage: UserDefaults.standard)

    private var animateNextEditingTransition = true
    private var isSuppressingKeyboardTransfer = false

    weak var unifiedToggleInputOmnibarActivating: UnifiedToggleInputOmnibarActivating?

    /// Manages shared text state for the iPad duck.ai ↔ search mode toggle.
    private let modeToggleTextModel: IPadModeToggleTextModeling = IPadModeToggleTextModel()

    override func loadView() {
        view = omniBarView
    }

    // MARK: - Key Commands

    override var keyCommands: [UIKeyCommand]? {
        guard dependencies.aiChatAddressBarExperience.shouldShowModeToggle,
              omniBarView.textField.isFirstResponder || omniBarView.aiChatTextView.isFirstResponder else {
            return super.keyCommands
        }

        let shiftEnter = UIKeyCommand(action: #selector(handleShiftEnter), input: "\r", modifierFlags: .shift)
        shiftEnter.wantsPriorityOverSystemBehavior = true
        return (super.keyCommands ?? []) + [shiftEnter]
    }

    @objc private func handleShiftEnter() {
        if selectedTextEntryMode == .aiChat {
            omniBarView.aiChatTextView.insertText("\n")
        } else {
            setSelectedTextEntryMode(.aiChat)
        }
    }

    // MARK: - Initialization

    override func viewDidLoad() {
        super.viewDidLoad()

        omniBarView.duckAITextViewDelegate = self
        omniBarView.isAIVoiceChatEnabled = DuckAIVoiceShortcutFeature(featureFlagger: dependencies.featureFlagger).isAvailable
        omniBarView.onSearchAreaExpandedStateChanged = { [weak self] isExpanded in
            self?.omniDelegate?.onOmniBarExpandedStateChanged(isExpanded: isExpanded)
        }

        // Handle address bar position changes to set the shadow correctly
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(addressBarPositionChanged),
                                               name: AppUserDefaults.Notifications.addressBarPositionChanged,
                                               object: nil)
    }

    override func onAIChatSendPressed() {
        let text = omniBarView.aiChatTextView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if text.isEmpty && omniBarView.isAIVoiceChatEnabled {
            omniDelegate?.onDuckAIVoiceModeRequested()
            return
        }
        submitIPadDuckAIText(from: omniBarView.aiChatTextView)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateShadowAppearanceByApplyingLayerMask()
    }

    // MARK: - Text Field Delegate Overrides

    override func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if omniBarView.isSearchAreaExpanded {
            return false
        }

        if unifiedToggleInputOmnibarActivating?.activateFromOmnibarIfNeeded(
            currentText: extractCurrentTextForEditing(textField)
        ) == .intercept {
            return false
        }

        if dependencies.aiChatAddressBarExperience.shouldUseExperimentalEditingState {
            if textFieldTapped {
                omniDelegate?.onExperimentalAddressBarTapped()
            }
            presentExperimentalEditingState(for: textField, animated: animateNextEditingTransition)

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
        guard let text = textField.text, !text.isEmpty else { return nil }
        if let url = URL(string: text), url.host != nil {
            return url.absoluteString
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

    override func beginEditing(animated: Bool, forTextEntryMode textEntryMode: TextEntryMode?) {
        animateNextEditingTransition = animated

        super.beginEditing(animated: animated, forTextEntryMode: textEntryMode)
        
        animateNextEditingTransition = true
    }

    override func endEditing() {
        if omniBarView.isSearchAreaExpanded {
            omniBarView.aiChatTextView.resignFirstResponder()
        }
        super.endEditing()
        editingStateViewController?.dismissAnimated()
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

    override func updateInterface(from oldState: any OmniBarState, to state: any OmniBarState) {
        super.updateInterface(from: oldState, to: state)

        let isLandscapeEditing = isPhoneLandscape && barView.textField.isEditing
        let newMode: OmniBarLayoutMode
        if !state.hasLargeWidth || isLandscapeEditing {
            newMode = .compact
        } else if isPhoneLandscape {
            newMode = .phoneLandscape
        } else {
            newMode = .expanded
        }

        omniBarView.setLayoutMode(newMode, animated: isPhoneLandscape)

        let hasTrailingAccessory = state.showAIChatButton || state.showAIChatModeToggle
        let hasAdjacentButton = state.showClear || state.showVoiceSearch || state.showRefresh || state.showAbort || state.showCustomizableButton
        omniBarView.isShowingSeparator = hasTrailingAccessory && hasAdjacentButton

        updateShadowAppearanceByApplyingLayerMask()
    }

    override func useSmallTopSpacing() {
        omniBarView.isUsingSmallTopSpacing = true
    }

    override func useRegularTopSpacing() {
        omniBarView.isUsingSmallTopSpacing = false
    }

    var shouldClipShadows: Bool {
        state.isBrowsing
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

    private func presentExperimentalEditingState(for textField: UITextField, animated: Bool = true) {
        guard editingStateViewController == nil else { return }
        guard let suggestionsDependencies = dependencies.suggestionTrayDependencies else { return }

        // Use explicit mode if set (programmatic beginEditing), otherwise fall back
        // to the tab's per-tab mode already stored in selectedTextEntryMode.
        let capturedTextEntryMode: TextEntryMode = textEntryMode ?? selectedTextEntryMode

        if let omniDelegate {
            omniDelegate.dismissContextualSheetIfNeeded { [weak self] in
                guard let self else { return }
                self.present(for: textField, suggestionsDependencies: suggestionsDependencies, textEntryMode: capturedTextEntryMode, animated: animated)
            }
        } else {
            present(for: textField, suggestionsDependencies: suggestionsDependencies, textEntryMode: capturedTextEntryMode, animated: animated)
        }
    }

    private func present(for textField: UITextField, suggestionsDependencies: SuggestionTrayDependencies, textEntryMode: TextEntryMode, animated: Bool) {
        guard editingStateViewController == nil else { return }

        let switchBarHandler = createSwitchBarHandler(for: textField, initialToggleState: textEntryMode)
        let shouldAutoSelectText = shouldAutoSelectTextForUrl(textField)

        let escapeHatch = omniDelegate?.escapeHatchForEditingState()
        let editingStateViewController = OmniBarEditingStateViewController(
            switchBarHandler: switchBarHandler,
            escapeHatch: escapeHatch
        )
        editingStateViewController.delegate = self

        editingStateViewController.modalPresentationStyle = .custom
        editingStateViewController.transitioningDelegate = self

        editingStateViewController.suggestionTrayDependencies = suggestionsDependencies
        editingStateViewController.automaticallySelectsTextOnAppear = shouldAutoSelectText
        editingStateViewController.useNewTransitionBehaviour = omniDelegate?.useNewOmnibarTransitionBehaviour() ?? false

        switchBarHandler.clearButtonTappedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.omniDelegate?.onExperimentalAddressBarClearPressed()
            }
            .store(in: &cancellables)

        self.editingStateViewController = editingStateViewController

        present(editingStateViewController, animated: animated)
    }

    private func createSwitchBarHandler(for textField: UITextField, initialToggleState: TextEntryMode? = nil) -> SwitchBarHandler {
        let isFireTab = omniDelegate?.isCurrentTabFireTab() ?? false
        let switchBarHandler = SwitchBarHandler(voiceSearchHelper: dependencies.voiceSearchHelper,
                                                aiChatSettings: dependencies.aiChatSettings,
                                                initialToggleState: initialToggleState,
                                                sessionStateMetrics: sessionStateMetrics,
                                                isFireTab: isFireTab)

        guard let currentText = omniBarView.text?.trimmingWhitespace(), !currentText.isEmpty, omniBarView.isFullAIChatHidden else {
            return switchBarHandler
        }

        /// Determine whether the current text in the omnibar is a search query or a URL.
        /// - If the text is a URL, retrieve the full URL from the delegate and update the text with the full URL for display.
        /// - If the text is a search query, simply update the text with the query itself.
        if URL(trimmedAddressBarString: currentText, useUnifiedLogic: isUsingUnifiedPredictor) != nil,
           let url = omniDelegate?.didRequestCurrentURL() {
            let urlText = AddressDisplayHelper.addressForDisplay(url: url, showsFullURL: true)
            switchBarHandler.updateCurrentText(urlText.string)
        } else {
            switchBarHandler.updateCurrentText(currentText)
        }

        return switchBarHandler
    }

    private func shouldAutoSelectTextForUrl(_ textField: UITextField) -> Bool {
        guard let textFieldText = textField.text else { return false }
        if URL(trimmedAddressBarString: textFieldText.trimmingWhitespace(), useUnifiedLogic: isUsingUnifiedPredictor) != nil {
            return true
        }
        return omniDelegate?.shouldAutoSelectTextForSERPQuery() ?? false
    }
}

// MARK: - iPad Duck.ai Mode Toggle
//
// On iPad, the address bar has a search/duck.ai toggle (gated by the iPadAIToggle feature flag).
// When the user switches between modes, the text must transfer seamlessly between the UITextField
// (search mode) and the UITextView (duck.ai expanded mode) while keeping the keyboard visible.

extension DefaultOmniBarViewController {

    fileprivate func submitIPadDuckAIText(from textView: UITextView) {
        let query = textView.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !query.isEmpty else { return }

        if selectedTextEntryMode == .aiChat {
            textView.text = ""
            omniBarView.updateTextFieldPlaceholderVisibility(hasText: false)
            omniBarView.updateAIChatSendButton(hasText: false)

            if URL.isValidAddressBarURLInput(query) {
                DailyPixel.fireDailyAndCount(pixel: .aiChatIPadToggleURLSubmitted)
                dismissIPadDuckAIMode()
                omniDelegate?.onOmniQuerySubmitted(query)
            } else {
                DailyPixel.fireDailyAndCount(pixel: .aiChatIPadTogglePromptSubmitted)
                omniDelegate?.onPromptSubmitted(query, tools: nil)
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
        // the expanded view starts empty.
        if mode == .aiChat && shouldClearTextWhenSwitchingToDuckAI() {
            omniBarView.textField.text = ""
        }

        let isKeyboardActive = omniBarView.aiChatTextView.isFirstResponder || omniBarView.textField.isFirstResponder
        let shouldTransferKeyboard = transition.needsKeyboardTransfer && !isSuppressingKeyboardTransfer && isKeyboardActive

        if shouldTransferKeyboard {
            modeToggleTextModel.beginTransition()

            omniBarView.onCollapseAnimationCompleted = { [weak self] in
                guard let self else { return }
                self.beginEditing(animated: false, forTextEntryMode: .search)
                self.updateQuery(transition.text)
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

        // If we're not editing, this is page URL display text.
        guard textField.isEditing else { return true }

        // If full URL text remains selected, user hasn't interacted with it yet.
        guard let selectedTextRange = textField.selectedTextRange,
              let selectedText = textField.text(in: selectedTextRange) else {
            return false
        }

        return selectedText == text
    }

}

// MARK: - OmniBarEditingStateViewControllerDelegate

extension DefaultOmniBarViewController: OmniBarEditingStateViewControllerDelegate {

    func onQueryUpdated(_ query: String) {
    }

    func onQuerySubmitted(_ query: String) {
        editingStateViewController?.dismissAnimated()
        omniDelegate?.onOmniQuerySubmitted(query)
    }

    func onPromptSubmitted(_ query: String, tools: [AIChatRAGTool]?) {
        editingStateViewController?.dismissAnimated { [weak self] in
            guard let self else { return }
            self.omniDelegate?.onPromptSubmitted(query, tools: tools)
        }
    }

    func onSelectFavorite(_ favorite: BookmarkEntity) {
        editingStateViewController?.dismissAnimated()
        omniDelegate?.onSelectFavorite(favorite)
    }

    func onEditFavorite(_ favorite: BookmarkEntity) {
        editingStateViewController?.dismissAnimated()
        omniDelegate?.onEditFavorite(favorite)
    }

    func onSelectSuggestion(_ suggestion: Suggestion) {
        omniDelegate?.onOmniSuggestionSelected(suggestion)
        editingStateViewController?.dismissAnimated()
    }

    func onVoiceSearchRequested(from mode: TextEntryMode) {
        editingStateViewController?.dismissAnimated { [weak self] in
            guard let self else { return }

            let voiceSearchTarget: VoiceSearchTarget = (mode == .aiChat) ? .AIChat : .SERP
            self.omniDelegate?.onVoiceSearchPressed(preferredTarget: voiceSearchTarget)
        }
    }

    func onChatHistorySelected(url: URL) {
        editingStateViewController?.dismissAnimated { [weak self] in
            guard let self else { return }
            self.omniDelegate?.onChatHistorySelected(url: url)
        }
    }

    func onDismissRequested() {
        // Restore the tab's committed mode — the user toggled but didn't submit.
        omniDelegate?.onExperimentalAddressBarCancelPressed()
        if let tabMode = omniDelegate?.preferredTextEntryModeForCurrentTab() {
            selectedTextEntryMode = tabMode
        }
    }

    func onSwitchToTab(_ tab: Tab) {
        omniDelegate?.onSwitchToTab(tab)
    }

    func onToggleModeSwitched(to mode: TextEntryMode) {
        // Sync the editing state's toggle back to selectedTextEntryMode so that
        // commitToggleStateToCurrentTab reads the correct value on submission.
        selectedTextEntryMode = mode
        omniDelegate?.onToggleModeSwitched()
    }

    func onVoiceModeRequested() {
        editingStateViewController?.dismissAnimated { [weak self] in
            guard let self else { return }
            self.omniDelegate?.onDuckAIVoiceModeRequested()
        }
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
            submitIPadDuckAIText(from: textView)
            return false
        }
        return true
    }

    func textViewDidChange(_ textView: UITextView) {
        let newQuery = textView.text ?? ""

        modeToggleTextModel.updateText(newQuery)

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

// MARK: - UIViewControllerTransitioningDelegate

extension DefaultOmniBarViewController: UIViewControllerTransitioningDelegate {

    func animationController(forPresented presented: UIViewController,
                             presenting: UIViewController,
                             source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        let useNew = (presented as? OmniBarEditingStateViewController)?.useNewTransitionBehaviour ?? false
        return UniversalOmniBarEditingStateTransition(isPresenting: true,
                                                      addressBarPosition: dependencies.appSettings.currentAddressBarPosition,
                                                      useNewTransitionBehaviour: useNew)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        UniversalOmniBarEditingStateTransition(isPresenting: false,
                                               addressBarPosition: dependencies.appSettings.currentAddressBarPosition)
    }
}
