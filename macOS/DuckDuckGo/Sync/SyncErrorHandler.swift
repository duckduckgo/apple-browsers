//
//  SyncErrorHandler.swift
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

import Common
import DDGSync
import Foundation
import PixelKit
import Persistence
import Combine
import SyncDataProviders
import os.log

/// The SyncErrorHandling protocol defines methods for handling sync errors related to specific data types such as bookmarks and credentials.
protocol SyncErrorHandling {
    func handleBookmarkError(_ error: Error)
    func handleCredentialError(_ error: Error)
    func handleCreditCardsError(_ error: Error)
    func handleIdentitiesError(_ error: Error)
    func handleSettingsError(_ error: Error)
    func handleAiChatsError(_ error: Error)
    func syncBookmarksSucceded()
    func syncCredentialsSucceded()
    func syncCreditCardsSucceded()
    func syncIdentitiesSucceded()
}

public class SyncErrorHandler: EventMapping<SyncError>, ObservableObject {

    @UserDefaultsWrapper(key: .syncBookmarksPaused, defaultValue: false)
    private(set) var isSyncBookmarksPaused: Bool {
        didSet {
            isSyncPausedChangedPublisher.send()
        }
    }

    @UserDefaultsWrapper(key: .syncCredentialsPaused, defaultValue: false)
    private(set) var isSyncCredentialsPaused: Bool {
        didSet {
            isSyncPausedChangedPublisher.send()
        }
    }

    @UserDefaultsWrapper(key: .syncCreditCardsPaused, defaultValue: false)
    private(set) var isSyncCreditCardsPaused: Bool {
        didSet {
            isSyncPausedChangedPublisher.send()
        }
    }

    @UserDefaultsWrapper(key: .syncIdentitiesPaused, defaultValue: false)
    private(set) var isSyncIdentitiesPaused: Bool {
        didSet {
            isSyncPausedChangedPublisher.send()
        }
    }

    @UserDefaultsWrapper(key: .syncIsPaused, defaultValue: false)
    private(set) var isSyncPaused: Bool {
        didSet {
            isSyncPausedChangedPublisher.send()
        }
    }

    @UserDefaultsWrapper(key: .syncBookmarksPausedErrorDisplayed, defaultValue: false)
    private var didShowBookmarksSyncPausedError: Bool

    @UserDefaultsWrapper(key: .syncCredentialsPausedErrorDisplayed, defaultValue: false)
    private var didShowCredentialsSyncPausedError: Bool

    @UserDefaultsWrapper(key: .syncCreditCardsPausedErrorDisplayed, defaultValue: false)
    private var didShowCreditCardsSyncPausedError: Bool

    @UserDefaultsWrapper(key: .syncIdentitiesPausedErrorDisplayed, defaultValue: false)
    private var didShowIdentitiesSyncPausedError: Bool

    @UserDefaultsWrapper(key: .syncInvalidLoginPausedErrorDisplayed, defaultValue: false)
    private var didShowInvalidLoginSyncPausedError: Bool

    @UserDefaultsWrapper(key: .syncLastErrorNotificationTime, defaultValue: nil)
    private var lastErrorNotificationTime: Date?

    @UserDefaultsWrapper(key: .syncLastSuccesfullTime, defaultValue: nil)
    private var lastSyncSuccessTime: Date?

    @UserDefaultsWrapper(key: .syncLastNonActionableErrorCount, defaultValue: 0)
    private var nonActionableErrorCount: Int

    @UserDefaultsWrapper(key: .syncCurrentAllPausedError, defaultValue: nil)
    private var currentSyncAllPausedError: String?

    @UserDefaultsWrapper(key: .syncCurrentBookmarksPausedError, defaultValue: nil)
    private var currentSyncBookmarksPausedError: String?

    @UserDefaultsWrapper(key: .syncCurrentCredentialsPausedError, defaultValue: nil)
    private var currentSyncCredentialsPausedError: String?

    @UserDefaultsWrapper(key: .syncCurrentCreditCardsPausedError, defaultValue: nil)
    private var currentSyncCreditCardsPausedError: String?

