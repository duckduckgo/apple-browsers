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
import FoundationExtensions
import Foundation

protocol AddressBarURLFiltering {
    func shouldUpdate(for newURL: URL) -> Bool
    mutating func commitNavigation(for url: URL?)
    mutating func beginUserNavigation()
    mutating func beginUserReload()
}

struct AddressBarURLFilter: AddressBarURLFiltering {

    private(set) var committedSecurityOrigin: SecurityOrigin?
    private(set) var isUserInitiatedNavigation: Bool = false

    /// Determines whether a URL change should update the address bar.
    ///
    /// User-initiated navigations always update immediately. For web-driven navigations
    /// (redirects, JS-initiated), the URL is only shown if its security origin matches
    /// the last committed origin. This prevents intermediate redirect URLs from flashing
    /// in the address bar.
    ///
    /// Matches macOS behavior: strict SecurityOrigin equality, no host-only fallback.
    func shouldUpdate(for newURL: URL) -> Bool {
        if isUserInitiatedNavigation {
            return true
        }

        if newURL.isCustomURLScheme() {
            return true
        }

        guard let committed = committedSecurityOrigin, !committed.isEmpty else {
            return false
        }

        return newURL.securityOrigin == committed
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
}
