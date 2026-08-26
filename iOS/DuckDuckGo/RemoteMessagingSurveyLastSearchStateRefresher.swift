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

protocol RemoteMessagingSurveyUsageStateRefreshing {
    func refreshSurveyUsageStates(forURLPath: String) -> String
}

struct RemoteMessagingSurveyUsageStateRefresher: RemoteMessagingSurveyUsageStateRefreshing {
    private let searchDauDateProvider: AutofillUsageProvider
    private let featureDiscovery: FeatureDiscovery
    private let refreshSurveyUsageStatesFunction: (_ path: String, _ lastSearchDate: Date?, _ daysSinceDuckAIUsed: Int?) -> String

    init(
        searchDauDateProvider: AutofillUsageProvider = AutofillUsageStore(),
        featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery(),
        refreshSurveyUsageStatesFunction: @escaping (String, Date?, Int?) -> String = DefaultRemoteMessagingSurveyURLBuilder.refreshSurveyUsageStates
    ) {
        self.searchDauDateProvider = searchDauDateProvider
        self.featureDiscovery = featureDiscovery
        self.refreshSurveyUsageStatesFunction = refreshSurveyUsageStatesFunction
    }

    func refreshSurveyUsageStates(forURLPath path: String) -> String {
        let queryItemNames = Set(URLComponents(string: path)?.queryItems?.map(\.name) ?? [])
        let lastSearchDate = queryItemNames.contains(RemoteMessagingSurveyActionParameter.lastSearchState.rawValue) ? searchDauDateProvider.searchDauDate : nil
        let daysSinceDuckAIUsed = queryItemNames.contains(RemoteMessagingSurveyActionParameter.lastDuckAIUsage.rawValue) ? featureDiscovery.daysSinceLastUsed(.aiChat) : nil
        return refreshSurveyUsageStatesFunction(path, lastSearchDate, daysSinceDuckAIUsed)
    }
}
