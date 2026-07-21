//
//  PIRDebugMiscTests.swift
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
import DataBrokerProtectionCore
@testable import PIRDebugKit

final class PIRDebugMiscTests: XCTestCase {

    // MARK: - Branch name sanitization

    func testBranchNameSanitizerReplacesDisallowedCharacters() {
        XCTAssertEqual(PIRDebugBranchNameSanitizer.sanitize("randerson/fix-foo"), "randerson-fix-foo")
    }

    func testBranchNameSanitizerLowercases() {
        XCTAssertEqual(PIRDebugBranchNameSanitizer.sanitize("Feature/ABC_123"), "feature-abc-123")
    }

    func testBranchNameSanitizerKeepsDotsAndDashes() {
        XCTAssertEqual(PIRDebugBranchNameSanitizer.sanitize("v1.2.3-rc.1"), "v1.2.3-rc.1")
    }

    func testBranchNameSanitizerReplacesSpacesAndSlashes() {
        XCTAssertEqual(PIRDebugBranchNameSanitizer.sanitize("my branch/name"), "my-branch-name")
    }

    // MARK: - Injected script source seam mapping

    func testInjectedScriptSourceBundledMapsToNil() {
        XCTAssertNil(InjectedScriptSource.bundled.customContentScopeJSURL)
    }

    func testInjectedScriptSourceFileMapsToURL() {
        let url = URL(fileURLWithPath: "/tmp/contentScopeIsolated.js")
        XCTAssertEqual(InjectedScriptSource.file(url).customContentScopeJSURL, url)
    }

    // MARK: - Services endpoint resolution

    func testServicesEndpointBaseURLs() {
        XCTAssertEqual(PIRServicesEndpoint.production.baseURL.absoluteString, "https://dbp.duckduckgo.com")
        XCTAssertEqual(PIRServicesEndpoint.staging.baseURL.absoluteString, "https://dbp-staging.duckduckgo.com")
        let custom = URL(string: "http://localhost:3001")!
        XCTAssertEqual(PIRServicesEndpoint.custom(custom).baseURL, custom)
    }

    func testRemoteBrokerEndpointStagingBranchAppliesSanitization() {
        let endpoint = RemoteBrokerEndpoint.stagingBranch("randerson/fix-foo")
        XCTAssertEqual(endpoint.baseURL.absoluteString,
                       "https://dbp-staging.duckduckgo.com/branches/randerson-fix-foo")
    }
}
