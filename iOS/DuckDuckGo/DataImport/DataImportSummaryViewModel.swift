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
import PrivacyConfig

protocol DataImportSummaryViewModelDelegate: AnyObject {
    func dataImportSummaryViewModelDidRequestLaunchSync(_ viewModel: DataImportSummaryViewModel, source: String?)
    func dataImportSummaryViewModelDidRequestContinueImportFromSafari(_ viewModel: DataImportSummaryViewModel)
    func dataImportSummaryViewModelComplete(_ viewModel: DataImportSummaryViewModel)
}

final class DataImportSummaryViewModel: ObservableObject {

    enum Footer: Equatable {
        case syncButton(title: String)
        case syncPromo(title: String)
        case passwordsPromo
        case bookmarksPromo
        case message(body: String)
    }

    enum ContinueImportDataType {
        case passwords
        case bookmarks
    }

    enum ContinueImportAction {
        case shown
        case dismissTapped
        case continueTapped
    }

    weak var delegate: DataImportSummaryViewModelDelegate?

    @Published var passwordsSummary: DataImport.DataTypeSummary?
    @Published var bookmarksSummary: DataImport.DataTypeSummary?
    @Published var creditCardsSummary: DataImport.DataTypeSummary?

    let importScreen: DataImportViewModel.ImportScreen
    private let syncService: DDGSyncing
    private let featureFlagger: FeatureFlagger
    private let syncPromoManager: SyncPromoManaging
    private let sessionImportedDataTypes: Set<DataImport.DataType>
    private let isSafariImportFlow: Bool
    private let importHubPixelContext: DataImportHubPixelContext?
    private let isSupportedOSVersion: () -> Bool

    private var isImportHubFlow: Bool {
        importHubPixelContext != nil
    }

    private var importHubPixelParameters: [String: String] {
        importHubPixelContext?.parameters ?? [:]
    }

    var shouldShowPasswordsFileDeletionHint: Bool {
        isSafariImportFlow && passwordsSummary != nil
    }

    var importedDataTypesCount: Int {
        [passwordsSummary, bookmarksSummary, creditCardsSummary].compactMap { $0 }.count
    }

    var footer: Footer? {
        if importScreen == .whatsNew {
            return .message(body: UserText.dataImportSummaryVisitSyncSettings)
        }

        if shouldUseNewImportPromoStrategy {
            return prioritizedFooterForNewImportFlow
        }

        if !syncIsActive {
            if featureFlagger.isFeatureOn(.dataImportSummarySyncPromotion) {
                guard syncPromoManager.shouldPresentPromoFor(.dataImport, count: successfulImportsCount) else {
                    return nil
                }
                return .syncPromo(title: newSyncPromoTitle)
            }
            return .syncButton(title: syncButtonTitle)
        }

        return nil
    }

    private var shouldUseNewImportPromoStrategy: Bool {
        isSupportedOSVersion() && featureFlagger.isFeatureOn(.dataImportNewUI) && isSafariImportFlow
    }

    private var prioritizedFooterForNewImportFlow: Footer? {
        if !hasImportedPasswordsInSession {
            return .passwordsPromo
        }

        if !hasImportedBookmarksInSession {
            return .bookmarksPromo
        }

        if !syncIsActive,
           syncPromoManager.shouldPresentPromoFor(.dataImport, count: successfulImportsCount) {
            return .syncPromo(title: newImportFlowSyncPromoTitle)
        }

        return nil
    }

    private var hasImportedPasswordsInSession: Bool {
        passwordsSummary != nil || sessionImportedDataTypes.contains(.passwords)
    }

    private var hasImportedBookmarksInSession: Bool {
        bookmarksSummary != nil || sessionImportedDataTypes.contains(.bookmarks)
    }

    private var hasImportedCreditCardsInSession: Bool {
        creditCardsSummary != nil || sessionImportedDataTypes.contains(.creditCards)
    }

    private var syncIsActive: Bool {
        syncService.authState != .inactive
    }

    private var successfulImportsCount: Int {
        let passwordsSuccess = passwordsSummary?.successful ?? 0
        let bookmarksSuccess = bookmarksSummary?.successful ?? 0
        let creditCardsSuccess = creditCardsSummary?.successful ?? 0
        return passwordsSuccess + bookmarksSuccess + creditCardsSuccess
    }

