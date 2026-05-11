//
//  SwitchBarTextEntryView.swift
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
import SwiftUI
import Combine
import DesignResourcesKitIcons
import Core

class SwitchBarTextEntryView: UIView {

    enum VoiceButtonAppearance {
        case automatic
        case microphone
        case aiVoicePlain
        /// Suppress the in-pill voice button (e.g. when an external flank already provides it).
        case hidden
    }

    private enum Constants {
        static let maxHeight: CGFloat = 120
        static let maxHeightWhenUsingFadeOutAnimation: CGFloat = 132
        static let minHeight: CGFloat = 44
        static let minHeightAIChat: CGFloat = 68
        static let fontSize: CGFloat = 16

        // Text container insets
        static let textTopInset: CGFloat = 12
        static let textBottomInset: CGFloat = 12
        static let textHorizontalInset: CGFloat = 12

        // Placeholder positioning
        static let placeholderTopOffset: CGFloat = 12
        static let placeholderHorizontalOffset: CGFloat = 16

        // Increased buttons spacing
        static let additionalVerticalButtonsPadding: CGFloat = 6

        // Matches UnifiedToggleInputView.Constants.animationDuration so icons ride the focus animation.
        static let buttonStateAnimationDuration: TimeInterval = 0.25
    }

    private let handler: SwitchBarHandling
    var voiceButtonAppearance: VoiceButtonAppearance {
        didSet {
            guard voiceButtonAppearance != oldValue else { return }
            updateButtonState()
        }
    }

    private let textView = SwitchBarTextView()
    private let placeholderLabel = UILabel()
    private var buttonsView = SwitchBarButtonsView()
    private var currentButtonState: SwitchBarButtonState {
        get { buttonsView.buttonState }
        set { buttonsView.buttonState = newValue }
    }

    private var currentMode: TextEntryMode {
        handler.currentToggleState
    }

    private var currentMinHeight: CGFloat {
        guard handler.isUsingFadeOutAnimation else {
            return Constants.minHeight
        }

        if currentMode == .search && !handler.isTopBarPosition {
            return Constants.minHeight
        }

        if currentMode == .aiChat {
            return handler.isTopBarPosition ? Constants.minHeightAIChat : Constants.minHeight
        }

        return Constants.minHeight
    }

    private var currentMaxHeight: CGFloat {
        handler.isUsingFadeOutAnimation ? Constants.maxHeightWhenUsingFadeOutAnimation : Constants.maxHeight
    }

    private var isUsingBottomBarIncreasedHeight: Bool {
        handler.isUsingExpandedBottomBarHeight
    }

    private var cancellables = Set<AnyCancellable>()

    private var heightConstraint: NSLayoutConstraint?
    private var buttonsTrailingConstraint: NSLayoutConstraint?

    private var wasTextEmptyForAutocorrection: Bool = true

    let textHeightChangeSubject = PassthroughSubject<Void, Never>()

    /// When true the text entry will expand the text when the selection changes, e.g.  If the user uses the space bar to move the caret then it updates the selection.
    ///   This gets set to true after selectAll() on the field gets call.
    var canExpandOnSelectionChange = false

    var hasBeenInteractedWith = false
    var isURL: Bool {
        // TODO some kind of text length check?
        URL(string: textView.text)?.navigationalScheme != nil
    }

    var onTextInputActivated: (() -> Void)?
    var onAIChatShortcutTapped: (() -> Void)?

    var isExpandable: Bool = false {
        didSet {
            updateTextViewHeight()
        }
    }

    /// A visible trailing button (e.g. stop-generating) forces `.natural` regardless of this
    /// value, so the placeholder doesn't sit lopsided under the icon.
    var placeholderTextAlignment: NSTextAlignment = .natural {
        didSet {
            updatePlaceholderAlignment()
        }
    }

    var isUsingIncreasedButtonPadding: Bool = false {
        didSet {
            updateButtonsPadding()
        }
    }

