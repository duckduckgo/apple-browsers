//
//  SingleTabBurnPerformanceTests.swift
//  UnitTests
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
import WebKit
@testable import Core
@testable import DuckDuckGo
@_spi(Testing) import Persistence
import WKAbstractions

@MainActor
final class SingleTabBurnPerformanceTests: XCTestCase {
    func testPairedWebsiteDataCleanupPerformance() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RUN_SINGLE_TAB_BURN_BENCHMARK"] == "1" else {
            throw XCTSkip("Opt in with RUN_SINGLE_TAB_BURN_BENCHMARK=1")
        }
        guard #available(iOS 17, *) else { throw XCTSkip("Requires an isolated persistent store") }
        let iterations = Int(environment["BURN_BENCHMARK_ITERATIONS"] ?? "100") ?? 100
        let warmups = Int(environment["BURN_BENCHMARK_WARMUPS"] ?? "5") ?? 5
        let identifier = UUID()
        do {
            try await runBenchmark(identifier: identifier, iterations: iterations, warmups: warmups)
        } catch {
            try? await WKWebsiteDataStore.remove(forIdentifier: identifier)
            throw error
        }
        try await removeBenchmarkStore(identifier: identifier)
    }

    @available(iOS 17, *)
    private func removeBenchmarkStore(identifier: UUID) async throws {
        for attempt in 0..<20 {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: identifier)
                return
            } catch {
                guard attempt < 19 else { throw error }
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    @available(iOS 17, *)
    private func runBenchmark(identifier: UUID, iterations: Int, warmups: Int) async throws {
        let store = WKWebsiteDataStore(forIdentifier: identifier)
        let flags = MockFeatureFlagger(enabledFeatureFlags: [])
        let keyValueStore = MockKeyValueStore()
        let fireproofing = MockFireproofing()
        fireproofing.isAllowedCookieDomainHandler = { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).hasPrefix("burn-protected-") }
        fireproofing.isAllowedFireproofDomainHandler = { $0.hasPrefix("burn-protected-") }
        let manager = WebCacheManager(cookieStorage: MigratableCookieStorage(store: keyValueStore),
                                      fireproofing: fireproofing,
                                      dataStoreIDManager: DataStoreIDManager(store: keyValueStore),
                                      dataStoreCleaner: MockDataStoreCleaner(),
                                      observationsCleaner: MockObservationsCleaner(),
                                      featureFlagger: flags,
                                      memoryCacheCleaner: MockMemoryCacheCleaner(),
                                      fireModeMemoryCacheCleaner: MockMemoryCacheCleaner())
        var samples: [[String: Any]] = []
        for fixture in [Fixture.dense, Fixture.small] {
            for pair in 0..<(warmups + iterations) {
                for enabled in pair.isMultiple(of: 2) ? [false, true] : [true, false] {
                    flags.enabledFeatureFlags = enabled ? [.singleTabBurnOptimization] : []
                    try await prepare(fixture, store: store)
                    let start = ProcessInfo.processInfo.systemUptime
                    let result = await manager.clear(dataStore: WebsiteDataStoreWrapper(wrapped: store), forDomains: fixture.visitedDomains, isFireMode: false)
                    let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
                    try result.safelyRemovableData.result.get()
                    try result.fireproofableData.result.get()
                    try result.cookies.result.get()
                    try result.observationsData.result.get()
                    try await validate(fixture, store: store)
                    let sample: [String: Any] = [
                        "workload": fixture.name, "pair": pair - warmups, "warmup": pair < warmups,
                        "enabled": enabled, "total_ms": milliseconds,
                        "cookies_ms": try duration(result.cookies),
                        "safe_data_ms": try duration(result.safelyRemovableData),
                        "fireproofable_data_ms": try duration(result.fireproofableData),
                        "cookie_count": fixture.cookies.count, "deleted_cookie_count": fixture.deletedCookieCount,
                        "validation": "passed", "debug": _isDebugAssertConfiguration(),
                        "os": ProcessInfo.processInfo.operatingSystemVersionString
                    ]
                    samples.append(sample)
                    let json = try JSONSerialization.data(withJSONObject: sample, options: [.sortedKeys])
                    print("BURN_BENCHMARK_SAMPLE \(try XCTUnwrap(String(data: json, encoding: .utf8)))")
                }
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: samples, options: [.sortedKeys]),
                                       uniformTypeIdentifier: "public.json")
        attachment.name = "single-tab-burn-benchmark.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func duration(_ action: ActionResult) throws -> Double {
        let start = try XCTUnwrap(action.measuredInterval.start)
        let end = try XCTUnwrap(action.measuredInterval.end)
        return end.timeIntervalSince(start) * 1_000
    }

    private func prepare(_ fixture: Fixture, store: WKWebsiteDataStore) async throws {
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        for domain in fixture.storageDomains {
            let page = BenchmarkPage(store: store)
            try await page.load(domain: domain)
            try await page.seed()
        }
        let cookies = fixture.cookies
        for offset in stride(from: 0, to: cookies.count, by: 32) {
            await withTaskGroup(of: Void.self) { group in
                for cookie in cookies[offset..<min(offset + 32, cookies.count)] {
                    group.addTask { await store.httpCookieStore.setCookie(cookie) }
                }
            }
        }
        let actual = await store.httpCookieStore.allCookies()
        try require(Set(actual.map(cookieSignature)) == Set(cookies.map(cookieSignature)), "Cookie fixture incomplete")
        for type in [WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeIndexedDBDatabases] {
            let records = await store.dataRecords(ofTypes: [type])
            try require(Set(records.map(\.displayName)) == Set(fixture.storageDomains), "Storage fixture incomplete: \(type)")
        }
    }

    private func validate(_ fixture: Fixture, store: WKWebsiteDataStore) async throws {
        let cookies = await store.httpCookieStore.allCookies()
        let expected = fixture.cookies.filter { !$0.domain.hasPrefix("burn-target-") }
        try require(Set(cookies.map(cookieSignature)) == Set(expected.map(cookieSignature)), "Cookie deletion or preservation failed")
        let retained = Array(fixture.storageDomains.dropFirst())
        for type in [WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeIndexedDBDatabases] {
            let records = await store.dataRecords(ofTypes: [type])
            try require(Set(records.map(\.displayName)) == Set(retained), "Storage deletion or preservation failed: \(type)")
        }
        for domain in retained {
            let page = BenchmarkPage(store: store)
            try await page.load(domain: domain)
            try require(try await page.contentsAreIntact(), "Retained storage contents changed: \(domain)")
        }
    }

    private func cookieSignature(_ cookie: HTTPCookie) -> String {
        "\(cookie.domain)|\(cookie.path)|\(cookie.name)|\(cookie.value)"
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw BenchmarkError.invalidData(message) }
    }

    private enum BenchmarkError: Error {
        case invalidData(String)
    }

    private struct Fixture {
        let name: String
        let targetDomains: Int
        let protectedDomains: Int
        let unrelatedDomains: Int
        let cookiesPerDomain: Int

        static let dense = Fixture(name: "dense", targetDomains: 20, protectedDomains: 10, unrelatedDomains: 10, cookiesPerDomain: 50)
        static let small = Fixture(name: "small", targetDomains: 1, protectedDomains: 1, unrelatedDomains: 1, cookiesPerDomain: 4)

        var storageDomains: [String] { ["burn-target-0.com", "burn-protected-0.com", "burn-unrelated-0.com"] }
        var deletedCookieCount: Int { targetDomains * cookiesPerDomain }
        var visitedDomains: [String] {
            (0..<targetDomains).map { "burn-target-\($0).com" } + (0..<protectedDomains).map { "burn-protected-\($0).com" }
        }
        var cookies: [HTTPCookie] {
            let domains = visitedDomains + (0..<unrelatedDomains).map { "burn-unrelated-\($0).com" }
            return domains.flatMap { domain in
                (0..<cookiesPerDomain).map { index in
                    HTTPCookie(properties: [.domain: domain, .path: "/", .name: "benchmark-\(index)",
                                            .value: String(repeating: "c", count: 256),
                                            .expires: Date(timeIntervalSinceNow: 86_400)])!
                }
            }
        }
    }
}

