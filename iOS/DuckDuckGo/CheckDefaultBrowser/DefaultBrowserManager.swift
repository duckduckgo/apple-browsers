//
//  DefaultBrowserManager.swift
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
import Common
import class UIKit.UIApplication

// MARK: - Model

struct DefaultBrowserInfo: Codable, Equatable {
    /// True if DDG browser is set as default, false otherwise.
    let isDefaultBrowser: Bool
    /// The time interval when we last got a valid result.
    let lastSuccessfulCheckDate: TimeInterval
    /// The time interval when we last attempted to check an updated result.
    let lastAttemptedCheckDate: TimeInterval
    /// Total number of times that the app requested an updated result.
    let numberOfTimesChecked: Int
    /// The time interval at which the app can next request an updated response.
    let nextRetryAvailableDate: TimeInterval?
}

@MainActor
protocol DefaultBrowserManaging: AnyObject {
    func defaultBrowserInfo() -> DefaultBrowserInfoResult
}

enum DefaultBrowserInfoResult: Equatable {
    enum Failure: Equatable {
        case notSupportedOnCurrentOSVersion
        case unknownError(NSError)
        case rateLimitReached(updatedStoredInfo: DefaultBrowserInfo?)
    }

    case failure(DefaultBrowserInfoResult.Failure)
    case success(newInfo: DefaultBrowserInfo)
}

extension DefaultBrowserInfoResult {

    @discardableResult
    func onNewValue(_ f: (DefaultBrowserInfo) -> Void) -> Self {
        if case let .success(newInfo) = self {
            f(newInfo)
        }
        return self
    }

    @discardableResult
    func onFailure(_ f: (Failure) -> Void) -> Self {
        if case let .failure(failure) = self {
            f(failure)
        }
        return self
    }
}

// MARK: - DefaultBrowserManager

@MainActor
final class DefaultBrowserManager: DefaultBrowserManaging {
    private let defaultBrowserChecker: CheckDefaultBrowserService
    private let defaultBrowserInfoStore: DefaultBrowserInfoStorage
    private let defaultBrowserEventMapper: EventMapping<DebugEvent>
    private let dateProvider: () -> Date

    init(
        defaultBrowserChecker: CheckDefaultBrowserService = SystemCheckDefaultBrowserService(),
        defaultBrowserInfoStore: DefaultBrowserInfoStorage = DefaultBrowserInfoStore(),
        defaultBrowserEventMapper: EventMapping<DebugEvent> = DefaultBrowserManagerEventMapper.debugEvents,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.defaultBrowserChecker = defaultBrowserChecker
        self.defaultBrowserInfoStore = defaultBrowserInfoStore
        self.defaultBrowserEventMapper = defaultBrowserEventMapper
        self.dateProvider = dateProvider
    }

    func defaultBrowserInfo() -> DefaultBrowserInfoResult {
        let defaultBrowserResult = defaultBrowserChecker.isDefaultWebBrowser()

        switch defaultBrowserResult {
        case let .success(value):
            let defaultBrowserInfo = makeDefaultBrowserInfo(isDefaultBrowser: value)
            saveDefaultBrowserInfo(defaultBrowserInfo)
            defaultBrowserEventMapper.fire(.successfulResult)
            return .success(newInfo: defaultBrowserInfo)
        case let .failure(.maxNumberOfAttemptsExceeded(nextRetryDate)):
            // If there's no previous information saved exit early. This should not happen.
            guard let storedDefaultBrowserInfo = defaultBrowserInfoStore.defaultBrowserInfo else {
                defaultBrowserEventMapper.fire(.rateLimitReachedNoExistingResultPersisted)
                return .failure(.rateLimitReached(updatedStoredInfo: nil))
            }
            // Update the current info and save them
            let defaultBrowserInfo = makeDefaultBrowserInfo(
                isDefaultBrowser: storedDefaultBrowserInfo.isDefaultBrowser,
                lastSuccessfulCheckDate: storedDefaultBrowserInfo.lastSuccessfulCheckDate,
                nextRetryAvailableDate: nextRetryDate
            )
            saveDefaultBrowserInfo(defaultBrowserInfo)
            defaultBrowserEventMapper.fire(.rateLimitReached)
            return .failure(.rateLimitReached(updatedStoredInfo: defaultBrowserInfo))
        case let .failure(.unknownError(error)):
            defaultBrowserEventMapper.fire(.unknownError)
            return .failure(.unknownError(error))
        case .failure(.notSupportedOnThisOSVersion):
            return .failure(.notSupportedOnCurrentOSVersion)
        }
    }

    private func makeDefaultBrowserInfo(isDefaultBrowser: Bool, lastSuccessfulCheckDate: TimeInterval? = nil, nextRetryAvailableDate: Date? = nil) -> DefaultBrowserInfo {
        let lastSuccessfulCheckDate = lastSuccessfulCheckDate ?? dateProvider().timeIntervalSince1970
        let lastAttemptedCheckDate = dateProvider().timeIntervalSince1970
        let currentNumberOfTimesChecked = defaultBrowserInfoStore.defaultBrowserInfo.flatMap(\.numberOfTimesChecked) ?? 0
        let nextRetryAvailableDate = nextRetryAvailableDate?.timeIntervalSince1970

        return DefaultBrowserInfo(
            isDefaultBrowser: isDefaultBrowser,
            lastSuccessfulCheckDate: lastSuccessfulCheckDate,
            lastAttemptedCheckDate: lastAttemptedCheckDate,
            numberOfTimesChecked: currentNumberOfTimesChecked + 1,
            nextRetryAvailableDate: nextRetryAvailableDate
        )
    }

    private func saveDefaultBrowserInfo(_ defaultBrowserInfo: DefaultBrowserInfo) {
        defaultBrowserInfoStore.defaultBrowserInfo = defaultBrowserInfo
    }
}

// MARK: - Debug Events

extension DefaultBrowserManager {

    enum DebugEvent {
        case successfulResult
        case rateLimitReached
        case rateLimitReachedNoExistingResultPersisted
        case unknownError
    }
    
}
