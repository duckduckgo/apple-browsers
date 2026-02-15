//
//  SyncErrorHandler.swift
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

import Common
import DDGSync
import Combine
import Persistence
import Foundation
import SyncDataProviders
import os.log

public enum AsyncErrorType: String {
    case bookmarksCountLimitExceeded
    case credentialsCountLimitExceeded
    case creditCardsCountLimitExceeded
    case aiChatsCountLimitExceeded
    case bookmarksRequestSizeLimitExceeded
    case credentialsRequestSizeLimitExceeded
    case creditCardsRequestSizeLimitExceeded
    case aiChatsRequestSizeLimitExceeded
    case invalidLoginCredentials
    case tooManyRequests
    case badRequestBookmarks
    case badRequestCredentials
    case badRequestCreditCards
    case badRequestAiChats
}

public class SyncErrorHandler: EventMapping<SyncError> {
    @UserDefaultsWrapper(key: .syncBookmarksPaused, defaultValue: false)
    private(set) public var isSyncBookmarksPaused: Bool {
        didSet {
            isSyncPausedChangedPublisher.send()
        }
    }

    @UserDefaultsWrapper(key: .syncCredentialsPaused, defaultValue: false)
    private(set) public var isSyncCredentialsPaused: Bool {
        didSet {
            isSyncPausedChangedPublisher.send()
        }
    }

    @UserDefaultsWrapper(key: .syncCreditCardsPaused, defaultValue: false)
    private(set) public var isSyncCreditCardsPaused: Bool {
        didSet {
            isSyncPausedChangedPublisher.send()
        }
    }

    @UserDefaultsWrapper(key: .syncIsPaused, defaultValue: false)
    private(set) public var isSyncPaused: Bool {
        didSet {
            isSyncPausedChangedPublisher.send()
        }
    }

    @UserDefaultsWrapper(key: .syncBookmarksPausedErrorDisplayed, defaultValue: false)
    var didShowBookmarksSyncPausedError: Bool

    @UserDefaultsWrapper(key: .syncCredentialsPausedErrorDisplayed, defaultValue: false)
    var didShowCredentialsSyncPausedError: Bool

    @UserDefaultsWrapper(key: .syncCreditCardsPausedErrorDisplayed, defaultValue: false)
    var didShowCreditCardsSyncPausedError: Bool

    @UserDefaultsWrapper(key: .syncInvalidLoginPausedErrorDisplayed, defaultValue: false)
    var didShowInvalidLoginSyncPausedError: Bool

    @UserDefaultsWrapper(key: .syncLastErrorNotificationTime, defaultValue: nil)
    var lastErrorNotificationTime: Date?

    @UserDefaultsWrapper(key: .syncLastSuccesfullTime, defaultValue: nil)
    var lastSyncSuccessTime: Date?

    @UserDefaultsWrapper(key: .syncLastNonActionableErrorCount, defaultValue: 0)
    var nonActionableErrorCount: Int

    @UserDefaultsWrapper(key: .syncCurrentAllPausedError, defaultValue: nil)
    public var currentSyncAllPausedError: String?

    @UserDefaultsWrapper(key: .syncCurrentBookmarksPausedError, defaultValue: nil)
    public var currentSyncBookmarksPausedError: String?

    @UserDefaultsWrapper(key: .syncCurrentCredentialsPausedError, defaultValue: nil)
    public var currentSyncCredentialsPausedError: String?

    @UserDefaultsWrapper(key: .syncCurrentCreditCardsPausedError, defaultValue: nil)
    public var currentSyncCreditCardsPausedError: String?

    var isSyncPausedChangedPublisher = PassthroughSubject<Void, Never>()
    let dateProvider: CurrentDateProviding
    public weak var alertPresenter: SyncAlertsPresenting?