    @UserDefaultsWrapper(key: .syncCurrentIdentitiesPausedError, defaultValue: nil)
    private var currentSyncIdentitiesPausedError: String?

    var isSyncPausedChangedPublisher = PassthroughSubject<Void, Never>()

    let alertPresenter: SyncAlertsPresenting

    static var errorHandlerMapping: Mapping {
        return { event, _, _, _ in
            switch event {
            case .migratedToFileStore:
                PixelKit.fire(DebugEvent(GeneralPixel.syncMigratedToFileStore))
            case .failedToMigrateToFileStore:
                PixelKit.fire(DebugEvent(GeneralPixel.syncFailedToMigrateToFileStore, error: event))
            case .failedToInitFileStore:
                PixelKit.fire(DebugEvent(GeneralPixel.syncFailedToInitFileStore, error: event))
            case .failedToReadSecureStore:
                PixelKit.fire(DebugEvent(GeneralPixel.syncSecureStorageReadError(error: event), error: event))
            case .failedToDecodeSecureStoreData(let error):
                PixelKit.fire(DebugEvent(GeneralPixel.syncSecureStorageDecodingError(error: error), error: error))
            case .accountRemoved(let reason):
                PixelKit.fire(DebugEvent(GeneralPixel.syncAccountRemoved(reason: reason.rawValue), error: event))
            default:
                PixelKit.fire(DebugEvent(GeneralPixel.syncSentUnauthenticatedRequest, error: event))
            }
        }
    }

    public init(alertPresenter: SyncAlertsPresenting = SyncAlertsPresenter()) {
        self.alertPresenter = alertPresenter
        super.init(mapping: Self.errorHandlerMapping)
    }

    override init(mapping: @escaping EventMapping<SyncError>.Mapping) {
        fatalError("Use init()")
    }

    var addErrorPublisher: AnyPublisher<Bool, Never> {
        addErrorSubject.eraseToAnyPublisher()
    }

    private let addErrorSubject: PassthroughSubject<Bool, Never> = .init()
    public let objectWillChange = ObservableObjectPublisher()

    private func resetBookmarksErrors() {
        isSyncBookmarksPaused = false
        didShowBookmarksSyncPausedError = false
        currentSyncAllPausedError = nil
        resetGeneralErrors()
    }

    private func resetCredentialsErrors() {
        isSyncCredentialsPaused = false
        didShowCredentialsSyncPausedError = false
        currentSyncCredentialsPausedError = nil
        resetGeneralErrors()
    }

    private func resetCreditCardsErrors() {
        isSyncCreditCardsPaused = false
        didShowCreditCardsSyncPausedError = false
        currentSyncCreditCardsPausedError = nil
        resetGeneralErrors()
    }

    private func resetIdentitiesErrors() {
        isSyncIdentitiesPaused = false
        didShowIdentitiesSyncPausedError = false
        currentSyncIdentitiesPausedError = nil
        resetGeneralErrors()
    }

    private func resetGeneralErrors() {
        isSyncPaused = false
        didShowInvalidLoginSyncPausedError = false
        lastErrorNotificationTime = nil
        currentSyncAllPausedError = nil
        nonActionableErrorCount = 0
    }

    private func shouldShowAlertForNonActionableError() -> Bool {
        let timeStamp = Date()
        nonActionableErrorCount += 1
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: timeStamp)!
        var lastErrorNotificationWasMoreThan24hAgo: Bool
        if let lastErrorNotificationTime {
            lastErrorNotificationWasMoreThan24hAgo = lastErrorNotificationTime < oneDayAgo
        } else {
            lastErrorNotificationWasMoreThan24hAgo = true
        }
        let areThere10ConsecutiveError = nonActionableErrorCount >= 10
        if nonActionableErrorCount >= 10 {
            nonActionableErrorCount = 0
        }
        let twelveHoursAgo = Calendar.current.date(byAdding: .hour, value: -12, to: timeStamp)!
        let noSuccessfulSyncInLast12h = nonActionableErrorCount > 1 && lastSyncSuccessTime ?? Date() <= twelveHoursAgo

