//
//  DefaultBrowserManagerMock.swift
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
@testable import DuckDuckGo

final class DefaultBrowserManagerMock: DefaultBrowserManaging {
    private(set) var didCallDefaultBrowserInfo: Bool = false

    var resultToReturn: DefaultBrowserInfoResult = .successful(isDefaultBrowser: true)

    func defaultBrowserInfo() -> DefaultBrowserInfoResult {
        didCallDefaultBrowserInfo = true
        return resultToReturn
    }
}

extension DefaultBrowserInfoResult {

    static func successful(isDefaultBrowser: Bool) -> DefaultBrowserInfoResult {
        .success(
            newInfo:
                DefaultBrowserInfo(
                    isDefaultBrowser: isDefaultBrowser,
                    lastSuccessfulCheckDate: 1741586108000,
                    lastAttemptedCheckDate: 1741586108000,
                    numberOfTimesChecked: 1,
                    nextRetryAvailableDate: nil
                )
        )
    }

    static func failed(reason: Failure) -> DefaultBrowserInfoResult {
        .failure(reason)
    }
}
