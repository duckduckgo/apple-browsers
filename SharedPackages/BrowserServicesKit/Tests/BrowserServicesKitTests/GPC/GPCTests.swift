//
//  GPCTests.swift
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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

import XCTest

@testable import BrowserServicesKit

final class GPCTests: XCTestCase {
    var appConfig: PrivacyConfiguration!

    override func setUp() {
        super.setUp()

        let gpcFeature = PrivacyConfigurationData.PrivacyFeature(state: "enabled",
                                                                 exceptions: [],
                                                                 settings: [
                "gpcHeaderEnabledSites": [
                    "washingtonpost.com",
                    "nytimes.com",
                    "global-privacy-control.glitch.me"
                ]
        ])
        let privacyData = PrivacyConfigurationData(features: [PrivacyFeature.gpc.rawValue: gpcFeature],
                                                   unprotectedTemporary: [],
                                                   trackerAllowlist: [:])
        let localProtection = MockDomainsProtectionStore()
        appConfig = AppPrivacyConfiguration(data: privacyData,
                                            identifier: "",
                                            localProtection: localProtection,
                                            internalUserDecider: DefaultInternalUserDecider())
    }

    func testWhenGPCEnableDomainIsHttpThenISGPCEnabledTrue() {
        let result = GPCRequestFactory().isGPCEnabled(url: URL(string: "https://www.washingtonpost.com")!, config: appConfig)
        XCTAssertTrue(result)
    }

    func testWhenGPCEnableDomainIsHttpsThenISGPCEnabledTrue() {
        let result = GPCRequestFactory().isGPCEnabled(url: URL(string: "http://www.washingtonpost.com")!, config: appConfig)
        XCTAssertTrue(result)
    }

    func testWhenGPCEnableDomainHasNoSubDomainThenISGPCEnabledTrue() {
        let result = GPCRequestFactory().isGPCEnabled(url: URL(string: "http://washingtonpost.com")!, config: appConfig)
        XCTAssertTrue(result)
    }

    func testWhenGPCEnableDomainHasPathThenISGPCEnabledTrue() {
        let result = GPCRequestFactory().isGPCEnabled(url: URL(string: "http://www.washingtonpost.com/test/somearticle.html")!, config: appConfig)
        XCTAssertTrue(result)
    }

    func testWhenGPCEnableDomainHasCorrectSubdomainThenISGPCEnabledTrue() {
        let result = GPCRequestFactory().isGPCEnabled(url: URL(string: "http://global-privacy-control.glitch.me")!, config: appConfig)
        XCTAssertTrue(result)
    }

    func testWhenGPCEnableDomainHasWrongSubdomainThenISGPCEnabledFalse() {
        let result = GPCRequestFactory().isGPCEnabled(url: URL(string: "http://glitch.me")!, config: appConfig)
        XCTAssertFalse(result)
    }

}