        return lastErrorNotificationWasMoreThan24hAgo &&
        (areThere10ConsecutiveError || noSuccessfulSyncInLast12h)
    }

    private func getErrorType(from errorString: String?) -> AsyncErrorType? {
        guard let errorString = errorString else {
            return nil
        }
        return AsyncErrorType(rawValue: errorString)
    }

    private var syncPausedTitle: String? {
        guard let error = getErrorType(from: currentSyncAllPausedError) else { return nil }
        switch error {
        case .invalidLoginCredentials:
            return UserText.syncPausedTitle
        case .tooManyRequests:
            return UserText.syncErrorTitle
        default:
            assertionFailure("Sync Paused error should be one of those listes")
            return nil
        }
    }

    private var syncPausedMessage: String? {
        guard let error = getErrorType(from: currentSyncAllPausedError) else { return nil }
        switch error {
        case .invalidLoginCredentials:
            return UserText.invalidLoginCredentialErrorDescription
        case .tooManyRequests:
            return UserText.tooManyRequestsErrorDescription
        default:
            assertionFailure("Sync Paused error should be one of those listes")
            return nil
        }
    }

    private var syncBookmarksPausedMessage: String? {
        guard let error = getErrorType(from: currentSyncBookmarksPausedError) else { return nil }
        switch error {
        case .bookmarksCountLimitExceeded, .bookmarksRequestSizeLimitExceeded:
            return UserText.bookmarksLimitExceededDescription
        case .badRequestBookmarks:
            return UserText.syncBookmarksBadRequestErrorDescription
        default:
            assertionFailure("Sync Bookmarks Paused error should be one of those listes")
            return nil
        }
    }

    private var syncCredentialsPausedMessage: String? {
        guard let error = getErrorType(from: currentSyncCredentialsPausedError) else { return nil }
        switch error {
        case .credentialsCountLimitExceeded, .credentialsRequestSizeLimitExceeded:
            return UserText.credentialsLimitExceededDescription
        case .badRequestCredentials:
            return UserText.syncCredentialsBadRequestErrorDescription
        default:
            assertionFailure("Sync Credentials Paused error should be one of those listed")
            return nil
        }
    }

    private var syncCreditCardsPausedMessage: String? {
        guard let error = getErrorType(from: currentSyncCreditCardsPausedError) else { return nil }
        switch error {
        case .creditCardsCountLimitExceeded, .creditCardsRequestSizeLimitExceeded:
            return UserText.creditCardsLimitExceededDescription
        case .badRequestCreditCards:
            return UserText.syncCreditCardsBadRequestErrorDescription
        default:
            assertionFailure("Sync Credit Cards Paused error should be one of those listed")
            return nil
        }
    }

    private var syncIdentitiesPausedMessage: String? {
        guard let error = getErrorType(from: currentSyncIdentitiesPausedError) else { return nil }
        switch error {
        case .identitiesCountLimitExceeded, .identitiesRequestSizeLimitExceeded:
            return UserText.identitiesLimitExceededDescription
        case .badRequestIdentities:
            return UserText.syncIdentitiesBadRequestErrorDescription
        default:
            assertionFailure("Sync Identities Paused error should be one of those listed")
            return nil
        }
    }
}

extension SyncErrorHandler: SyncErrorHandling {

    func syncCredentialsSucceded() {
        lastSyncSuccessTime = Date()
        resetCredentialsErrors()
    }

    func syncCreditCardsSucceded() {
        lastSyncSuccessTime = Date()
        resetCreditCardsErrors()
    }

    func syncIdentitiesSucceded() {
        lastSyncSuccessTime = Date()
        resetIdentitiesErrors()
    }

    func syncBookmarksSucceded() {
        lastSyncSuccessTime = Date()
        resetBookmarksErrors()
    }

    func handleBookmarkError(_ error: Error) {
        handleError(error, modelType: .bookmarks)
    }

    func handleCredentialError(_ error: Error) {
        handleError(error, modelType: .credentials)
    }

    func handleCreditCardsError(_ error: Error) {
        handleError(error, modelType: .creditCards)
    }

    func handleIdentitiesError(_ error: Error) {
        handleError(error, modelType: .identities)
    }

