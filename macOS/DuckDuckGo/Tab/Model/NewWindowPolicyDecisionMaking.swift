//
//  NewWindowPolicyDecisionMaking.swift
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

import WebKit

/// Represents a decision about whether to allow or cancel opening a new window/tab.
enum NewWindowPolicyDecision: Equatable {
    /// Allow opening with the specified new window policy (tab, popup, or window)
    case allow(NewWindowPolicy)
    /// Cancel the new window request
    case cancel
}

/// Protocol for objects that can make decisions about new window/tab creation.
@MainActor
protocol NewWindowPolicyDecisionMaking {
    /// Decides whether and how to open a new window/tab for a navigation action.
    /// - Parameter navigationAction: The navigation action requesting a new window
    /// - Returns: A decision to allow with a policy, cancel, or nil to defer to the next decision maker
    func decideNewWindowPolicy(for navigationAction: WKNavigationAction) -> NewWindowPolicyDecision?
}

extension LinkOpenBehavior {
    func newWindowPolicy(isBurner: Bool) -> NewWindowPolicy? {
        switch self {
        case .newWindow(let selected):
            return .window(active: selected, burner: isBurner)
        case .newTab(let selected):
            return .tab(selected: selected, burner: isBurner)
        case .currentTab:
            return .none
        }
    }
}
