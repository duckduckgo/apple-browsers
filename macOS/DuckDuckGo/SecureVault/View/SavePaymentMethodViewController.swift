//
//  SavePaymentMethodViewController.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import AppKit
import BrowserServicesKit
import Combine
import Common
import FoundationExtensions
import Foundation
import os.log
import PixelKit

protocol SavePaymentMethodDelegate: AnyObject {

    func shouldCloseSavePaymentMethodViewController(_: SavePaymentMethodViewController)

}

final class SavePaymentMethodViewController: NSViewController {

    private enum LayoutConstants {
        static let contentSize = CGSize(width: 376, height: 156)
        static let inset: CGFloat = 16
        static let settingsButtonSide: CGFloat = 20
        static let logoSide: CGFloat = 24
        static let cardIconSide: CGFloat = 32
        static let titleWidth: CGFloat = 280
    }

    static func create() -> SavePaymentMethodViewController {
        let controller = SavePaymentMethodViewController(nibName: nil, bundle: nil)
        // Calling loadView() directly won't send viewDidLoad()
        _ = controller.view

        return controller
    }

    var cardDetailsLabel: NSTextField!
    var cardExpirationLabel: NSTextField!
    var titleLabel: NSTextField!
    var saveButton: NSButton!
    var dontSaveButton: NSButton!
    var cardIconImageView: NSImageView!

    weak var delegate: SavePaymentMethodDelegate?

    private var paymentMethod: SecureVaultModels.CreditCard?

    override func loadView() {
        let view = NSView(frame: NSRect(origin: .zero, size: LayoutConstants.contentSize))

        let logoImageView = NSImageView()
        logoImageView.translatesAutoresizingMaskIntoConstraints = false
        logoImageView.image = .daxLockScreenLogo
        logoImageView.imageScaling = .scaleProportionallyDown
        logoImageView.imageAlignment = .alignLeft
        logoImageView.refusesFirstResponder = true
        logoImageView.animates = true

        titleLabel = NSTextField(labelWithString: "")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .medium)

        let openPreferencesButton = MouseOverButton(frame: .zero)
        openPreferencesButton.translatesAutoresizingMaskIntoConstraints = false
        openPreferencesButton.setButtonType(.momentaryChange)
        openPreferencesButton.isBordered = false
        openPreferencesButton.bezelStyle = .rounded
        openPreferencesButton.image = .settings16
        openPreferencesButton.imagePosition = .imageOnly
        openPreferencesButton.title = ""
        openPreferencesButton.imageScaling = .scaleProportionallyDown
        openPreferencesButton.alignment = .center
        openPreferencesButton.target = self
        openPreferencesButton.action = #selector(onOpenPreferencesClicked(sender:))

        let headerStackView = NSStackView(views: [logoImageView, titleLabel, openPreferencesButton])
        headerStackView.translatesAutoresizingMaskIntoConstraints = false
        headerStackView.orientation = .horizontal
        headerStackView.distribution = .fill
        headerStackView.alignment = .centerY
        headerStackView.spacing = 10
        headerStackView.detachesHiddenViews = true

        let topSeparator = NSBox()
        topSeparator.translatesAutoresizingMaskIntoConstraints = false
        topSeparator.boxType = .separator
        topSeparator.setContentHuggingPriority(.init(750), for: .vertical)

        cardIconImageView = NSImageView()
        cardIconImageView.translatesAutoresizingMaskIntoConstraints = false
        cardIconImageView.image = .card
        cardIconImageView.imageScaling = .scaleProportionallyDown
        cardIconImageView.imageAlignment = .alignLeft
        cardIconImageView.refusesFirstResponder = true

        let bottomSeparator = NSBox()
        bottomSeparator.translatesAutoresizingMaskIntoConstraints = false
        bottomSeparator.boxType = .separator
        bottomSeparator.setContentHuggingPriority(.init(750), for: .vertical)

        cardDetailsLabel = NSTextField(labelWithString: "")
        cardDetailsLabel.translatesAutoresizingMaskIntoConstraints = false
        cardDetailsLabel.lineBreakMode = .byClipping

        cardExpirationLabel = NSTextField(labelWithString: "")
        cardExpirationLabel.translatesAutoresizingMaskIntoConstraints = false
        cardExpirationLabel.lineBreakMode = .byClipping

