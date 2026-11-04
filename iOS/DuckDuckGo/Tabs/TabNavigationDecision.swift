//
//  TabNavigationDecision.swift
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

import WebKit

/// A tab's navigation decision, independent of WebKit's policy representation.
/// Match `case .allow` for navigation side effects so both app-link modes are handled.
enum TabNavigationDecision: Sendable {
    enum AppLinks: Sendable {
        case enabled
        case disabled
    }

    case allow(appLinks: AppLinks)
    case cancel

    /// Convert only when returning the decision to WebKit.
    var webKitPolicy: WKNavigationActionPolicy {
        switch self {
        case .allow(appLinks: .enabled):
            return .allow
        case .allow(appLinks: .disabled):
            // _WKNavigationActionPolicyAllowWithoutTryingAppLink still allows the page to load.
            // Keep its private value here so internal navigation checks cannot mistake it for a denial.
            return WKNavigationActionPolicy(rawValue: 3) ?? .allow
        case .cancel:
            return .cancel
        }
    }
}
