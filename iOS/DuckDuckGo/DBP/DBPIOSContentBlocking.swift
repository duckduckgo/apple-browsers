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

/// iOS-side adapter that snapshots compiled rule lists and surrogate tracker data for the
/// DBP broker job webview at job-start time.
@MainActor
struct DBPIOSContentBlocking: DBPWebViewContentBlocking {
    let contentRuleLists: [WKContentRuleList]
    let surrogateTrackerData: TrackerData?

    init(contentBlockingManager: CompiledRuleListsSource) {
        // Snapshot once; jobs are short-lived.
        self.contentRuleLists = contentBlockingManager.currentRules.map { $0.rulesList }
        self.surrogateTrackerData = DefaultTrackerProtectionDataSource(
            contentBlockingManager: contentBlockingManager
        ).surrogateFilteredTrackerData
    }
}