    public func handleSettingsError(_ error: Error) {
         handleError(error, modelType: .settings)
     }

    func handleAiChatsError(_ error: Error) {
        handleError(error, modelType: .aiChats)
    }

    private func handleError(_ error: Error, modelType: ModelType) {
        switch error {
        case SyncError.patchPayloadCompressionFailed(let errorCode):
            PixelKit.fire(DebugEvent(modelType.patchPayloadCompressionFailedPixel), withAdditionalParameters: ["error": "\(errorCode)"])
        case let syncError as SyncError:
            handleSyncError(syncError, modelType: modelType)
            PixelKit.fire(DebugEvent(modelType.syncFailedPixel, error: syncError))
        case let settingsMetadataError as SettingsSyncMetadataSaveError:
            let underlyingError = settingsMetadataError.underlyingError
            let processedErrors = CoreDataErrorsParser.parse(error: underlyingError as NSError)
            let params = processedErrors.errorPixelParameters
            PixelKit.fire(DebugEvent(GeneralPixel.syncSettingsMetadataUpdateFailed, error: underlyingError), withAdditionalParameters: params)
        default:
            let nsError = error as NSError
            if nsError.domain != NSURLErrorDomain {
                let processedErrors = CoreDataErrorsParser.parse(error: error as NSError)
                let params = processedErrors.errorPixelParameters
                PixelKit.fire(DebugEvent(modelType.syncFailedPixel, error: error), withAdditionalParameters: params)
            }
            let modelTypeString = modelType.rawValue.capitalized
            Logger.sync.error("\(modelTypeString, privacy: .public) Sync error: \(String(reflecting: error), privacy: .public)")
        }
    }

    private func handleSyncError(_ syncError: SyncError, modelType: ModelType) {
        switch syncError {
        case .unexpectedStatusCode(409):
            switch modelType {
            case .bookmarks:
                syncIsPaused(errorType: .bookmarksCountLimitExceeded)
            case .credentials:
                syncIsPaused(errorType: .credentialsCountLimitExceeded)
            case .creditCards:
                syncIsPaused(errorType: .creditCardsCountLimitExceeded)
            case .identities:
                syncIsPaused(errorType: .identitiesCountLimitExceeded)
            case .aiChats:
                syncIsPaused(errorType: .aiChatsCountLimitExceeded)
            case .settings:
                break
            }
        case .unexpectedStatusCode(413):
            switch modelType {
            case .bookmarks:
                syncIsPaused(errorType: .bookmarksRequestSizeLimitExceeded)
            case .credentials:
                syncIsPaused(errorType: .credentialsRequestSizeLimitExceeded)
            case .creditCards:
                syncIsPaused(errorType: .creditCardsRequestSizeLimitExceeded)
            case .identities:
                syncIsPaused(errorType: .identitiesRequestSizeLimitExceeded)
            case .aiChats:
                syncIsPaused(errorType: .aiChatsRequestSizeLimitExceeded)
            case .settings:
                break
            }
        case .unexpectedStatusCode(400):
            switch modelType {
            case .bookmarks:
                syncIsPaused(errorType: .badRequestBookmarks)
            case .credentials:
                syncIsPaused(errorType: .badRequestCredentials)
            case .creditCards:
                syncIsPaused(errorType: .badRequestCreditCards)
            case .identities:
                syncIsPaused(errorType: .badRequestIdentities)
            case .aiChats:
                syncIsPaused(errorType: .badRequestAiChats)
            case .settings:
                break
            }
            PixelKit.fire(modelType.badRequestPixel, frequency: .legacyDailyNoSuffix)
        case .unexpectedStatusCode(401):
            switch modelType {
            case .aiChats:
                break
            default:
                syncIsPaused(errorType: .invalidLoginCredentials)
            }
        case .unexpectedStatusCode(418), .unexpectedStatusCode(429):
            syncIsPaused(errorType: .tooManyRequests)
            PixelKit.fire(modelType.tooManyRequestsPixel, frequency: .legacyDailyNoSuffix)
        default:
            break
        }
    }

