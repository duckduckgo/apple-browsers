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
    case searchGoToOnly
    case voiceAndSearchGoTo
    case stopGeneratingOnly
    case stopGeneratingAndSearchGoTo

    var showsClearButton: Bool {
        switch self {
        case .clearOnly:
            return true
        case .noButtons, .voiceOnly, .searchGoToOnly, .voiceAndSearchGoTo,
             .stopGeneratingOnly, .stopGeneratingAndSearchGoTo:
            return false
        }
    }

    var showsVoiceButton: Bool {
        switch self {
        case .voiceOnly, .voiceAndSearchGoTo:
            return true
        case .noButtons, .clearOnly, .searchGoToOnly,
             .stopGeneratingOnly, .stopGeneratingAndSearchGoTo:
            return false
        }
    }

    var showsSearchGoToButton: Bool {
        switch self {
        case .searchGoToOnly, .voiceAndSearchGoTo, .stopGeneratingAndSearchGoTo:
            return true
        case .noButtons, .clearOnly, .voiceOnly, .stopGeneratingOnly:
            return false
        }
    }

    var showsSeparator: Bool {
        switch self {
        case .voiceAndSearchGoTo, .stopGeneratingAndSearchGoTo:
            return true
        case .noButtons, .clearOnly, .voiceOnly, .searchGoToOnly, .stopGeneratingOnly:
            return false
        }
    }

    var showsStopGeneratingButton: Bool {
        switch self {
        case .stopGeneratingOnly, .stopGeneratingAndSearchGoTo:
            return true
        case .noButtons, .clearOnly, .voiceOnly, .searchGoToOnly, .voiceAndSearchGoTo:
            return false
        }
    }

    var showsAnyButton: Bool {
        switch self {
        case .noButtons:
            return false
        case .clearOnly, .voiceOnly, .searchGoToOnly, .voiceAndSearchGoTo,
             .stopGeneratingOnly, .stopGeneratingAndSearchGoTo:
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
    var onSearchGoToTapped: (() -> Void)?
    var onStopGeneratingTapped: (() -> Void)?

    private let stack = UIStackView()
    private let clearButton = BrowserChromeButton(.secondary)
    private lazy var stopGeneratingButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .white
        config.image = DesignSystemImages.Glyphs.Size16.stopSquare
        config.contentInsets = .zero
        return UIButton(configuration: config)
    }()
    private let stopGeneratingBackdrop: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = UIColor(designSystemColor: .destructivePrimary)
        view.layer.cornerRadius = 14
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }()
    private let voiceButton = BrowserChromeButton(.primary)
    private let separatorView = UIView()
    private let searchGoToButton = BrowserChromeButton(.primary)

    private enum Constants {
        static let buttonSize: CGFloat = 44
        static let separatorWidth: CGFloat = 1
        static let separatorHeight: CGFloat = 20

        static let stopButtonBackdropInset: CGFloat = 2
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
        stack.alignment = .center

        addSubview(stack)

        stack.addArrangedSubview(clearButton)
        stopGeneratingButton.insertSubview(stopGeneratingBackdrop, at: 0)
        stack.addArrangedSubview(stopGeneratingButton)
        stack.addArrangedSubview(voiceButton)
        stack.addArrangedSubview(separatorView)
        stack.addArrangedSubview(searchGoToButton)
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

            separatorView.widthAnchor.constraint(equalToConstant: Constants.separatorWidth),
            separatorView.heightAnchor.constraint(equalToConstant: Constants.separatorHeight),

            searchGoToButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            searchGoToButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
        ])
    }

    private func setUpProperties() {
        clearButton.setImage(DesignSystemImages.Glyphs.Size24.closeCircleSmall)
        clearButton.addAction(UIAction { [weak self] _ in self?.onClearTapped?() }, for: .touchUpInside)

        stopGeneratingButton.addAction(UIAction { [weak self] _ in self?.onStopGeneratingTapped?() }, for: .touchUpInside)

        voiceButton.setImage(DesignSystemImages.Glyphs.Size24.microphone)
        voiceButton.addAction(UIAction { [weak self] _ in self?.onVoiceTapped?() }, for: .touchUpInside)

        separatorView.backgroundColor = UIColor(designSystemColor: .decorationPrimary)

        searchGoToButton.setImage(DesignSystemImages.Glyphs.Size24.searchFindGoTo)
        searchGoToButton.addAction(UIAction { [weak self] _ in self?.onSearchGoToTapped?() }, for: .touchUpInside)
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

        searchGoToButton.accessibilityLabel = "Search"
        searchGoToButton.accessibilityIdentifier = "\(Constants.accessibilityPrefix).Button.SearchGoTo"
        searchGoToButton.accessibilityTraits = .button
    }

    private func updateButtonsVisibility() {
        clearButton.isHidden = !buttonState.showsClearButton
        stopGeneratingButton.isHidden = !buttonState.showsStopGeneratingButton
        voiceButton.isHidden = !buttonState.showsVoiceButton
        separatorView.isHidden = !buttonState.showsSeparator
        searchGoToButton.isHidden = !buttonState.showsSearchGoToButton
    }
}
