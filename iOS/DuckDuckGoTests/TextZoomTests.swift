//
//  TextZoomTests.swift
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
@testable import DuckDuckGo
import BrowserServicesKit
import Core
import Persistence
import XCTest
import WebKit

final class TextZoomTests: XCTestCase {

    let viewScaleKey = "viewScale"

    func testZoomLevelAppliedToWebView() {
        let storage = SpyTextZoomStorage()

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        let webView = URLFixedWebView(frame: .zero, configuration: .nonPersistent())

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onNavigationCommitted(applyToWebView: webView)
        XCTAssertEqual(1.0, webView.value(forKey: viewScaleKey) as? Double)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onTextZoomChange(applyToWebView: webView)
        XCTAssertEqual(1.0, webView.value(forKey: viewScaleKey) as? Double)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onWebViewCreated(applyToWebView: webView)
        XCTAssertEqual(1.0, webView.value(forKey: viewScaleKey) as? Double)

        let host = "example.com"
        webView.fixed = URL(string: "https://\(host)")
        coordinator.set(textZoomLevel: .percent120, forHost: host)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onNavigationCommitted(applyToWebView: webView)
        XCTAssertEqual(1.2, webView.value(forKey: viewScaleKey) as? Double)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onTextZoomChange(applyToWebView: webView)
        XCTAssertEqual(1.2, webView.value(forKey: viewScaleKey) as? Double)

        webView.setValue(0.1, forKey: viewScaleKey)
        coordinator.onWebViewCreated(applyToWebView: webView)
        XCTAssertEqual(1.2, webView.value(forKey: viewScaleKey) as? Double)

        // When reset to default, coordinator should remove the domain from storage (spy records remove)
        coordinator.set(textZoomLevel: .percent100, forHost: host)
        XCTAssertEqual(storage.removeCalls, ["example.com"])
    }

    func testMenuItemCreation() {
        let host = "example.com"
        let storage = SpyTextZoomStorage()

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        coordinator.set(textZoomLevel: .percent120, forHost: host)

        let controller = UIViewController()
        let webView = WKWebView(frame: .zero, configuration: .nonPersistent())

        let item1 = coordinator.makeBrowsingMenuEntry(
            forLink: makeLink(url: URL(string: "https://other.org")!),
            inController: controller,
            forWebView: webView,
            useSmallIcon: true,
            percentageInDetail: false)

        // Expecting the 'default' value
        if case .regular(let name, _, _, _, _, _, _, _) = item1 {
            XCTAssertEqual(UserText.textZoomMenuItem, name)
        } else {
            XCTFail("Unexpected menu item type")
        }

        let item2 = coordinator.makeBrowsingMenuEntry(
            forLink: makeLink(url: URL(string: "https://\(host)")!),
            inController: controller,
            forWebView: webView,
            useSmallIcon: true,
            percentageInDetail: false)

        // Expecting the menu item to include the percent
        if case .regular(let name, _, _, _, _, _, _, _) = item2 {
            XCTAssertEqual(UserText.textZoomWithPercentForMenuItem(120), name)
        } else {
            XCTFail("Unexpected menu item type")
        }

    }

