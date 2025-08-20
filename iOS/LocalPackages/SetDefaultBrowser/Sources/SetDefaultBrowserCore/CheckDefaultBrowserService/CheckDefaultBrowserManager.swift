//
//  CheckDefaultBrowserManager.swift
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
import class UIKit.UIApplication

@MainActor
public protocol DefaultBrowserManaging: AnyObject {
    func defaultBrowserInfo() -> DefaultBrowserInfoResult
}

// MARK: - DefaultBrowserManager

@MainActor
public final class DefaultBrowserManager: DefaultBrowserManaging {
    private let defaultBrowserInfoStore: DefaultBrowserContextStorage
    private let defaultBrowserEventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserManagerDebugEvent>
    private let defaultBrowserChecker: CheckDefaultBrowserService
    private let dateProvider: () -> Date

    public init(
        defaultBrowserInfoStore: DefaultBrowserContextStorage,
        defaultBrowserEventMapper: any DefaultBrowserPromptEventMapping<DefaultBrowserManagerDebugEvent>,
        defaultBrowserChecker: CheckDefaultBrowserService = SystemCheckDefaultBrowserService(),
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.defaultBrowserChecker = defaultBrowserChecker
        self.defaultBrowserInfoStore = defaultBrowserInfoStore
        self.defaultBrowserEventMapper = defaultBrowserEventMapper
        self.dateProvider = dateProvider
    }

    public func defaultBrowserInfo() -> DefaultBrowserInfoResult {
        let defaultBrowserResult = defaultBrowserChecker.isDefaultWebBrowser()

        switch defaultBrowserResult {
        case let .success(value):
            let defaultBrowserInfo = makeDefaultBrowserInfo(isDefaultBrowser: value)
            saveDefaultBrowserInfo(defaultBrowserInfo)
            defaultBrowserEventMapper.fire(.successfulResult)
            return .success(newInfo: defaultBrowserInfo)
        case let .failure(.maxNumberOfAttemptsExceeded(nextRetryDate)):
            // If there's no previous information saved exit early. This should not happen.
            guard let storedDefaultBrowserInfo = defaultBrowserInfoStore.defaultBrowserContext else {
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
            defaultBrowserEventMapper.fire(.unknownError, error: error)
            return .failure(.unknownError(error))
        case .failure(.notSupportedOnThisOSVersion):
            return .failure(.notSupportedOnCurrentOSVersion)
        }
    }

    private func makeDefaultBrowserInfo(isDefaultBrowser: Bool, lastSuccessfulCheckDate: TimeInterval? = nil, nextRetryAvailableDate: Date? = nil) -> DefaultBrowserContext {
        let lastSuccessfulCheckDate = lastSuccessfulCheckDate ?? dateProvider().timeIntervalSince1970
        let lastAttemptedCheckDate = dateProvider().timeIntervalSince1970
        let currentNumberOfTimesChecked = defaultBrowserInfoStore.defaultBrowserContext.flatMap(\.numberOfTimesChecked) ?? 0
        let nextRetryAvailableDate = nextRetryAvailableDate?.timeIntervalSince1970

        return DefaultBrowserContext(
            isDefaultBrowser: isDefaultBrowser,
            lastSuccessfulCheckDate: lastSuccessfulCheckDate,
            lastAttemptedCheckDate: lastAttemptedCheckDate,
            numberOfTimesChecked: currentNumberOfTimesChecked + 1,
            nextRetryAvailableDate: nextRetryAvailableDate
        )
    }

    private func saveDefaultBrowserInfo(_ defaultBrowserInfo: DefaultBrowserContext) {
        defaultBrowserInfoStore.defaultBrowserContext = defaultBrowserInfo
    }
}
