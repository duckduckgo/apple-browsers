//
//  WebExtensionPixelTests.swift
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

import PixelKit
import PrivacyConfig
import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class WebExtensionPixelTests: XCTestCase {

    private let bitwardenStoreID = "nngceckbapebfimnlniiiahkandclblb"

    func testWhenAnExtensionIsInstalledOrUninstalled_ThenThePixelNamesItsCatalogEntry() {
        let installed = WebExtensionPixel.installed(extension: .catalog(.bitwarden), extensionID: bitwardenStoreID, category: "password-manager")

        XCTAssertEqual(installed.parameters, ["extension": "bitwarden", "extension_id": bitwardenStoreID, "category": "password-manager"])
        XCTAssertEqual(WebExtensionPixel.uninstalled(extension: .other, extensionID: nil, category: nil).parameters, ["extension": "other"])
        XCTAssertEqual(WebExtensionPixel.installError(extension: .catalog(.lastPass), error: URLError(.badURL)).parameters,
                       ["extension": "lastPass"])
        XCTAssertEqual(installed.name, "m_mac_web_extension_installed")
    }

    func testExtensionManagementPixels() {
        let pixels: [(WebExtensionPixel, String)] = [
            (.enabled(extensionID: bitwardenStoreID, category: "password-manager"), "web_extension_enabled_macos"),
            (.disabled(extensionID: bitwardenStoreID, category: "password-manager"), "web_extension_disabled_macos"),
            (.detailsOpened(extensionID: bitwardenStoreID, category: "password-manager"), "web_extension_details_opened_macos"),
            (.getClicked(extensionID: bitwardenStoreID, category: "password-manager"), "web_extension_get_clicked_macos"),
            (.publisherLinkClicked(extensionID: bitwardenStoreID, category: "password-manager"), "web_extension_publisher_link_clicked_macos"),
            (.retained(extensionID: bitwardenStoreID, category: "password-manager"), "web_extension_retained_14d_macos"),
            (.churned(extensionID: bitwardenStoreID, category: "password-manager"), "web_extension_churned_14d_macos")
        ]

        for (pixel, name) in pixels {
            XCTAssertEqual(pixel.name, name)
            XCTAssertEqual(pixel.parameters, ["extension_id": bitwardenStoreID, "category": "password-manager"])
            XCTAssertEqual(pixel.namePrefix, .none)
        }
    }

    func testWhenTheCategoryIsUnknown_ThenExtensionManagementPixelsOmitIt() {
        XCTAssertEqual(WebExtensionPixel.enabled(extensionID: bitwardenStoreID, category: nil).parameters, ["extension_id": bitwardenStoreID])
    }

    func testBitwardenDailyActivePixel() {
        let pixel = WebExtensionPixel.bitwardenDailyActive(isDefault: true)

        XCTAssertEqual(pixel.name, "web_extension_bitwarden_dau_macos")
        XCTAssertEqual(pixel.parameters, ["is_default": "true"])
        XCTAssertEqual(pixel.namePrefix, .none)
    }

    func testDefaultPasswordManagerSetPixel() {
        let pixel = WebExtensionPixel.defaultPasswordManagerSet(extension: .catalog(.bitwarden))

        XCTAssertEqual(pixel.name, "web_extension_default_password_manager_set_macos")
        XCTAssertEqual(pixel.parameters, ["extension": "bitwarden"])
        XCTAssertEqual(pixel.namePrefix, .none)
    }

    func testAPICompatibilityGapsPixelsAreNamedPerCatalogExtension() {
        let names = ExtensionsCatalogSubfeature.allCases.map {
            WebExtensionPixel.apiCompatibilityGaps(extension: $0, version: "1", missingAPICount: 0, unsupportedURLCount: 0).name
        }
        let pixel = WebExtensionPixel.apiCompatibilityGaps(extension: .bitwarden, version: "2026.10.1", missingAPICount: 31, unsupportedURLCount: 2)

        XCTAssertEqual(names, ["web_extension_api_gaps_bitwarden_macos",
                               "web_extension_api_gaps_onepassword_macos",
                               "web_extension_api_gaps_lastpass_macos",
                               "web_extension_api_gaps_icloudpasswords_macos",
                               "web_extension_api_gaps_darkreader_macos"])
        XCTAssertEqual(pixel.parameters, ["extension_version": "2026.10.1", "missing_api_count": "31", "unsupported_url_count": "2"])
        XCTAssertEqual(pixel.namePrefix, .none)
    }
}
