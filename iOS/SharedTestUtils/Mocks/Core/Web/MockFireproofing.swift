//
//  MockFireproofing.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
@testable import Core

class MockFireproofing: Fireproofing {

    var loginDetectionEnabled: Bool = false
    var allowedDomains: [String]

    var isAllowedCookieDomainHandler: ((String) -> Bool)?
    var isAllowedFireproofDomainHandler: ((String) -> Bool)?

    init(domains: [String] = []) {
        self.allowedDomains = domains
    }

    func addToAllowed(domain: String) {
        allowedDomains.append(domain)
    }

    func remove(domain: String) {
        allowedDomains.removeAll { $0 == domain }
    }

    func clearAll() {
        allowedDomains.removeAll()
    }

    func isAllowed(cookieDomain: String) -> Bool {
        isAllowedCookieDomainHandler?(cookieDomain) ?? false
    }

    func isAllowed(fireproofDomain domain: String) -> Bool {
        isAllowedFireproofDomainHandler?(domain) ?? false
    }

    func displayDomain(for domain: String) -> String {
        domain
    }

    func migrateFireproofDomainsToETLDPlus1IfNeeded() -> Bool {
        false
    }

}
