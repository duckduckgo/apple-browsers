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

    private enum Constants {
        static let maxHeight: CGFloat = 120
        static let maxHeightWhenUsingFadeOutAnimation: CGFloat = 132
        static let minHeight: CGFloat = 44
        static let minHeightAIChat: CGFloat = 68
        static let minHeightAIChatBottomBar: CGFloat = 96
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
    }

    private let handler: SwitchBarHandling

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
            return handler.isUsingSmallerBottomInput ? Constants.minHeight : Constants.minHeightAIChatBottomBar
        }

        if currentMode == .aiChat {
            return handler.isTopBarPosition ? Constants.minHeightAIChat : Constants.minHeightAIChatBottomBar
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

    let textHeightChangeSubject = PassthroughSubject<Void, Never>()

    /// When true the text entry will expand the text when the selection changes, e.g.  If the user uses the space bar to move the caret then it updates the selection.
    ///   This gets set to true after selectAll() on the field gets call.
    var canExpandOnSelectionChange = false

    var hasBeenInteractedWith = false
    var isURL: Bool {
        // TODO some kind of text length check?
        URL(string: textView.text)?.navigationalScheme != nil
    }

    var isExpandable: Bool = false {
        didSet {
            updateTextViewHeight()
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

    override var isFirstResponder: Bool {
        textView.isFirstResponder
    }

    // MARK: - Initialization
    init(handler: SwitchBarHandling) {
        self.handler = handler
        super.init(frame: .zero)

        setupView()
        setupSubscriptions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        let fontMetrics = UIFontMetrics(forTextStyle: .body)
        let textFont = fontMetrics.scaledFont(for: UIFont.systemFont(ofSize: Constants.fontSize))
        textView.font = textFont
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = UIColor.clear
        textView.tintColor = UIColor(designSystemColor: .accent)
        textView.textColor = UIColor(designSystemColor: .textPrimary)
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false

        placeholderLabel.font = textFont
        placeholderLabel.adjustsFontForContentSizeCategory = true
        placeholderLabel.textColor = UIColor(designSystemColor: .textSecondary)

        // Truncate text in case it exceeds single line
        placeholderLabel.numberOfLines = 1

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
            self?.hasBeenInteractedWith = true
            self?.fireClearButtonPressedPixel()
            self?.handler.clearText()
            self?.handler.clearButtonTapped()
        }

        buttonsView.onVoiceTapped = { [weak self] in
            self?.handler.microphoneButtonTapped()
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

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: Constants.placeholderTopOffset),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: Constants.placeholderHorizontalOffset),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -Constants.placeholderHorizontalOffset),

            buttonsView.centerYAnchor.constraint(equalTo: placeholderLabel.centerYAnchor)
        ])
    }

    // MARK: - UI Updates

    private func updateForCurrentMode() {
        switch currentMode {
        case .search:
            placeholderLabel.text = UserText.searchDuckDuckGo
            textView.autocapitalizationType = .none
            textView.autocorrectionType = .no
            textView.spellCheckingType = .no
        case .aiChat:
            placeholderLabel.text = UserText.searchInputFieldPlaceholderDuckAI
            textView.autocapitalizationType = .sentences
            textView.autocorrectionType = .default
            textView.spellCheckingType = .default
            
            /// Auto-focus the text field when switching to duck.ai mode
            /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210975209610640?focus=true
            DispatchQueue.main.async { [weak self] in
                self?.textView.becomeFirstResponder()
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
        case .aiChat:
            if handler.isUsingFadeOutAnimation {
                textView.keyboardType = .default
                textView.returnKeyType = .default
            } else {
                textView.keyboardType = .webSearch
                textView.returnKeyType = .go
            }
        }

        if handler.isUsingFadeOutAnimation {
            textView.reloadInputViews()
        }
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    private func updateButtonState() {
        let newButtonState = handler.buttonState

        if newButtonState != currentButtonState {
            currentButtonState = newButtonState

            // Prevent unexpected animations of this change
            UIView.performWithoutAnimation {
                adjustTextViewContentInset()
                buttonsView.layoutIfNeeded()
            }
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
            textView.text.isBlank {

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
                    self.textView.text = text
                    self.updatePlaceholderVisibility()
                    self.updateTextViewHeight()
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
        textView.selectAll(nil)
        canExpandOnSelectionChange = true
    }
}

extension SwitchBarTextEntryView: UITextViewDelegate {

    func textViewDidChangeSelection(_ textView: UITextView) {
        guard canExpandOnSelectionChange else { return }
        textViewDidChange(textView)
        canExpandOnSelectionChange = false
    }

    func textViewDidBeginEditing(_ textView: UITextView) {
        fireTextAreaFocusedPixel()
    }

    func textViewDidChange(_ textView: UITextView) {
        hasBeenInteractedWith = true
        
        updatePlaceholderVisibility()
        updateButtonState()
        updateTextViewHeight()
        handler.updateCurrentText(textView.text ?? "")
        handler.markUserInteraction()

        textView.reloadInputViews()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        if text == "\n" {
            if handler.isUsingFadeOutAnimation && currentMode == .aiChat {
                return true
            }

            fireKeyboardGoPressedPixel()
            /// https://app.asana.com/1/137249556945/project/1204167627774280/task/1210629837418046?focus=true
            let currentText = textView.text ?? ""
            if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handler.submitText(currentText)
            }
            /// Prevent adding newline when there's no content or just whitespace
            /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210989002857245?focus=true
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
