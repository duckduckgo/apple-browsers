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

@_spi(Testing) import PixelKit
import PrivacyConfig
import PrivacyConfigTestsUtils
import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@available(macOS 15.4, *)
@MainActor
final class ExtensionsManagementPreferencesTests: XCTestCase {

    private let storeID = "nngceckbapebfimnlniiiahkandclblb"
    private var pixels: PixelKitMock!
    private var windowControllersManager: WindowControllersManagerMock!
    private var model: ExtensionsManagementPreferences!

    override func setUp() {
        super.setUp()
        pixels = PixelKitMock()
        windowControllersManager = WindowControllersManagerMock()
        model = ExtensionsManagementPreferences(configurationManager: MockPrivacyConfigurationManager(),
                                                windowControllersManager: windowControllersManager,
                                                pixelFiring: pixels)
    }

    override func tearDown() {
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
                                                                            isRemotelyDisabled: false, permissions: [])

        model.showDetails(for: entry)

        try assertSingleFire("web_extension_details_opened_macos")
    }

    // MARK: - Helpers

    /// Built by the real catalog from a Bitwarden catalog entry, as the app does.
    private func listing(publisherURL: String? = "https://bitwarden.com") throws -> ChromeWebStoreListing {
        var settings: [String: String] = [
            "id": storeID,
            "name": "Bitwarden",
            "publisher": "Bitwarden Inc.",
            "categoryId": "password-manager",
            "cwsUri": "https://chromewebstore.google.com/detail/\(self.storeID)"
        ]
        settings["publisherUri"] = publisherURL
        let configuration = MockPrivacyConfiguration()
        configuration.subfeatureSettings = String(data: try JSONEncoder().encode(settings), encoding: .utf8)
        let catalog = ChromeWebStoreCatalog(configurationManager: MockPrivacyConfigurationManager(privacyConfig: configuration))
        return try XCTUnwrap(catalog.listing(of: .bitwarden))
    }

    private func assertSingleFire(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(pixels.actualFireCalls.count, 1, file: file, line: line)
        let call = try XCTUnwrap(pixels.actualFireCalls.first, file: file, line: line)
        XCTAssertEqual(call.pixel.name, name, file: file, line: line)
        XCTAssertEqual(call.pixel.parameters, ["extension_id": storeID, "category": "password-manager"], file: file, line: line)
        XCTAssertEqual(call.frequency, .dailyAndCount, file: file, line: line)
    }
}