    private var syncButtonTitle: String {
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
    
    private var newSyncPromoTitle: String {
        let nonNilCount = [passwordsSummary, bookmarksSummary, creditCardsSummary].compactMap { $0 }.count
        if nonNilCount > 1 {
            return UserText.syncPromoDataImportTitle
        } else if passwordsSummary != nil {
            return UserText.syncPromoPasswordsTitle
        } else if bookmarksSummary != nil {
            return UserText.syncPromoBookmarksTitle
        } else if creditCardsSummary != nil {
            return UserText.syncPromoCreditCardsTitle
        }
        
        return ""
    }

    private var newImportFlowSyncPromoTitle: String {
        let importedDataTypes = [hasImportedPasswordsInSession, hasImportedBookmarksInSession, hasImportedCreditCardsInSession]
        let importedDataTypesCount = importedDataTypes.filter { $0 }.count

        if importedDataTypesCount > 1 {
            return UserText.syncPromoDataImportTitle
        } else if hasImportedPasswordsInSession {
            return UserText.syncPromoPasswordsTitle
        } else if hasImportedBookmarksInSession {
            return UserText.syncPromoBookmarksTitle
        } else if hasImportedCreditCardsInSession {
            return UserText.syncPromoCreditCardsTitle
        }

        return ""
    }

    init(summary: DataImportSummary,
         importScreen: DataImportViewModel.ImportScreen,
         syncService: DDGSyncing,
         sessionImportedDataTypes: Set<DataImport.DataType> = [],
         isSafariImportFlow: Bool = false,
         importHubPixelContext: DataImportHubPixelContext? = nil,
         isSupportedOSVersion: @escaping () -> Bool = {
             if #available(iOS 26.4, *) {
                 return true
             } else {
                 return false
             }
         },
         syncPromoManager: SyncPromoManaging? = nil,
         featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger) {
        self.passwordsSummary = try? summary[.passwords]?.get()
        self.bookmarksSummary = try? summary[.bookmarks]?.get()
        self.creditCardsSummary = try? summary[.creditCards]?.get()
        self.importScreen = importScreen
        self.syncService = syncService
        self.sessionImportedDataTypes = sessionImportedDataTypes
        self.isSafariImportFlow = isSafariImportFlow
        self.importHubPixelContext = importHubPixelContext
        self.isSupportedOSVersion = isSupportedOSVersion
        self.syncPromoManager = syncPromoManager ?? SyncPromoManager(syncService: syncService, featureFlagger: featureFlagger)
        self.featureFlagger = featureFlagger

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

        if featureFlagger.isFeatureOn(.autofillCreditCards) {
            guard let creditCards = creditCardsSummary,
                  creditCards.failed == 0,
                  creditCards.duplicate == 0 else {
                return false
            }
        }

        return true
    }

