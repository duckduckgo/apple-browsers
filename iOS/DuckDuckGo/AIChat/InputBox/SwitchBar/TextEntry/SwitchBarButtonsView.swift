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
    case stopGeneratingOnly
    case aiChatShortcutOnly
    case voiceAndAIChatShortcut
    case clearAndAIChatShortcut

    var showsClearButton: Bool {
        switch self {
        case .clearOnly, .clearAndAIChatShortcut:
            return true
        case .noButtons, .voiceOnly, .stopGeneratingOnly,
             .aiChatShortcutOnly, .voiceAndAIChatShortcut:
            return false
        }
    }

    var showsVoiceButton: Bool {
        switch self {
        case .voiceOnly, .voiceAndAIChatShortcut:
            return true
        case .noButtons, .clearOnly, .stopGeneratingOnly,
             .aiChatShortcutOnly, .clearAndAIChatShortcut:
            return false
        }
    }

    var showsSeparator: Bool {
        switch self {
        case .noButtons, .clearOnly, .voiceOnly, .stopGeneratingOnly,
             .aiChatShortcutOnly, .voiceAndAIChatShortcut, .clearAndAIChatShortcut:
            return false
        }
    }

    var showsStopGeneratingButton: Bool {
        switch self {
        case .stopGeneratingOnly:
            return true
        case .noButtons, .clearOnly, .voiceOnly,
             .aiChatShortcutOnly, .voiceAndAIChatShortcut, .clearAndAIChatShortcut:
            return false
        }
    }

    var showsAIChatShortcutButton: Bool {
        switch self {
        case .aiChatShortcutOnly, .voiceAndAIChatShortcut, .clearAndAIChatShortcut:
            return true
        case .noButtons, .clearOnly, .voiceOnly, .stopGeneratingOnly:
            return false
        }
    }

    var showsAnyButton: Bool {
        switch self {
        case .noButtons:
            return false
        case .clearOnly, .voiceOnly, .stopGeneratingOnly,
             .aiChatShortcutOnly, .voiceAndAIChatShortcut, .clearAndAIChatShortcut:
            return true
        }
    }
}

class SwitchBarButtonsView: UIView {
    enum VoiceButtonStyle {
        case microphone
        case aiVoiceAccent
        case aiVoicePlain
    }

    private enum Constants {
        static let buttonSize: CGFloat = 44
        static let separatorWidth: CGFloat = 1
        static let separatorHeight: CGFloat = 20

        static let stopButtonBackdropInset: CGFloat = 2
        static let stopButtonBackdropCornerRadius: CGFloat = (buttonSize - (stopButtonBackdropInset * 2)) / 2

        /// Chip is laid out as a 40pt circle (Figma) — same diameter as the inline back button.
        static let aiChatShortcutChipSize: CGFloat = 40
        /// 8pt of trailing space inside the stack so the chip's right edge sits 8pt from the
        /// buttonsView trailing — matches the back button's leading 8pt for symmetry.
        static let stackTrailingInset: CGFloat = 8

        static let accessibilityPrefix = "Browser.OmniBar"
    }

    var buttonState: SwitchBarButtonState = .noButtons {
        didSet {
            updateButtonsVisibility()
        }
    }

    var voiceButtonStyle: VoiceButtonStyle = .microphone {
        didSet {
            updateVoiceButtonAppearance()
        }
    }

    var onClearTapped: (() -> Void)?
    var onVoiceTapped: (() -> Void)?
    var onStopGeneratingTapped: (() -> Void)?
    var onAIChatShortcutTapped: (() -> Void)?

