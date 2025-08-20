//
//  DataImportSummaryViewModel.swift
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
import BrowserServicesKit
import DDGSync
import Core

protocol DataImportSummaryViewModelDelegate: AnyObject {
    func dataImportSummaryViewModelDidRequestLaunchSync(_ viewModel: DataImportSummaryViewModel)
    func dataImportSummaryViewModelComplete(_ viewModel: DataImportSummaryViewModel)
}

final class DataImportSummaryViewModel: ObservableObject {

    weak var delegate: DataImportSummaryViewModelDelegate?

    @Published var passwordsSummary: DataImport.DataTypeSummary?
    @Published var bookmarksSummary: DataImport.DataTypeSummary?
    @Published var creditCardsSummary: DataImport.DataTypeSummary?

    let importScreen: DataImportViewModel.ImportScreen
    private let syncService: DDGSyncing

    var syncIsActive: Bool {
        syncService.authState != .inactive
    }

    var syncButtonTitle: String {
        if passwordsSummary != nil && bookmarksSummary != nil {
            return String(format: UserText.dataImportSummarySync,
                          UserText.dataImportSummarySyncData)
        } else if passwordsSummary != nil {
            return String(format: UserText.dataImportSummarySync,
                          UserText.dataImportSummarySyncPasswords)
        } else {
            return String(format: UserText.dataImportSummarySync,
                          UserText.dataImportSummarySyncBookmarks)
        }
    }

    init(summary: DataImportSummary, importScreen: DataImportViewModel.ImportScreen, syncService: DDGSyncing) {
        self.passwordsSummary = try? summary[.passwords]?.get()
        self.bookmarksSummary = try? summary[.bookmarks]?.get()
        self.creditCardsSummary = try? summary[.creditCards]?.get()
        self.importScreen = importScreen
        self.syncService = syncService

        fireSummaryPixels()
    }

    /// Returns true only when ALL supported data types (passwords, bookmarks, and optionally credit cards)
    /// have been imported successfully with zero failures and duplicates for specific UI layout
    func isAllSuccessful() -> Bool {
        guard let passwords = passwordsSummary,
              passwords.failed == 0,
              passwords.duplicate == 0 else {
            return false
        }

        guard let bookmarks = bookmarksSummary,
              bookmarks.failed == 0,
              bookmarks.duplicate == 0 else {
            return false
        }

        if AppDependencyProvider.shared.featureFlagger.isFeatureOn(.autofillCreditCards) {
            guard let creditCards = creditCardsSummary,
                  creditCards.failed == 0,
                  creditCards.duplicate == 0 else {
                return false
            }
        }

        return true
    }

    func fireSyncButtonShownPixel() {
        Pixel.fire(pixel: .importResultSyncButtonShown, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue])
    }
    
    func fireSummaryPixels() {
        if let passwords = passwordsSummary {
            let successBucket = AutofillPixelReporter.accountsBucketNameFrom(count: passwords.successful)
            let skippedBucket = AutofillPixelReporter.accountsBucketNameFrom(count: passwords.duplicate + passwords.failed)
            Pixel.fire(pixel: .importResultPasswordsSuccess, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue,
                                                                                        PixelParameters.savedCredentials: successBucket,
                                                                                        PixelParameters.skippedCredentials: skippedBucket])
        }
        if let bookmarks = bookmarksSummary {
            Pixel.fire(pixel: .importResultBookmarksSuccess, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue,
                                                                                        PixelParameters.bookmarkCount: "\(bookmarks.successful)"])
        }
        if let creditCards = creditCardsSummary {
            let successBucket = AutofillPixelReporter.creditCardsBucketNameFrom(count: creditCards.successful)
            let skippedBucket = AutofillPixelReporter.creditCardsBucketNameFrom(count: creditCards.duplicate + creditCards.failed)
            Pixel.fire(pixel: .importResultCreditCardsSuccess, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue,
                                                                                          PixelParameters.savedCreditCards: successBucket,
                                                                                          PixelParameters.skippedCreditCards: skippedBucket])
        }
    }

    func dismiss() {
        delegate?.dataImportSummaryViewModelComplete(self)
    }

    func launchSync() {
        delegate?.dataImportSummaryViewModelDidRequestLaunchSync(self)
        Pixel.fire(pixel: .importResultSyncButtonTapped, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue])
    }

}