    func fireSyncButtonShownPixel() {
        guard !isImportHubFlow else { return }

        Pixel.fire(pixel: .importResultSyncButtonShown, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue])
    }

    func fireSyncPromoDisplayedPixel() {
        Pixel.fire(.syncPromoDisplayed, withAdditionalParameters: ["source": SyncPromoManager.Touchpoint.dataImport.rawValue])

        if isImportHubFlow {
            Pixel.fire(pixel: .importHubResultSyncPromoShown, withAdditionalParameters: importHubPixelParameters)
        }
    }
    
    func fireSummaryPixels() {
        if let passwords = passwordsSummary {
            let successBucket = AutofillPixelReporter.accountsBucketNameFrom(count: passwords.successful)
            let skippedBucket = AutofillPixelReporter.accountsBucketNameFrom(count: passwords.duplicate + passwords.failed)
            if let importHubPixelContext {
                var parameters = importHubPixelContext.parameters
                parameters[PixelParameters.savedCredentials] = successBucket
                parameters[PixelParameters.skippedCredentials] = skippedBucket
                Pixel.fire(pixel: .importHubResultPasswordsSuccess, withAdditionalParameters: parameters)
            } else {
                Pixel.fire(pixel: .importResultPasswordsSuccess, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue,
                                                                                            PixelParameters.savedCredentials: successBucket,
                                                                                            PixelParameters.skippedCredentials: skippedBucket])
            }
        }
        if let bookmarks = bookmarksSummary {
            if let importHubPixelContext {
                var parameters = importHubPixelContext.parameters
                parameters[PixelParameters.bookmarkCount] = "\(bookmarks.successful)"
                Pixel.fire(pixel: .importHubResultBookmarksSuccess, withAdditionalParameters: parameters)
            } else {
                Pixel.fire(pixel: .importResultBookmarksSuccess, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue,
                                                                                            PixelParameters.bookmarkCount: "\(bookmarks.successful)"])
            }
        }
        if let creditCards = creditCardsSummary {
            let successBucket = AutofillPixelReporter.creditCardsBucketNameFrom(count: creditCards.successful)
            let skippedBucket = AutofillPixelReporter.creditCardsBucketNameFrom(count: creditCards.duplicate + creditCards.failed)
            if let importHubPixelContext {
                var parameters = importHubPixelContext.parameters
                parameters[PixelParameters.savedCreditCards] = successBucket
                parameters[PixelParameters.skippedCreditCards] = skippedBucket
                Pixel.fire(pixel: .importHubResultCreditCardsSuccess, withAdditionalParameters: parameters)
            } else {
                Pixel.fire(pixel: .importResultCreditCardsSuccess, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue,
                                                                                              PixelParameters.savedCreditCards: successBucket,
                                                                                              PixelParameters.skippedCreditCards: skippedBucket])
            }
        }
    }

    func dismiss() {
        delegate?.dataImportSummaryViewModelComplete(self)
    }

    func doneTapped() {
        if let importHubPixelContext {
            Pixel.fire(pixel: .importHubResultDoneTapped, withAdditionalParameters: importHubPixelContext.parameters)
        }

        delegate?.dataImportSummaryViewModelComplete(self)
    }

    func dismissSyncPromo() {
        if let importHubPixelContext {
            Pixel.fire(pixel: .importHubResultSyncPromoDismissed, withAdditionalParameters: importHubPixelContext.parameters)
        }
        syncPromoManager.dismissPromoFor(.dataImport, reason: .userTapped)
        dismiss()
    }

    func continueImportFromSafari() {
        handleContinueImportAction(.continueTapped, for: .passwords)
    }

    func handleContinueImportAction(_ action: ContinueImportAction, for dataType: ContinueImportDataType) {
        if isImportHubFlow {
            Pixel.fire(pixel: continueImportPixel(for: action, dataType: dataType), withAdditionalParameters: importHubPixelParameters)
        }

        switch action {
        case .shown:
            return
        case .dismissTapped:
            dismiss()
        case .continueTapped:
            delegate?.dataImportSummaryViewModelDidRequestContinueImportFromSafari(self)
        }
    }

    func launchSync(source: String? = nil, fromSyncPromo: Bool = false) {
        delegate?.dataImportSummaryViewModelDidRequestLaunchSync(self, source: source)

        if !isImportHubFlow {
            Pixel.fire(pixel: .importResultSyncButtonTapped, withAdditionalParameters: [PixelParameters.source: importScreen.rawValue])
        }

        if fromSyncPromo, let importHubPixelContext {
            Pixel.fire(pixel: .importHubResultSyncPromoTapped, withAdditionalParameters: importHubPixelContext.parameters)
        }
        
        if featureFlagger.isFeatureOn(.dataImportSummarySyncPromotion) {
            Pixel.fire(.syncPromoConfirmed, withAdditionalParameters: ["source": SyncPromoManager.Touchpoint.dataImport.rawValue])
        }
    }

    private func continueImportPixel(for action: ContinueImportAction, dataType: ContinueImportDataType) -> Pixel.Event {
        switch (dataType, action) {
        case (.passwords, .shown):
            return .importHubResultContinueToSafariPasswordsShown
        case (.passwords, .dismissTapped):
            return .importHubResultContinueToSafariPasswordsDismissed
        case (.passwords, .continueTapped):
            return .importHubResultContinueToSafariPasswordsTapped
        case (.bookmarks, .shown):
            return .importHubResultContinueToSafariBookmarksShown
        case (.bookmarks, .dismissTapped):
            return .importHubResultContinueToSafariBookmarksDismissed
        case (.bookmarks, .continueTapped):
            return .importHubResultContinueToSafariBookmarksTapped
        }
    }

}
