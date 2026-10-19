//
//  CPMStableBaseURLIntegrationTests.swift
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

import FeatureFlags_macOS
import WebExtensions
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

#if DEBUG
@available(macOS 15.4, *)
@MainActor
final class CPMStableBaseURLIntegrationTests: CPMAppIntegrationTestCase {
    func testReloadKeepsCPMOriginAndFirstNavigationHealthy() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "reload-baseline"))
        let initial = try XCTUnwrap(harness.context)
        let origin = initial.baseURL
        for iteration in 0..<3 {
            let began = Date()
            try await harness.manager.reloadExtension(identifier: initial.uniqueIdentifier)
            let context = try XCTUnwrap(harness.context)
            let backgroundAtLoadReturn = CPMAppWebKit.background(context) != nil
            XCTAssertEqual(harness.originMigrationCount, 0, "WebKit requested origin migration on CPM reload")
            XCTAssertEqual(context.baseURL, origin, "CPM reload changed origin and reintroduced WebKit origin migration")
            assertHealthy(try await harness.navigate(tab, label: "immediate-after-reload-\(iteration)"))
            harness.note(["reloadSeconds": Date().timeIntervalSince(began), "originBefore": origin.absoluteString,
                          "originAfter": context.baseURL.absoluteString, "backgroundAtLoadReturn": backgroundAtLoadReturn])
        }
    }

    func testFullDataClearReloadWorksFromDisk() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "disk-load-baseline"))
        let origin = try XCTUnwrap(harness.context).baseURL
        harness.manager.unloadAllExtensions()
        await harness.dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        await harness.manager.loadInstalledExtensions()
        XCTAssertNotEqual(harness.context?.baseURL, origin, "Data clear must discard the old worker origin")
        assertHealthy(try await harness.navigate(tab, label: "immediate-after-disk-load"))
    }

    func testPersistentCacheReloadKeepsOriginAndMessaging() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        XCTAssertEqual(tab.webView.configuration.websiteDataStore.identifier, harness.dataStore.identifier)
        XCTAssertNotNil(harness.dataStore.identifier)
        assertHealthy(try await harness.navigate(tab, label: "fill?n=20000", timeout: 180))
        try await harness.waitForCacheReads(in: tab, entries: 20000)
        let hasDiskCache = await withCheckedContinuation { continuation in
            harness.dataStore.fetchDataRecords(ofTypes: [WKWebsiteDataTypeDiskCache]) { records in
                continuation.resume(returning: !records.isEmpty)
            }
        }
        XCTAssertTrue(hasDiskCache, "The owned persistent WebKit store has no disk-cache data")
        let initial = try XCTUnwrap(harness.context)
        let began = Date()
        try await harness.manager.reloadExtension(identifier: initial.uniqueIdentifier)
        let context = try XCTUnwrap(harness.context)
        XCTAssertEqual(context.baseURL, initial.baseURL, "Large-cache reload changed CPM origin")
        XCTAssertEqual(harness.originMigrationCount, 0, "WebKit requested origin migration with a populated cache")
        let probe = try await harness.navigate(tab, label: "after-large-cache-reload")
        assertHealthy(probe)
        harness.note(["cacheEntries": 20000, "serverSendCompletions": harness.server.completedCacheResponses, "reloadToReplySeconds": Date().timeIntervalSince(began),
                      "originBefore": initial.baseURL.absoluteString, "originAfter": context.baseURL.absoluteString,
                      "p3NoBackgroundFailure": probe.failures.contains { $0["bg_view_alive"] == "false" }])
    }

    func testRuntimeKillSwitchAppliesOnNextReloadWithoutChangingLiveContext() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "flag-baseline"))
        let initial = try XCTUnwrap(harness.context)
        harness.setFlag(.cpmStableBaseURL, enabled: false)
        XCTAssertEqual(harness.context?.baseURL, initial.baseURL)
        try await harness.manager.reloadExtension(identifier: initial.uniqueIdentifier)
        let disabled = try XCTUnwrap(harness.context)
        XCTAssertNotEqual(disabled.baseURL, initial.baseURL)
        try await harness.waitForBackgroundReady()
        assertHealthy(try await harness.navigate(tab, label: "flag-off"))
        harness.setFlag(.cpmStableBaseURL, enabled: true)
        try await harness.manager.reloadExtension(identifier: initial.uniqueIdentifier)
        let restored = try XCTUnwrap(harness.context)
        let record = try XCTUnwrap(harness.installationStore?.installedExtension(withUniqueIdentifier: initial.uniqueIdentifier))
        let origin = record.cpmOriginIdentifier?.uuidString ?? initial.uniqueIdentifier
        XCTAssertEqual(restored.baseURL.absoluteString, "webkit-extension://\(origin.lowercased())/")
        try await harness.waitForBackgroundReady()
        assertHealthy(try await harness.navigate(tab, label: "flag-on"))
    }

    func testVersionUpgradeUsesNewInstallationOriginAndKeepsCPMHealthy() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "upgrade-baseline"))
        let previous = try XCTUnwrap(harness.context)
        try XCTUnwrap(harness.installationStore).markInstalledVersionAsOutdated()
        await harness.manager.syncEmbeddedExtensions(enabledTypes: [.embedded])
        let upgraded = try XCTUnwrap(harness.context)
        XCTAssertNotEqual(upgraded.uniqueIdentifier, previous.uniqueIdentifier)
        XCTAssertNotEqual(upgraded.baseURL, previous.baseURL)
        try await harness.waitForBackgroundReady()
        assertHealthy(try await harness.navigate(tab, label: "upgrade-fresh-document"))
        try await harness.manager.reloadExtension(identifier: upgraded.uniqueIdentifier)
        try await harness.waitForBackgroundReady()
        assertHealthy(try await harness.navigate(tab, label: "upgrade-reloaded"))
    }

    func testNetworkCrashCanRecoverWithStableOriginAfterExplicitReload() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "network-crash-baseline"))
        let initial = try XCTUnwrap(harness.context)
        let pid = try XCTUnwrap(CPMAppWebKit.network(CPMAppWebKit.background(initial)))
        XCTAssertEqual(kill(pid, SIGKILL), 0)
        // Isolate P3 from the independent Network recovery treatment: explicitly reload this context.
        try await harness.manager.reloadExtension(identifier: initial.uniqueIdentifier)
        assertHealthy(try await harness.navigate(tab, label: "network-crash-explicit-reload"))
    }

    func testLightweightDataClearReloadStillWorks() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "data-clear-baseline"))
        harness.manager.unloadAllExtensions()
        await harness.dataStore.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        await harness.manager.reloadInstalledExtensions()
        assertHealthy(try await harness.navigate(tab, label: "after-data-clear"))
        let rotated = try XCTUnwrap(harness.context)
        try await harness.manager.reloadExtension(identifier: rotated.uniqueIdentifier)
        XCTAssertEqual(harness.context?.baseURL, rotated.baseURL)
        assertHealthy(try await harness.navigate(tab, label: "after-data-clear-second-reload"))
    }

    func testStorageSurvivesRuntimeRollbackAndReenable() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "storage-baseline"))
        let identifier = try XCTUnwrap(harness.context).uniqueIdentifier
        let key = UUID().uuidString
        let value = UUID().uuidString
        let written = try await storage(in: tab, harness: harness, key: key, value: value)
        XCTAssertEqual(written, value)
        for enabled in [false, true] {
            harness.setFlag(.cpmStableBaseURL, enabled: enabled)
            try await harness.manager.reloadExtension(identifier: identifier)
            try await harness.waitForBackgroundReady()
            assertHealthy(try await harness.navigate(tab, label: "storage-flag-\(enabled)"))
            let stored = try await storage(in: tab, harness: harness, key: key)
            XCTAssertEqual(stored, value, "Runtime rollback lost CPM extension storage")
        }
    }

    func testWebPageCannotReadStableExtensionResources() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "resource-privacy"))
        let resource = try XCTUnwrap(harness.context).baseURL.appendingPathComponent("manifest.json")
        let quoted = String(data: try JSONSerialization.data(withJSONObject: resource.absoluteString, options: [.fragmentsAllowed]), encoding: .utf8)!
        _ = try await harness.evaluate("window.cpmResourceProbe = 'pending'; fetch(\(quoted)).then(() => window.cpmResourceProbe = 'exposed').catch(() => window.cpmResourceProbe = 'blocked'); 'started'", in: tab.webView)
        let deadline = Date().addingTimeInterval(5)
        var outcome: String?
        repeat {
            outcome = try await harness.evaluate("window.cpmResourceProbe", in: tab.webView)
            if outcome != "pending" { break }
            try await harness.pause(0.05)
        } while Date() < deadline
        XCTAssertEqual(outcome, "blocked", "A normal web page could read the CPM extension origin")
    }

    private func storage(in tab: Tab, harness: CPMAppIntegrationHarness, key: String, value: String? = nil) async throws -> String? {
        var input = ["key": key]
        input["value"] = value
        let json = String(data: try JSONSerialization.data(withJSONObject: input), encoding: .utf8)!
        let quoted = String(data: try JSONSerialization.data(withJSONObject: json, options: [.fragmentsAllowed]), encoding: .utf8)!
        _ = try await harness.evaluate("document.documentElement.removeAttribute('data-cpm-app-storage-result'); document.documentElement.setAttribute('data-cpm-app-storage-input', \(quoted)); document.dispatchEvent(new Event('cpm-app-storage')); 'sent'", in: tab.webView)
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let response = try await harness.evaluate("document.documentElement.getAttribute('data-cpm-app-storage-result')", in: tab.webView) {
                let object = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: String]
                return object?["value"]
            }
            try await harness.pause(0.05)
        } while Date() < deadline
        XCTFail("No real browser.storage.local response")
        return nil
    }

    func testBackgroundProcessCrashStillRecovers() async throws {
        let harness = try await start()
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "background-crash-baseline"))
        let initial = try XCTUnwrap(harness.context)
        let pid = try XCTUnwrap(CPMAppWebKit.process(CPMAppWebKit.background(initial)))
        XCTAssertEqual(kill(pid, SIGKILL), 0)
        try await harness.wait("owned background crash", timeout: 12) { CPMAppWebKit.process(CPMAppWebKit.background(initial)) != pid }
        XCTAssertTrue(harness.context === initial)
        assertHealthy(try await harness.navigate(tab, label: "background-crash-recovered"))
    }
}
#endif
