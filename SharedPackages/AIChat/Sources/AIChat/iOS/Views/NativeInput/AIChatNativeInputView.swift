//
//  AIChatNativeInputView.swift
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

#if os(iOS)
import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

// MARK: - Delegate Protocol

/// Delegate protocol for handling user interactions with the native input view.
public protocol AIChatNativeInputViewDelegate: AnyObject {
    func nativeInputViewDidChangeText(_ view: AIChatNativeInputView, text: String)
    func nativeInputViewDidTapSubmit(_ view: AIChatNativeInputView, text: String)
    func nativeInputViewDidTapVoice(_ view: AIChatNativeInputView)
    func nativeInputViewDidTapClear(_ view: AIChatNativeInputView)
    func nativeInputViewDidTapAttach(_ view: AIChatNativeInputView)
}

// MARK: - View

/// Native text input view with multi-line support, voice/clear button, and submit functionality.
public final class AIChatNativeInputView: UIView {

    // MARK: - Constants

    private enum Constants {
        static let fontSize: CGFloat = 16
        static let textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 48)
        static let placeholderTopOffset: CGFloat = 12
        static let placeholderHorizontalOffset: CGFloat = 16
        static let placeholderTrailingSpacing: CGFloat = 8
        static let buttonSize: CGFloat = 40
        static let bottomBarHeight: CGFloat = 40
        static let bottomBarHorizontalPadding: CGFloat = 8
        static let cornerRadius: CGFloat = 12
        static let textViewMinHeight: CGFloat = 48
        static let textViewMaxHeight: CGFloat = 200
    }

    // MARK: - Properties

    public weak var delegate: AIChatNativeInputViewDelegate?

    public var text: String {
        get { textView.text ?? "" }
        set {
            textView.text = newValue
            updatePlaceholderVisibility()
            updateButtonStates()
            updateTextViewHeight()
        }
    }

    public var placeholder = "" {
        didSet { placeholderLabel.text = placeholder }
    }

    public var isVoiceButtonEnabled = true {
        didSet { updateButtonStates() }
    }

    public var isAttachButtonHidden = false {
        didSet { attachButton.isHidden = isAttachButtonHidden }
    }

    // MARK: - UI Components

    private lazy var mainContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .backgroundTertiary)
        view.layer.cornerRadius = Constants.cornerRadius
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.black.withAlphaComponent(0.1).cgColor
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.08
        view.layer.shadowOffset = CGSize(width: 0, height: 2)
        view.layer.shadowRadius = 8
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var textView: UITextView = {
        let textView = UITextView()
        let fontMetrics = UIFontMetrics(forTextStyle: .body)
        textView.font = fontMetrics.scaledFont(for: UIFont.systemFont(ofSize: Constants.fontSize))
        textView.adjustsFontForContentSizeCategory = true
        textView.backgroundColor = .clear
        textView.tintColor = UIColor(designSystemColor: .accent)
        textView.textColor = UIColor(designSystemColor: .textPrimary)
        textView.textContainerInset = Constants.textContainerInset
        textView.isScrollEnabled = false
        textView.delegate = self
        textView.translatesAutoresizingMaskIntoConstraints = false
        return textView
    }()

    private lazy var placeholderLabel: UILabel = {
        let label = UILabel()
        let fontMetrics = UIFontMetrics(forTextStyle: .body)
        label.font = fontMetrics.scaledFont(for: UIFont.systemFont(ofSize: Constants.fontSize))
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textSecondary)
        label.numberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private lazy var topRightButton: UIButton = {
        let button = UIButton(type: .system)
        button.tintColor = UIColor(designSystemColor: .textSecondary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(topRightButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var chipContainer: UIView = {
        let view = UIView()
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var bottomBar: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var attachButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size16.attach, for: .normal)
        button.tintColor = UIColor(designSystemColor: .textSecondary)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(attachButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var submitButtonContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .clear
        view.layer.cornerRadius = Constants.buttonSize / 2
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private lazy var submitButton: UIButton = {
        let button = UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.arrowUp, for: .normal)
        button.tintColor = UIColor(designSystemColor: .accent)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(submitButtonTapped), for: .touchUpInside)
        button.isEnabled = false
        return button
    }()

    // MARK: - State

    private var isShowingClearButton = false
    private var textViewHeightConstraint: NSLayoutConstraint?

    // MARK: - Initialization

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public Methods

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        return textView.becomeFirstResponder()
    }

    @discardableResult
    public override func resignFirstResponder() -> Bool {
        return textView.resignFirstResponder()
    }

    public override var isFirstResponder: Bool {
        return textView.isFirstResponder
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        updateTextViewHeight()
    }
}

// MARK: - Private Setup

private extension AIChatNativeInputView {

