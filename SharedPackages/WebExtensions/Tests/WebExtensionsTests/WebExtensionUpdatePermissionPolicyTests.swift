//
//  WebExtensionUpdatePermissionPolicyTests.swift
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
import XCTest
@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class WebExtensionUpdatePermissionPolicyTests: XCTestCase {
    private let policy = WebExtensionUpdatePermissionPolicy()
    private let now = Date(timeIntervalSince1970: 1_000)

    func testRequiredAPIsNeedCurrentUnexpiredApproval() async throws {
        let candidate = try await makeExtension(["permissions": ["storage"]])
        var settings = WebExtensionPermissionSettings()
        XCTAssertFalse(policy.canActivate(candidate, settings: settings, now: now))
        settings.grantedPermissions["storage"] = now
        XCTAssertFalse(policy.canActivate(candidate, settings: settings, now: now))
        settings.grantedPermissions["storage"] = .distantFuture
        XCTAssertTrue(policy.canActivate(candidate, settings: settings, now: now))
        settings.grantedPermissions.removeValue(forKey: "storage")
        XCTAssertFalse(policy.canActivate(candidate, settings: settings, now: now))
    }

    func testOptionalDeclarationsAloneDoNotIncreaseAccess() async throws {
        let candidate = try await makeExtension(["optional_permissions": ["tabs", "privacy"],
                                                 "optional_host_permissions": ["<all_urls>"]])
        XCTAssertTrue(policy.canActivate(candidate, settings: WebExtensionPermissionSettings(), now: now))
    }

    func testOptionalToRequiredNeedsApprovalEvenWhenTheManifestAlreadyDeclaredIt() async throws {
        let candidate = try await makeExtension(["permissions": ["tabs"]])
        var settings = WebExtensionPermissionSettings()
        XCTAssertFalse(policy.canActivate(candidate, settings: settings, now: now))
        settings.grantedPermissions["tabs"] = .distantFuture
        XCTAssertTrue(policy.canActivate(candidate, settings: settings, now: now))
    }

    func testRequiredAppPermissionUsesGrantPresenceRatherThanAnExpiryDate() async throws {
        let candidate = try await makeExtension(["permissions": ["privacy"]])
        var settings = WebExtensionPermissionSettings()
        XCTAssertFalse(policy.canActivate(candidate, settings: settings, now: now))
        settings.grantedAppPermissions["privacy"] = .distantPast
        XCTAssertTrue(policy.canActivate(candidate, settings: settings, now: now))
        settings.grantedAppPermissions.removeValue(forKey: "privacy")
        XCTAssertFalse(policy.canActivate(candidate, settings: settings, now: now))
    }

    func testMissingConsentFailsClosedEvenWithoutRequiredPowers() async throws {
        let candidate = try await makeExtension([:])
        XCTAssertFalse(policy.canActivate(candidate, settings: nil, now: now))
    }

    func testUnsupportedAPIsWithoutAnImplementationConferNoNewPower() async throws {
        let candidate = try await makeExtension(["permissions": ["ddg_unimplemented_test_permission"]])
        XCTAssertTrue(candidate.requestedPermissions.isEmpty)
        XCTAssertTrue(policy.canActivate(candidate, settings: WebExtensionPermissionSettings(), now: now))
    }

    func testHostContainmentIsDirectionalAcrossSchemesSubdomainsPathsAndAllURLs() async throws {
        let cases: [(approved: [String], requested: String, allowed: Bool)] = [
            (["<all_urls>"], "https://example.com/private/*", true),
            (["https://*.example.com/*"], "https://sub.example.com/private/*", true),
            (["https://example.com/*"], "https://*.example.com/*", false),
            (["https://example.com/redirect://*.tracking/*"], "https://*.example.com/redirect://*.tracking/*", false),
            (["https://*.sub.example.com/*"], "https://*.example.com/*", false),
            (["https://example.com/*"], "*://example.com/*", false),
            (["http://example.com/*", "https://example.com/*"], "*://example.com/*", true),
            (["*://example.com/*"], "https://example.com/*", true),
            (["https://example.com/*"], "https://example.com/private/*", true),
            (["https://example.com/private/*"], "https://example.com/*", false),
            (["https://example.com/*"], "https://other.example/*", false),
            (["https://example.com/*"], "<all_urls>", false)
        ]
        for testCase in cases {
            let candidate = try await makeExtension(["host_permissions": [testCase.requested]])
            var settings = WebExtensionPermissionSettings()
            settings.grantedMatchPatterns = Dictionary(uniqueKeysWithValues: testCase.approved.map { ($0, .distantFuture) })
            XCTAssertEqual(policy.canActivate(candidate, settings: settings, now: now), testCase.allowed,
                           "\(testCase.approved) must \(testCase.allowed ? "cover" : "not cover") \(testCase.requested)")
        }
    }

    func testExpiredAndMalformedHostGrantsDoNotProvideApproval() async throws {
        let candidate = try await makeExtension(["host_permissions": ["https://example.com/*"]])
        var settings = WebExtensionPermissionSettings()
        settings.grantedMatchPatterns = ["https://example.com/*": now, "invalid-pattern": .distantFuture]
        XCTAssertFalse(policy.canActivate(candidate, settings: settings, now: now))
    }

    func testMalformedSavedPatternsFailClosedEvenWhenExpiredAndNotRequiredByCandidate() async throws {
        let candidate = try await makeExtension(["permissions": ["storage"]])
        var settings = WebExtensionPermissionSettings()
        settings.grantedPermissions["storage"] = .distantFuture
        settings.grantedMatchPatterns["invalid-pattern"] = .distantPast
        XCTAssertFalse(policy.canActivate(candidate, settings: settings, now: now))
    }

    func testNativeRequiredAggregateCoversMV2HostsContentScriptsAndExternalConnections() async throws {
        let cases: [(manifest: [String: Any], required: String)] = [
            (["manifest_version": 2, "permissions": ["https://mv2.example/*"]], "https://mv2.example/*"),
            (["content_scripts": [["matches": ["https://script.example/*"], "js": ["content.js"]]]], "https://script.example/*"),
            (["externally_connectable": ["matches": ["https://external.example/*"]]], "https://external.example/*")
        ]
        for testCase in cases {
            let candidate = try await makeExtension(testCase.manifest)
            var settings = WebExtensionPermissionSettings()
            XCTAssertFalse(policy.canActivate(candidate, settings: settings, now: now), testCase.required)
            settings.grantedMatchPatterns[testCase.required] = .distantFuture
            XCTAssertTrue(policy.canActivate(candidate, settings: settings, now: now), testCase.required)
        }
    }

    private func makeExtension(_ fields: [String: Any]) async throws -> WKWebExtension {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        var manifest: [String: Any] = ["manifest_version": 3, "name": "Update permission fixture", "version": "2.0"]
        manifest.merge(fields) { _, supplied in supplied }
        try JSONSerialization.data(withJSONObject: manifest).write(to: directory.appendingPathComponent("manifest.json"))
        try Data().write(to: directory.appendingPathComponent("content.js"))
        return try await WKWebExtension(resourceBaseURL: directory)
    }
}
