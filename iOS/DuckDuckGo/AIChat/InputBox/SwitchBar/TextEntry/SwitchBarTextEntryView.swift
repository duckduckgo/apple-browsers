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

        // Clear button
        static let clearButtonSize: CGFloat = 24
        static let clearButtonTrailingOffset: CGFloat = -12
        static let clearButtonSpacing: CGFloat = -8

        // Animation
        static let animationDuration: TimeInterval = 0.2
    }
    private let handler: SwitchBarHandling

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let microphoneButton = UIButton(type: .system)

    private var currentMode: TextEntryMode {
        handler.currentToggleState
    }
    private var cancellables = Set<AnyCancellable>()

    private var heightConstraint: NSLayoutConstraint?
    private var textViewTrailingConstraint: NSLayoutConstraint?
    private var textViewTrailingConstraintWithButton: NSLayoutConstraint?

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

        // Setup clear button
        clearButton.setImage(DesignSystemImages.Glyphs.Size24.clear, for: .normal)
        clearButton.tintColor = UIColor.systemGray
        clearButton.isHidden = true
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)

        // Setup microphone button
        microphoneButton.setImage(DesignSystemImages.Glyphs.Size24.microphone, for: .normal)
        microphoneButton.tintColor = UIColor.systemGray
        microphoneButton.isHidden = !handler.isVoiceSearchEnabled  // Initially visible when no text and voice search is enabled
        microphoneButton.addTarget(self, action: #selector(microphoneButtonTapped), for: .touchUpInside)

        addSubview(textView)
        addSubview(placeholderLabel)
        addSubview(clearButton)
        addSubview(microphoneButton)

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        microphoneButton.translatesAutoresizingMaskIntoConstraints = false

        heightConstraint = heightAnchor.constraint(equalToConstant: Constants.minHeight)
        heightConstraint?.isActive = true

        // Create both trailing constraints for textView
        textViewTrailingConstraint = textView.trailingAnchor.constraint(equalTo: trailingAnchor)
        textViewTrailingConstraintWithButton = textView.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: Constants.clearButtonSpacing)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: Constants.placeholderTopOffset),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: Constants.placeholderHorizontalOffset),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -Constants.placeholderHorizontalOffset),

            clearButton.centerYAnchor.constraint(equalTo: placeholderLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: Constants.clearButtonTrailingOffset),
            clearButton.widthAnchor.constraint(equalToConstant: Constants.clearButtonSize),
            clearButton.heightAnchor.constraint(equalToConstant: Constants.clearButtonSize),

            microphoneButton.centerYAnchor.constraint(equalTo: placeholderLabel.centerYAnchor),
            microphoneButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: Constants.clearButtonTrailingOffset),
            microphoneButton.widthAnchor.constraint(equalToConstant: Constants.clearButtonSize),
            microphoneButton.heightAnchor.constraint(equalToConstant: Constants.clearButtonSize)
        ])

        // Initially determine which constraint to activate based on initial state
        updateConstraintsForButtonVisibility()

        updateForCurrentMode()
        updateTextViewHeight()
    }

    // MARK: - Button Actions
    
    @objc private func clearButtonTapped() {
        handler.clearText()
    }

    @objc private func microphoneButtonTapped() {
        handler.microphoneButtonTapped()
    }

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
        updateActionButtonsVisibility()
        updateTextViewHeight()
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    /// Updates visibility of action buttons (clear/microphone) - they are mutually exclusive
    /// - Clear button shows when there's text
    /// - Microphone button shows when there's no text and voice search is enabled
    private func updateActionButtonsVisibility() {
        let hasText = !textView.text.isEmpty
        let shouldShowMicrophoneButton = !hasText && handler.isVoiceSearchEnabled
        
        UIView.animate(withDuration: Constants.animationDuration) {
            self.clearButton.isHidden = !hasText
            self.microphoneButton.isHidden = !shouldShowMicrophoneButton
        }
        
        updateConstraintsForButtonVisibility()
    }

    private func updateConstraintsForButtonVisibility() {
        let hasText = !textView.text.isEmpty
        let shouldShowMicrophoneButton = !hasText && handler.isVoiceSearchEnabled
        let anyButtonVisible = hasText || shouldShowMicrophoneButton
        
        if anyButtonVisible {
            textViewTrailingConstraint?.isActive = false
            textViewTrailingConstraintWithButton?.isActive = true
        } else {
            textViewTrailingConstraintWithButton?.isActive = false
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
                    self.updateActionButtonsVisibility()
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
    }
}

extension SwitchBarTextEntryView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        updateActionButtonsVisibility()
        updateTextViewHeight()
        handler.updateCurrentText(textView.text ?? "")
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
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