    func setupUI() {
        addSubview(mainContainer)
        mainContainer.addSubview(textView)
        mainContainer.addSubview(placeholderLabel)
        mainContainer.addSubview(topRightButton)
        mainContainer.addSubview(chipContainer)
        mainContainer.addSubview(bottomBar)
        bottomBar.addSubview(attachButton)
        bottomBar.addSubview(submitButtonContainer)
        submitButtonContainer.addSubview(submitButton)

        setupConstraints()
        updateButtonStates()
    }

    func setupConstraints() {
        textViewHeightConstraint = textView.heightAnchor.constraint(equalToConstant: Constants.textViewMinHeight)

        NSLayoutConstraint.activate([
            mainContainer.topAnchor.constraint(equalTo: topAnchor),
            mainContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            textView.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            textView.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            textViewHeightConstraint!,

            placeholderLabel.topAnchor.constraint(equalTo: textView.topAnchor, constant: Constants.placeholderTopOffset),
            placeholderLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: Constants.placeholderHorizontalOffset),
            placeholderLabel.trailingAnchor.constraint(equalTo: topRightButton.leadingAnchor, constant: -Constants.placeholderTrailingSpacing),

            topRightButton.topAnchor.constraint(equalTo: mainContainer.topAnchor),
            topRightButton.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor, constant: -Constants.bottomBarHorizontalPadding),
            topRightButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            topRightButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            chipContainer.topAnchor.constraint(equalTo: textView.bottomAnchor),
            chipContainer.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            chipContainer.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            chipContainer.heightAnchor.constraint(equalToConstant: 0),

            bottomBar.topAnchor.constraint(equalTo: chipContainer.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: mainContainer.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: mainContainer.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: mainContainer.bottomAnchor, constant: -Constants.bottomBarHorizontalPadding),
            bottomBar.heightAnchor.constraint(equalToConstant: Constants.bottomBarHeight),

            attachButton.leadingAnchor.constraint(equalTo: bottomBar.leadingAnchor, constant: Constants.bottomBarHorizontalPadding),
            attachButton.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            attachButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            attachButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            submitButtonContainer.trailingAnchor.constraint(equalTo: bottomBar.trailingAnchor, constant: -Constants.bottomBarHorizontalPadding),
            submitButtonContainer.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
            submitButtonContainer.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            submitButtonContainer.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            submitButton.centerXAnchor.constraint(equalTo: submitButtonContainer.centerXAnchor),
            submitButton.centerYAnchor.constraint(equalTo: submitButtonContainer.centerYAnchor),
        ])
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    func updateTextViewHeight() {
        guard textView.bounds.width > 0 else { return }

        let size = textView.sizeThatFits(CGSize(width: textView.bounds.width, height: .greatestFiniteMagnitude))
        let newHeight = min(max(size.height, Constants.textViewMinHeight), Constants.textViewMaxHeight)

        textView.isScrollEnabled = size.height > Constants.textViewMaxHeight

        if textViewHeightConstraint?.constant != newHeight {
            textViewHeightConstraint?.constant = newHeight
        }
    }

    func updateButtonStates() {
        let hasText = !text.isEmpty
        let hasSubmittableText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasText {
            topRightButton.setImage(DesignSystemImages.Glyphs.Size24.clear, for: .normal)
            topRightButton.isHidden = false
            isShowingClearButton = true
        } else if isVoiceButtonEnabled {
            topRightButton.setImage(DesignSystemImages.Glyphs.Size24.microphone, for: .normal)
            topRightButton.isHidden = false
            isShowingClearButton = false
        } else {
            topRightButton.isHidden = true
            isShowingClearButton = false
        }

        submitButton.isEnabled = hasSubmittableText
        if hasSubmittableText {
            submitButton.setImage(DesignSystemImages.Glyphs.Size24.arrowRight, for: .normal)
            submitButtonContainer.backgroundColor = UIColor(designSystemColor: .accent)
            submitButton.tintColor = .white
        } else {
            submitButton.setImage(DesignSystemImages.Glyphs.Size24.arrowUp, for: .normal)
            submitButtonContainer.backgroundColor = .clear
            submitButton.tintColor = UIColor(designSystemColor: .textSecondary)
        }
    }
}

// MARK: - Actions

private extension AIChatNativeInputView {

    @objc func topRightButtonTapped() {
        if isShowingClearButton {
            text = ""
            delegate?.nativeInputViewDidTapClear(self)
        } else {
            delegate?.nativeInputViewDidTapVoice(self)
        }
    }

    @objc func attachButtonTapped() {
        delegate?.nativeInputViewDidTapAttach(self)
    }

    @objc func submitButtonTapped() {
        let currentText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentText.isEmpty else { return }
        delegate?.nativeInputViewDidTapSubmit(self, text: currentText)
    }
}

// MARK: - UITextViewDelegate

extension AIChatNativeInputView: UITextViewDelegate {

    public func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderVisibility()
        updateButtonStates()
        updateTextViewHeight()
        delegate?.nativeInputViewDidChangeText(self, text: text)
    }
}
#endif
