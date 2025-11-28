//
//  UserChurnPixelTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

final class UserChurnPixelTests: XCTestCase {

    // MARK: - Tests: Browser detection from bundle identifier

    func testWhenBundleIdIsChrome_ThenNewDefaultIsChrome() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: "com.google.Chrome", atb: nil)

        // Then
        XCTAssertEqual(pixel.parameters?["newDefault"], "Chrome")
    }

    func testWhenBundleIdIsSafari_ThenNewDefaultIsSafari() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: "com.apple.Safari", atb: nil)

        // Then
        XCTAssertEqual(pixel.parameters?["newDefault"], "Safari")
    }

    func testWhenBundleIdIsFirefox_ThenNewDefaultIsFirefox() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: "org.mozilla.firefox", atb: nil)

        // Then
        XCTAssertEqual(pixel.parameters?["newDefault"], "Firefox")
    }

    func testWhenBundleIdIsBrave_ThenNewDefaultIsBrave() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: "com.brave.Browser", atb: nil)

        // Then
        XCTAssertEqual(pixel.parameters?["newDefault"], "Brave")
    }

    func testWhenBundleIdIsUnknownBrowser_ThenNewDefaultIsOther() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: "com.example.SomeBrowser", atb: nil)

        // Then
        XCTAssertEqual(pixel.parameters?["newDefault"], "Other")
    }

    func testWhenBundleIdIsNil_ThenNewDefaultIsOther() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: nil, atb: nil)

        // Then
        XCTAssertEqual(pixel.parameters?["newDefault"], "Other")
    }

    // MARK: - Tests: ATB parameter handling

    func testWhenAtbIsProvided_ThenParametersIncludeAtb() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: "com.apple.Safari", atb: "v123-4")

        // Then
        XCTAssertEqual(pixel.parameters?["atb"], "v123-4")
    }

    func testWhenAtbIsNil_ThenParametersDoNotIncludeAtb() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: "com.apple.Safari", atb: nil)

        // Then
        XCTAssertNil(pixel.parameters?["atb"])
    }

    func testWhenAtbIsProvided_ThenParametersContainBothNewDefaultAndAtb() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: "org.mozilla.firefox", atb: "v456-7ab")

        // Then
        XCTAssertEqual(pixel.parameters?.count, 2)
        XCTAssertEqual(pixel.parameters?["newDefault"], "Firefox")
        XCTAssertEqual(pixel.parameters?["atb"], "v456-7ab")
    }

    func testWhenAtbIsNil_ThenParametersContainOnlyNewDefault() {
        // Given
        let pixel = UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: "org.mozilla.firefox", atb: nil)

        // Then
        XCTAssertEqual(pixel.parameters?.count, 1)
        XCTAssertEqual(pixel.parameters?["newDefault"], "Firefox")
    }
}