@MainActor
private final class BenchmarkPage: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private var navigation: CheckedContinuation<Void, Error>?

    init(store: WKWebsiteDataStore) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func load(domain: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigation = continuation
            webView.loadHTMLString("<html><body>Burn benchmark</body></html>", baseURL: URL(string: "https://\(domain)/")!)
        }
    }

    func seed() async throws {
        _ = try await webView.callAsyncJavaScript("""
            const value = 's'.repeat(1024);
            for (let i = 0; i < 64; i++) localStorage.setItem('benchmark-' + i, value);
            const db = await new Promise((resolve, reject) => {
                const request = indexedDB.open('burn-benchmark', 1);
                request.onupgradeneeded = () => request.result.createObjectStore('values');
                request.onsuccess = () => resolve(request.result);
                request.onerror = () => reject(request.error);
            });
            await new Promise((resolve, reject) => {
                const transaction = db.transaction('values', 'readwrite');
                for (let i = 0; i < 128; i++) transaction.objectStore('values').put(value, i);
                transaction.oncomplete = resolve;
                transaction.onerror = () => reject(transaction.error);
            });
            db.close();
            return true;
            """, arguments: [:], in: nil, contentWorld: .page)
    }

    func contentsAreIntact() async throws -> Bool {
        let result = try await webView.callAsyncJavaScript("""
            const value = 's'.repeat(1024);
            if (localStorage.length !== 64) return false;
            for (let i = 0; i < 64; i++) if (localStorage.getItem('benchmark-' + i) !== value) return false;
            const db = await new Promise((resolve, reject) => {
                const request = indexedDB.open('burn-benchmark', 1);
                request.onsuccess = () => resolve(request.result);
                request.onerror = () => reject(request.error);
            });
            const values = await new Promise((resolve, reject) => {
                const request = db.transaction('values').objectStore('values').getAll();
                request.onsuccess = () => resolve(request.result);
                request.onerror = () => reject(request.error);
            });
            db.close();
            return values.length === 128 && values.every(item => item === value);
            """, arguments: [:], in: nil, contentWorld: .page)
        return result as? Bool == true
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        self.navigation?.resume()
        self.navigation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        self.navigation?.resume(throwing: error)
        self.navigation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        self.webView(webView, didFail: navigation, withError: error)
    }
}