    private func syncIsPaused(errorType: AsyncErrorType) {
        showSyncPausedAlertIfNeeded(for: errorType)
        switch errorType {
        case .bookmarksCountLimitExceeded:
            currentSyncBookmarksPausedError = errorType.rawValue
            self.isSyncBookmarksPaused = true
            PixelKit.fire(GeneralPixel.syncBookmarksObjectLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .credentialsCountLimitExceeded:
            currentSyncCredentialsPausedError = errorType.rawValue
            self.isSyncCredentialsPaused = true
            PixelKit.fire(GeneralPixel.syncCredentialsObjectLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .creditCardsCountLimitExceeded:
            currentSyncCreditCardsPausedError = errorType.rawValue
            self.isSyncCreditCardsPaused = true
            PixelKit.fire(GeneralPixel.syncCreditCardsObjectLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .identitiesCountLimitExceeded:
            currentSyncIdentitiesPausedError = errorType.rawValue
            self.isSyncIdentitiesPaused = true
            PixelKit.fire(GeneralPixel.syncIdentitiesObjectLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .aiChatsCountLimitExceeded:
            PixelKit.fire(GeneralPixel.syncAiChatsObjectLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .bookmarksRequestSizeLimitExceeded:
            currentSyncBookmarksPausedError = errorType.rawValue
            self.isSyncBookmarksPaused = true
            PixelKit.fire(GeneralPixel.syncBookmarksRequestSizeLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .credentialsRequestSizeLimitExceeded:
            currentSyncCredentialsPausedError = errorType.rawValue
            self.isSyncCredentialsPaused = true
            PixelKit.fire(GeneralPixel.syncCredentialsRequestSizeLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .creditCardsRequestSizeLimitExceeded:
            currentSyncCreditCardsPausedError = errorType.rawValue
            self.isSyncCreditCardsPaused = true
            PixelKit.fire(GeneralPixel.syncCreditCardsRequestSizeLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .identitiesRequestSizeLimitExceeded:
            currentSyncIdentitiesPausedError = errorType.rawValue
            self.isSyncIdentitiesPaused = true
            PixelKit.fire(GeneralPixel.syncIdentitiesRequestSizeLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .aiChatsRequestSizeLimitExceeded:
            PixelKit.fire(GeneralPixel.syncAiChatsRequestSizeLimitExceededDaily, frequency: .legacyDailyNoSuffix)
        case .badRequestBookmarks:
            currentSyncBookmarksPausedError = errorType.rawValue
            self.isSyncBookmarksPaused = true
        case .badRequestCredentials:
            currentSyncCredentialsPausedError = errorType.rawValue
            self.isSyncCredentialsPaused = true
        case .badRequestCreditCards:
            currentSyncCreditCardsPausedError = errorType.rawValue
            self.isSyncCreditCardsPaused = true
        case .badRequestIdentities:
            currentSyncIdentitiesPausedError = errorType.rawValue
            self.isSyncIdentitiesPaused = true
        case .badRequestAiChats:
            break
        case .invalidLoginCredentials:
            currentSyncAllPausedError = errorType.rawValue
            self.isSyncPaused = true
        case .tooManyRequests:
            currentSyncAllPausedError = errorType.rawValue
            self.isSyncPaused = true
        }
    }

    private func showSyncPausedAlertIfNeeded(for errorType: AsyncErrorType) {
        switch errorType {
        case .bookmarksCountLimitExceeded, .bookmarksRequestSizeLimitExceeded:
            guard !didShowBookmarksSyncPausedError else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncBookmarkPausedAlertTitle, informative: UserText.syncBookmarkPausedAlertDescription)
            didShowBookmarksSyncPausedError = true
        case .credentialsCountLimitExceeded, .credentialsRequestSizeLimitExceeded:
            guard !didShowCredentialsSyncPausedError else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncCredentialsPausedAlertTitle, informative: UserText.syncCredentialsPausedAlertDescription)
            didShowCredentialsSyncPausedError = true
        case .creditCardsCountLimitExceeded, .creditCardsRequestSizeLimitExceeded:
            guard !didShowCreditCardsSyncPausedError else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncCreditCardsPausedAlertTitle, informative: UserText.syncCreditCardsPausedAlertDescription)
            didShowCreditCardsSyncPausedError = true
        case .identitiesCountLimitExceeded, .identitiesRequestSizeLimitExceeded:
            guard !didShowIdentitiesSyncPausedError else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncIdentitiesPausedAlertTitle, informative: UserText.syncIdentitiesPausedAlertDescription)
            didShowIdentitiesSyncPausedError = true
        case .badRequestBookmarks:
            guard !didShowBookmarksSyncPausedError else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncBookmarkPausedAlertTitle, informative: UserText.syncBookmarksBadRequestAlertDescription)
            didShowBookmarksSyncPausedError = true
        case .badRequestCredentials:
            guard !didShowCredentialsSyncPausedError else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncBookmarkPausedAlertTitle, informative: UserText.syncCredentialsBadRequestAlertDescription)
            didShowCredentialsSyncPausedError = true
        case .badRequestCreditCards:
            guard !didShowCreditCardsSyncPausedError else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncCreditCardsPausedAlertTitle, informative: UserText.syncCreditCardsBadRequestAlertDescription)
            didShowCreditCardsSyncPausedError = true
        case .badRequestIdentities:
            guard !didShowIdentitiesSyncPausedError else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncIdentitiesPausedAlertTitle, informative: UserText.syncIdentitiesBadRequestAlertDescription)
            didShowIdentitiesSyncPausedError = true
        case .badRequestAiChats, .aiChatsCountLimitExceeded, .aiChatsRequestSizeLimitExceeded:
            break
        case .invalidLoginCredentials:
            guard !didShowInvalidLoginSyncPausedError else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncPausedAlertTitle, informative: UserText.syncInvalidLoginAlertDescription)
            didShowInvalidLoginSyncPausedError = true
        case .tooManyRequests:
            guard shouldShowAlertForNonActionableError() == true else { return }
            alertPresenter.showSyncPausedAlert(title: UserText.syncErrorAlertTitle, informative: UserText.syncTooManyRequestsAlertDescription)
            lastErrorNotificationTime = Date()
        }
    }

