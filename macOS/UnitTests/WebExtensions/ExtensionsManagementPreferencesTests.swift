//
//  ExtensionsManagementPreferencesTests.swift
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
@_spi(Testing) import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import WebExtensions
import WebKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class ExtensionsManagementPreferencesTests: XCTestCase {

    private let storeID = "nngceckbapebfimnlniiiahkandclblb"
    private var pixels: PixelKitMock!
    private var windowControllersManager: WindowControllersManagerMock!
    private var model: ExtensionsManagementPreferences!
    private var cancellables = Set<AnyCancellable>()

    override func setUp() {
        super.setUp()
        pixels = PixelKitMock()
        windowControllersManager = WindowControllersManagerMock()
        model = ExtensionsManagementPreferences(configurationManager: MockPrivacyConfigurationManager(),
                                                windowControllersManager: windowControllersManager,
                                                pixelFiring: pixels)
    }

    override func tearDown() {
        cancellables.removeAll()
        model = nil
        windowControllersManager = nil
        pixels = nil
        super.tearDown()
    }

    func testWhenGetIsClicked_ThenTheStorePageOpensAndTheGetPixelFires() throws {
        let item = try listing()

        model.openStorePage(for: item)

        XCTAssertEqual(windowControllersManager.showCalled?.url, item.storeURL)
        try assertSingleFire("web_extension_get_clicked_macos")
    }

    func testWhenThePublisherIsClicked_ThenThePublisherSiteOpensAndThePublisherPixelFires() throws {
        let item = try listing()

        model.openPublisherPage(for: item)

        XCTAssertEqual(windowControllersManager.showCalled?.url, item.publisherURL)
        try assertSingleFire("web_extension_publisher_link_clicked_macos")
    }

    func testWhenAListingHasNoPublisherURL_ThenClickingThePublisherDoesNothing() throws {
        model.openPublisherPage(for: try listing(publisherURL: nil))

        XCTAssertNil(windowControllersManager.showCalled)
        XCTAssertTrue(pixels.actualFireCalls.isEmpty)
    }

    func testWhenDetailsAreOpened_ThenTheDetailsPixelFires() throws {
        let record = InstalledWebExtension(uniqueIdentifier: "bitwarden", filename: "bitwarden", name: nil, version: "1",
                                           storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: storeID))
        let entry = ExtensionsManagementPreferences.InstalledExtensionEntry(record: record, listing: try listing(),
                                                                            isRemotelyDisabled: false, permissions: [], matchPatterns: [],
                                                                            hasAccessToPrivateData: nil, hasHitNativeMessagingLimitation: false)

        model.showDetails(for: entry)

        try assertSingleFire("web_extension_details_opened_macos")
    }

    func testWhenAnExtensionFirstHitsTheNativeMessagingLimit_ThenItsOpenDetailsShowTheWarning() throws {
        let manager = StubWebExtensionManager(store: StubChromeWebStore(storeID: storeID, listing: try listing()), installedExtension: bitwardenRecord())
        let settings = makeModel(webExtensionManager: manager)
        settings.showDetails(for: try XCTUnwrap(settings.installedExtensions.first))
        let warningShown = expectWarning(in: settings)
        manager.limitedIdentifiers.insert("bitwarden")

        NotificationCenter.default.post(name: .webExtensionNativeMessagingLimitationDidChange, object: nil)

        wait(for: [warningShown], timeout: 5)
        XCTAssertEqual(settings.detailsEntry?.hasHitNativeMessagingLimitation, true)
    }

    func testWhenLearnMoreIsClicked_ThenTheConfiguredPageOpensAndTheLearnMorePixelFires() throws {
        let settings = makeModel(featureSettings: ["learnMoreUrl": "https://duckduckgo.com/duckduckgo-help-pages/extensions"])

        settings.openLearnMore()

        XCTAssertEqual(windowControllersManager.showCalled?.url, URL(string: "https://duckduckgo.com/duckduckgo-help-pages/extensions"))
        try assertSingleFire("web_extension_learn_more_clicked_macos", parameters: nil)
    }

    func testWhenTheConfigurationHasNoLearnMoreURL_ThenLearnMoreOpensTheHelpPages() {
        makeModel(featureSettings: [:]).openLearnMore()

        XCTAssertEqual(windowControllersManager.showCalled?.url, URL(string: "https://duckduckgo.com/duckduckgo-help-pages"))
    }

    func testWhenTheLearnMoreURLIsNotAbsolute_ThenLearnMoreOpensTheHelpPages() {
        makeModel(featureSettings: ["learnMoreUrl": "duckduckgo-help-pages/extensions"]).openLearnMore()

        XCTAssertEqual(windowControllersManager.showCalled?.url, URL(string: "https://duckduckgo.com/duckduckgo-help-pages"))
    }

    func testWhenRemoteDisableLearnMoreIsClicked_ThenTheConfiguredPageOpensAndItsPixelFires() throws {
        let settings = makeModel(featureSettings: ["learnMoreUrlRemoteDisable": "https://duckduckgo.com/duckduckgo-help-pages/extensions/disabled"])

        settings.openRemoteDisableLearnMore()

        XCTAssertEqual(windowControllersManager.showCalled?.url, URL(string: "https://duckduckgo.com/duckduckgo-help-pages/extensions/disabled"))
        try assertSingleFire("web_extension_learn_more_remote_disable_clicked_macos", parameters: nil)
    }

    func testWhenTheConfigurationHasNoRemoteDisableLearnMoreURL_ThenItOpensTheHelpPages() {
        makeModel(featureSettings: ["learnMoreUrl": "https://duckduckgo.com/duckduckgo-help-pages/extensions"]).openRemoteDisableLearnMore()

        XCTAssertEqual(windowControllersManager.showCalled?.url, URL(string: "https://duckduckgo.com/duckduckgo-help-pages"))
    }

    // MARK: - Helpers

    private func makeModel(featureSettings: [String: Any]) -> ExtensionsManagementPreferences {
        let configuration = MockPrivacyConfiguration()
        configuration.featureSettings = featureSettings
        return ExtensionsManagementPreferences(configurationManager: MockPrivacyConfigurationManager(privacyConfig: configuration),
                                               windowControllersManager: windowControllersManager,
                                               pixelFiring: pixels)
    }

    private func makeModel(webExtensionManager: WebExtensionManaging) -> ExtensionsManagementPreferences {
        ExtensionsManagementPreferences(configurationManager: MockPrivacyConfigurationManager(),
                                        webExtensionManager: webExtensionManager,
                                        windowControllersManager: windowControllersManager,
                                        pixelFiring: pixels)
    }

    private func bitwardenRecord() -> InstalledWebExtension {
        InstalledWebExtension(uniqueIdentifier: "bitwarden", filename: "bitwarden", name: nil, version: "1",
                              storeIdentity: WebExtensionStoreIdentity(store: .chromeWebStore, id: storeID))
    }

    private func expectWarning(in model: ExtensionsManagementPreferences) -> XCTestExpectation {
        let expectation = expectation(description: "Details show the native messaging warning")
        model.$installedExtensions
            .filter { $0.first?.hasHitNativeMessagingLimitation == true }
            .first()
            .sink { _ in expectation.fulfill() }
            .store(in: &cancellables)
        return expectation
    }

    private func listing(publisherURL: String? = "https://bitwarden.com") throws -> ChromeWebStoreListing {
        var settings: [String: String] = [
            "id": storeID,
            "name": "Bitwarden",
            "publisher": "Bitwarden Inc.",
            "cwsUri": "https://chromewebstore.google.com/detail/\(self.storeID)"
        ]
        settings["publisherUri"] = publisherURL
        let configuration = MockPrivacyConfiguration()
        configuration.subfeatureSettings = String(data: try JSONEncoder().encode(settings), encoding: .utf8)
        let catalog = ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: configuration),
                                            isExtensionsEnabled: { true })
        return try XCTUnwrap(catalog.listing(of: .bitwarden))
    }

    private func assertSingleFire(_ name: String, parameters: [String: String]? = ["extension": "bitwarden"],
                                  file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(pixels.actualFireCalls.count, 1, file: file, line: line)
        let call = try XCTUnwrap(pixels.actualFireCalls.first, file: file, line: line)
        XCTAssertEqual(call.pixel.name, name, file: file, line: line)
        XCTAssertEqual(call.pixel.parameters, parameters, file: file, line: line)
        XCTAssertEqual(call.frequency, .dailyAndCount, file: file, line: line)
    }
}

