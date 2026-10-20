//
//  WebExtensionPixelExtensionTests.swift
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
@testable import WebExtensions

final class WebExtensionPixelExtensionTests: XCTestCase {

    /// Pinned to the `web_extension` enum in macOS `params_dictionary.json5`, so a new
    /// catalog entry can't ship without its value in the definition, which would reject the pixel.
    func testParameterValuesMatchThePixelDefinition() {
        XCTAssertEqual(WebExtensionPixelExtension.allCases.map(\.parameterValue),
                       ["bitwarden", "onePassword", "lastPass", "other"])
    }

    func testOnlyAChromeFormatVersionIsSent() {
        XCTAssertEqual(WebExtensionPixelExtension.version("2026.10.1"), "2026.10.1")
        XCTAssertEqual(WebExtensionPixelExtension.version("1.2.3.4"), "1.2.3.4")
        XCTAssertEqual(WebExtensionPixelExtension.version("1.2.3.4.5"), "other")
        XCTAssertEqual(WebExtensionPixelExtension.version("1.0 beta"), "other")
        XCTAssertEqual(WebExtensionPixelExtension.version(""), "other")
        XCTAssertEqual(WebExtensionPixelExtension.version(nil), "other")
    }
}