    private let stack = UIStackView()
    private let clearButton = BrowserChromeButton(.secondary)
    private lazy var stopGeneratingButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = UIColor(designSystemColor: .textPrimary)
        config.image = DesignSystemImages.Glyphs.Size24.stopSquare
        config.contentInsets = .zero
        return UIButton(configuration: config)
    }()
    private let stopGeneratingBackdrop: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(singleUseColor: .unifiedToggleInputStopButtonBackground)
        view.layer.cornerRadius = Constants.stopButtonBackdropCornerRadius
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()
    private let voiceButton = BrowserChromeButton(.primary)
    private let aiChatShortcutButton = BrowserChromeButton(.primary)
    private let aiChatShortcutBackdrop: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
        view.layer.cornerRadius = Constants.aiChatShortcutChipSize / 2
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()
    private let separatorView = UIView()

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
        stack.alignment = .center
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: 0, trailing: Constants.stackTrailingInset)

        addSubview(stack)

        stack.addArrangedSubview(clearButton)
        stopGeneratingButton.insertSubview(stopGeneratingBackdrop, at: 0)
        stack.addArrangedSubview(stopGeneratingButton)
        stack.addArrangedSubview(voiceButton)
        stack.addArrangedSubview(separatorView)
        aiChatShortcutButton.insertSubview(aiChatShortcutBackdrop, at: 0)
        stack.addArrangedSubview(aiChatShortcutButton)
    }

    private func setUpConstraints() {
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),

            clearButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            clearButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            stopGeneratingButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            stopGeneratingButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            stopGeneratingBackdrop.topAnchor.constraint(equalTo: stopGeneratingButton.topAnchor, constant: Constants.stopButtonBackdropInset),
            stopGeneratingBackdrop.leadingAnchor.constraint(equalTo: stopGeneratingButton.leadingAnchor, constant: Constants.stopButtonBackdropInset),
            stopGeneratingBackdrop.trailingAnchor.constraint(equalTo: stopGeneratingButton.trailingAnchor, constant: -Constants.stopButtonBackdropInset),
            stopGeneratingBackdrop.bottomAnchor.constraint(equalTo: stopGeneratingButton.bottomAnchor, constant: -Constants.stopButtonBackdropInset),

            voiceButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            voiceButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            aiChatShortcutButton.widthAnchor.constraint(equalToConstant: Constants.aiChatShortcutChipSize),
            aiChatShortcutButton.heightAnchor.constraint(equalToConstant: Constants.aiChatShortcutChipSize),

            aiChatShortcutBackdrop.topAnchor.constraint(equalTo: aiChatShortcutButton.topAnchor),
            aiChatShortcutBackdrop.leadingAnchor.constraint(equalTo: aiChatShortcutButton.leadingAnchor),
            aiChatShortcutBackdrop.trailingAnchor.constraint(equalTo: aiChatShortcutButton.trailingAnchor),
            aiChatShortcutBackdrop.bottomAnchor.constraint(equalTo: aiChatShortcutButton.bottomAnchor),

            separatorView.widthAnchor.constraint(equalToConstant: Constants.separatorWidth),
            separatorView.heightAnchor.constraint(equalToConstant: Constants.separatorHeight),
        ])
    }

    private func setUpProperties() {
        clearButton.setImage(DesignSystemImages.Glyphs.Size24.closeCircleSmall)
        clearButton.addAction(UIAction { [weak self] _ in self?.onClearTapped?() }, for: .touchUpInside)

        stopGeneratingButton.addAction(UIAction { [weak self] _ in self?.onStopGeneratingTapped?() }, for: .touchUpInside)

        voiceButton.setImage(DesignSystemImages.Glyphs.Size24.microphone)
        voiceButton.addAction(UIAction { [weak self] _ in self?.onVoiceTapped?() }, for: .touchUpInside)

        aiChatShortcutButton.setImage(DesignSystemImages.Glyphs.Size24.aiChat)
        aiChatShortcutButton.addAction(UIAction { [weak self] _ in self?.onAIChatShortcutTapped?() }, for: .touchUpInside)

        separatorView.backgroundColor = UIColor(designSystemColor: .decorationPrimary)
    }

    private func setUpAccessibility() {
        clearButton.accessibilityLabel = "Clear text"
        clearButton.accessibilityIdentifier = "\(Constants.accessibilityPrefix).Button.ClearText"
        clearButton.accessibilityTraits = .button

        stopGeneratingButton.accessibilityLabel = "Stop generating"
        stopGeneratingButton.accessibilityIdentifier = "\(Constants.accessibilityPrefix).Button.StopGenerating"
        stopGeneratingButton.accessibilityTraits = .button

        voiceButton.accessibilityLabel = "Voice search"
        voiceButton.accessibilityIdentifier = "\(Constants.accessibilityPrefix).Button.VoiceSearch"
        voiceButton.accessibilityTraits = .button

        aiChatShortcutButton.accessibilityLabel = UserText.duckAiFeatureName
        aiChatShortcutButton.accessibilityIdentifier = "\(Constants.accessibilityPrefix).Button.AIChat"
        aiChatShortcutButton.accessibilityTraits = .button
    }

    private func updateButtonsVisibility() {
        clearButton.isHidden = !buttonState.showsClearButton
        stopGeneratingButton.isHidden = !buttonState.showsStopGeneratingButton
        voiceButton.isHidden = !buttonState.showsVoiceButton
        aiChatShortcutButton.isHidden = !buttonState.showsAIChatShortcutButton
        separatorView.isHidden = !buttonState.showsSeparator
    }

    /// Iterates the stack so newly-added buttons are auto-covered — the duck.ai chip stays
    /// visible so it can solo-animate to the omnibar's chat-icon position via
    /// `setAIChatShortcutDismissed`.
    func setNonChipButtonsAlpha(_ alpha: CGFloat) {
        for view in stack.arrangedSubviews where view !== aiChatShortcutButton {
            view.alpha = alpha
        }
    }

    /// Slides + fades the duck.ai chip so it crossfades with the omnibar's aiChat button (which
    /// fades in at its own X) — avoids the two-icons-visible-at-once moment when the chip's
    /// landing X doesn't exactly match. Restore via `setAIChatShortcutDismissed(false, …)`.
    func setAIChatShortcutDismissed(_ dismissed: Bool, duration: TimeInterval, horizontalOffset: CGFloat = 0) {
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.aiChatShortcutButton.transform = dismissed ? CGAffineTransform(translationX: horizontalOffset, y: 0) : .identity
            self.aiChatShortcutButton.alpha = dismissed ? 0 : 1
        }
    }

    private func updateVoiceButtonAppearance() {
        switch voiceButtonStyle {
        case .microphone:
            voiceButton.setImage(DesignSystemImages.Glyphs.Size24.microphone)
            voiceButton.backgroundColor = .clear
            voiceButton.tintColor = nil
            voiceButton.layer.cornerRadius = 0
            voiceButton.clipsToBounds = false
        case .aiVoiceAccent:
            voiceButton.setImage(DesignSystemImages.Glyphs.Size24.voice)
            voiceButton.backgroundColor = UIColor(designSystemColor: .accentPrimary)
            voiceButton.tintColor = UIColor(designSystemColor: .accentContentPrimary)
            voiceButton.layer.cornerRadius = Constants.buttonSize / 2
            voiceButton.clipsToBounds = true
        case .aiVoicePlain:
            voiceButton.setImage(DesignSystemImages.Glyphs.Size24.voice)
            voiceButton.backgroundColor = .clear
            voiceButton.tintColor = UIColor(designSystemColor: .textPrimary)
            voiceButton.layer.cornerRadius = 0
            voiceButton.clipsToBounds = false
        }
    }
}
