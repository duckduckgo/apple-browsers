//
//  WebExtensionIdentifierTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
@testable import WebExtensions

@available(macOS 15.4, *)
final class WebExtensionIdentifierTests: XCTestCase {

    // MARK: - Default Path Tests

    func testThatBitwardenDefaultPath_ReturnsExpectedPath() {
        let expectedPath = "file:///Applications/Bitwarden.app/Contents/PlugIns/safari.appex"

        XCTAssertEqual(WebExtensionIdentifier.bitwarden.defaultPath, expectedPath)
    }

    // MARK: - Raw Value Tests

    func testThatBitwardenRawValue_IsBitwarden() {
        XCTAssertEqual(WebExtensionIdentifier.bitwarden.rawValue, "bitwarden")
    }

    // MARK: - Bundle Identification Tests

    func testWhenBundleHasNoBundleId_ThenIdentifierIsNil() {
        let bundle = MockBundle(bundleIdentifier: nil)

        let identifier = WebExtensionIdentifier.identify(bundle: bundle)

        XCTAssertNil(identifier)
    }

    func testWhenBundleIsBitwarden_ThenIdentifierIsBitwarden() {
        let bundle = MockBundle(bundleIdentifier: "com.bitwarden.desktop.safari")

        let identifier = WebExtensionIdentifier.identify(bundle: bundle)

        XCTAssertEqual(identifier, .bitwarden)
    }

    func testWhenBundleIsUnknown_ThenIdentifierIsNil() {
        let bundle = MockBundle(bundleIdentifier: "com.unknown.extension")

        let identifier = WebExtensionIdentifier.identify(bundle: bundle)

        XCTAssertNil(identifier)
    }
}

// MARK: - Mock Bundle

private class MockBundle: Bundle {
    private let mockBundleIdentifier: String?

    init(bundleIdentifier: String?) {
        self.mockBundleIdentifier = bundleIdentifier
        super.init()
    }

    override var bundleIdentifier: String? {
        mockBundleIdentifier
    }
}
