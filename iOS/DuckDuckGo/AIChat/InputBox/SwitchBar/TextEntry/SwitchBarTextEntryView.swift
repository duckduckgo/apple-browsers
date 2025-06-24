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
import Combine
import DesignResourcesKitIcons

class SwitchBarTextEntryView: UIView {

    private enum Constants {
        static let maxHeight: CGFloat = 120
        static let minHeight: CGFloat = 44
        static let fontSize: CGFloat = 16

        // Text container insets
        static let textTopInset: CGFloat = 12
        static let textBottomInset: CGFloat = 8
        static let textHorizontalInset: CGFloat = 12

        // Placeholder positioning
        static let placeholderTopOffset: CGFloat = 12
        static let placeholderHorizontalOffset: CGFloat = 16

        // Button view
        static let buttonViewTrailingOffset: CGFloat = -12
        static let textButtonSpacing: CGFloat = -8

        // Animation
        static let animationDuration: TimeInterval = 0.2
    }
    
    private let handler: SwitchBarHandling

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let buttonsView = SwitchBarButtonsView()

    private var currentMode: TextEntryMode {
        handler.currentToggleState
    }
    private var cancellables = Set<AnyCancellable>()
    private var isInInitialSelectedState = false

    private var heightConstraint: NSLayoutConstraint?
    private var textViewTrailingConstraint: NSLayoutConstraint?
    private var textViewTrailingConstraintWithButtons: NSLayoutConstraint?

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
        textView.font = UIFont.systemFont(ofSize: Constants.fontSize)
        textView.backgroundColor = UIColor.clear
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.textContainerInset = UIEdgeInsets(top: Constants.textTopInset, left: Constants.textHorizontalInset, bottom: Constants.textBottomInset, right: Constants.textHorizontalInset)

        placeholderLabel.font = UIFont.systemFont(ofSize: Constants.fontSize)
        placeholderLabel.textColor = UIColor.placeholderText
        placeholderLabel.numberOfLines = 0

        // Setup buttons view
        buttonsView.onMicrophoneTapped = { [weak self] in
            self?.handler.microphoneButtonTapped()
        }
        
        buttonsView.onClearTapped = { [weak self] in
            // When clear button is tapped, exit initial selected state
            if self?.isInInitialSelectedState == true {
                self?.isInInitialSelectedState = false
            }
            self?.handler.clearText()
        }

        addSubview(textView)
        addSubview(placeholderLabel)
        addSubview(buttonsView)

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        buttonsView.translatesAutoresizingMaskIntoConstraints = false

        heightConstraint = heightAnchor.constraint(equalToConstant: Constants.minHeight)
        heightConstraint?.isActive = true

        // Create both trailing constraints for textView
        textViewTrailingConstraint = textView.trailingAnchor.constraint(equalTo: trailingAnchor)
        textViewTrailingConstraintWithButtons = textView.trailingAnchor.constraint(equalTo: buttonsView.leadingAnchor, constant: Constants.textButtonSpacing)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: Constants.placeholderTopOffset),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: Constants.placeholderHorizontalOffset),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -Constants.placeholderHorizontalOffset),

            buttonsView.centerYAnchor.constraint(equalTo: placeholderLabel.centerYAnchor),
            buttonsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: Constants.buttonViewTrailingOffset)
        ])

        updateButtonState()
        updateForCurrentMode()
        updateTextViewHeight()
    }

    // MARK: - Button State Management

    // MARK: - UI Updates
    
    private func updateForCurrentMode() {
        switch currentMode {
        case .search:
            placeholderLabel.text = "Search..."
            textView.keyboardType = .webSearch
            textView.textContentType = .none
            textView.returnKeyType = .search
        case .aiChat:
            placeholderLabel.text = "Ask Duck.ai..."
            textView.keyboardType = .default
            textView.returnKeyType = .default
        }
        textView.reloadInputViews()
        updatePlaceholderVisibility()
        updateButtonState()
        updateTextViewHeight()
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    /// Determines and updates the current button state based on text content and special states
    private func updateButtonState() {
        let hasText = !textView.text.isEmpty
        let isVoiceSearchEnabled = handler.isVoiceSearchEnabled
        
        let newButtonState: SwitchBarButtonsView.ButtonState
        
        if isInInitialSelectedState && hasText {
            // Special case: both buttons visible when in initial selected state with text
            newButtonState = .initialSelected
        } else if hasText {
            // Normal case: clear button only when there's text
            newButtonState = .clearOnly
        } else if isVoiceSearchEnabled {
            // No text but voice search enabled: mic button only
            newButtonState = .micOnly
        } else {
            // No text and no voice search: no buttons
            newButtonState = .noButtons
        }
        
        if newButtonState != buttonsView.getButtonState() {
            buttonsView.setButtonState(newButtonState)
            updateConstraintsForButtonVisibility()
        }
    }

    private func updateConstraintsForButtonVisibility() {
        let currentButtonState = buttonsView.getButtonState()
        if currentButtonState.showsAnyButton {
            textViewTrailingConstraint?.isActive = false
            textViewTrailingConstraintWithButtons?.isActive = true
        } else {
            textViewTrailingConstraintWithButtons?.isActive = false
            textViewTrailingConstraint?.isActive = true
        }
    }

    private func updateTextViewHeight() {
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
        let newHeight = max(Constants.minHeight, min(Constants.maxHeight, size.height))

        heightConstraint?.constant = newHeight

        let contentExceedsMaxHeight = size.height > Constants.maxHeight
        textView.isScrollEnabled = contentExceedsMaxHeight
        textView.showsVerticalScrollIndicator = contentExceedsMaxHeight

        if contentExceedsMaxHeight {
            let bottom = NSRange(location: textView.text.count, length: 0)
            textView.scrollRangeToVisible(bottom)
        }
    }

    private func setupSubscriptions() {
        handler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateForCurrentMode()
            }
            .store(in: &cancellables)

        handler.currentTextPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self = self else { return }

                if self.textView.text != text {
                    self.textView.text = text
                    self.updatePlaceholderVisibility()
                    self.updateButtonState()
                    self.updateTextViewHeight()
                }
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
        // When text is selected initially, enter the special state where both buttons are visible
        isInInitialSelectedState = true
        updateButtonState()
    }
    
    // MARK: - Public Methods
    
    /// Sets the initial selected state where both mic and clear buttons should be visible
    func setInitialSelectedState(_ isInitialSelected: Bool) {
        isInInitialSelectedState = isInitialSelected
        updateButtonState()
    }
}

extension SwitchBarTextEntryView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        updateButtonState()
        updateTextViewHeight()
        handler.updateCurrentText(textView.text ?? "")
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Exit initial selected state when user starts typing
        if isInInitialSelectedState && !text.isEmpty {
            isInInitialSelectedState = false
        }
        
        if text == "\n" {
            switch currentMode {
            case .search:
                let currentText = textView.text ?? ""
                if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    handler.submitText(currentText)
                }
                return false
            case .aiChat:
                return true
            }
        }
        return true
    }
}
