//
//  DomainsProtectionStore.swift
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

public protocol DomainsProtectionStore: AnyObject {

    var unprotectedDomains: Set<String> { get }

    func disableProtection(forDomain domain: String)

    func enableProtection(forDomain domain: String)
}

/// Forwards to another store and calls `didChange` after a write changes the stored domains, so the user's allowlist
/// can be observed when it is written rather than when something derived from it, such as content blocking rules, is
/// rebuilt. Writes that change nothing, such as turning protections on for a site that isn't listed, don't call it.
final class ObservedDomainsProtectionStore: DomainsProtectionStore {

    private let store: DomainsProtectionStore
    private let didChange: () -> Void

    init(_ store: DomainsProtectionStore, didChange: @escaping () -> Void) {
        self.store = store
        self.didChange = didChange
    }

    var unprotectedDomains: Set<String> {
        store.unprotectedDomains
    }

    func disableProtection(forDomain domain: String) {
        notifyIfChanged { store.disableProtection(forDomain: domain) }
    }

    func enableProtection(forDomain domain: String) {
        notifyIfChanged { store.enableProtection(forDomain: domain) }
    }

    private func notifyIfChanged(_ write: () -> Void) {
        let before = store.unprotectedDomains
        write()
        if store.unprotectedDomains != before {
            didChange()
        }
    }
}
