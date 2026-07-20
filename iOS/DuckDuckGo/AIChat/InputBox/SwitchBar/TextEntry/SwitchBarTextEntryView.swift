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

    private enum TextEntryPose: Equatable {
        case compact
        case tallTopAlignedAIChat

        var usesTopAlignedPlaceholder: Bool {
            switch self {
            case .compact:
                return false
            case .tallTopAlignedAIChat:
                return true
            }
        }
    }

    private enum Constants {
        static let maxHeight: CGFloat = 120
        static let maxHeightWhenUsingFadeOutAnimation: CGFloat = 132
        static let minHeight: CGFloat = 44
        static let minHeightAIChat: CGFloat = 51
        static let fontSize: CGFloat = 16

        // Legacy Layout
        static let legacyMinHeightAIChat: CGFloat = 68
        static let legacyTextHorizontalInset: CGFloat = 12
        static let legacyPlaceholderHorizontalOffset: CGFloat = 16

        // Text container insets
        static let textTopInset: CGFloat = 12
        static let textBottomInset: CGFloat = 12
        static let textHorizontalInset: CGFloat = 16

        // Placeholder positioning
        static let placeholderTopOffset: CGFloat = 12
        static let placeholderHorizontalOffset: CGFloat = 20

        // Increased buttons spacing
        static let additionalVerticalButtonsPadding: CGFloat = 6

        // Matches UnifiedToggleInputView.Constants.animationDuration so icons ride the focus animation.
        static let buttonStateAnimationDuration: TimeInterval = 0.25

        /// Horizontal distance the duck.ai chip slides during the dismiss snapshot so it lands
        /// at the unfocused omnibar's chat-icon position. Positive = right.
        static let dismissedChipHorizontalOffset: CGFloat = 6
    }

    private let handler: SwitchBarHandling
    private(set) var voiceButtonAppearance: VoiceButtonAppearance

    enum Style {
        /// Single-line UITextField with native horizontal scroll. Used when there is no
        /// Search↔Duck.ai toggle (search-only mode).
        case singleLine
        /// Expanding UITextView composer. Used when the toggle is present.
        case multiLine
    }

    var style: Style = .multiLine {
        didSet {
            guard style != oldValue else { return }
            let wasFirstResponder = textView.isFirstResponder || textField.isFirstResponder

            // Unhide and populate the incoming control before touching first responder.
            if style == .singleLine {
                textField.text = handler.currentText
                textField.isHidden = false
            } else {
                textView.text = handler.currentText
                textView.isHidden = false
            }

            // Without this the caret animates in from a stale position, because the style flip runs
            // inside the coordinator's mode-change UIView.animate. updateTextViewHeight stays outside
            // so the height still animates with that transaction.
            UIView.performWithoutAnimation {
                adjustTextViewContentInset()
                if wasFirstResponder { _ = becomeFirstResponder() }
                if style == .singleLine && textView.isFirstResponder { _ = textView.resignFirstResponder() }
                if style == .multiLine && textField.isFirstResponder { _ = textField.resignFirstResponder() }
                syncActiveControl()
                updatePlaceholderVisibility()
                updateKeyboardConfiguration()
                (usesTextField ? textField : textView).layoutIfNeeded()
            }

            updateTextViewHeight()
        }
    }

    private var usesTextField: Bool { style == .singleLine }

    /// Pass `animated: false` when the caller drives its own animation — the snapshot crossfade
    /// would otherwise capture the old layout and drift as the parent moves.
    func setVoiceButtonAppearance(_ appearance: VoiceButtonAppearance, animated: Bool = true) {
        guard appearance != voiceButtonAppearance else { return }
        voiceButtonAppearance = appearance
        updateButtonState(animated: animated)
    }

    private let textView = SwitchBarTextView()
    private let textField = SwitchBarTextField()
    private let placeholderLabel = UILabel()
    private var buttonsView = SwitchBarButtonsView()
    private var currentButtonState: SwitchBarButtonState {
        get { buttonsView.buttonState }
        set { buttonsView.buttonState = newValue }
    }

    private var currentMode: TextEntryMode {
        handler.currentToggleState
    }

    private var currentPose: TextEntryPose {
        if isExpandable && currentMode == .aiChat && handler.isTopBarPosition && handler.usesExpandedAIChatTextEntryLayout {
            return .tallTopAlignedAIChat
        }

        return .compact
    }

    // The tall AIChat height is shared by both the UTI and the legacy iPhone path, so it tracks
    // `usesExpandedAIChatTextEntryLayout` (true for both).
    private var minHeightAIChat: CGFloat {
        handler.usesLegacyLayoutMetrics ? Constants.legacyMinHeightAIChat : Constants.minHeightAIChat
    }

    // The horizontal insets/offsets only revert on the legacy (non-UTI) path. The UTI keeps the new
    // metrics even though it also reports `usesExpandedAIChatTextEntryLayout == true`.
    private var textHorizontalInset: CGFloat {
        handler.usesLegacyLayoutMetrics ? Constants.legacyTextHorizontalInset : Constants.textHorizontalInset
    }

    private var placeholderHorizontalOffset: CGFloat {
        handler.usesLegacyLayoutMetrics ? Constants.legacyPlaceholderHorizontalOffset : Constants.placeholderHorizontalOffset
    }

    private var currentMinHeight: CGFloat {
        if currentPose == .tallTopAlignedAIChat {
            return minHeightAIChat
        }

        guard handler.isUsingFadeOutAnimation else {
            return Constants.minHeight
        }

        if currentMode == .search && !handler.isTopBarPosition {
            return Constants.minHeight
        }

        if currentMode == .aiChat {
            return handler.isTopBarPosition ? minHeightAIChat : Constants.minHeight
        }

        return Constants.minHeight
    }

    /// Optional ceiling imposed by the host when vertical space is constrained (e.g. landscape,
    /// where the keyboard leaves little room). The field caps at this height and scrolls internally.
    var externalMaxHeightCap: CGFloat? {
        didSet {
            guard externalMaxHeightCap != oldValue else { return }
            updateTextViewHeight()
        }
    }

    private var currentMaxHeight: CGFloat {
        let base = handler.isUsingFadeOutAnimation ? Constants.maxHeightWhenUsingFadeOutAnimation : Constants.maxHeight
        guard let externalMaxHeightCap else { return base }
        return max(currentMinHeight, min(base, externalMaxHeightCap))
    }

    private var isUsingBottomBarIncreasedHeight: Bool {
        handler.isUsingExpandedBottomBarHeight
    }

    private var usesTopAlignedPlaceholder: Bool {
        currentPose.usesTopAlignedPlaceholder
    }

    private var cancellables = Set<AnyCancellable>()

    private var heightConstraint: NSLayoutConstraint?
    private var buttonsTrailingConstraint: NSLayoutConstraint?
    private var placeholderTopConstraint: NSLayoutConstraint?
    private var placeholderCenterYConstraint: NSLayoutConstraint?

    private var wasTextEmptyForAutocorrection: Bool = true

    let textHeightChangeSubject = PassthroughSubject<Void, Never>()

    /// When true the text entry will expand the text when the selection changes, e.g.  If the user uses the space bar to move the caret then it updates the selection.
    ///   This gets set to true after selectAll() on the field gets call.
    var canExpandOnSelectionChange = false

    var hasBeenInteractedWith = false
    var isURL: Bool {
        let text = usesTextField ? (textField.text ?? "") : (textView.text ?? "")
        return URL(string: text)?.navigationalScheme != nil
    }

    var onTextInputActivated: (() -> Void)?
    var onAIChatShortcutTapped: (() -> Void)?

    var isExpandable: Bool = false {
        didSet {
            updatePoseForCurrentState()
        }
    }

    func updatePoseForCurrentState() {
        updatePlaceholderVerticalAlignment()
        updateTextViewHeight()
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
        get { usesTextField ? textField.selectedTextRange : textView.selectedTextRange }
        set {
            if usesTextField {
                textField.selectedTextRange = newValue
            } else {
                textView.selectedTextRange = newValue
            }
        }
    }

    var placeholderTextColor: UIColor {
        get { placeholderLabel.textColor }
        set { placeholderLabel.textColor = newValue }
    }

    override var isFirstResponder: Bool {
        usesTextField ? textField.isFirstResponder : textView.isFirstResponder
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

        // Match the omnibar's placeholder font so UTI ↔ omnibar transitions don't show a size jump.
        let textFont = UIFont.daxBodyRegular()
        textView.font = textFont
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = UIColor.clear
        textView.textColor = UIColor(designSystemColor: .textPrimary)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false

        placeholderLabel.font = textFont
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = defaultPlaceholderColor

        // Truncate text in case it exceeds single line
        placeholderLabel.numberOfLines = 1
        placeholderLabel.lineBreakMode = .byTruncatingTail

        setupButtonsView()

        addSubview(textView)
        addSubview(textField)
        addSubview(placeholderLabel)
        addSubview(buttonsView)

        buttonsView.translatesAutoresizingMaskIntoConstraints = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        heightConstraint = heightAnchor.constraint(equalToConstant: currentMinHeight)
        heightConstraint?.isActive = true

        setupConstraints()

        updateButtonState()
        updateForCurrentMode()
        updateTextViewHeight()
        updateButtonsPadding()

        textView.onTouchesBeganHandler = self.onTextViewTouchesBegan

        let tintColor: UIColor = handler.isFireTab
            ? UIColor(singleUseColor: .fireModeAccent)
            : UIColor(designSystemColor: .accentPrimary)
        textField.font = textFont
        textField.adjustsFontForContentSizeCategory = true
        textField.textColor = UIColor(designSystemColor: .textPrimary)
        textField.tintColor = tintColor
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.keyboardType = .webSearch
        textField.returnKeyType = .search
        textField.delegate = self
        textField.addTarget(self, action: #selector(textFieldEditingChanged), for: .editingChanged)
        syncActiveControl()
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

            if self.usesTextField {
                self.textField.text = ""
            } else {
                self.textView.text = ""
            }
            self.updatePlaceholderVisibility()
            self.updateButtonState(animated: false)
            self.updateTextViewHeight()

            self.handler.clearText()
            self.handler.clearButtonTapped()

            self.wasTextEmptyForAutocorrection = false
            self.updateAutoCorrectionSetupForAIChat(for: "")
        }

        buttonsView.onVoiceTapped = { [weak self] in
            self?.handler.microphoneButtonTapped()
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
        let placeholderTopConstraint = placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: Constants.placeholderTopOffset)
        let placeholderCenterYConstraint = placeholderLabel.centerYAnchor.constraint(equalTo: textView.centerYAnchor)
        self.placeholderTopConstraint = placeholderTopConstraint
        self.placeholderCenterYConstraint = placeholderCenterYConstraint
        placeholderTopConstraint.isActive = false

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),

            textField.topAnchor.constraint(equalTo: topAnchor),
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),

            placeholderCenterYConstraint,
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: placeholderHorizontalOffset),
            // Trail to the buttons so a visible stop / search-go-to / voice button truncates the
            // placeholder. When `.noButtons`, buttonsView has zero width so this is a no-op.
            placeholderLabel.trailingAnchor.constraint(equalTo: buttonsView.leadingAnchor),

            // Pin to the top row so the button stays top-right when the field grows multi-line.
            buttonsView.centerYAnchor.constraint(equalTo: topAnchor, constant: Constants.minHeight / 2)
        ])
    }

    // MARK: - UI Updates

    /// Visual-only render override for the dismiss collapse so the UTI lands on the omnibar's
    /// destination state. Handler is untouched — `currentTextPublisher` runs async via main-queue
    /// dispatch, so clearing it here would clobber `textView.text` mid-collapse. The real handler
    /// reset happens at dismiss completion via the coordinator's `clearText()`.
    func applyDismissSnapshot(_ snapshot: UTIDismissSnapshot) {
        if usesTextField {
            textField.text = snapshot.text
        } else {
            textView.text = snapshot.text
        }
        setPlaceholderText(placeholderText(for: snapshot.placeholderMode))
        updatePlaceholderVisibility()
        // State lags dismiss — hide non-chip buttons explicitly so they don't collide with the
        // omnibar icons fading in. Chip stays animatable to crossfade with the omnibar's aiChat.
        buttonsView.setNonChipButtonsAlpha(0)
        buttonsView.setAIChatShortcutDismissed(true,
                                                duration: Constants.buttonStateAnimationDuration,
                                                horizontalOffset: Constants.dismissedChipHorizontalOffset)
    }

    /// Restore the override applied by `applyDismissSnapshot` so the reused view re-presents
    /// in sync with the handler — chip visible at its resting position.
    func clearDismissSnapshot() {
        buttonsView.setNonChipButtonsAlpha(1)
        buttonsView.setAIChatShortcutDismissed(false, duration: Constants.buttonStateAnimationDuration)
        setPlaceholderText(placeholderText(for: currentMode))
        let currentText = handler.currentText
        if usesTextField {
            if textField.text != currentText {
                textField.text = currentText
                updatePlaceholderVisibility()
            }
            // Sync button state to handler so textRightInset reflects any text already set
            // by the coordinator before this method was called.
            updateButtonState(animated: false)
        } else {
            if textView.text != currentText {
                textView.text = currentText
                updatePlaceholderVisibility()
            }
            updateButtonState(animated: false)
        }
    }

    private func syncActiveControl() {
        let useField = usesTextField
        textView.isHidden = useField
        textField.isHidden = !useField
        textView.accessibilityIdentifier = useField ? nil : "searchEntry"
        textField.accessibilityIdentifier = useField ? "searchEntry" : nil
    }

    // Keeps in-flight color-transition overlays in sync so their captured text doesn't
    // composite over the new text mid-animation.
    private func setPlaceholderText(_ text: String) {
        placeholderLabel.text = text
        for case let overlay as UILabel in placeholderLabel.subviews {
            overlay.text = text
        }
    }

    // Sync hook used by the coordinator to beat the async `hasSubmittedPromptPublisher`
    // sink before the flanked UTI first renders.
    func refreshPlaceholderForCurrentMode() {
        setPlaceholderText(placeholderText(for: currentMode))
    }

    private func placeholderText(for mode: TextEntryMode) -> String {
        switch mode {
        case .search:
            return UserText.searchDuckDuckGo
        case .aiChat:
            if handler.hasSubmittedPrompt {
                return UserText.aiChatFollowUpPlaceholder
            }
            return handler.isImageGenerationSelected
                ? UserText.aiChatImageGenerationPlaceholder
                : UserText.searchInputFieldPlaceholderDuckAI
        }
    }

    private func updateForCurrentMode() {
        wasTextEmptyForAutocorrection = textView.text.isEmpty

        setPlaceholderText(placeholderText(for: currentMode))
        switch currentMode {
        case .search:
            textView.autocapitalizationType = .none
        case .aiChat:
            textView.autocapitalizationType = .sentences

            /// Auto-focus the text field when switching to duck.ai mode (OmniBar toggle only)
            /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210975209610640?focus=true
            if handler.isUsingFadeOutAnimation {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.window != nil else { return }
                    self.becomeFirstResponder()
                }
            }
        }
        updateKeyboardConfiguration()
        updatePoseForCurrentState()
        updatePlaceholderVisibility()
        updateButtonState()
    }

    private func updateKeyboardConfiguration() {
        if usesTextField {
            textField.keyboardType = .webSearch
            textField.returnKeyType = .search
            textField.reloadInputViews()
            return
        }
        switch currentMode {
        case .search:
            textView.keyboardType = .webSearch
            textView.returnKeyType = .search
            disableAutoCorrectionAndSpellChecking()
        case .aiChat:
            textView.keyboardType = .default
            textView.returnKeyType = aiChatReturnKeyType
            if handler.shouldDisableAutocorrectOnEmpty && textView.text.isEmpty {
                disableAutoCorrectionAndSpellChecking()
            } else {
                enableAutoCorrectionAndSpellChecking()
            }
        }

        textView.reloadInputViews()
    }

    private func updatePlaceholderVisibility() {
        let text = usesTextField ? (textField.text ?? "") : (textView.text ?? "")
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func updateButtonState(animated: Bool = true) {
        // Update handler-side flags first so `handler.buttonState` reflects the new appearance.
        updateVoiceButtonStyle()
        let newButtonState = handler.buttonState

        guard newButtonState != currentButtonState else { return }

        let apply = {
            UIView.performWithoutAnimation {
                self.currentButtonState = newButtonState
                self.adjustTextViewContentInset()
                self.updatePlaceholderAlignment()
                self.layoutIfNeeded()
            }
        }

        if animated {
            if usesTextField {
                // Apply inset before crossfade so UITextField's editingRect is at its final width
                // when the button fades in — the change is instant and visible otherwise.
                apply()
                UIView.transition(with: buttonsView,
                                  duration: Constants.buttonStateAnimationDuration,
                                  options: .transitionCrossDissolve,
                                  animations: {})
            } else {
                UIView.transition(with: buttonsView,
                                  duration: Constants.buttonStateAnimationDuration,
                                  options: .transitionCrossDissolve,
                                  animations: apply)
            }
        } else {
            apply()
        }
    }

    private func updatePlaceholderAlignment() {
        placeholderLabel.textAlignment = currentButtonState.showsAnyButton ? .natural : placeholderTextAlignment
    }

    private func updatePlaceholderVerticalAlignment() {
        guard placeholderTopConstraint?.isActive != usesTopAlignedPlaceholder else { return }

        if usesTopAlignedPlaceholder {
            placeholderCenterYConstraint?.isActive = false
            placeholderTopConstraint?.isActive = true
        } else {
            placeholderTopConstraint?.isActive = false
            placeholderCenterYConstraint?.isActive = true
        }
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
        // lineFragmentPadding (5pt default, never overridden) pads the glyph from the container
        // edge. UITextField uses textRect insets to match UITextView's effective glyph start.
        let fragmentPadding = textView.textContainer.lineFragmentPadding

        if usesTextField {
            let fittingWidth = buttonsView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).width
            let buttonsWidth = currentButtonState.showsAnyButton ? fittingWidth : 0
            let rightInset = buttonsWidth > 0 ? buttonsWidth : textHorizontalInset
            textField.textLeftInset = textHorizontalInset + fragmentPadding
            textField.textRightInset = rightInset + fragmentPadding
        } else {
            let buttonsIntersectionWidth = textView.frame.intersection(buttonsView.frame).width
            let rightInset = currentButtonState.showsAnyButton ? buttonsIntersectionWidth : textHorizontalInset
            textView.textContainerInset = UIEdgeInsets(
                top: Constants.textTopInset,
                left: textHorizontalInset,
                bottom: Constants.textBottomInset,
                right: rightInset
            )
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // UITextField inset is pre-computed from intrinsic button sizes and only changes when
        // button state changes — skip recomputing on every animation-frame layout pass.
        if !usesTextField {
            adjustTextViewContentInset()
        }
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
    /// UITextField (search-only) returns before reaching this method. Only reached when
    /// toggle is present — URL stays single-line until the user has actively interacted.
    private func isUnexpandedURL() -> Bool {
        guard isURL else { return false }
        return !hasBeenInteractedWith
    }

    private func updateTextViewHeight() {

        let currentHeight = heightConstraint?.constant
        defer {
            if currentHeight != heightConstraint?.constant {
                textHeightChangeSubject.send()
            }
        }

        if usesTextField {
            let requiredHeight = requiredHeightForSingleLineContent()
            heightConstraint?.constant = max(currentMinHeight, min(currentMaxHeight, requiredHeight))
            return
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

        guard !usesTextField, !hasBeenInteractedWith, !textView.text.isEmpty else {
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
        let tintColor: UIColor = isFireTab
            ? UIColor(singleUseColor: .fireModeAccent)
            : UIColor(designSystemColor: .accentPrimary)
        textView.tintColor = tintColor
        textField.tintColor = tintColor
    }

    private func setupSubscriptions() {
        handler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                // Snap — animating the buttonsView-driven width change reveals the new placeholder
                // tail progressively. Pose Y is animated by `setInputMode`'s outer UIView.animate.
                UIView.performWithoutAnimation {
                    self.updateForCurrentMode()
                    self.layoutIfNeeded()
                }
            }
            .store(in: &cancellables)

        handler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] text in
                guard let self = self else { return }

                if self.usesTextField {
                    if (self.textField.text ?? "") != text {
                        // Don't overwrite text while user is actively typing.
                        let isUserActivelyTyping = self.textField.isFirstResponder && self.hasBeenInteractedWith
                        guard !isUserActivelyTyping else { return }
                        self.textField.text = text
                        self.updatePlaceholderVisibility()
                        self.updateTextViewHeight()
                    }
                } else {
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
                self.setPlaceholderText(self.placeholderText(for: .aiChat))
                self.updateKeyboardConfiguration()
            }
            .store(in: &cancellables)

        handler.submitsAIChatOnKeyboardReturnPublisher
            .receive(on: DispatchQueue.main)
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, self.currentMode == .aiChat else { return }
                self.updateKeyboardConfiguration()
            }
            .store(in: &cancellables)
    }

    private func updateAutoCorrectionSetupForAIChat(for text: String) {
        guard !usesTextField, handler.shouldDisableAutocorrectOnEmpty, currentMode == .aiChat else { return }

        let isTextEmpty = text.isEmpty
        let stateChanged = isTextEmpty != wasTextEmptyForAutocorrection
        guard stateChanged else { return }

        wasTextEmptyForAutocorrection = isTextEmpty

        if isTextEmpty {
            disableAutoCorrectionAndSpellChecking()
        } else {
            textView.keyboardType = currentMode == .aiChat ? .default : .webSearch
            textView.returnKeyType = currentMode == .aiChat ? aiChatReturnKeyType : .search
            enableAutoCorrectionAndSpellChecking()
        }

        textView.reloadInputViews()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        return usesTextField ? textField.becomeFirstResponder() : textView.becomeFirstResponder()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        return usesTextField ? textField.resignFirstResponder() : textView.resignFirstResponder()
    }

    func selectAllText() {
        if !hasBeenInteractedWith {
            hasBeenInteractedWith = true
            updateTextViewHeight()
        }
        if usesTextField {
            // UIResponder.selectAll(_:) is unreliable on UITextField — use selectedTextRange directly.
            textField.selectedTextRange = textField.textRange(from: textField.beginningOfDocument,
                                                               to: textField.endOfDocument)
        } else {
            textView.selectAll(nil)
            canExpandOnSelectionChange = true
        }
    }

    func setQueryText(_ text: String) {
        if usesTextField {
            textField.text = text
        } else {
            textView.text = text
        }
        updatePlaceholderVisibility()
        // Handler first so `updateButtonState` reads the fresh state synchronously.
        handler.updateCurrentText(text)
        updateButtonState()
        updateTextViewHeight()
    }

    func insertNewlineAtCursor() {
        guard !usesTextField else { return }
        let selectedRange = textView.selectedTextRange
            ?? textView.textRange(from: textView.endOfDocument, to: textView.endOfDocument)
        if let selectedRange {
            textView.replace(selectedRange, withText: "\n")
        } else {
            textView.text.append("\n")
        }
        textViewDidChange(textView)
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
        if usesTextField {
            textField.transform = transform
        } else {
            textView.transform = transform
        }
        placeholderLabel.transform = transform
    }

    /// Shifts text so its first glyph (not caret) lands at `windowX` — UITextView's caret sits
    /// 1pt left of its glyph (`lineFragmentPadding`).
    @discardableResult
    func alignVisibleTextLeadingEdge(toWindowX windowX: CGFloat) -> CGFloat {
        setTextHorizontalShift(0)
        guard placeholderLabel.window != nil else { return 0 }
        let shift = windowX - visibleTextLeadingWindowX
        setTextHorizontalShift(shift)
        return shift
    }

    private var visibleTextLeadingWindowX: CGFloat {
        if placeholderLabel.isHidden {
            if usesTextField {
                // Use textLeftInset, not firstRect — firstRect reflects internal scroll state
                // and gives wrong values during the dismiss animation.
                return textField.convert(CGPoint(x: textField.textLeftInset, y: 0), to: nil).x
            } else if let end = textView.position(from: textView.beginningOfDocument, offset: 1),
                      let range = textView.textRange(from: textView.beginningOfDocument, to: end) {
                return textView.convert(textView.firstRect(for: range).origin, to: nil).x
            }
        }
        return placeholderLabel.convert(CGPoint.zero, to: nil).x
    }

    @objc private func textFieldEditingChanged() {
        hasBeenInteractedWith = true
        updatePlaceholderVisibility()
        handler.updateCurrentText((textField.text ?? "").strippingDictationPlaceholder)
        updateButtonState()
        updateTextViewHeight()
        handler.markUserInteraction()
    }

    private func disableAutoCorrectionAndSpellChecking() {
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
    }

    private func enableAutoCorrectionAndSpellChecking() {
        textView.autocorrectionType = .default
        textView.spellCheckingType = .default
    }

    private var aiChatReturnKeyType: UIReturnKeyType {
        handler.submitsAIChatOnKeyboardReturn ? .go : .default
    }
}

extension SwitchBarTextEntryView: UITextViewDelegate {

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard canExpandOnSelectionChange else { return }
        canExpandOnSelectionChange = false
        // A selection change (e.g. the select-all on focus) only needs the expandable-height
        // recompute — it is NOT a text edit, so it must not run the full `textViewDidChange`
        // (which marks user interaction and would flash suggestions over favorites/logo).
        updateTextViewHeight()
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
            if currentMode == .aiChat && !handler.submitsAIChatOnKeyboardReturn {
                return true
            }
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

extension SwitchBarTextEntryView: UITextFieldDelegate {

    func textFieldDidBeginEditing(_ textField: UITextField) {
        hasBeenInteractedWith = true
        onTextInputActivated?()
        fireTextAreaFocusedPixel()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard usesTextField else { return false }
        fireKeyboardGoPressedPixel()
        let currentText = textField.text ?? ""
        if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handler.submitText(currentText)
        }
        return false
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
