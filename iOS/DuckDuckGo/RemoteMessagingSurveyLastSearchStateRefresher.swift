//
//  RemoteMessagingSurveyLastSearchStateRefresher.swift
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
import RemoteMessaging
import BrowserServicesKit

protocol RemoteMessagingLastSearchStateRefresher {
    func refreshLastSearchState(forURLPath: String) -> String
}

struct RemoteMessagingSurveyLastSearchStateRefresher: RemoteMessagingLastSearchStateRefresher {
    private let searchDauDateProvider: AutofillUsageProvider
    private let refreshLastSearchStateFunction: (_ path: String, _ lastSearchDate: Date?) -> String
    
    init(
        searchDauDateProvider: AutofillUsageProvider = AutofillUsageStore(),
        refreshLastSearchStateFunction: @escaping (String, Date?) -> String = DefaultRemoteMessagingSurveyURLBuilder.refreshLastSearchState
    ) {
        self.searchDauDateProvider = searchDauDateProvider
        self.refreshLastSearchStateFunction = refreshLastSearchStateFunction
    }
    
    func refreshLastSearchState(forURLPath path: String) -> String {
        let lastSearchDate = searchDauDateProvider.searchDauDate
        return refreshLastSearchStateFunction(path, lastSearchDate)
    }
}
