//
//  DBPIOSContentBlocking.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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

import BrowserServicesKit
import DataBrokerProtectionCore
import TrackerRadarKit
import WebKit

/// iOS-side adapter that reads compiled rule lists and surrogate tracker data fresh from
/// `ContentBlocking.shared.contentBlockingManager` on every access. This provider is
/// constructed once at app launch and reused across all background jobs, so TDS
/// recompilations land in subsequent jobs without restarting the app.
@MainActor
struct DBPIOSContentBlocking: DBPWebViewContentBlocking {
    private let contentBlockingManager: CompiledRuleListsSource

    init(contentBlockingManager: CompiledRuleListsSource) {
        self.contentBlockingManager = contentBlockingManager
    }

    var contentRuleLists: [WKContentRuleList] {
        contentBlockingManager.currentRules.map { $0.rulesList }
    }

    var surrogateTrackerData: TrackerData? {
        DefaultTrackerProtectionDataSource(
            contentBlockingManager: contentBlockingManager
        ).surrogateFilteredTrackerData
    }
}
