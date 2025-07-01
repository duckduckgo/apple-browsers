//
//  DefaultBrowserInfoResult.swift
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

public struct DefaultBrowserContext: Codable, Equatable {
    /// True if DDG browser is set as default, false otherwise.
    public let isDefaultBrowser: Bool
    /// The time interval when we last got a valid result.
    public let lastSuccessfulCheckDate: TimeInterval
    /// The time interval when we last attempted to check an updated result.
    public let lastAttemptedCheckDate: TimeInterval
    /// Total number of times that the app requested an updated result.
    public let numberOfTimesChecked: Int
    /// The time interval at which the app can next request an updated response.
    public let nextRetryAvailableDate: TimeInterval?

    public init(isDefaultBrowser: Bool, lastSuccessfulCheckDate: TimeInterval, lastAttemptedCheckDate: TimeInterval, numberOfTimesChecked: Int, nextRetryAvailableDate: TimeInterval?) {
        self.isDefaultBrowser = isDefaultBrowser
        self.lastSuccessfulCheckDate = lastSuccessfulCheckDate
        self.lastAttemptedCheckDate = lastAttemptedCheckDate
        self.numberOfTimesChecked = numberOfTimesChecked
        self.nextRetryAvailableDate = nextRetryAvailableDate
    }
}

public enum DefaultBrowserInfoResult: Equatable {
    public enum Failure: Equatable {
        case notSupportedOnCurrentOSVersion
        case unknownError(NSError)
        case rateLimitReached(updatedStoredInfo: DefaultBrowserContext?)
    }

    case failure(DefaultBrowserInfoResult.Failure)
    case success(newInfo: DefaultBrowserContext)
}

public extension DefaultBrowserInfoResult {

    @discardableResult
    func onNewValue(_ f: (DefaultBrowserContext) -> Void) -> Self {
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

    func isDefaultBrowser() -> Bool {
        guard case let .success(newInfo) = self else { return false }
        return newInfo.isDefaultBrowser
    }
}
