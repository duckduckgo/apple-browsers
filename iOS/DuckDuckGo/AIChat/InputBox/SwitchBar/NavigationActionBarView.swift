//
//  NavigationActionBarView.swift
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
import DesignResourcesKit
import DesignResourcesKitIcons
import Combine

final class NavigationActionBarView: UIView {
    
    // MARK: - Constants
    enum Constants {
        static let barHeight: CGFloat = 76
        static let buttonSize: CGFloat = 44
        static let padding: CGFloat = 16
        static let buttonSpacing: CGFloat = 12
        static let cornerRadius: CGFloat = 8
        
        static let shadowRadius1: CGFloat = 6
        static let shadowOffset1Y: CGFloat = 2
        static let shadowRadius2: CGFloat = 16
        static let shadowOffset2Y: CGFloat = 16
    }
    
    // MARK: - Properties
    private let viewModel: NavigationActionBarViewModel
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UI Elements
    private let mainStackView = UIStackView()
    private let rightStackView = UIStackView()
    private let webSearchToggleButton = CircularButton()
    private let microphoneButton = CircularButton()
    private let newLineButton = CircularButton()
    private let searchButton = CircularButton()
    private let backgroundGradientView = GradientBackgroundView()
    private let solidView = UIView()

    // MARK: - Initialization
    init(viewModel: NavigationActionBarViewModel) {
        self.viewModel = viewModel
        super.init(frame: .zero)
        setupUI()
        setupBindings()
        updateUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Setup
    private func setupUI() {
        // Setup stack views
        mainStackView.axis = .horizontal
        mainStackView.spacing = Constants.buttonSpacing
        mainStackView.alignment = .center
        mainStackView.distribution = .fill
        
        rightStackView.axis = .horizontal
        rightStackView.spacing = Constants.buttonSpacing
        rightStackView.alignment = .center
        rightStackView.distribution = .fill

        solidView.backgroundColor = UIColor(designSystemColor: .surface).withAlphaComponent(0.8)

        // Setup buttons
        setupWebSearchToggleButton()
        setupMicrophoneButton()
        setupNewLineButton()
        setupSearchButton()
        
        // Add to stack views
        rightStackView.addArrangedSubview(microphoneButton)
        rightStackView.addArrangedSubview(newLineButton)
        rightStackView.addArrangedSubview(searchButton)
        
        mainStackView.addArrangedSubview(webSearchToggleButton)
        
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        mainStackView.addArrangedSubview(spacer)
        
        mainStackView.addArrangedSubview(rightStackView)
        
        // Add to view
        addSubview(solidView)
        addSubview(backgroundGradientView)
        addSubview(mainStackView)
        
        // Setup constraints
        solidView.translatesAutoresizingMaskIntoConstraints = false
        mainStackView.translatesAutoresizingMaskIntoConstraints = false
        backgroundGradientView.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            // Main stack view constraints
            mainStackView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: Constants.padding),
            mainStackView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -Constants.padding),
            mainStackView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: Constants.padding),
            mainStackView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor, constant: -Constants.padding),

            // Background gradient should align with the keyboard (or bottom safe area)
            backgroundGradientView.leadingAnchor.constraint(equalTo: leadingAnchor),
            backgroundGradientView.trailingAnchor.constraint(equalTo: trailingAnchor),
            backgroundGradientView.topAnchor.constraint(equalTo: mainStackView.topAnchor),
            backgroundGradientView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),

            // Position the solid view under gradient and extend to the bottom of the view
            solidView.topAnchor.constraint(equalTo: backgroundGradientView.bottomAnchor),
            solidView.bottomAnchor.constraint(equalTo: bottomAnchor),
            solidView.leadingAnchor.constraint(equalTo: backgroundGradientView.leadingAnchor),
            solidView.trailingAnchor.constraint(equalTo: backgroundGradientView.trailingAnchor),

            // Button size constraints
            webSearchToggleButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            webSearchToggleButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            microphoneButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            microphoneButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            newLineButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            newLineButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize),
            searchButton.widthAnchor.constraint(equalToConstant: Constants.buttonSize),
            searchButton.heightAnchor.constraint(equalToConstant: Constants.buttonSize)
        ])
    }
    
    private func setupWebSearchToggleButton() {
        webSearchToggleButton.setIcon(DesignSystemImages.Glyphs.Size24.globe)
        webSearchToggleButton.addTarget(self, action: #selector(webSearchToggleTapped), for: .touchUpInside)
    }
    
    private func setupMicrophoneButton() {
        microphoneButton.setIcon(DesignSystemImages.Glyphs.Size24.microphone)
        microphoneButton.addTarget(self, action: #selector(microphoneTapped), for: .touchUpInside)
    }
    
    private func setupNewLineButton() {
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        let returnImage = UIImage(systemName: "return", withConfiguration: config)
        newLineButton.setIcon(returnImage)
        newLineButton.setColors(
            foreground: UIColor(designSystemColor: .textPrimary),
            background: UIColor(designSystemColor: .surface)
        )
        newLineButton.addTarget(self, action: #selector(newLineTapped), for: .touchUpInside)
    }
    
    private func setupSearchButton() {
        searchButton.addTarget(self, action: #selector(searchTapped), for: .touchUpInside)
    }
    
    private func setupBindings() {
        // Observe view model changes
        viewModel.$isSearchMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)
        
        viewModel.$hasText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)
        
        viewModel.$isWebSearchEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)
        
        viewModel.$isVoiceSearchEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)
        
        viewModel.$isCurrentTextValidURL
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateUI()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Actions
    @objc private func webSearchToggleTapped() {
        viewModel.handleWebSearchToggle()
    }
    
    @objc private func microphoneTapped() {
        viewModel.onMicrophoneTapped()
    }
    
    @objc private func newLineTapped() {
        viewModel.onNewLineTapped()
    }
    
    @objc private func searchTapped() {
        viewModel.onSearchTapped()
    }

    // MARK: - UI Updates
    private func updateUI() {
        updateWebSearchToggleButton()
        updateMicrophoneButton()
        updateSearchButton()
        updateButtonVisibility()
    }
    
    private func updateWebSearchToggleButton() {
        let isEnabled = viewModel.isWebSearchEnabled
        webSearchToggleButton.setColors(
            foreground: isEnabled ? .white : UIColor(designSystemColor: .textPrimary),
            background: isEnabled ? UIColor(designSystemColor: .accent) : UIColor(designSystemColor: .surface)
        )
    }
    
    private func updateMicrophoneButton() {
        let isEnabled = viewModel.isVoiceSearchEnabled
        microphoneButton.alpha = isEnabled ? 1.0 : 0.5
        microphoneButton.isEnabled = isEnabled
        microphoneButton.setColors(
            foreground: UIColor(designSystemColor: .textPrimary),
            background: UIColor(designSystemColor: .surface)
        )
    }
    
    private func updateSearchButton() {
        let hasText = viewModel.hasText
        let isValidURL = viewModel.isCurrentTextValidURL
        let isSearchMode = viewModel.isSearchMode
        
        // Determine icon
        let icon: UIImage? = {
            if isValidURL {
                return DesignSystemImages.Glyphs.Size24.globe
            } else if isSearchMode {
                return DesignSystemImages.Glyphs.Size24.searchFind
            } else {
                return DesignSystemImages.Glyphs.Size24.arrowUp
            }
        }()
        
        searchButton.setIcon(icon)
        searchButton.setColors(
            foreground: hasText ? .white : UIColor(designSystemColor: .textPlaceholder),
            background: hasText ? UIColor(designSystemColor: .accent) : UIColor(designSystemColor: .surface)
        )
        searchButton.isEnabled = hasText
        
        // Animate changes
        UIView.animate(withDuration: 0.2) {
            self.searchButton.alpha = hasText ? 1.0 : 0.5
        }
    }
    
    private func updateButtonVisibility() {
        // Update web search toggle visibility
        let shouldShowWebSearchToggle = !viewModel.isSearchMode
        webSearchToggleButton.isHidden = !shouldShowWebSearchToggle
        
        // Update microphone button visibility  
        let shouldShowMicButton = viewModel.shouldShowMicButton
        microphoneButton.isHidden = !shouldShowMicButton
        
        // Update search button visibility
        let shouldShowSearchButton = viewModel.hasText
        searchButton.isHidden = !shouldShowSearchButton
    }

    // MARK: - Touch Handling
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // First let the default hit test happen
        guard let hitView = super.hitTest(point, with: event) else {
            return nil
        }
        
        // If the hit view is one of our buttons or their subviews, allow the touch
        let buttons: [UIView] = [webSearchToggleButton, microphoneButton, newLineButton, searchButton]
        
        for button in buttons {
            if !button.isHidden && (hitView == button || hitView.isDescendant(of: button)) {
                return hitView
            }
        }
        
        // Otherwise, pass through the touch
        return nil
    }
}

