//
//  UnifiedToggleInputVoiceListeningView.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import DesignResourcesKit
import DesignResourcesKitIcons
import UIKit

/// Takes the toolbar row's place while speech is transcribed into the field: stop, a "Listening" status and submit.
final class UnifiedToggleInputVoiceListeningView: UIView {

    private enum Constants {
        static let verticalPadding: CGFloat = 4
        static let horizontalPadding: CGFloat = 8
        static let buttonSize: CGFloat = 40
    }

    var onStopTapped: (() -> Void)?
    var onSubmitTapped: (() -> Void)?

    var isSubmitEnabled: Bool = false {
        didSet {
            guard oldValue != isSubmitEnabled else { return }
            updateSubmitButtonAppearance()
        }
    }

    private var isFireTab = false

    private lazy var stopButton: CircularButton = {
        let button = CircularButton()
        button.isShadowHidden = true
        button.setImage(DesignSystemImages.Glyphs.Size24.stopSquare, for: .normal)
        button.setColors(
            foreground: UIColor(designSystemColor: .textPrimary),
            background: UIColor(singleUseColor: .unifiedToggleInputStopButtonBackground)
        )
        button.accessibilityLabel = UserText.inlineVoiceToTextStopButtonAccessibilityLabel
        button.accessibilityIdentifier = "AIChat.Toolbar.Button.StopListening"
        button.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        return button
    }()

    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = UserText.inlineVoiceToTextListening
        label.font = .daxBodyRegular()
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(designSystemColor: .textSecondary)
        label.textAlignment = .center
        label.accessibilityTraits = .updatesFrequently
        return label
    }()

    private lazy var submitButton: CircularButton = {
        let button = CircularButton()
        button.isShadowHidden = true
        button.setImage(DesignSystemImages.Glyphs.Size24.arrowUp, for: .normal)
        button.accessibilityLabel = UserText.aiChatToolbarSubmitButtonAccessibilityLabel
        button.accessibilityIdentifier = "AIChat.Toolbar.Button.SubmitWhileListening"
        button.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        return button
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpUI()
        updateSubmitButtonAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refreshFireMode(fireMode: Bool) {
        isFireTab = fireMode
        overrideUserInterfaceStyle = fireMode ? .dark : .unspecified
        updateSubmitButtonAppearance()
    }

    private func setUpUI() {
        [stopButton, statusLabel, submitButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            stopButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Constants.horizontalPadding),
            stopButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            stopButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            stopButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            submitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Constants.horizontalPadding),
            submitButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            submitButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            submitButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),

            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: stopButton.trailingAnchor, constant: Constants.horizontalPadding),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: submitButton.leadingAnchor, constant: -Constants.horizontalPadding),
        ])
    }

    private func updateSubmitButtonAppearance() {
        submitButton.isEnabled = isSubmitEnabled
        submitButton.applySubmitStyle(isActive: isSubmitEnabled, isFireTab: isFireTab, activeForeground: .white)
    }

    @objc private func stopTapped() {
        onStopTapped?()
    }

    @objc private func submitTapped() {
        guard isSubmitEnabled else { return }
        onSubmitTapped?()
    }
}
