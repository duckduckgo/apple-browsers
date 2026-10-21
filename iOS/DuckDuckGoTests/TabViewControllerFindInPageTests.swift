//
//  TabViewControllerFindInPageTests.swift
//  DuckDuckGo
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

import WebKit
import XCTest
@_spi(Testing) import PixelKit

@testable import DuckDuckGo

@available(iOS 16.0, *)
final class TabViewControllerFindInPageTests: XCTestCase {

    func testWhenFindInPageIsRequestedThenFiresDailyUsagePixelWithoutSearchData() {
        let pixelFiring = PixelKitMock()
        let tab = TabViewController.fake(pixelFiring: pixelFiring)
        (tab.webView as? WebView)?.lastFindInPageQuery = "private search"

        tab.requestFindInPage()

        let calls = pixelFiring.actualFireCalls.filter { $0.pixel is FindInPagePixel }
        XCTAssertEqual(calls, [ExpectedFireCall(pixel: FindInPagePixel.opened, frequency: .daily)])
        XCTAssertNil(calls.first?.pixel.parameters)
        XCTAssertNil(calls.first?.pixel.standardParameters)
        XCTAssertNil(calls.first?.additionalParameters)
    }
}
