//
//  SwitchBarButtonsView.swift
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
import DesignResourcesKitIcons

enum SwitchBarButtonState {
    case noButtons
    case clearOnly
    case voiceOnly

    var showsClearButton: Bool {
        switch self {
        case .noButtons:
            return false
        case .clearOnly:
            return true
        case .voiceOnly:
            return false
        }
    }

    var showsVoiceButton: Bool {
        switch self {
        case .noButtons:
            return false
        case .clearOnly:
            return false
        case .voiceOnly:
            return true
        }
    }

    var showsAnyButton: Bool {
        switch self {
        case .noButtons:
            return false
        case .clearOnly, .voiceOnly:
            return true
        }
    }
}

class SwitchBarButtonsView: UIView {
    var buttonState: SwitchBarButtonState = .noButtons {
        didSet {
            updateButtonsVisibility()
        }
    }

    var onClearTapped: (() -> Void)?
    var onVoiceTapped: (() -> Void)?

    private let stack = UIStackView()
    private let clearButton = BrowserChromeButton(.secondary)
    private let voiceButton = BrowserChromeButton(.primary)

    private enum Constants {
        static let buttonSize: CGFloat = 44

        static let accessibilityPrefix = "Browser.OmniBar"
    }

    init() {
        super.init(frame: CGRect(origin: .zero,
                                 size: CGSize(width: Constants.buttonSize,
                                              height: Constants.buttonSize)))

        setUpSubviews()
        setUpConstraints()
        setUpProperties()

        setUpAccessibility()

        updateButtonsVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setUpSubviews() {
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)

        stack.addArrangedSubview(clearButton)
        stack.addArrangedSubview(voiceButton)
    }

    private func setUpConstraints() {
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            clearButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            clearButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            voiceButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            voiceButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
        ])
    }

    private func setUpProperties() {
        clearButton.setImage(DesignSystemImages.Glyphs.Size24.closeCircleSmall)
        clearButton.addAction(UIAction { [weak self] _ in self?.onClearTapped?() }, for: .touchUpInside)

        voiceButton.setImage(DesignSystemImages.Glyphs.Size24.microphone)
        voiceButton.addAction(UIAction { [weak self] _ in self?.onVoiceTapped?() }, for: .touchUpInside)
    }

    private func setUpAccessibility() {
        clearButton.accessibilityLabel = "Clear text"
        clearButton.accessibilityIdentifier = "\(Constants.accessibilityPrefix).Button.ClearText"
        clearButton.accessibilityTraits = .button

        voiceButton.accessibilityLabel = "Voice search"
        voiceButton.accessibilityIdentifier = "\(Constants.accessibilityPrefix).Button.VoiceSearch"
        voiceButton.accessibilityTraits = .button
    }

    private func updateButtonsVisibility() {
        clearButton.isHidden = !buttonState.showsClearButton
        voiceButton.isHidden = !buttonState.showsVoiceButton
    }
}
