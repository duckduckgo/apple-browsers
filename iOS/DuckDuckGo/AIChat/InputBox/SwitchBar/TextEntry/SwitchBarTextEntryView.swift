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
        static let buttonViewTrailingOffset: CGFloat = -14
        static let textButtonSpacing: CGFloat = -8

        // Animation
        static let animationDuration: TimeInterval = 0.2
    }

    private let handler: SwitchBarHandling

    private let textView = UITextView()
    private let placeholderLabel = UILabel()
    private var buttonsHostingController: UIHostingController<SwitchBarButtonsView>?
    private var currentButtonState: SwitchBarButtonState = .noButtons

    private var currentMode: TextEntryMode {
        handler.currentToggleState
    }
    private var cancellables = Set<AnyCancellable>()

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

        // Setup SwiftUI buttons view
        setupButtonsView()

        addSubview(textView)
        addSubview(placeholderLabel)

        textView.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

        heightConstraint = heightAnchor.constraint(equalToConstant: Constants.minHeight)
        heightConstraint?.isActive = true

        // Create both trailing constraints for textView
        textViewTrailingConstraint = textView.trailingAnchor.constraint(equalTo: trailingAnchor)

        setupConstraints()

        updateButtonState()
        updateForCurrentMode()
        updateTextViewHeight()
    }

    // MARK: - Setup Methods

    private func setupButtonsView() {
        let buttonsView = SwitchBarButtonsView(
            buttonState: currentButtonState,
            onClearTapped: { [weak self] in
                self?.handler.clearText()
            }
        )

        let hostingController = UIHostingController(rootView: buttonsView)
        hostingController.view.backgroundColor = .clear
        buttonsHostingController = hostingController

        addSubview(hostingController.view)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
    }

    private func setupConstraints() {
        guard let buttonsView = buttonsHostingController?.view else { return }

        textViewTrailingConstraintWithButtons = textView.trailingAnchor.constraint(equalTo: buttonsView.leadingAnchor, constant: Constants.textButtonSpacing)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: Constants.placeholderTopOffset),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: Constants.placeholderHorizontalOffset),
            placeholderLabel.trailingAnchor.constraint(equalTo: textView.trailingAnchor, constant: -Constants.placeholderHorizontalOffset),

            buttonsView.centerYAnchor.constraint(equalTo: placeholderLabel.centerYAnchor),
            buttonsView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: Constants.buttonViewTrailingOffset),
            buttonsView.heightAnchor.constraint(equalToConstant: 24),
            buttonsView.widthAnchor.constraint(lessThanOrEqualToConstant: 60)
        ])
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
            textView.returnKeyType = .go
        }
        textView.reloadInputViews()
        updatePlaceholderVisibility()
        updateButtonState()
        updateTextViewHeight()
    }

    private func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !textView.text.isEmpty
    }

    private func updateButtonState() {
        let hasText = !textView.text.isEmpty
        let newButtonState: SwitchBarButtonState

        if hasText {
            newButtonState = .clearOnly
        } else {
            newButtonState = .noButtons
        }

        if newButtonState != currentButtonState {
            currentButtonState = newButtonState
            updateButtonsView()
            updateConstraintsForButtonVisibility()
        }
    }

    private func updateButtonsView() {
        let buttonsView = SwitchBarButtonsView(
            buttonState: currentButtonState,
            onClearTapped: { [weak self] in
                self?.handler.clearText()
            }
        )

        buttonsHostingController?.rootView = buttonsView

        if let hostingView = buttonsHostingController?.view {
            hostingView.invalidateIntrinsicContentSize()
        }
    }

    private func updateConstraintsForButtonVisibility() {
        if currentButtonState.showsClearButton {
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
        if text == "\n" {
            /// https://app.asana.com/1/137249556945/project/1204167627774280/task/1210629837418046?focus=true
            let currentText = textView.text ?? ""
            if !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handler.submitText(currentText)
            }
        }
        return true
    }
}
