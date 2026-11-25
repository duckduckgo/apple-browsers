//
//  WebPageTranslationSettingsTests.swift
//  DuckDuckGoTests
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

import XCTest
import PrivacyConfig
import PrivacyConfigTestsUtils
import Core
@testable import DuckDuckGo

final class WebPageTranslationSettingsTests: XCTestCase {

    func testReadsSampleLengthFromTheFeatureSettings() throws {
        XCTAssertEqual(try makeSUT(settings: #"{"sampleLength": 2000}"#).sampleLength, 2000)
    }

    func testDefaultsWhenTheFeatureIsMissing() throws {
        XCTAssertEqual(try makeSUT(settings: nil).sampleLength, 4096)
    }

    func testDefaultsWhenKeyAbsent() throws {
        XCTAssertEqual(try makeSUT(settings: "{}").sampleLength, 4096)
    }

    func testDefaultsWhenValueWrongType() throws {
        XCTAssertEqual(try makeSUT(settings: #"{"sampleLength": "2000"}"#).sampleLength, 4096)
    }

    func testDefaultsWhenValueNotPositive() throws {
        XCTAssertEqual(try makeSUT(settings: #"{"sampleLength": 0}"#).sampleLength, 4096)
        XCTAssertEqual(try makeSUT(settings: #"{"sampleLength": -5}"#).sampleLength, 4096)
    }

    func testFollowsAConfigUpdateWhileRunning() throws {
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = try Self.config(settings: #"{"sampleLength": 2000}"#)
        let sut = WebPageTranslationSettings(privacyConfigurationManager: manager)
        XCTAssertEqual(sut.sampleLength, 2000)

        manager.privacyConfig = try Self.config(settings: #"{"sampleLength": 1000}"#)
        XCTAssertEqual(sut.sampleLength, 1000)
    }

    func testIsDisabledOnExceptedDomains() throws {
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = try Self.config(settings: "{}", exceptions: ["example.fr"])
        let sut = WebPageTranslationSettings(privacyConfigurationManager: manager)
        XCTAssertFalse(sut.isEnabled(forDomain: "example.fr"))
        XCTAssertTrue(sut.isEnabled(forDomain: "example.com"))
    }

    func testBlocksNoSiteWhenTheFeatureIsMissing() throws {
        let sut = try makeSUT(settings: nil)
        XCTAssertTrue(sut.isEnabled(forDomain: "example.fr"))
        XCTAssertTrue(sut.isEnabled(forDomain: nil))
    }

    func testBlocksNoSiteWhereProtectionsAreOff() throws {
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = try Self.config(settings: "{}", unprotectedDomains: ["example.fr"])
        let sut = WebPageTranslationSettings(privacyConfigurationManager: manager)
        XCTAssertTrue(sut.isEnabled(forDomain: "example.fr"))
    }

    private func makeSUT(settings: String?) throws -> WebPageTranslationSettings {
        let manager = MockPrivacyConfigurationManager()
        manager.privacyConfig = try Self.config(settings: settings)
        return WebPageTranslationSettings(privacyConfigurationManager: manager)
    }

    /// A real config with `features.pageTranslation` carrying `settings`; nil leaves the feature out.
    static func config(settings: String?,
                       exceptions: [String] = [],
                       unprotectedDomains: Set<String> = []) throws -> PrivacyConfiguration {
        let exceptionsJSON = exceptions.map { #"{"domain": "\#($0)"}"# }.joined(separator: ",")
        let feature = settings.map {
            #", "pageTranslation": {"state": "enabled", "exceptions": [\#(exceptionsJSON)], "settings": \#($0)}"#
        } ?? ""
        let json = #"{"features": {"contentBlocking": {"state": "enabled", "exceptions": []}\#(feature)}, "unprotectedTemporary": []}"#
        return AppPrivacyConfiguration(data: try PrivacyConfigurationData(data: Data(json.utf8)),
                                       identifier: "",
                                       localProtection: MockDomainsProtectionStore(unprotectedDomains: unprotectedDomains),
                                       internalUserDecider: DefaultInternalUserDecider(store: InternalUserStore()))
    }
}
