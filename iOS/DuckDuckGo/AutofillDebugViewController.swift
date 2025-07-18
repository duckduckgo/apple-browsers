//
//  AutofillDebugViewController.swift
//  DuckDuckGo
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import BrowserServicesKit
import Core
import Common
import PrivacyDashboard
import os.log
import Persistence

class AutofillDebugViewController: UITableViewController {

    enum Row: Int {
        case toggleAutofillDebugScript = 201
        case resetEmailProtectionInContextSignUp = 202
        case resetDaysSinceInstalledTo0 = 203
        case deleteAllCredentials = 204
        case deleteAllCreditCards = 205
        case addAutofillCredentials = 206
        case addAutofillCreditCards = 207
        case resetAutofillSettings = 208
        case resetAutofillBrokenReports = 209
        case resetAutofillSurveys = 210
        case viewAllCredentials = 211
        case resetAutofillImportPromos = 212
    }

    let defaults = AppUserDefaults()
    var keyValueStore: ThrowingKeyValueStoring?

    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        if cell.tag == Row.toggleAutofillDebugScript.rawValue {
            cell.accessoryType = defaults.autofillDebugScriptEnabled ? .checkmark : .none
        }
    }

    @UserDefaultsWrapper(key: .autofillSaveModalRejectionCount, defaultValue: 0)
    private var autofillSaveModalRejectionCount: Int

    @UserDefaultsWrapper(key: .autofillSaveModalDisablePromptShown, defaultValue: false)
    private var autofillSaveModalDisablePromptShown: Bool

    @UserDefaultsWrapper(key: .autofillFirstTimeUser, defaultValue: true)
    private var autofillFirstTimeUser: Bool
    
    @UserDefaultsWrapper(key: .autofillCreditCardsSaveModalRejectionCount, defaultValue: 0)
    private var autofillCreditCardsSaveModalRejectionCount: Int
    
    @UserDefaultsWrapper(key: .autofillCreditCardsSaveModalDisablePromptShown, defaultValue: false)
    private var autofillCreditCardsSaveModalDisablePromptShown: Bool

    @UserDefaultsWrapper(key: .autofillCreditCardsFirstTimeUser, defaultValue: true)
    private var autofillCreditCardsFirstTimeUser: Bool

    // swiftlint:disable:next cyclomatic_complexity
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if let cell = tableView.cellForRow(at: indexPath) {
            if cell.tag == Row.toggleAutofillDebugScript.rawValue {
                defaults.autofillDebugScriptEnabled.toggle()
                cell.accessoryType = defaults.autofillDebugScriptEnabled ? .checkmark : .none
                NotificationCenter.default.post(Notification(name: AppUserDefaults.Notifications.autofillDebugScriptToggled))
            } else if cell.tag == Row.deleteAllCredentials.rawValue {
                let secureVault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
                // delete all credential related data
                try? secureVault?.deleteAllWebsiteCredentials()
                ActionMessageView.present(message: "All credentials deleted")
            } else if cell.tag == Row.deleteAllCreditCards.rawValue {
                let secureVault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
                // delete all credit card related data
                let creditCards = try? secureVault?.creditCards()
                for card in creditCards ?? [] {
                    guard let id = card.id else { continue }
                    try? secureVault?.deleteCreditCardFor(cardId: id)
                }
                ActionMessageView.present(message: "All credit cards deleted")
            } else if cell.tag == Row.addAutofillCredentials.rawValue {
                promptForNumberOfLoginsToAdd()
            } else if cell.tag == Row.addAutofillCreditCards.rawValue {
                let amexCC = SecureVaultModels.CreditCard(cardNumber: "378282246310005", cardholderName: "Dax Smith", cardSecurityCode: "123", expirationMonth: 12, expirationYear: 2025)
                let visaCC = SecureVaultModels.CreditCard(cardNumber: "4222222222222", cardholderName: "Daxie Duck", cardSecurityCode: "123", expirationMonth: 1, expirationYear: 2026)
                let mastercardCC = SecureVaultModels.CreditCard(cardNumber: "5555555555554444", cardholderName: "Dax Duckling", cardSecurityCode: "123", expirationMonth: nil, expirationYear: nil)

                for creditCard in [amexCC, visaCC, mastercardCC] {
                    do {
                        let secureVault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())
                        _ = try secureVault?.storeCreditCard(creditCard)
                    } catch let error {
                        Logger.general.error("Error inserting credit card: \(error.localizedDescription, privacy: .public)")
                    }
                }
                ActionMessageView.present(message: "Credit Cards added")
            } else if cell.tag == Row.resetAutofillSettings.rawValue {
                let autofillPixelReporter = AutofillPixelReporter(
                        usageStore: AutofillUsageStore(),
                        autofillEnabled: AppUserDefaults().autofillCredentialsEnabled,
                        eventMapping: EventMapping<AutofillPixelEvent> { _, _, _, _ in })
                autofillPixelReporter.resetStoreDefaults()

                autofillSaveModalRejectionCount = 0
                autofillSaveModalDisablePromptShown = false
                autofillFirstTimeUser = true
                _ = AppDependencyProvider.shared.autofillNeverPromptWebsitesManager.deleteAllNeverPromptWebsites()

                autofillCreditCardsSaveModalRejectionCount = 0
                autofillCreditCardsSaveModalDisablePromptShown = false
                autofillCreditCardsFirstTimeUser = true
                ActionMessageView.present(message: "Autofill Settings reset")
            } else if cell.tag == Row.resetEmailProtectionInContextSignUp.rawValue {
                EmailManager().resetEmailProtectionInContextPrompt()
                ActionMessageView.present(message: "Email Protection InContext Sign Up reset")
            } else if cell.tag == Row.resetDaysSinceInstalledTo0.rawValue {
                StatisticsUserDefaults().installDate = Date()
            } else if cell.tag == Row.resetAutofillBrokenReports.rawValue {
                let reporter = BrokenSiteReporter(pixelHandler: { _ in }, keyValueStoring: UserDefaults.standard, storageConfiguration: .autofillConfig)
                let expiryDate = Calendar.current.date(byAdding: .day, value: 60, to: Date())!
                _ = reporter.persistencyManager.removeExpiredItems(currentDate: expiryDate)
                ActionMessageView.present(message: "Autofill Broken Reports reset")
            } else if cell.tag == Row.resetAutofillSurveys.rawValue {
                let autofillSurveyManager = AutofillSurveyManager()
                autofillSurveyManager.resetSurveys()
                ActionMessageView.present(message: "Autofill Surveys reset")
            } else if cell.tag == Row.resetAutofillImportPromos.rawValue {
                guard let keyValueStore = keyValueStore else {
                    ActionMessageView.present(message: "Failed to reset Import Prompts")
                    return
                }
                let importState = AutofillLoginImportState(keyValueStore: keyValueStore)
                importState.hasImportedLogins = false
                importState.isCredentialsImportPromoInBrowserPermanentlyDismissed = false
                importState.isCredentialsImportPromoInPasswordsScreenPermanentlyDismissed = false
                try? keyValueStore.set(nil, forKey: SettingsViewModel.Constants.didDismissImportPasswordsKey)
                ActionMessageView.present(message: "Import Prompts reset")
            }
        }
    }

    private func promptForNumberOfLoginsToAdd() {
        let alertController = UIAlertController(title: "Enter number of Logins to add for autofill.me", message: nil, preferredStyle: .alert)

        alertController.addTextField { textField in
            textField.placeholder = "Number"
            textField.keyboardType = .numberPad
        }

        let submitAction = UIAlertAction(title: "Add", style: .default) { [unowned alertController] _ in
            let textField = alertController.textFields![0]
            if let numberString = textField.text, let number = Int(numberString) {
                self.addLogins(number)
            }
        }
        alertController.addAction(submitAction)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alertController, animated: true)
    }

    private func addLogins(_ count: Int) {
        let secureVault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter())

        for i in 1...count {
            let account = SecureVaultModels.WebsiteAccount(title: "", username: "Dax \(i)", domain: "autofill.me", notes: "")
            let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: "password".data(using: .utf8))
            do {
                _ = try secureVault?.storeWebsiteCredentials(credentials)
            } catch let error {
                Logger.general.error("Error inserting credential \(error.localizedDescription, privacy: .public)")
            }
        }

        ActionMessageView.present(message: "Autofill Data added")
    }

}