@available(macOS 15.4, *)
private final class StubChromeWebStore: ChromeWebStoreManaging {
    let catalogExtensionIDs: [String]
    private let storeListing: ChromeWebStoreListing

    init(storeID: String, listing: ChromeWebStoreListing) {
        storeListing = listing
        catalogExtensionIDs = [storeID]
    }

    func status(for identifier: String) -> ChromeWebStoreStatus { .installed }
    func install(identifier: String, downloadURL: URL) async -> Bool { false }
    func remove(identifier: String) async -> Bool { false }
    func checkForUpdatesNow() async {}
    func catalogEntry(of identifier: String) -> ExtensionsCatalogSubfeature? { catalogExtensionIDs.contains(identifier) ? storeListing.entry : nil }
    func listing(of subfeature: ExtensionsCatalogSubfeature) -> ChromeWebStoreListing? { subfeature == storeListing.entry ? storeListing : nil }
}

/// Lists one installed extension and reports the native messaging limitation for `limitedIdentifiers`.
@available(macOS 15.4, *)
private final class StubWebExtensionManager: WebExtensionManaging {
    let chromeWebStore: ChromeWebStoreManaging?
    let installedRecord: InstalledWebExtension
    var limitedIdentifiers: Set<String> = []
    let cpmMessagingHealthMonitor: CPMMessagingHealthMonitoring = NoOpCPMMessagingHealthMonitor()
    let badgeColors = WebExtensionBadgeColorStore()
    let eventsListener: WebExtensionEventsListening = WebExtensionEventsListener()
    let extensionsDirectory = FileManager.default.temporaryDirectory
    let loadedExtensions: Set<WKWebExtensionContext> = []
    var webExtensionIdentifiers: [String] { [installedRecord.uniqueIdentifier] }
    let extensionUpdates = AsyncStream<Void>.makeStream().stream
    let lifecycleEvents = AsyncStream<WebExtensionLifecycleEvent>.makeStream().stream