        saveButton = NSButton(title: "", target: self, action: #selector(onSaveClicked(sender:)))
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        saveButton.bezelStyle = .rounded

        dontSaveButton = NSButton(title: "", target: self, action: #selector(onDontSaveClicked(sender:)))
        dontSaveButton.translatesAutoresizingMaskIntoConstraints = false
        dontSaveButton.bezelStyle = .rounded

        view.addSubview(headerStackView)
        view.addSubview(topSeparator)
        view.addSubview(cardIconImageView)
        view.addSubview(bottomSeparator)
        view.addSubview(cardDetailsLabel)
        view.addSubview(cardExpirationLabel)
        view.addSubview(saveButton)
        view.addSubview(dontSaveButton)

        NSLayoutConstraint.activate([
            logoImageView.widthAnchor.constraint(equalToConstant: LayoutConstants.logoSide),
            logoImageView.heightAnchor.constraint(equalToConstant: LayoutConstants.logoSide),
            titleLabel.widthAnchor.constraint(equalToConstant: LayoutConstants.titleWidth),
            openPreferencesButton.widthAnchor.constraint(equalToConstant: LayoutConstants.settingsButtonSide),
            openPreferencesButton.heightAnchor.constraint(equalToConstant: LayoutConstants.settingsButtonSide),

            headerStackView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.inset),
            headerStackView.topAnchor.constraint(equalTo: view.topAnchor, constant: 11),
            view.trailingAnchor.constraint(equalTo: headerStackView.trailingAnchor, constant: LayoutConstants.inset),

            topSeparator.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            topSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: topSeparator.trailingAnchor),

            cardIconImageView.widthAnchor.constraint(equalToConstant: LayoutConstants.cardIconSide),
            cardIconImageView.heightAnchor.constraint(equalToConstant: LayoutConstants.cardIconSide),
            cardIconImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: LayoutConstants.inset),
            cardIconImageView.topAnchor.constraint(equalTo: topSeparator.bottomAnchor, constant: LayoutConstants.inset),

            cardDetailsLabel.leadingAnchor.constraint(equalTo: cardIconImageView.trailingAnchor, constant: LayoutConstants.inset),
            cardDetailsLabel.centerYAnchor.constraint(equalTo: cardIconImageView.centerYAnchor),
            cardExpirationLabel.leadingAnchor.constraint(equalTo: cardDetailsLabel.trailingAnchor, constant: LayoutConstants.inset),
            cardExpirationLabel.centerYAnchor.constraint(equalTo: cardDetailsLabel.centerYAnchor),
            view.trailingAnchor.constraint(greaterThanOrEqualTo: cardExpirationLabel.trailingAnchor, constant: LayoutConstants.inset),

            bottomSeparator.topAnchor.constraint(equalTo: cardIconImageView.bottomAnchor, constant: LayoutConstants.inset),
            bottomSeparator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: bottomSeparator.trailingAnchor),

            saveButton.topAnchor.constraint(equalTo: bottomSeparator.bottomAnchor, constant: 12),
            view.trailingAnchor.constraint(equalTo: saveButton.trailingAnchor, constant: LayoutConstants.inset),
            view.bottomAnchor.constraint(equalTo: saveButton.bottomAnchor, constant: 12),
            saveButton.leadingAnchor.constraint(equalTo: dontSaveButton.trailingAnchor, constant: 8),
            dontSaveButton.centerYAnchor.constraint(equalTo: saveButton.centerYAnchor),
        ])

        self.view = view
    }

    // MARK: - Public

    override func viewDidLoad() {
        super.viewDidLoad()
        setUpStrings()
    }

    func savePaymentMethod(_ paymentMethod: SecureVaultModels.CreditCard) {
        self.paymentMethod = paymentMethod

        let type = CreditCardValidation.type(for: paymentMethod.cardNumber)
        cardDetailsLabel.stringValue = "\(type.displayName) ••••\(paymentMethod.cardSuffix)"

        if let expirationMonth = paymentMethod.expirationMonth, let expirationYear = paymentMethod.expirationYear {
            let formattedDate = String(format: "%02d/%d", expirationMonth, expirationYear)
            cardExpirationLabel.stringValue = String(format: UserText.pmCardExpiresFormat, formattedDate)
        } else {
            cardExpirationLabel.stringValue = ""
        }

        cardIconImageView.image = paymentMethod.iconImage
    }

    // MARK: - Actions

    @objc func onDontSaveClicked(sender: NSButton) {
        self.delegate?.shouldCloseSavePaymentMethodViewController(self)
    }

    @objc func onSaveClicked(sender: NSButton) {
        defer {
            self.delegate?.shouldCloseSavePaymentMethodViewController(self)
        }

        guard var paymentMethod = paymentMethod else {
            assertionFailure("Tried to save payment method, but the view controller didn't have one")
            return
        }

        paymentMethod.title = CreditCardValidation.type(for: paymentMethod.cardNumber).displayName

        do {
            try AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter.shared).storeCreditCard(paymentMethod)

            if let syncService = NSApp.delegateTyped.syncService {
                syncService.scheduler.requestSyncImmediately()
            }
        } catch {
            Logger.secureVault.error("Failed to store payment method \(error.localizedDescription)")
            PixelKit.fire(DebugEvent(GeneralPixel.secureVaultError(error: error), error: error))
        }
    }

    @objc func onOpenPreferencesClicked(sender: NSButton) {
        Application.appDelegate.windowControllersManager.showPreferencesTab()
        self.delegate?.shouldCloseSavePaymentMethodViewController(self)
    }

    private func setUpStrings() {
        titleLabel.stringValue = UserText.passwordManagementSaveCard
        dontSaveButton.title = UserText.dontSave
        saveButton.title = UserText.save
    }
}