    public init(dateProvider: CurrentDateProviding = DefaultCurrentDateProvider()) {
        self.dateProvider = dateProvider
        super.init { event, error, _, _ in
            switch event {
            case .migratedToFileStore:
                Pixel.fire(pixel: .syncMigratedToFileStore)
            case .failedToMigrateToFileStore:
                Pixel.fire(pixel: .syncFailedToMigrateToFileStore, error: error)
            case .failedToInitFileStore:
                Pixel.fire(pixel: .syncFailedToInitFileStore, error: error)
            case .failedToLoadAccount:
                Pixel.fire(pixel: .syncFailedToLoadAccount, error: error)
            case .failedToSetupEngine:
                Pixel.fire(pixel: .syncFailedToSetupEngine, error: error)
            case .failedToReadSecureStore:
                Pixel.fire(pixel: .syncSecureStorageReadError, error: error)
            case .failedToDecodeSecureStoreData(let error):
                Pixel.fire(pixel: .syncSecureStorageDecodingError, error: error)
            case .accountRemoved(let reason):
                Pixel.fire(pixel: .syncAccountRemoved(reason: reason.rawValue), error: error)
            default:
                // Should this be so generic?
                let domainEvent = Pixel.Event.syncSentUnauthenticatedRequest
                Pixel.fire(pixel: domainEvent, error: event)
            }
        }
    }

    override init(mapping: @escaping EventMapping<SyncError>.Mapping) {
        fatalError("Use init()")
    }
}

// MARK: - Private functions
extension SyncErrorHandler {
    private func resetBookmarksErrors() {
        isSyncBookmarksPaused = false
        didShowBookmarksSyncPausedError = false
        currentSyncBookmarksPausedError = nil
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
    private func resetGeneralErrors() {
        isSyncPaused = false
        didShowInvalidLoginSyncPausedError = false
        lastErrorNotificationTime = nil
        currentSyncAllPausedError = nil
        nonActionableErrorCount = 0
    }

    private func shouldShowAlertForNonActionableError() -> Bool {
        let currentDate = dateProvider.currentDate
        nonActionableErrorCount += 1
        let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: currentDate)!
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
        let twelveHoursAgo = Calendar.current.date(byAdding: .hour, value: -12, to: currentDate)!
        let noSuccessfulSyncInLast12h = nonActionableErrorCount > 1 && lastSyncSuccessTime ?? currentDate <= twelveHoursAgo

        return lastErrorNotificationWasMoreThan24hAgo &&
        (areThere10ConsecutiveError || noSuccessfulSyncInLast12h)
    }

