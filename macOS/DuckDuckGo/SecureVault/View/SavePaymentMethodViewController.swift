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
import Foundation
import os.log
import PixelKit

protocol SavePaymentMethodDelegate: AnyObject {

    func shouldCloseSavePaymentMethodViewController(_: SavePaymentMethodViewController)

}

final class SavePaymentMethodViewController: NSViewController {

    enum Constants {
        static let storyboardName = "PasswordManager"
        static let identifier = "SavePaymentMethod"
    }

    static func create() -> SavePaymentMethodViewController {
        let storyboard = NSStoryboard(name: Constants.storyboardName, bundle: nil)
        let controller: SavePaymentMethodViewController = storyboard.instantiateController(identifier: Constants.identifier)
        controller.loadView()

        return controller
    }

    @IBOutlet weak var cardDetailsLabel: NSTextField!
    @IBOutlet weak var cardExpirationLabel: NSTextField!
    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var saveButton: NSButton!
    @IBOutlet weak var dontSaveButton: NSButton!
    @IBOutlet weak var cardIconImageView: NSImageView!

    weak var delegate: SavePaymentMethodDelegate?

    private var paymentMethod: SecureVaultModels.CreditCard?

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

    @IBAction func onDontSaveClicked(sender: NSButton) {
        self.delegate?.shouldCloseSavePaymentMethodViewController(self)
    }

    @IBAction func onSaveClicked(sender: NSButton) {
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

    @IBAction func onOpenPreferencesClicked(sender: NSButton) {
        Application.appDelegate.windowControllersManager.showPreferencesTab()
        self.delegate?.shouldCloseSavePaymentMethodViewController(self)
    }

    private func setUpStrings() {
        titleLabel.stringValue = UserText.passwordManagementSaveCard
        dontSaveButton.title = UserText.dontSave
        saveButton.title = UserText.save
    }
}