    func testSettingAndResetingDomainTextZoomLevels() {
        let host1 = "example.com"
        let host2 = "another.org"
        let storage = SpyTextZoomStorage()

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        coordinator.set(textZoomLevel: .percent120, forHost: host1)
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host1), .percent120)

        coordinator.set(textZoomLevel: .percent140, forHost: host2)
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host2), .percent140)

        coordinator.resetTextZoomLevels(excludingDomains: [host1])
        XCTAssertEqual(storage.resetExcludingDomainsCalls, [[host1]])
        // Simulate storage having cleared host2 only; coordinator then returns default for host2, stored value for host1
        storage.stubbedLevels.removeValue(forKey: host2)
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host1), .percent120)
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host2), AppSettingsMock().defaultTextZoomLevel)
    }

    func testResetTextZoomLevelsForVisitedDomains_ClearsSpecifiedDomains() {
        let host1 = "example.com"
        let host2 = "another.org"
        let storage = SpyTextZoomStorage()

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        coordinator.set(textZoomLevel: .percent120, forHost: host1)
        coordinator.set(textZoomLevel: .percent140, forHost: host2)

        coordinator.resetTextZoomLevels(forVisitedDomains: [host1], excludingDomains: [])
        XCTAssertEqual(storage.resetForVisitedDomainsCalls.count, 1)
        XCTAssertEqual(storage.resetForVisitedDomainsCalls[0].visited, [host1])
        XCTAssertEqual(storage.resetForVisitedDomainsCalls[0].excluding, [])
        // Simulate storage having cleared host1 only
        storage.stubbedLevels.removeValue(forKey: host1)

        XCTAssertEqual(coordinator.textZoomLevel(forHost: host1), AppSettingsMock().defaultTextZoomLevel)
        XCTAssertEqual(coordinator.textZoomLevel(forHost: host2), .percent140)
    }

    func testResetTextZoomLevelsForVisitedDomains_SubdomainClearsETLDplus1() {
        let storage = SpyTextZoomStorage()

        let coordinator: TextZoomCoordinating = makeTextZoomCoordinator(storage: storage)
        coordinator.set(textZoomLevel: .percent120, forHost: "example.com")

        coordinator.resetTextZoomLevels(forVisitedDomains: ["www.example.com"], excludingDomains: [])
        XCTAssertEqual(storage.resetForVisitedDomainsCalls.last?.visited, ["www.example.com"])
        // Simulate storage having cleared example.com (eTLD+1 of www.example.com)
        storage.stubbedLevels.removeValue(forKey: "example.com")

        XCTAssertEqual(coordinator.textZoomLevel(forHost: "example.com"), AppSettingsMock().defaultTextZoomLevel)
    }

    private func makeTextZoomCoordinator(appSettings: AppSettings = AppSettingsMock(),
                                         storage: TextZoomStoring) -> TextZoomCoordinating {
        return TextZoomCoordinator(appSettings: appSettings,
                                   storage: storage)
    }

    private func makeLink(title: String? = "title", url: URL = .ddg, localPath: URL? = nil) -> Link {
        return Link(title: title, url: url, localPath: localPath)
    }

    func testWhenUsingDifferentStorageKeys_ThenStoragesAreIsolated() {
        let normalStorage = TextZoomStorage(storageKey: TextZoomContext.normal.storageKey)
        let fireStorage = TextZoomStorage(storageKey: TextZoomContext.fireMode.storageKey)
        normalStorage.clearAll()
        fireStorage.clearAll()

        let appSettings = AppSettingsMock()
        let normalCoordinator = TextZoomCoordinator(appSettings: appSettings, storage: normalStorage)
        let fireCoordinator = TextZoomCoordinator(appSettings: appSettings, storage: fireStorage)

        normalCoordinator.set(textZoomLevel: .percent120, forHost: "example.com")
        fireCoordinator.set(textZoomLevel: .percent140, forHost: "example.com")

        XCTAssertEqual(normalCoordinator.textZoomLevel(forHost: "example.com"), .percent120)
        XCTAssertEqual(fireCoordinator.textZoomLevel(forHost: "example.com"), .percent140)

        fireStorage.clearAll()
        XCTAssertEqual(normalCoordinator.textZoomLevel(forHost: "example.com"), .percent120)
        XCTAssertEqual(fireCoordinator.textZoomLevel(forHost: "example.com"), appSettings.defaultTextZoomLevel)
    }

}

// MARK: - SpyTextZoomStorage

/// Spy with no storage logic: records calls and returns/updates only stubbedLevels for get/set/remove.
private final class SpyTextZoomStorage: TextZoomStoring {

    /// Return value for textZoomLevelForDomain. Updated by set (add) and remove (remove) only.
    var stubbedLevels: [String: TextZoomLevel] = [:]

    private(set) var setCalls: [(TextZoomLevel, String)] = []
    private(set) var removeCalls: [String] = []
    private(set) var resetExcludingDomainsCalls: [[String]] = []
    private(set) var resetForVisitedDomainsCalls: [(visited: [String], excluding: [String])] = []
    private(set) var clearAllCallCount = 0

