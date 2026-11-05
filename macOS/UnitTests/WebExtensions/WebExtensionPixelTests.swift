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

    func testWhenAnExtensionIsInstalledOrUninstalled_ThenThePixelNamesItsCatalogEntry() {
        XCTAssertEqual(WebExtensionPixel.installed(extension: .catalog(.bitwarden)).parameters, ["extension": "bitwarden"])
        XCTAssertEqual(WebExtensionPixel.uninstalled(extension: .other).parameters, ["extension": "other"])
        XCTAssertEqual(WebExtensionPixel.installError(extension: .catalog(.lastPass), error: URLError(.badURL)).parameters,
                       ["extension": "lastPass"])
        XCTAssertEqual(WebExtensionPixel.installed(extension: .catalog(.bitwarden)).name, "m_mac_web_extension_installed")
    }

    func testExtensionManagementPixels() {
        let pixels: [(WebExtensionPixel, String)] = [
            (.enabled(extension: .catalog(.bitwarden)), "web_extension_enabled_macos"),
            (.disabled(extension: .catalog(.bitwarden)), "web_extension_disabled_macos"),
            (.remotelyDisabled(extension: .catalog(.bitwarden)), "web_extension_remotely_disabled_macos"),
            (.retained14Days(extension: .catalog(.bitwarden)), "web_extension_retained_14d_macos"),
            (.churned14Days(extension: .catalog(.bitwarden)), "web_extension_churned_14d_macos"),
            (.getClicked(extension: .catalog(.bitwarden)), "web_extension_get_clicked_macos"),
            (.detailsOpened(extension: .catalog(.bitwarden)), "web_extension_details_opened_macos"),
            (.publisherLinkClicked(extension: .catalog(.bitwarden)), "web_extension_publisher_link_clicked_macos"),
            (.toolbarClicked(extension: .catalog(.bitwarden)), "web_extension_toolbar_clicked_macos")
        ]

        for (pixel, name) in pixels {
            XCTAssertEqual(pixel.name, name)
            XCTAssertEqual(pixel.parameters, ["extension": "bitwarden"])
            XCTAssertEqual(pixel.namePrefix, .none)
        }
    }

    func testInstalledCountPixelSendsWindowsBuckets() {
        let pixel = WebExtensionPixel.installedCount(installed: 5, enabled: 3)

        XCTAssertEqual(pixel.name, "web_extension_installed_count_macos")
        XCTAssertEqual(pixel.parameters, ["count": "4", "enabled_count": "2"])
        XCTAssertEqual(pixel.namePrefix, .none)
        XCTAssertEqual([0, 1, 2, 3, 4, 5, 6, 40].map(WebExtensionPixel.countBucket), ["0", "1", "2", "2", "4", "4", "6", "6"])
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
