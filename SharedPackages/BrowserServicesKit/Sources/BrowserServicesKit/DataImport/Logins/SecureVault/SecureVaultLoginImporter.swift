//
//  SecureVaultLoginImporter.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import SecureStorage

public class SecureVaultLoginImporter: LoginImporter {
    private var loginImportState: AutofillLoginImportStateStoring?

    public init(loginImportState: AutofillLoginImportStateStoring? = nil) {
        self.loginImportState = loginImportState
    }

    private enum ImporterError: Error {
        case duplicate
    }

    public func importLogins(_ logins: [ImportedLoginCredential], reporter: SecureVaultReporting, progressCallback: @escaping (Int) throws -> Void) throws -> DataImport.DataTypeSummary {

        let vault = try AutofillSecureVaultFactory.makeVault(reporter: reporter)

        var successful: Int = 0
        var duplicateItems: [DataImport.DataImportItem] = []
        var failedItems: [DataImport.DataImportItem] = []

        let encryptionKey = try vault.getEncryptionKey()
        let hashingSalt = try vault.getHashingSalt()

        let accounts = (try? vault.accounts()) ?? .init()

        try vault.inDatabaseTransaction { [weak self] database in
            for (idx, login) in logins.enumerated() {
                let title = login.title
                let account = SecureVaultModels.WebsiteAccount(title: title, username: login.username, domain: login.url, notes: login.notes)
                let credentials = SecureVaultModels.WebsiteCredentials(account: account, password: login.password.data(using: .utf8)!)

                do {
                    if let signature = try vault.encryptPassword(for: credentials, key: encryptionKey, salt: hashingSalt).account.signature {
                        let isDuplicate = accounts.contains {
                            $0.isDuplicateOf(accountToBeImported: account, signatureOfAccountToBeImported: signature, passwordToBeImported: login.password)
                        }
                        if isDuplicate {
                            throw ImporterError.duplicate
                        }
                    }
                    _ = try vault.storeWebsiteCredentials(credentials, in: database, encryptedUsing: encryptionKey, hashedUsing: hashingSalt)
                    successful += 1
                } catch {
                    let domain = login.url ?? login.eTldPlusOne ?? ""
                    let isDuplicate = self?.isDuplicateError(error) ?? false
                    let errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription

                    let importItem = DataImport.DataImportItem.password(
                        title: login.title,
                        domain: domain,
                        username: login.username,
                        errorMessage: errorMessage
                    )

                    if isDuplicate {
                        duplicateItems.append(importItem)
                    } else {
                        failedItems.append(importItem)
                    }
                }

                try progressCallback(idx + 1)
            }
        }

        if successful > 0 {
            NotificationCenter.default.post(name: .autofillSaveEvent, object: nil, userInfo: nil)
        }

        loginImportState?.hasImportedLogins = true
        return DataImport.DataTypeSummary(
            successful: successful,
            duplicateItems: duplicateItems,
            failedItems: failedItems
        )
    }

    private func isDuplicateError(_ error: Error) -> Bool {
        if case .duplicateRecord = error as? SecureStorageError {
            return true
        } else if case .duplicate = error as? ImporterError {
            return true
        } else {
            return false
        }
    }
}

extension SecureVaultModels.WebsiteAccount {

    // Deduplication rules: https://app.asana.com/0/0/1207598052765977/f
    func isDuplicateOf(accountToBeImported: Self, signatureOfAccountToBeImported: String, passwordToBeImported: String?) -> Bool {
        guard signature == signatureOfAccountToBeImported || passwordToBeImported.isNilOrEmpty else {
            return false
        }
        guard username == accountToBeImported.username || accountToBeImported.username.isNilOrEmpty else {
            return false
        }
        guard domain == accountToBeImported.domain || accountToBeImported.domain.isNilOrEmpty else {
            return false
        }
        guard notes == accountToBeImported.notes || accountToBeImported.notes.isNilOrEmpty else {
            return false
        }
        guard patternMatchedTitle() == accountToBeImported.patternMatchedTitle() || accountToBeImported.patternMatchedTitle().isEmpty else {
            return false
        }
        return true
    }
}
