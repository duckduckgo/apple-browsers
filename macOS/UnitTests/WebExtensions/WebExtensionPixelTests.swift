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
import WebExtensions
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class WebExtensionPixelTests: XCTestCase {

    func testWhenAnExtensionIsInstalledOrUninstalled_ThenThePixelNamesItsCatalogEntry() {
        XCTAssertEqual(WebExtensionPixel.installed(extensionName: "bitwarden").parameters, ["extension": "bitwarden"])
        XCTAssertEqual(WebExtensionPixel.uninstalled(extensionName: "other").parameters, ["extension": "other"])
        XCTAssertEqual(WebExtensionPixel.installError(extensionName: "lastPass", error: URLError(.badURL)).parameters,
                       ["extension": "lastPass"])
        XCTAssertEqual(WebExtensionPixel.installed(extensionName: "bitwarden").name, "m_mac_web_extension_installed")
    }

    func testBitwardenDailyActivePixel() {
        let pixel = WebExtensionPixel.bitwardenDailyActive(isDefault: true)

        XCTAssertEqual(pixel.name, "web_extension_bitwarden_dau_macos")
        XCTAssertEqual(pixel.parameters, ["is_default": "true"])
        XCTAssertEqual(pixel.namePrefix, .none)
    }

    func testDefaultPasswordManagerPixels() {
        let set = WebExtensionPixel.defaultPasswordManagerSet(extensionName: "bitwarden")
        let removed = WebExtensionPixel.defaultPasswordManagerRemoved(extensionName: "bitwarden", source: .settings)

        XCTAssertEqual(set.name, "web_extension_default_password_manager_set_macos")
        XCTAssertEqual(set.parameters, ["extension": "bitwarden"])
        XCTAssertEqual(set.namePrefix, .none)
        XCTAssertEqual(removed.name, "web_extension_default_password_manager_removed_macos")
        XCTAssertEqual(removed.parameters, ["extension": "bitwarden", "source": "settings"])
        XCTAssertEqual(removed.namePrefix, .none)
    }
}