    func textZoomLevelForDomain(_ domain: String) -> TextZoomLevel? {
        stubbedLevels[domain]
    }

    func set(textZoomLevel: TextZoomLevel, forDomain domain: String) {
        setCalls.append((textZoomLevel, domain))
        stubbedLevels[domain] = textZoomLevel
    }

    func removeTextZoomLevel(forDomain domain: String) {
        removeCalls.append(domain)
        stubbedLevels.removeValue(forKey: domain)
    }

    func resetTextZoomLevels(excludingDomains: [String]) {
        resetExcludingDomainsCalls.append(excludingDomains)
    }

    func resetTextZoomLevels(forVisitedDomains visitedDomains: [String], excludingDomains: [String]) {
        resetForVisitedDomainsCalls.append((visitedDomains, excludingDomains))
    }

    func clearAll() {
        clearAllCallCount += 1
    }
}

// MARK: - TextZoomStorageTests

final class TextZoomStorageTests: XCTestCase {

    private func makeStorage() -> TextZoomStorage {
        TextZoomStorage(store: InMemoryKeyValueStore(), storageKey: TextZoomContext.normal.storageKey)
    }

    func testSetAndGetTextZoomLevel() {
        let storage = makeStorage()
        XCTAssertNil(storage.textZoomLevelForDomain("example.com"))
        storage.set(textZoomLevel: .percent120, forDomain: "example.com")
        XCTAssertEqual(storage.textZoomLevelForDomain("example.com"), .percent120)
        storage.set(textZoomLevel: .percent140, forDomain: "example.com")
        XCTAssertEqual(storage.textZoomLevelForDomain("example.com"), .percent140)
    }

    func testRemoveTextZoomLevel() {
        let storage = makeStorage()
        storage.set(textZoomLevel: .percent120, forDomain: "example.com")
        storage.removeTextZoomLevel(forDomain: "example.com")
        XCTAssertNil(storage.textZoomLevelForDomain("example.com"))
    }

    func testResetTextZoomLevelsExcludingDomains() {
        let storage = makeStorage()
        storage.set(textZoomLevel: .percent120, forDomain: "example.com")
        storage.set(textZoomLevel: .percent140, forDomain: "another.org")
        storage.resetTextZoomLevels(excludingDomains: ["example.com"])
        XCTAssertEqual(storage.textZoomLevelForDomain("example.com"), .percent120)
        XCTAssertNil(storage.textZoomLevelForDomain("another.org"))
    }

    func testResetTextZoomLevelsForVisitedDomains_ClearsVisitedNotExcluded() {
        let storage = makeStorage()
        storage.set(textZoomLevel: .percent120, forDomain: "example.com")
        storage.set(textZoomLevel: .percent140, forDomain: "another.org")
        storage.resetTextZoomLevels(forVisitedDomains: ["example.com"], excludingDomains: [])
        XCTAssertNil(storage.textZoomLevelForDomain("example.com"))
        XCTAssertEqual(storage.textZoomLevelForDomain("another.org"), .percent140)
    }

    func testResetTextZoomLevelsForVisitedDomains_WhenSubdomainVisitedAndRootExcluded_ThenNotCleared() {
        let storage = makeStorage()
        storage.set(textZoomLevel: .percent120, forDomain: "amazon.com")
        storage.resetTextZoomLevels(forVisitedDomains: ["mail.amazon.com"], excludingDomains: ["amazon.com"])
        XCTAssertEqual(storage.textZoomLevelForDomain("amazon.com"), .percent120)
    }

    func testClearAll() {
        let storage = makeStorage()
        storage.set(textZoomLevel: .percent120, forDomain: "example.com")
        storage.clearAll()
        XCTAssertNil(storage.textZoomLevelForDomain("example.com"))
    }
}

// MARK: - InMemoryKeyValueStore

private final class InMemoryKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]

    func object(forKey defaultName: String) -> Any? {
        storage[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        storage[defaultName] = value
    }

    func removeObject(forKey defaultName: String) {
        storage.removeValue(forKey: defaultName)
    }
}

private class URLFixedWebView: WKWebView {

    var fixed: URL?

    override var url: URL? {
        fixed
    }

}
