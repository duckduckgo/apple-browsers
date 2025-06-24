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

/// A view that manages the microphone and clear buttons in a stack view
class SwitchBarButtonsView: UIView {
    
    // MARK: - Button State Enum
    
    /// Represents the different button states for the buttons view
    enum ButtonState {
        case noButtons          // No buttons visible
        case micOnly           // Only microphone button visible (no text, voice search enabled)
        case clearOnly         // Only clear button visible (has text, normal state)
        case initialSelected   // Both mic and clear buttons visible (initial selected state with text)
        
        var showsMicButton: Bool {
            switch self {
            case .noButtons, .clearOnly:
                return false
            case .micOnly, .initialSelected:
                return true
            }
        }
        
        var showsClearButton: Bool {
            switch self {
            case .noButtons, .micOnly:
                return false
            case .clearOnly, .initialSelected:
                return true
            }
        }
        
        var showsAnyButton: Bool {
            return showsMicButton || showsClearButton
        }
    }
    
    // MARK: - Constants
    
    private enum Constants {
        static let buttonSize: CGFloat = 24
        static let buttonSpacing: CGFloat = 2
    }
    
    // MARK: - Properties
    
    private let stackView = UIStackView()
    private let microphoneButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    
    private var currentButtonState: ButtonState = .noButtons {
        didSet {
            updateButtonVisibility()
        }
    }
    
    // MARK: - Callbacks
    
    var onMicrophoneTapped: (() -> Void)?
    var onClearTapped: (() -> Void)?
    
    // MARK: - Initialization
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        setupButtons()
        setupStackView()
        setupConstraints()
        updateButtonVisibility()
    }
    
    private func setupButtons() {
        // Setup microphone button
        microphoneButton.setImage(DesignSystemImages.Glyphs.Size24.microphone, for: .normal)
        microphoneButton.tintColor = UIColor.systemGray
        microphoneButton.addTarget(self, action: #selector(microphoneButtonTapped), for: .touchUpInside)
        
        // Setup clear button
        clearButton.setImage(DesignSystemImages.Glyphs.Size24.clear, for: .normal)
        clearButton.tintColor = UIColor.systemGray
        clearButton.addTarget(self, action: #selector(clearButtonTapped), for: .touchUpInside)
        
        // Set button sizes
        microphoneButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            microphoneButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            microphoneButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            clearButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            clearButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize)
        ])
    }
    
    private func setupStackView() {
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = Constants.buttonSpacing
        
        // Add buttons to stack view (mic button on left, clear button on right)
        stackView.addArrangedSubview(microphoneButton)
        stackView.addArrangedSubview(clearButton)
        
        addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    
    // MARK: - Button Actions
    
    @objc private func microphoneButtonTapped() {
        onMicrophoneTapped?()
    }
    
    @objc private func clearButtonTapped() {
        onClearTapped?()
    }
    
    // MARK: - Public Methods
    
    /// Updates the button state and visibility
    func setButtonState(_ state: ButtonState) {
        currentButtonState = state
    }
    
    /// Gets the current button state
    func getButtonState() -> ButtonState {
        return currentButtonState
    }
    
    // MARK: - Private Methods
    
    /// Updates the button visibility based on current button state
    private func updateButtonVisibility() {
        microphoneButton.isHidden = !currentButtonState.showsMicButton
        clearButton.isHidden = !currentButtonState.showsClearButton
        isHidden = !currentButtonState.showsAnyButton
    }
} 