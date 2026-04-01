//
//  AddressBarURLFilter.swift
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

import Common
import Foundation

protocol AddressBarURLFiltering {
    func shouldUpdate(for newURL: URL, currentURL: URL?) -> Bool
    mutating func commitNavigation(for url: URL?)
    mutating func beginUserNavigation()
    mutating func beginUserReload()
    mutating func invalidate()
}

struct AddressBarURLFilter: AddressBarURLFiltering {

    var committedSecurityOrigin: SecurityOrigin?
    var isUserInitiatedNavigation: Bool = false

    /// Determines whether a URL change should update the address bar.
    ///
    /// User-initiated navigations always update immediately. For web-driven navigations
    /// (redirects, JS-initiated), the URL is only shown if its security origin matches
    /// the last committed origin. This prevents intermediate redirect URLs from flashing
    /// in the address bar.
    func shouldUpdate(for newURL: URL, currentURL: URL?) -> Bool {
        if isUserInitiatedNavigation {
            return true
        }

        if newURL.isCustomURLScheme() {
            return true
        }

        if let committed = committedSecurityOrigin, !committed.isEmpty {
            return newURL.securityOrigin == committed
        }

        if let currentHost = currentURL?.host, let newHost = newURL.host {
            return currentHost == newHost
        }

        return true
    }

    mutating func commitNavigation(for url: URL?) {
        committedSecurityOrigin = url?.securityOrigin
        isUserInitiatedNavigation = false
    }

    mutating func beginUserNavigation() {
        isUserInitiatedNavigation = true
        committedSecurityOrigin = nil
    }

    mutating func beginUserReload() {
        isUserInitiatedNavigation = true
    }

    mutating func invalidate() {
        committedSecurityOrigin = nil
    }
}