    init(store: ChromeWebStoreManaging, installedExtension: InstalledWebExtension) {
        chromeWebStore = store
        installedRecord = installedExtension
    }

    func attachExtensions(to configuration: WKWebViewConfiguration) {}
    func loadInstalledExtensions() async {}
    func reloadInstalledExtensions() async {}
    func installExtension(from sourceURL: URL) async throws {}
    func installExtension(from sourceURL: URL, storeIdentity: WebExtensionStoreIdentity?, replacing oldIdentifier: String?) async throws {}
    func uninstallExtension(identifier: String) throws {}
    func uninstallAllExtensions() -> [Result<Void, Error>] { [] }
    func syncEmbeddedExtensions(enabledTypes: Set<DuckDuckGoWebExtensionType>) async {}
    func uninstallEmbeddedExtension(type: DuckDuckGoWebExtensionType) {}
    func installedEmbeddedExtension(for type: DuckDuckGoWebExtensionType) -> InstalledWebExtension? { nil }
    func installedExtensionPath(for type: DuckDuckGoWebExtensionType) -> URL? { nil }
    func unloadAllExtensions() {}
    func reloadExtension(identifier: String) async throws {}
    func disableExtension(identifier: String) async throws {}
    func enableExtension(identifier: String) async throws {}
    func installedExtension(identifier: String) -> InstalledWebExtension? { identifier == installedRecord.uniqueIdentifier ? installedRecord : nil }
    func isRemotelyDisabled(identifier: String) -> Bool { false }
    func extensionName(for identifier: String) -> String? { nil }
    func extensionVersion(for identifier: String) -> String? { nil }
    func extensionPermissions(for identifier: String) -> [String] { [] }
    func extensionMatchPatterns(for identifier: String) -> [String] { [] }
    func hasAccessToPrivateData(for identifier: String) -> Bool? { nil }
    @MainActor func hasHitNativeMessagingLimitation(identifier: String) -> Bool { limitedIdentifiers.contains(identifier) }
    @MainActor func isNativeMessagingAlertSuppressed(identifier: String) -> Bool { false }
    @MainActor func suppressNativeMessagingAlert(identifier: String) {}
    @MainActor func pixelExtension(identifier: String) -> WebExtensionPixelExtension { .other }
    func setHasAccessToPrivateData(_ allowed: Bool, for identifier: String) throws {}
    func extensionContext(for url: URL) -> WKWebExtensionContext? { nil }
    func context(for identifier: String) -> WKWebExtensionContext? { nil }
    func clearCachedScriptlets() {}
    func scriptletDebugInfo() -> [ScriptletDebugInfo] { [] }
}