    private enum AsyncErrorType: String {
        case bookmarksCountLimitExceeded
        case credentialsCountLimitExceeded
        case creditCardsCountLimitExceeded
        case identitiesCountLimitExceeded
        case aiChatsCountLimitExceeded
        case bookmarksRequestSizeLimitExceeded
        case credentialsRequestSizeLimitExceeded
        case creditCardsRequestSizeLimitExceeded
        case identitiesRequestSizeLimitExceeded
        case aiChatsRequestSizeLimitExceeded
        case invalidLoginCredentials
        case tooManyRequests
        case badRequestBookmarks
        case badRequestCredentials
        case badRequestCreditCards
        case badRequestIdentities
        case badRequestAiChats
    }

    private enum ModelType: String {
        case bookmarks
        case credentials
        case creditCards
        case identities
        case settings
        case aiChats

        var syncFailedPixel: GeneralPixel {
            switch self {
            case .bookmarks:
                    .syncBookmarksFailed
            case .credentials:
                    .syncCredentialsFailed
            case .creditCards:
                    .syncCreditCardsFailed
            case .identities:
                    .syncIdentitiesFailed
            case .settings:
                    .syncSettingsFailed
            case .aiChats:
                    .syncAiChatsFailed
            }
        }

        var patchPayloadCompressionFailedPixel: GeneralPixel {
            switch self {
            case .bookmarks:
                    .syncBookmarksPatchCompressionFailed
            case .credentials:
                    .syncCredentialsPatchCompressionFailed
            case .creditCards:
                    .syncCreditCardsPatchCompressionFailed
            case .identities:
                    .syncIdentitiesPatchCompressionFailed
            case .settings:
                    .syncSettingsPatchCompressionFailed
            case .aiChats:
                    .syncAiChatsPatchCompressionFailed
            }
        }

