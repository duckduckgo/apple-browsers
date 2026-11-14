//
//  DefaultBrowserWinBackPixelTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DefaultBrowserWinBackPixelTests: XCTestCase {

    func testPixelsAreSentWithoutPrefixAndWithExpectedParameters() {
        let pixels: [(DefaultBrowserWinBackPixel, String, [String: String]?)] = [
            (.shown(type: .setAsDefaultPrompt), "default-browser-win-back_shown_macos", ["contentType": "set-as-default"]),
            (.confirmButtonClicked(type: .bothDefaultBrowserAndDockPrompt), "default-browser-win-back_confirm-action_macos",
             ["contentType": "set-as-default-and-add-to-dock"]),
            (.dismissed(type: .setAsDefaultPrompt), "default-browser-win-back_cancel-action_macos", ["contentType": "set-as-default"]),
            (.defaultSetWithoutPromoAction, "default-browser-win-back_default-set-without-promo-action_macos", nil)
        ]
        for (pixel, name, parameters) in pixels {
            XCTAssertEqual(pixel.name, name)
            XCTAssertEqual(pixel.namePrefix, PixelKitNamePrefix.none)
            XCTAssertEqual(pixel.parameters, parameters)
        }
    }
}
