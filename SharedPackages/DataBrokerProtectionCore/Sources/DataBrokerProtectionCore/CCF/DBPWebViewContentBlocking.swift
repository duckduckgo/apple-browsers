//
//  DBPWebViewContentBlocking.swift
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

import Foundation
import TrackerRadarKit
import WebKit

/// Source of content-blocking assets the DBP broker job webview installs.
///
/// Snapshot at handler-init time: the job webview is short-lived (one scan or opt-out)
/// so we do not subscribe to rule-list updates. Implementations are expected to read
/// fresh values at construction.
@MainActor
public protocol DBPWebViewContentBlocking {
    /// Compiled WKContentRuleLists to install on `DataBrokerUserContentController`.
    var contentRuleLists: [WKContentRuleList] { get }

    /// Surrogate-filtered tracker data passed to the non-isolated `ContentScopeUserScript`
    /// so C-S-S can inject surrogates for blocked third-party scripts.
    var surrogateTrackerData: TrackerData? { get }
}