    private func handleError(_ error: Error, modelType: ModelType) {
        switch error {
        case SyncError.patchPayloadCompressionFailed(let errorCode):
            Pixel.fire(pixel: modelType.patchPayloadCompressionFailedPixel, withAdditionalParameters: ["error": "\(errorCode)"])
        case let syncError as SyncError:
            handleSyncError(syncError, modelType: modelType)
            Pixel.fire(pixel: modelType.syncFailedPixel, error: syncError)
        case let settingsMetadataError as SettingsSyncMetadataSaveError:
            let underlyingError = settingsMetadataError.underlyingError
            let processedErrors = CoreDataErrorsParser.parse(error: underlyingError as NSError)
            let params = processedErrors.errorPixelParameters
            Pixel.fire(pixel: .syncSettingsMetadataUpdateFailed, error: underlyingError, withAdditionalParameters: params)
        default:
            let nsError = error as NSError
            if nsError.domain != NSURLErrorDomain {
                let processedErrors = CoreDataErrorsParser.parse(error: error as NSError)
                let params = processedErrors.errorPixelParameters
                Pixel.fire(pixel: modelType.syncFailedPixel, error: error, withAdditionalParameters: params)
            }
        }
        let modelTypeString = modelType.rawValue.capitalized
        Logger.sync.error("\(modelTypeString, privacy: .public) Sync error: \(error.localizedDescription, privacy: .public)")
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
            case .settings:
                break
            case .aiChats:
                syncIsPaused(errorType: .aiChatsCountLimitExceeded)
            }
        case .unexpectedStatusCode(413):
            switch modelType {
            case .bookmarks:
                syncIsPaused(errorType: .bookmarksRequestSizeLimitExceeded)
            case .credentials:
                syncIsPaused(errorType: .credentialsRequestSizeLimitExceeded)
            case .creditCards:
                syncIsPaused(errorType: .creditCardsRequestSizeLimitExceeded)
            case .settings:
                break
            case .aiChats:
                syncIsPaused(errorType: .aiChatsRequestSizeLimitExceeded)
            }
        case .unexpectedStatusCode(400):
            switch modelType {
            case .bookmarks:
                syncIsPaused(errorType: .badRequestBookmarks)
            case .credentials:
                syncIsPaused(errorType: .badRequestCredentials)
            case .creditCards:
                syncIsPaused(errorType: .badRequestCreditCards)
            case .settings:
                break
            case .aiChats:
                syncIsPaused(errorType: .badRequestAiChats)
            }
            DailyPixel.fire(pixel: modelType.badRequestPixel)
        case .unexpectedStatusCode(401):
            syncIsPaused(errorType: .invalidLoginCredentials)
        case .unexpectedStatusCode(418), .unexpectedStatusCode(429):
            syncIsPaused(errorType: .tooManyRequests)
            DailyPixel.fire(pixel: modelType.tooManyRequestsPixel)
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
            DailyPixel.fire(pixel: .syncBookmarksObjectLimitExceededDaily)
        case .credentialsCountLimitExceeded:
            currentSyncCredentialsPausedError = errorType.rawValue
            self.isSyncCredentialsPaused = true
            DailyPixel.fire(pixel: .syncCredentialsObjectLimitExceededDaily)
        case .aiChatsCountLimitExceeded:
            DailyPixel.fire(pixel: .syncAiChatsObjectLimitExceededDaily)
        case .bookmarksRequestSizeLimitExceeded:
            currentSyncBookmarksPausedError = errorType.rawValue
            self.isSyncBookmarksPaused = true
            DailyPixel.fire(pixel: .syncBookmarksRequestSizeLimitExceededDaily)
        case .credentialsRequestSizeLimitExceeded:
            currentSyncCredentialsPausedError = errorType.rawValue
            self.isSyncCredentialsPaused = true
            DailyPixel.fire(pixel: .syncCredentialsRequestSizeLimitExceededDaily)
        case .aiChatsRequestSizeLimitExceeded:
            DailyPixel.fire(pixel: .syncAiChatsRequestSizeLimitExceededDaily)
        case .badRequestBookmarks:
            currentSyncBookmarksPausedError = errorType.rawValue
            self.isSyncBookmarksPaused = true
        case .badRequestCredentials:
            currentSyncCredentialsPausedError = errorType.rawValue
            self.isSyncCredentialsPaused = true
        case .badRequestAiChats:
            break;
        case .invalidLoginCredentials:
            currentSyncAllPausedError = errorType.rawValue
            self.isSyncPaused = true
        case .tooManyRequests:
            currentSyncAllPausedError = errorType.rawValue
            self.isSyncPaused = true
        case .creditCardsCountLimitExceeded:
            currentSyncCreditCardsPausedError = errorType.rawValue
            self.isSyncCreditCardsPaused = true
            DailyPixel.fire(pixel: .syncCreditCardsObjectLimitExceededDaily)
        case .creditCardsRequestSizeLimitExceeded:
            currentSyncCreditCardsPausedError = errorType.rawValue
            self.isSyncCreditCardsPaused = true
            DailyPixel.fire(pixel: .syncCreditCardsRequestSizeLimitExceededDaily)
        case .badRequestCreditCards:
            currentSyncCreditCardsPausedError = errorType.rawValue
            self.isSyncCreditCardsPaused = true
        }
    }
    private func showSyncPausedAlertIfNeeded(for errorType: AsyncErrorType) {
        switch errorType {
        case .bookmarksCountLimitExceeded, .bookmarksRequestSizeLimitExceeded:
            guard !didShowBookmarksSyncPausedError else { return }
            alertPresenter?.showSyncPausedAlert(for: errorType)
            didShowBookmarksSyncPausedError = true
        case .credentialsCountLimitExceeded, .credentialsRequestSizeLimitExceeded:
            guard !didShowCredentialsSyncPausedError else { return }
            alertPresenter?.showSyncPausedAlert(for: errorType)
            didShowCredentialsSyncPausedError = true
        case .badRequestBookmarks:
            guard !didShowBookmarksSyncPausedError else { return }
            alertPresenter?.showSyncPausedAlert(for: errorType)
            didShowBookmarksSyncPausedError = true
        case .badRequestCredentials:
            guard !didShowCredentialsSyncPausedError else { return }
            alertPresenter?.showSyncPausedAlert(for: errorType)
            didShowCredentialsSyncPausedError = true
        case .invalidLoginCredentials:
            guard !didShowInvalidLoginSyncPausedError else { return }
            alertPresenter?.showSyncPausedAlert(for: errorType)
            didShowInvalidLoginSyncPausedError = true
        case .tooManyRequests:
            guard shouldShowAlertForNonActionableError() == true else { return }
            alertPresenter?.showSyncPausedAlert(for: errorType)
            lastErrorNotificationTime = dateProvider.currentDate
        case .creditCardsCountLimitExceeded, .creditCardsRequestSizeLimitExceeded:
            guard !didShowCreditCardsSyncPausedError else { return }
            alertPresenter?.showSyncPausedAlert(for: errorType)
            didShowCreditCardsSyncPausedError = true
        case .badRequestCreditCards:
            guard !didShowCreditCardsSyncPausedError else { return }
            alertPresenter?.showSyncPausedAlert(for: errorType)
            didShowCreditCardsSyncPausedError = true
        case .badRequestAiChats, .aiChatsCountLimitExceeded, .aiChatsRequestSizeLimitExceeded:
            break
        }
    }
    private enum ModelType: String {
        case bookmarks
        case credentials
        case creditCards
        case settings
        case aiChats

        var syncFailedPixel: Pixel.Event {
            switch self {
            case .bookmarks:
                    .syncBookmarksFailed
            case .credentials:
                    .syncCredentialsFailed
            case .creditCards:
                    .syncCreditCardsFailed
            case .settings:
                    .syncSettingsFailed
            case .aiChats:
                    .syncAiChatsFailed
            }
        }

        var patchPayloadCompressionFailedPixel: Pixel.Event {
            switch self {
            case .bookmarks:
                    .syncBookmarksPatchCompressionFailed
            case .credentials:
                    .syncCredentialsPatchCompressionFailed
            case .creditCards:
                    .syncCreditCardsPatchCompressionFailed
            case .settings:
                    .syncSettingsPatchCompressionFailed
            case .aiChats:
                    .syncAiChatsPatchCompressionFailed
            }
        }

        var tooManyRequestsPixel: Pixel.Event {
            switch self {
            case .bookmarks:
                    .syncBookmarksTooManyRequestsDaily
            case .credentials:
                    .syncCredentialsTooManyRequestsDaily
            case .creditCards:
                    .syncCreditCardsTooManyRequestsDaily
            case .settings:
                    .syncSettingsTooManyRequestsDaily
            case .aiChats:
                    .syncAiChatsTooManyRequestsDaily
            }
        }

        var badRequestPixel: Pixel.Event {
            switch self {
            case .bookmarks:
                    .syncBookmarksValidationErrorDaily
            case .credentials:
                    .syncCredentialsValidationErrorDaily
            case .creditCards:
                    .syncCreditCardsValidationErrorDaily
            case .settings:
                    .syncSettingsValidationErrorDaily
            case .aiChats:
                    .syncAiChatsValidationErrorDaily
            }
        }
    }
}

