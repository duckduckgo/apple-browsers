//
//  CreditCardInputAccessoryView.swift
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

import Foundation
import UIKit
import SwiftUI
import BrowserServicesKit
import DesignResourcesKit
import DesignResourcesKitIcons

class CreditCardInputAccessoryView: UIView {

    var onCardSelected: ((SecureVaultModels.CreditCard?) -> Void)?
    var onCardManagementSelected: (() -> Void)?

    private var creditCards: [CreditCardRowViewModel] = []
    private let authenticator = AutofillLoginListAuthenticator(reason: UserText.autofillCreditCardFillPromptAuthentication,
                                                               cancelTitle: UserText.autofillLoginListAuthenticationCancelButton)

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // Performance optimization
        scrollView.layer.shouldRasterize = false
        return scrollView
    }()

    private lazy var cardStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .horizontal
        stackView.spacing = 8
        stackView.alignment = .center
        stackView.translatesAutoresizingMaskIntoConstraints = false
        return stackView
    }()

    private lazy var gradientView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor.clear
        // Optimize layer performance
        view.layer.shouldRasterize = true
        view.layer.rasterizationScale = UIScreen.main.scale
        return view
    }()

    private var gradientLayer: CAGradientLayer?

    private lazy var manageButton: UIButton = {
        let button = ThemeManager.shared.properties.isExperimentalThemingEnabled ? BrowserChromeButton() : UIButton(type: .system)
        button.setImage(DesignSystemImages.Glyphs.Size24.expand, for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tintColor = UIColor(designSystemColor: .buttonsSecondaryFillText)
        button.addTarget(self, action: #selector(manageButtonTapped), for: .touchUpInside)
        return button
    }()

    private lazy var doneButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(UserText.navigationTitleDone, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(doneButtonTapped), for: .touchUpInside)
        return button
    }()

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(designSystemColor: .background)
        return view
    }()

    // MARK: - Initialization

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        setupGradient()
    }
    
    // MARK: - Dark Mode Support

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            // Reset gradient for color appearance changes
            DispatchQueue.main.async { [weak self] in
                self?.gradientLayer?.removeFromSuperlayer()
                self?.gradientLayer = nil
                self?.setupGradient()
            }
        }
    }

    // MARK: - Public Methods

    func updateCreditCards(_ cards: [SecureVaultModels.CreditCard]) {
        let creditCards = cards.asCardRowViewModels

        guard creditCards != self.creditCards else { return }

        self.creditCards = creditCards
        
        // Clear existing card views efficiently
        cardStackView.arrangedSubviews.forEach { view in
            cardStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        // Add new card views
        for card in creditCards {
            let cardView = createCardView(for: card)
            cardStackView.addArrangedSubview(cardView)
        }

        // Update gradient visibility after adding cards
        setNeedsLayout()
    }

    // MARK: - Private Methods

    private func setupViews() {
        backgroundColor = UIColor(designSystemColor: .background)

        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.frame = bounds.isEmpty ? CGRect(x: 0, y: 0, width: 390, height: 48) : bounds
        addSubview(containerView)

        containerView.addSubview(scrollView)
        containerView.addSubview(gradientView)
        containerView.addSubview(manageButton)
        containerView.addSubview(doneButton)

        scrollView.addSubview(cardStackView)

        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: topAnchor),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: trailingAnchor),

            manageButton.widthAnchor.constraint(equalToConstant: 44),
            manageButton.heightAnchor.constraint(equalToConstant: 44),
            doneButton.heightAnchor.constraint(equalToConstant: 44),

            manageButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            doneButton.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            doneButton.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            manageButton.trailingAnchor.constraint(equalTo: doneButton.leadingAnchor, constant: -2),

            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: manageButton.leadingAnchor, constant: 0),

            gradientView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            gradientView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            gradientView.widthAnchor.constraint(equalToConstant: 22),
            gradientView.heightAnchor.constraint(equalToConstant: 48)
        ])

        // Setup card stack after scroll view has been laid out
        NSLayoutConstraint.activate([
            cardStackView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            cardStackView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            cardStackView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            cardStackView.heightAnchor.constraint(equalToConstant: 44)
        ])

        layoutIfNeeded()
    }

    var gradientColorLight: UIColor = {
        let lightTraitCollection = UITraitCollection(userInterfaceStyle: .light)
        return UIColor(designSystemColor: .background).resolvedColor(with: lightTraitCollection)
    }()
    var gradientColorDark: UIColor = {
        let darkTraitCollection = UITraitCollection(userInterfaceStyle: .dark)
        return UIColor(designSystemColor: .background).resolvedColor(with: darkTraitCollection)
    }()

    private func setupGradient() {
        if gradientLayer == nil || gradientLayer?.frame != gradientView.bounds {
            gradientLayer?.removeFromSuperlayer()

            let newGradient = CAGradientLayer()
            let backgroundColor: UIColor
            if ThemeManager.shared.currentInterfaceStyle == .dark {
                backgroundColor = gradientColorDark
            } else {
                backgroundColor = gradientColorLight
            }
            
            newGradient.colors = [
                backgroundColor.withAlphaComponent(0).cgColor,  // Transparent
                backgroundColor.withAlphaComponent(1).cgColor   // Solid
            ]

            newGradient.locations = [0, 1]
            newGradient.startPoint = CGPoint(x: 0, y: 0.5)
            newGradient.endPoint = CGPoint(x: 1, y: 0.5)
            newGradient.frame = gradientView.bounds

            // Performance optimizations
            newGradient.shouldRasterize = true
            newGradient.rasterizationScale = UIScreen.main.scale
            newGradient.allowsGroupOpacity = false

            gradientView.layer.addSublayer(newGradient)

            // Store reference
            gradientLayer = newGradient
        }
    }

    private func createCardView(for card: CreditCardRowViewModel) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        if ThemeManager.shared.properties.isExperimentalThemingEnabled {
            containerView.backgroundColor = UIColor(designSystemColor: .controlsFillPrimary)
            containerView.layer.cornerRadius = 16
        } else {
            containerView.backgroundColor = UIColor(designSystemColor: .container)
            containerView.layer.cornerRadius = 8
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(cardTapped(_:)))
        containerView.addGestureRecognizer(tapGesture)
        containerView.isUserInteractionEnabled = true
        containerView.tag = creditCards.firstIndex(of: card) ?? -1

        let cardContentView = createCardContent(for: card)
        containerView.addSubview(cardContentView)

        NSLayoutConstraint.activate([
            cardContentView.topAnchor.constraint(equalTo: containerView.topAnchor),
            cardContentView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            cardContentView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 5),
            cardContentView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -5)
        ])

        return containerView
    }

    private func createCardContent(for card: CreditCardRowViewModel) -> UIView {
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        let iconImageView = UIImageView(image: card.uiIcon)
        iconImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(iconImageView)

        let textStackView = UIStackView()
        textStackView.axis = .vertical
        textStackView.spacing = 0
        textStackView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(textStackView)

        // Title
        let titleLabel = UILabel()
        titleLabel.text = card.compactDisplayTitle
        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = UIColor(designSystemColor: .textSecondary)
        titleLabel.numberOfLines = 1
        containerView.addSubview(titleLabel)

        // Details
        let detailsContainer = UIView()
        detailsContainer.translatesAutoresizingMaskIntoConstraints = false

        let dotsLabel = UILabel()
        dotsLabel.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        dotsLabel.text = "••••"
        dotsLabel.textColor = UIColor(designSystemColor: .textSecondary)
        dotsLabel.translatesAutoresizingMaskIntoConstraints = false

        let digitsLabel = UILabel()
        digitsLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        digitsLabel.text = card.lastFourDigits
        digitsLabel.textColor = UIColor(designSystemColor: .textSecondary)
        digitsLabel.translatesAutoresizingMaskIntoConstraints = false

        detailsContainer.addSubview(dotsLabel)
        detailsContainer.addSubview(digitsLabel)

        NSLayoutConstraint.activate([
            dotsLabel.leadingAnchor.constraint(equalTo: detailsContainer.leadingAnchor),
            dotsLabel.centerYAnchor.constraint(equalTo: detailsContainer.centerYAnchor),

            digitsLabel.leadingAnchor.constraint(equalTo: dotsLabel.trailingAnchor, constant: 4),
            digitsLabel.centerYAnchor.constraint(equalTo: detailsContainer.centerYAnchor),
            detailsContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 16)
        ])

        // Add vertical separator and expiration date only if expiration date is available
        if !card.compactExpirationDate.isEmpty {
            let verticalLine = UIView()
            verticalLine.backgroundColor = UIColor(designSystemColor: .lines)
            verticalLine.translatesAutoresizingMaskIntoConstraints = false

            let expirationLabel = UILabel()
            expirationLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
            expirationLabel.text = card.compactExpirationDate
            expirationLabel.textColor = UIColor(designSystemColor: .textSecondary)
            expirationLabel.translatesAutoresizingMaskIntoConstraints = false

            detailsContainer.addSubview(verticalLine)
            detailsContainer.addSubview(expirationLabel)

            NSLayoutConstraint.activate([
                verticalLine.leadingAnchor.constraint(equalTo: digitsLabel.trailingAnchor, constant: 6),
                verticalLine.centerYAnchor.constraint(equalTo: detailsContainer.centerYAnchor),
                verticalLine.widthAnchor.constraint(equalToConstant: 1),
                verticalLine.heightAnchor.constraint(equalToConstant: 14),

                expirationLabel.leadingAnchor.constraint(equalTo: verticalLine.trailingAnchor, constant: 6),
                expirationLabel.centerYAnchor.constraint(equalTo: detailsContainer.centerYAnchor),
                expirationLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailsContainer.trailingAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                digitsLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailsContainer.trailingAnchor)
            ])
        }

        textStackView.addArrangedSubview(titleLabel)
        textStackView.addArrangedSubview(detailsContainer)

        NSLayoutConstraint.activate([
            iconImageView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 4),
            iconImageView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),
            iconImageView.widthAnchor.constraint(equalToConstant: 32),
            iconImageView.heightAnchor.constraint(equalToConstant: 32),

            textStackView.leadingAnchor.constraint(equalTo: iconImageView.trailingAnchor, constant: 8),
            textStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -6),
            textStackView.centerYAnchor.constraint(equalTo: containerView.centerYAnchor),

            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        return containerView
    }

    @objc private func cardTapped(_ gesture: UITapGestureRecognizer) {
        if let view = gesture.view,
           let index = creditCards.indices.contains(view.tag) ? view.tag : nil {

            if AppDependencyProvider.shared.autofillLoginSession.isSessionValid {
                onCardSelected?(creditCards[index].creditCard)
                return
            }

            authenticator.authenticate { [weak self] error in
                defer {
                    self?.authenticator.logOut()
                }
                if let _ = error {
                    AppDependencyProvider.shared.autofillLoginSession.endSession()
                    self?.onCardSelected?(nil)
                    return
                }

                guard let creditCards = self?.creditCards else {
                    self?.onCardSelected?(nil)
                    return
                }
                self?.onCardSelected?(creditCards[index].creditCard)
                AppDependencyProvider.shared.autofillLoginSession.startSession()
            }
        }
    }
    
    @objc private func manageButtonTapped() {
        onCardManagementSelected?()
    }

    @objc private func doneButtonTapped() {
        onCardSelected?(nil)
    }
}
