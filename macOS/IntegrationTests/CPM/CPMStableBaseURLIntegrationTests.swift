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

    // Research-only characterization: a healthy probe is a negative reproduction result.
    // No startup delay, migration hold or fabricated monitor callback is introduced.
    func testP3ResearchPersistentCacheReload() async throws {
        try await exerciseP3Research(loadFromDisk: false)
    }

    func testP3ResearchPersistentCacheDiskLoad() async throws {
        try await exerciseP3Research(loadFromDisk: true)
    }

    private func exerciseP3Research(loadFromDisk: Bool) async throws {
        executionTimeAllowance = 3600
        let environment = ProcessInfo.processInfo.environment
        let entries = Int(environment["CPM_APP_INTEGRATION_P3_CACHE_ENTRIES"] ?? "") ?? 20000
        let iterations = Int(environment["CPM_APP_INTEGRATION_P3_RELOADS"] ?? "") ?? 3
        let harness = try XCTUnwrap(self.harness)
        // The diagnostics observer joins WebKit's real background load. Do not add a second
        // unbounded await here: error 6 can arrive without completing that callback (P2).
        print("CPM P3 RESEARCH starting owned context")
        try await harness.start(awaitBackgroundLoad: false)
        try await harness.waitForBackgroundReady()
        print("CPM P3 RESEARCH initial background ready")
        let tab = try XCTUnwrap(harness.openWindow().first)
        // Record cold-window startup separately; the cache experiment starts from a verified
        // healthy navigation and never counts an initial-load race as P3.
        _ = try await harness.navigate(tab, label: "research-cold-window-control")
        try requireHealthyResearchControl(try await harness.navigate(tab, label: "research-baseline"))
        XCTAssertEqual(tab.webView.configuration.websiteDataStore.identifier, harness.dataStore.identifier)
        print("CPM P3 RESEARCH filling persistent cache entries=\(entries)")
        try requireHealthyResearchControl(try await harness.navigate(tab, label: "fill?n=\(entries)", timeout: 1800))
        try await harness.waitForCacheReads(in: tab, entries: entries)
        let hasDiskCache = await withCheckedContinuation { continuation in
            harness.dataStore.fetchDataRecords(ofTypes: [WKWebsiteDataTypeDiskCache]) { records in
                continuation.resume(returning: !records.isEmpty)
            }
        }
        XCTAssertTrue(hasDiskCache)
        harness.note(["researchDiskCacheVerified": hasDiskCache])
        guard hasDiskCache else {
            throw NSError(domain: "CPMResearchPrecondition", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Owned persistent store has no disk-cache data"])
        }
        print("CPM P3 RESEARCH persistent cache reads completed")
        for iteration in 0..<iterations {
            let previous = try XCTUnwrap(harness.context)
            let began = Date()
            if loadFromDisk {
                // Preserve the populated website store. Reparse the installation from disk through
                // the real manager, rather than clearing the cache under investigation.
                harness.manager.unloadAllExtensions()
                await harness.manager.loadInstalledExtensions()
            } else {
                try await harness.manager.reloadExtension(identifier: previous.uniqueIdentifier)
            }
            let loaded = try XCTUnwrap(harness.context)
            let viewAtReturn = CPMAppWebKit.background(loaded) != nil
            let probe = try await harness.navigate(tab, label: "research-\(loadFromDisk ? "disk" : "reload")-\(iteration)")
            let p3 = probe.failures.contains { snapshot in
                let events = (snapshot["bg_events"] ?? "").split(separator: ">").map(String.init)
                return snapshot["context_loaded"] == "true" && snapshot["bg_view_alive"] == "false"
                    && events.contains("load") && !events.contains("view")
            }
            harness.note(["research": true, "diskLoad": loadFromDisk, "iteration": iteration,
                          "cacheEntriesRequested": entries, "originBefore": previous.baseURL.absoluteString,
                          "originAfter": loaded.baseURL.absoluteString, "backgroundAtLoadReturn": viewAtReturn,
                          "reloadToProbeSeconds": Date().timeIntervalSince(began), "p3NoBackgroundFailure": p3,
                          "probeResponded": probe.responded, "pageReceivedInitResponse": probe.pageReceivedInitResponse])
            print("CPM P3 RESEARCH iteration=\(iteration) disk=\(loadFromDisk) p3=\(p3) responded=\(probe.responded)")
            try await harness.waitForBackgroundReady()
            try requireHealthyResearchControl(try await harness.navigate(tab, label: "research-readiness-control-\(iteration)"))
        }
    }

    private func requireHealthyResearchControl(_ probe: CPMAppIntegrationHarness.Probe) throws {
        assertHealthy(probe)
        guard probe.responded, probe.pageReceivedInitResponse, probe.failures.isEmpty else {
            throw NSError(domain: "CPMResearchPrecondition", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unhealthy control before further measurements: \(probe.label)"])
        }
    }

    func testBackgroundProcessCrashStillRecovers() async throws {
        let harness = try await start()
        // Keep the shipped error-6 retry and confirmed-hang fallback enabled. Other P3
        // scenarios isolate the origin policy with the independent recovery flags disabled.
        harness.setFlag(.cpmBackgroundLoadRecovery, enabled: true)
        harness.setFlag(.cpmMessagingHangRecovery, enabled: true)
        let tab = try XCTUnwrap(harness.openWindow().first)
        assertHealthy(try await harness.navigate(tab, label: "background-crash-baseline"))
        let initial = try XCTUnwrap(harness.context)
        let pid = try XCTUnwrap(CPMAppWebKit.process(CPMAppWebKit.background(initial)))
        XCTAssertEqual(kill(pid, SIGKILL), 0)
        try await harness.wait("owned background crash", timeout: 12) { CPMAppWebKit.process(CPMAppWebKit.background(initial)) != pid }
        // WebKit may recover natively or leave error 6 after the retry. In the latter case,
        // exercise the shipped confirmed-hang fallback using two real navigation timeouts.
        for attempt in 1...2 {
            let probe = try await harness.navigate(tab, label: "background-crash-recovery-\(attempt)")
            if probe.responded && probe.pageReceivedInitResponse && probe.failures.isEmpty {
                assertHealthy(probe)
                return
            }
            if attempt == 1 {
                assertFailed(probe)
            } else {
                // Automatic context replacement cancels the confirming measurement, so its
                // missing reply need not produce a second timeout diagnostic from the old context.
                XCTAssertFalse(probe.responded)
                XCTAssertFalse(probe.pageReceivedInitResponse)
            }
        }
        try await harness.wait("confirmed-hang recovery replaces the crashed context", timeout: 12) { harness.context !== initial }
        XCTAssertEqual(harness.context?.uniqueIdentifier, initial.uniqueIdentifier)
        XCTAssertNotEqual(harness.context?.baseURL, initial.baseURL, "Failed worker recovery must abandon its broken registration")
        try await harness.waitForBackgroundReady()
        assertHealthy(try await harness.navigate(tab, label: "background-crash-recovered"))
    }
}
#endif
