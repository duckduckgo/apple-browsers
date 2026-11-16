//
//  WebExtensionsDebugMenuTests.swift
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

import AppKit
import EventHub
import FeatureFlags_macOS
@_spi(Testing) import Persistence
import PrivacyConfig
import SharedTestUtilities
import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class WebExtensionsDebugMenuTests: XCTestCase {
    private func menu(store: ChromeWebStoreManaging?) -> WebExtensionsDebugMenu {
        let flags = MockFeatureFlagger(featuresStub: [FeatureFlag.webExtensionUpdateDiscovery.rawValue: false])
        let manager = WebExtensionManagerFactory.makeManager(keyValueStore: InMemoryThrowingKeyValueStore(),
                                                             privacyConfigurationManager: MockPrivacyConfigurationManaging(),
                                                             autoconsentPreferences: Preferences(),
                                                             themeManager: ThemeManager(appearancePreferences: .mock),
                                                             featureFlagger: flags,
                                                             eventHub: RecordingEventHub())
        manager.chromeWebStore = store
        return WebExtensionsDebugMenu(webExtensionManager: manager,
                                      cpmMessagingHealthMonitor: CPMMessagingHealthMonitor(pixelFiring: NoOpWebExtensionPixelFiring(), isUnmeasuredPage: { _ in false }))
    }

    private func checkItem(in menu: NSMenu) throws -> NSMenuItem {
        try XCTUnwrap(menu.item(withTitle: "Check for Updates…"))
    }

    private func invoke(_ item: NSMenuItem) throws {
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item))
    }

    func testCheckForUpdatesOpensTheWindowWithoutStartingACheck() async throws {
        let store = Store()
        let menu = menu(store: store)
        let existingWindow = MockWindow(isVisible: false)
        existingWindow.identifier = WebExtensionUpdateVersionsWindowPresenter.identifier
        defer { existingWindow.close() }
        let registeredWindow = try XCTUnwrap(NSApp.windows.first { $0 === existingWindow })
        XCTAssertTrue(registeredWindow === existingWindow)
        let checked = expectation(description: "Opening the window does not start a check")
        checked.isInverted = true
        store.onCheck = { checked.fulfill() }
        for enabled in [false, true] {
            store.canCheckForUpdates = enabled
            menu.update()
            XCTAssertNil(menu.item(withTitle: "Check for Extension Updates Now"))
            let item = try checkItem(in: menu)
            XCTAssertTrue(item.isEnabled)
            XCTAssertTrue(menu.validateMenuItem(item))
            try invoke(item)
            let window = try XCTUnwrap(NSApp.windows.first {
                $0.identifier == WebExtensionUpdateVersionsWindowPresenter.identifier
            })
            XCTAssertTrue(window === existingWindow)
        }
        await fulfillment(of: [checked], timeout: 0.1)
        XCTAssertEqual(store.checkCount, 0)
    }

    private struct Preferences: AutoconsentPreferencesProviding {
        var cookiePopupPreference: CookiePopupPreference { .off }
    }

    private final class Store: ChromeWebStoreManaging {
        var canCheckForUpdates = false
        var catalogExtensionIDs: [String] = []
        var learnMoreURL: URL?
        var checkCount = 0
        var onCheck: (() -> Void)?

        func status(for identifier: String) -> ChromeWebStoreStatus { .unknown }
        func install(identifier: String, downloadURL: URL) async -> Bool { false }
        func remove(identifier: String) async -> Bool { false }
        func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing? { nil }
        func checkForUpdatesNow() async {
            checkCount += 1
            onCheck?()
        }
    }
}