        var tooManyRequestsPixel: GeneralPixel {
            switch self {
            case .bookmarks:
                    .syncBookmarksTooManyRequestsDaily
            case .credentials:
                    .syncCredentialsTooManyRequestsDaily
            case .creditCards:
                    .syncCreditCardsTooManyRequestsDaily
            case .identities:
                    .syncIdentitiesTooManyRequestsDaily
            case .settings:
                    .syncSettingsTooManyRequestsDaily
            case .aiChats:
                    .syncAiChatsTooManyRequestsDaily
            }
        }

        var badRequestPixel: GeneralPixel {
            switch self {
            case .bookmarks:
                    .syncBookmarksValidationErrorDaily
            case .credentials:
                    .syncCredentialsValidationErrorDaily
            case .creditCards:
                    .syncCreditCardsValidationErrorDaily
            case .identities:
                    .syncIdentitiesValidationErrorDaily
            case .settings:
                    .syncSettingsValidationErrorDaily
            case .aiChats:
                    .syncAiChatsValidationErrorDaily
            }
        }
    }

    @MainActor
    private func manageBookmarks() {
        guard let mainVC = Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController else { return }
        mainVC.showManageBookmarks(self)
    }

    @MainActor
    private func manageLogins() {
        guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else { return }
        let navigationViewController = parentWindowController.mainViewController.navigationBarViewController
        navigationViewController.showPasswordManagerPopover(selectedCategory: .allItems, source: .sync)
    }

    @MainActor
    private func manageCreditCards() {
        guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else { return }
        let navigationViewController = parentWindowController.mainViewController.navigationBarViewController
        navigationViewController.showPasswordManagerPopover(selectedCategory: .cards, source: .sync)
    }

    @MainActor
    private func manageIdentities() {
        guard let parentWindowController = Application.appDelegate.windowControllersManager.lastKeyMainWindowController else { return }
        let navigationViewController = parentWindowController.mainViewController.navigationBarViewController
        navigationViewController.showPasswordManagerPopover(selectedCategory: .identities, source: .sync)
    }

}

extension SyncErrorHandler: SyncPausedStateManaging {
    var syncPausedMessageData: SyncPausedMessageData? {
        guard let syncPausedMessage else { return nil }
        guard let syncPausedTitle else { return nil }
        return SyncPausedMessageData(title: syncPausedTitle,
                                       description: syncPausedMessage,
                                       buttonTitle: "",
                                       action: nil)
    }

    @MainActor
    var syncBookmarksPausedMessageData: SyncPausedMessageData? {
        guard let syncBookmarksPausedMessage else { return nil }
        return SyncPausedMessageData(title: UserText.syncLimitExceededTitle,
                                     description: syncBookmarksPausedMessage,
                                     buttonTitle: "",
                                     action: manageBookmarks)
    }

    @MainActor
    var syncCredentialsPausedMessageData: SyncPausedMessageData? {
        guard let syncCredentialsPausedMessage else { return nil }
        return SyncPausedMessageData(title: UserText.syncLimitExceededTitle,
                                     description: syncCredentialsPausedMessage,
                                     buttonTitle: "",
                                     action: manageLogins)
    }

    @MainActor
    var syncCreditCardsPausedMessageData: SyncPausedMessageData? {
        guard let syncCreditCardsPausedMessage else { return nil }
        return SyncPausedMessageData(title: UserText.syncLimitExceededTitle,
                                     description: syncCreditCardsPausedMessage,
                                     buttonTitle: "",
                                     action: manageCreditCards)
    }

    @MainActor
    var syncIdentitiesPausedMessageData: SyncPausedMessageData? {
        guard let syncIdentitiesPausedMessage else { return nil }
        return SyncPausedMessageData(title: UserText.syncLimitExceededTitle,
                                     description: syncIdentitiesPausedMessage,
                                     buttonTitle: "",
                                     action: manageIdentities)
    }

    var syncPausedChangedPublisher: AnyPublisher<Void, Never> {
        isSyncPausedChangedPublisher.eraseToAnyPublisher()
    }

    func syncDidTurnOff() {
        resetBookmarksErrors()
        resetCredentialsErrors()
        resetCreditCardsErrors()
        resetIdentitiesErrors()
    }
}