// MARK: - CircularButton

private class CircularButton: UIButton {

    private let secondShadowLayer = CALayer()
    private var definedBackgroundColor: UIColor?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupButton()
    }
    
    private func setupButton() {
        layer.cornerRadius = NavigationActionBarView.Constants.buttonSize / 2
        layer.masksToBounds = false
        
        // Add shadows
        layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        layer.shadowOpacity = 1.0
        layer.shadowOffset = CGSize(width: 0, height: NavigationActionBarView.Constants.shadowOffset1Y)
        layer.shadowRadius = NavigationActionBarView.Constants.shadowRadius1
        
        // Add second shadow layer
        secondShadowLayer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        secondShadowLayer.shadowOpacity = 1.0
        secondShadowLayer.shadowOffset = CGSize(width: 0, height: NavigationActionBarView.Constants.shadowOffset2Y)
        secondShadowLayer.shadowRadius = NavigationActionBarView.Constants.shadowRadius2
        secondShadowLayer.masksToBounds = false
        layer.insertSublayer(secondShadowLayer, at: 0)
        
        imageView?.contentMode = .scaleAspectFit
        adjustsImageWhenHighlighted = false
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.15) {
                self.backgroundColor = self.isHighlighted ? self.definedBackgroundColor?.withAlphaComponent(0.8) : self.definedBackgroundColor
            }
        }
    }

    func setIcon(_ image: UIImage?) {
        setImage(image, for: .normal)
        imageView?.tintColor = UIColor(designSystemColor: .textPrimary)
    }
    
    func setColors(foreground: UIColor, background: UIColor) {
        definedBackgroundColor = background
        backgroundColor = background
        imageView?.tintColor = foreground
        setTitleColor(foreground, for: .normal)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        layer.cornerRadius = min(bounds.width, bounds.height) / 2
        secondShadowLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            layer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
            secondShadowLayer.shadowColor = UIColor(designSystemColor: .shadowSecondary).cgColor
        }
    }
}

// MARK: - GradientBackgroundView

private class GradientBackgroundView: UIView {
    
    private let gradientLayer = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGradient()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupGradient()
    }
    
    private func setupGradient() {
        gradientLayer.colors = [
            UIColor(designSystemColor: .surface).withAlphaComponent(0.0).cgColor,
            UIColor(designSystemColor: .surface).withAlphaComponent(0.8).cgColor
        ]
        gradientLayer.locations = [0.0, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 1.0)
        
        layer.insertSublayer(gradientLayer, at: 0)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()

        gradientLayer.frame = bounds
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            gradientLayer.colors = [
                UIColor(designSystemColor: .surface).withAlphaComponent(0.0).cgColor,
                UIColor(designSystemColor: .surface).withAlphaComponent(0.8).cgColor
            ]
        }
    }
}