    var currentTextSelection: UITextRange? {
        get { textView.selectedTextRange }
        set { textView.selectedTextRange = newValue }
    }

    var placeholderTextColor: UIColor {
        get { placeholderLabel.textColor }
        set { placeholderLabel.textColor = newValue }
    }

    override var isFirstResponder: Bool {
        textView.isFirstResponder
    }

    // MARK: - Initialization
    init(handler: SwitchBarHandling, voiceButtonAppearance: VoiceButtonAppearance = .automatic) {
        self.handler = handler
        self.voiceButtonAppearance = voiceButtonAppearance
        super.init(frame: .zero)

        setupView()
        setupSubscriptions()
        updateButtonState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        applyFireModeAppearance(isFireTab: handler.isFireTab)

        let fontMetrics = UIFontMetrics(forTextStyle: .body)
        let textFont = fontMetrics.scaledFont(for: UIFont.systemFont(ofSize: Constants.fontSize))
        textView.font = textFont
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = UIColor.clear
        textView.textColor = UIColor(designSystemColor: .textPrimary)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.accessibilityIdentifier = "searchEntry"

        placeholderLabel.font = textFont
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = defaultPlaceholderColor

        // Truncate text in case it exceeds single line
        placeholderLabel.numberOfLines = 1
        placeholderLabel.lineBreakMode = .byTruncatingTail

        setupButtonsView()

        addSubview(textView)
        addSubview(placeholderLabel)
        addSubview(buttonsView)

        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        heightConstraint = heightAnchor.constraint(equalToConstant: currentMinHeight)
        heightConstraint?.isActive = true

        setupConstraints()

        updateButtonState()
        updateForCurrentMode()
        updateTextViewHeight()
        updateButtonsPadding()

        textView.onTouchesBeganHandler = self.onTextViewTouchesBegan
    }

    // MARK: - Setup Methods

    private func onTextViewTouchesBegan() {
        textView.onTouchesBeganHandler = nil
        hasBeenInteractedWith = true
        updateTextViewHeight()
    }

    private func setupButtonsView() {
        buttonsView.onClearTapped = { [weak self] in
            guard let self else { return }
            self.hasBeenInteractedWith = true
            self.fireClearButtonPressedPixel()
            
            self.textView.text = ""
            self.updatePlaceholderVisibility()
            self.updateButtonState()
            self.updateTextViewHeight()
            
            self.handler.clearText()
            self.handler.clearButtonTapped()
            
            self.wasTextEmptyForAutocorrection = false
            self.updateAutoCorrectionSetupForAIChat(for: "")
        }

        buttonsView.onVoiceTapped = { [weak self] in
            self?.handler.microphoneButtonTapped()
        }

        buttonsView.onSearchGoToTapped = { [weak self] in
            self?.handler.searchGoToButtonTapped()
        }

        buttonsView.onStopGeneratingTapped = { [weak self] in
            self?.handler.stopGeneratingButtonTapped()
        }

        buttonsView.onAIChatShortcutTapped = { [weak self] in
            self?.onAIChatShortcutTapped?()
        }
    }

    private func updateButtonsPadding() {
        buttonsTrailingConstraint?.constant = isUsingIncreasedButtonPadding ? -Constants.additionalVerticalButtonsPadding : 0
    }

    private func setupConstraints() {

        buttonsTrailingConstraint = buttonsView.trailingAnchor.constraint(equalTo: trailingAnchor)
        buttonsTrailingConstraint?.isActive = true

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),

            placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: Constants.placeholderHorizontalOffset),
            // Trail to the buttons so a visible stop / search-go-to / voice button truncates the
            // placeholder. When `.noButtons`, buttonsView has zero width so this is a no-op.
            placeholderLabel.trailingAnchor.constraint(equalTo: buttonsView.leadingAnchor),

            buttonsView.centerYAnchor.constraint(equalTo: placeholderLabel.centerYAnchor)
        ])
    }

    // MARK: - UI Updates

    private func updateForCurrentMode() {
        wasTextEmptyForAutocorrection = textView.text.isEmpty

        switch currentMode {
        case .search:
            placeholderLabel.text = UserText.searchDuckDuckGo
            textView.autocapitalizationType = .none
        case .aiChat:
            placeholderLabel.text = handler.hasSubmittedPrompt
                ? UserText.aiChatFollowUpPlaceholder
                : UserText.searchInputFieldPlaceholderDuckAI
            textView.autocapitalizationType = .sentences

            /// Auto-focus the text field when switching to duck.ai mode (OmniBar toggle only)
            /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210975209610640?focus=true
            if handler.isUsingFadeOutAnimation {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.window != nil else { return }
                    self.textView.becomeFirstResponder()
                }
            }
        }
        updateKeyboardConfiguration()
        updatePlaceholderVisibility()
        updateButtonState()
        updateTextViewHeight()
    }

    private func updateKeyboardConfiguration() {
        switch currentMode {
        case .search:
            textView.keyboardType = .webSearch
            textView.returnKeyType = .search
            disableAutoCorrectionAndSpellChecking()
        case .aiChat:
            textView.keyboardType = .default
            textView.returnKeyType = .go
            if handler.shouldDisableAutocorrectOnEmpty && textView.text.isEmpty {
                disableAutoCorrectionAndSpellChecking()
            } else {
                enableAutoCorrectionAndSpellChecking()
            }
        }

        textView.reloadInputViews()
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    private func updateButtonState() {
        // Update handler-side flags first so `handler.buttonState` reflects the new appearance.
        updateVoiceButtonStyle()
        let newButtonState = handler.buttonState

        if newButtonState != currentButtonState {
            // Snapshot crossfade so icons fade in/out without UIStackView's `isHidden` jank.
            UIView.transition(with: buttonsView,
                              duration: Constants.buttonStateAnimationDuration,
                              options: .transitionCrossDissolve) {
                UIView.performWithoutAnimation {
                    self.currentButtonState = newButtonState
                    self.adjustTextViewContentInset()
                    self.updatePlaceholderAlignment()
                    self.layoutIfNeeded()
                }
            }
        }
    }

    private func updatePlaceholderAlignment() {
        placeholderLabel.textAlignment = currentButtonState.showsAnyButton ? .natural : placeholderTextAlignment
    }

    private func updateVoiceButtonStyle() {
        handler.hidesVoiceButton = voiceButtonAppearance == .hidden
        let showsAIVoiceChatButton = handler.isAIVoiceChatEnabled && handler.currentToggleState == .aiChat
        switch voiceButtonAppearance {
        case .automatic:
            buttonsView.voiceButtonStyle = showsAIVoiceChatButton ? .aiVoiceAccent : .microphone
        case .microphone:
            buttonsView.voiceButtonStyle = .microphone
        case .aiVoicePlain:
            buttonsView.voiceButtonStyle = showsAIVoiceChatButton ? .aiVoicePlain : .microphone
        case .hidden:
            break
        }
    }

    private func adjustTextViewContentInset() {
        let buttonsIntersectionWidth = textView.frame.intersection(buttonsView.frame).width

        // Use default inset or the amount of how buttons interset with the view + required spacing
        let rightInset = currentButtonState.showsAnyButton ? buttonsIntersectionWidth : Constants.textHorizontalInset

        textView.textContainerInset = UIEdgeInsets(
            top: Constants.textTopInset,
            left: Constants.textHorizontalInset,
            bottom: Constants.textBottomInset,
            right: rightInset
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        adjustTextViewContentInset()
        if !hasBeenInteractedWith {
            updateTextViewHeight()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            /// Dynamic Type size changed, calculate views layout
            updateTextViewHeight()
            adjustTextViewContentInset()
        }
    }

    /// https://app.asana.com/1/137249556945/project/392891325557410/task/1210835160047733?focus=true
    private func isUnexpandedURL() -> Bool {
        return !hasBeenInteractedWith && isURL
    }

    private func updateTextViewHeight() {

        let currentHeight = heightConstraint?.constant
        defer {
            if currentHeight != heightConstraint?.constant {
                textHeightChangeSubject.send()
            }
        }

        // Reset defaults
        textView.textContainer.lineBreakMode = .byWordWrapping

        if isUnexpandedURL() ||
            // https://app.asana.com/1/137249556945/project/392891325557410/task/1210916875279070?focus=true
            (isExpandable ? textView.text.isEmpty : textView.text.isBlank) {

            /// When empty (or showing an unexpanded URL), size to one line  to avoid clipping at larger accessibility sizes.
            let requiredEmptyStateHeight = requiredHeightForSingleLineContent()
            heightConstraint?.constant = max(currentMinHeight, min(currentMaxHeight, requiredEmptyStateHeight))
            textView.isScrollEnabled = false
            textView.showsVerticalScrollIndicator = false
            textView.textContainer.lineBreakMode = .byTruncatingTail
        } else if isExpandable {
            let contentHeight = getCurrentContentHeight()
            let contentExceedsMaxHeight = contentHeight > currentMaxHeight

            let newHeight: CGFloat
            if isUsingBottomBarIncreasedHeight {
                let singleLineHeight = requiredHeightForSingleLineContent()
                let textRequiresMultipleLines = contentHeight > singleLineHeight + 1
                if textRequiresMultipleLines {
                    newHeight = max(currentMinHeight, min(currentMaxHeight, contentHeight))
                } else {
                    newHeight = currentMinHeight
                }
            } else {
                newHeight = max(currentMinHeight, min(currentMaxHeight, contentHeight))
            }

            heightConstraint?.constant = newHeight

            textView.isScrollEnabled = contentExceedsMaxHeight
            textView.showsVerticalScrollIndicator = contentExceedsMaxHeight
        } else {
            heightConstraint?.constant = currentMinHeight
            textView.isScrollEnabled = true
            textView.showsVerticalScrollIndicator = true
            return
        }

        adjustScrollPosition()
    }

    private func getCurrentContentHeight() -> CGFloat {
        let previousScrollSetting = textView.isScrollEnabled
        defer {
            textView.isScrollEnabled = previousScrollSetting
        }

        textView.isScrollEnabled = false
        return textView.systemLayoutSizeFitting(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude)).height
    }

    /// Computes the min height for one line given current fonts/insets, using the larger of the text view or placeholder font.
    private func requiredHeightForSingleLineContent() -> CGFloat {
        let textLineHeight = (textView.font ?? UIFont.systemFont(ofSize: Constants.fontSize)).lineHeight
        let textNeeded = textLineHeight + Constants.textTopInset + Constants.textBottomInset

        let placeholderLineHeight = placeholderLabel.font.lineHeight
        let placeholderNeeded = placeholderLineHeight + Constants.placeholderTopOffset + Constants.textBottomInset

        return ceil(max(textNeeded, placeholderNeeded))
    }

    private func adjustScrollPosition() {

        guard !hasBeenInteractedWith, !textView.text.isEmpty else {
            return
        }

        var range: NSRange?
        if isURL {
            range = NSRange(location: 0, length: 0)
        } else {
            range = NSRange(location: textView.text.count, length: 0)
        }

        if let range {
            textView.scrollRangeToVisible(range)
        }
    }

    func refreshFireMode(fireMode: Bool) {
        applyFireModeAppearance(isFireTab: fireMode)
    }

    private func applyFireModeAppearance(isFireTab: Bool) {
        overrideUserInterfaceStyle = isFireTab ? .dark : .unspecified
        textView.tintColor = isFireTab
            ? UIColor(singleUseColor: .fireModeAccent)
            : UIColor(designSystemColor: .accent)
    }

    private func setupSubscriptions() {
        handler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }

                if self.handler.isUsingFadeOutAnimation {
                    self.window?.layoutIfNeeded()
                    self.updateForCurrentMode()
                    UIView.animate(withDuration: 0.25) {
                        self.window?.layoutIfNeeded()
                    }
                } else {
                    self.updateForCurrentMode()
                }
            }
            .store(in: &cancellables)

        handler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self = self else { return }
                
                if self.textView.text != text {
                    // Don't overwrite text while user is actively typing - the publisher
                    // may deliver stale values due to async scheduling, which would
                    // interfere with iOS autocomplete.
                    // Note: Clear button updates textView directly to avoid race conditions.
                    let isUserActivelyTyping = self.textView.isFirstResponder && self.hasBeenInteractedWith
                    let isNewLineInsertion = text == (self.textView.text ?? "") + "\n"
                    
                    guard !isUserActivelyTyping || isNewLineInsertion else { return }
                    
                    self.textView.text = text
                    self.updatePlaceholderVisibility()
                    self.updateTextViewHeight()
                }
                
                self.updateAutoCorrectionSetupForAIChat(for: self.textView.text ?? "")
            }
            .store(in: &cancellables)

        handler.currentButtonStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.updateButtonState()
            }
            .store(in: &cancellables)

        handler.hasSubmittedPromptPublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.currentMode == .aiChat else { return }
                self.placeholderLabel.text = self.handler.hasSubmittedPrompt
                    ? UserText.aiChatFollowUpPlaceholder
                    : UserText.searchInputFieldPlaceholderDuckAI
            }
            .store(in: &cancellables)
    }

    private func updateAutoCorrectionSetupForAIChat(for text: String) {
        guard handler.shouldDisableAutocorrectOnEmpty, currentMode == .aiChat else { return }

        let isTextEmpty = text.isEmpty
        let stateChanged = isTextEmpty != wasTextEmptyForAutocorrection
        guard stateChanged else { return }

        wasTextEmptyForAutocorrection = isTextEmpty

        if isTextEmpty {
            disableAutoCorrectionAndSpellChecking()
        } else {
            textView.keyboardType = currentMode == .aiChat ? .default : .webSearch
            textView.returnKeyType = currentMode == .aiChat ? .go : .search
            enableAutoCorrectionAndSpellChecking()
        }

        textView.reloadInputViews()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return textView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        return textView.resignFirstResponder()
    }

    func selectAllText() {
        if !hasBeenInteractedWith {
            hasBeenInteractedWith = true
            updateTextViewHeight()
        }
        textView.selectAll(nil)
        canExpandOnSelectionChange = true
    }

    func setQueryText(_ text: String) {
        textView.text = text
        updatePlaceholderVisibility()
        updateButtonState()
        updateTextViewHeight()
        handler.updateCurrentText(text)
    }

    /// Reflects the current transform; reset the shift to zero before reading the natural x.
    var placeholderWindowX: CGFloat? {
        guard placeholderLabel.window != nil else { return nil }
        return placeholderLabel.convert(CGPoint.zero, to: nil).x
    }

    /// Stable design-token color, immune to transient `textColor` changes from color crossfades.
    /// `.textTertiary` matches the spec ("Text/Placeholder, Labels/Tertiary, System/System Text Tertiary").
    var defaultPlaceholderColor: UIColor { UIColor(designSystemColor: .textTertiary) }

    // Two transient overlays composite directly over the parent background (the original label is
    // cleared) so a low-alpha source/target color isn't stacked atop the destination color, which
    // would otherwise composite darker than either color alone.
    func animatePlaceholderColorTransition(from: UIColor, to color: UIColor, duration: TimeInterval) {
        let bounds = placeholderLabel.bounds
        guard bounds.width > 0, bounds.height > 0, !(placeholderLabel.text ?? "").isEmpty else {
            placeholderLabel.textColor = color
            return
        }
        guard !from.isEqual(color) else {
            placeholderLabel.textColor = color
            return
        }

        placeholderLabel.textColor = .clear
        let sourceOverlay = makePlaceholderColorOverlay(color: from, frame: bounds, alpha: 1)
        let targetOverlay = makePlaceholderColorOverlay(color: color, frame: bounds, alpha: 0)
        placeholderLabel.addSubview(sourceOverlay)
        placeholderLabel.addSubview(targetOverlay)

        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseOut, animations: {
            sourceOverlay.alpha = 0
            targetOverlay.alpha = 1
        }, completion: { [weak self] _ in
            self?.placeholderLabel.textColor = color
            sourceOverlay.removeFromSuperview()
            targetOverlay.removeFromSuperview()
        })
    }

    private func makePlaceholderColorOverlay(color: UIColor, frame: CGRect, alpha: CGFloat) -> UILabel {
        let overlay = UILabel()
        overlay.text = placeholderLabel.text
        overlay.font = placeholderLabel.font
        overlay.textColor = color
        overlay.textAlignment = placeholderLabel.textAlignment
        overlay.adjustsFontForContentSizeCategory = placeholderLabel.adjustsFontForContentSizeCategory
        overlay.frame = frame
        overlay.isUserInteractionEnabled = false
        overlay.alpha = alpha
        return overlay
    }

    func setTextHorizontalShift(_ shift: CGFloat) {
        let transform = shift == 0 ? .identity : CGAffineTransform(translationX: shift, y: 0)
        textView.transform = transform
        placeholderLabel.transform = transform
    }

    @discardableResult
    func alignPlaceholderHorizontally(toWindowX windowX: CGFloat) -> CGFloat {
        setTextHorizontalShift(0)
        guard placeholderLabel.window != nil else { return 0 }
        let currentX = placeholderLabel.convert(CGPoint.zero, to: nil).x
        let shift = windowX - currentX
        setTextHorizontalShift(shift)
        return shift
    }

    private func disableAutoCorrectionAndSpellChecking() {
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
    }

    private func enableAutoCorrectionAndSpellChecking() {
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
    }
}

