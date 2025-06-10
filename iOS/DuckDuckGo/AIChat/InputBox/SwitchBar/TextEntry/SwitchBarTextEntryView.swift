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

class SwitchBarTextEntryView: UIView {
    private let handler: SwitchBarHandling

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private let clearButton = UIButton(type: .system)

    private var currentMode: TextEntryMode {
        handler.currentToggleState
    }
    private var cancellables = Set<AnyCancellable>()

    private let maxHeight: CGFloat = 120
    private let minHeight: CGFloat = 44
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
        textView.font = UIFont.systemFont(ofSize: 16)
        textView.backgroundColor = UIColor.clear
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.delegate = self
        textView.isScrollEnabled = false
        textView.showsVerticalScrollIndicator = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)

        placeholderLabel.font = UIFont.systemFont(ofSize: 16)
        placeholderLabel.textColor = UIColor.placeholderText
        placeholderLabel.numberOfLines = 0

        // Setup clear button
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = UIColor.systemGray
        clearButton.isHidden = true
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)

        addSubview(textView)
        addSubview(placeholderLabel)
        addSubview(clearButton)

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        heightConstraint = heightAnchor.constraint(equalToConstant: minHeight)
        heightConstraint?.isActive = true

        // Create both trailing constraints for textView
        textViewTrailingConstraint = textView.trailingAnchor.constraint(equalTo: trailingAnchor)
        textViewTrailingConstraintWithButton = textView.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -8)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 16),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -16),

            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            clearButton.widthAnchor.constraint(equalToConstant: 20),
            clearButton.heightAnchor.constraint(equalToConstant: 20)
        ])

        // Initially activate the constraint without button
        textViewTrailingConstraint?.isActive = true

        updateForCurrentMode()
        updateTextViewHeight()
    }

    @objc private func clearButtonTapped() {
        handler.clearText()
    }

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
        updateClearButtonVisibility()
        updateTextViewHeight()
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    private func updateClearButtonVisibility() {
        let shouldShowClearButton = currentMode == .search && !textView.text.isEmpty

        UIView.animate(withDuration: 0.2) {
            self.clearButton.isHidden = !shouldShowClearButton
        }

        // Update text view constraints based on clear button visibility
        if shouldShowClearButton {
            textViewTrailingConstraint?.isActive = false
            textViewTrailingConstraintWithButton?.isActive = true
        } else {
            textViewTrailingConstraintWithButton?.isActive = false
            textViewTrailingConstraint?.isActive = true
        }
    }

    private func updateTextViewHeight() {
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
        let newHeight = max(minHeight, min(maxHeight, size.height))

        heightConstraint?.constant = newHeight

        let contentExceedsMaxHeight = size.height > maxHeight
        textView.isScrollEnabled = contentExceedsMaxHeight
        textView.showsVerticalScrollIndicator = contentExceedsMaxHeight

        if contentExceedsMaxHeight {
            let bottom = NSMakeRange(textView.text.count, 0)
            textView.scrollRangeToVisible(bottom)
        }
    }

    private func setupSubscriptions() {
        handler.toggleStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMode in
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
                    self.updateClearButtonVisibility()
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
}

extension SwitchBarTextEntryView: UITextViewDelegate {

    func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        updateClearButtonVisibility()
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
