//
//  PrivacyConfigurationManagerUserAllowlistTests.swift
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

import Combine
import XCTest
import PrivacyConfigTestsUtils
import PrivacyConfig

final class PrivacyConfigurationManagerUserAllowlistTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()

    private func makeManager(store: MockDomainsProtectionStore) -> PrivacyConfigurationManager {
        // swiftlint:disable:next force_try
        let embedded = try! JSONSerialization.data(withJSONObject: ["version": 1, "features": [:], "unprotectedTemporary": []])
        return PrivacyConfigurationManager(fetchedETag: nil,
                                           fetchedData: nil,
                                           embeddedDataProvider: MockEmbeddedDataProvider(data: embedded, etag: "embedded"),
                                           localProtection: store,
                                           internalUserDecider: MockInternalUserDecider())
    }

    func testWhenUserTogglesProtectionThenPublisherFiresAfterTheStoreChanges() {
        let store = MockDomainsProtectionStore()
        let manager = makeManager(store: store)
        var listsWhenPublished: [[String]] = []
        manager.userUnprotectedDomainsPublisher
            .sink { listsWhenPublished.append(manager.privacyConfig.userUnprotectedDomains) }
            .store(in: &cancellables)

        manager.privacyConfig.userDisabledProtection(forDomain: "example.com")
        manager.privacyConfig.userEnabledProtection(forDomain: "example.com")

        XCTAssertEqual(listsWhenPublished, [["example.com"], []])
        XCTAssertEqual(store.unprotectedDomains, [])
    }

    func testWhenToggleLeavesTheListUnchangedThenPublisherDoesNotFire() {
        let manager = makeManager(store: MockDomainsProtectionStore())
        var fired = 0
        manager.userUnprotectedDomainsPublisher.sink { fired += 1 }.store(in: &cancellables)

        manager.privacyConfig.userEnabledProtection(forDomain: "example.com")
        manager.privacyConfig.userDisabledProtection(forDomain: "example.com")
        manager.privacyConfig.userDisabledProtection(forDomain: "example.com")

        XCTAssertEqual(fired, 1)
    }

    func testWhenConfigIsReloadedThenPublisherDoesNotFire() {
        let manager = makeManager(store: MockDomainsProtectionStore())
        var fired = false
        manager.userUnprotectedDomainsPublisher.sink { fired = true }.store(in: &cancellables)

        manager.reload(etag: nil, data: nil)

        XCTAssertFalse(fired)
    }
}