extension SwitchBarTextEntryView: UITextViewDelegate {

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard canExpandOnSelectionChange else { return }
        textViewDidChange(textView)
        canExpandOnSelectionChange = false
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        onTextInputActivated?()
        fireTextAreaFocusedPixel()
    }

    func textViewDidChange(_ textView: UITextView) {
        hasBeenInteractedWith = true
        
        updatePlaceholderVisibility()
        updateButtonState()
        updateTextViewHeight()
        handler.updateCurrentText((textView.text ?? "").strippingDictationPlaceholder)
        handler.markUserInteraction()

        // On iPad, reload input views on each keystroke (old behavior, without fade-out animation)
        // On iPhone, skip reloadInputViews() as it causes the publisher to deliver
        // stale text values that interfere with iOS autocomplete.
        // https://app.asana.com/1/137249556945/inbox/1210947754150827/item/1212750684390654/story/1212749500239461?focus=true
        if !handler.isUsingFadeOutAnimation {
            textView.reloadInputViews()
        }
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            fireKeyboardGoPressedPixel()
            let currentText = textView.text ?? ""
            if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handler.submitText(currentText)
            }
            return false
        }
        return true
    }
}

// MARK: Pixels

private extension SwitchBarTextEntryView {
    func fireTextAreaFocusedPixel() {
        let parameters = ["orientation": UIDevice.current.orientation.orientationDescription]
        Pixel.fire(pixel: .aiChatExperimentalOmnibarTextAreaFocused, withAdditionalParameters: parameters)
    }
    
    func fireClearButtonPressedPixel() {
        Pixel.fire(pixel: .aiChatExperimentalOmnibarClearButtonPressed, withAdditionalParameters: handler.modeParameters)
    }
    
    func fireKeyboardGoPressedPixel() {
        Pixel.fire(pixel: .aiChatExperimentalOmnibarKeyboardGoPressed, withAdditionalParameters: handler.modeParameters)
    }
}

// MARK: Other extensions

private extension UIDeviceOrientation {
    var orientationDescription: String {
        isLandscape ? "landscape" : "portrait"
    }
}