// MARK: - SyncErrorHandler
extension SyncErrorHandler: SyncErrorHandling {
    public func handleSettingsError(_ error: Error) {
        handleError(error, modelType: .settings)
    }

    public func handleBookmarkError(_ error: Error) {
        handleError(error, modelType: .bookmarks)
    }

    public func handleCredentialError(_ error: Error) {
        handleError(error, modelType: .credentials)
    }

    public func handleCreditCardsError(_ error: any Error) {
        handleError(error, modelType: .creditCards)
    }

    public func handleAiChatsError(_ error: any Error) {
        handleError(error, modelType: .aiChats)
    }

    public func syncBookmarksSucceded() {
        lastSyncSuccessTime = dateProvider.currentDate
        resetBookmarksErrors()
    }

    public func syncCredentialsSucceded() {
        lastSyncSuccessTime = dateProvider.currentDate
        resetCredentialsErrors()
    }

    public func syncCreditCardsSucceded() {
        lastSyncSuccessTime = dateProvider.currentDate
        resetCreditCardsErrors()
    }
}

// MARK: - syncPausedStateManager
extension SyncErrorHandler: SyncPausedStateManaging {
    public var syncPausedChangedPublisher: AnyPublisher<Void, Never> {
        isSyncPausedChangedPublisher.eraseToAnyPublisher()
    }

    public func syncDidTurnOff() {
        resetBookmarksErrors()
        resetCredentialsErrors()
        resetCreditCardsErrors()
    }
}
