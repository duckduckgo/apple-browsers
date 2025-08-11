//
//  NewTabPagePreloaderTests.swift
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
import CoreGraphics
@testable import DuckDuckGo_Privacy_Browser

@MainActor
class NewTabPageTabPreloaderTests: XCTestCase {

    func test_initialLoad_withNilProvider_usesDefaultSize() {
        let preloader = NewTabPageTabPreloader(viewSizeProvider: { nil })
        guard let tab = preloader.newTab() else {
            XCTFail("newTab should not return nil")
            return
        }
        XCTAssertEqual(tab.webViewSize, CGSize(width: 1024, height: 768))
    }

    func test_initialLoad_withCustomSizeProvider_usesProvidedSize() {
        let expectedSize = CGSize(width: 320, height: 480)
        let preloader = NewTabPageTabPreloader(viewSizeProvider: { expectedSize })
        guard let tab = preloader.newTab() else {
            XCTFail("newTab should not return nil")
            return
        }
        XCTAssertEqual(tab.webViewSize, expectedSize)
    }

    func test_newTab_deferredReload_generatesDistinctTabs() {
        let expectedSize = CGSize(width: 100, height: 200)
        let preloader = NewTabPageTabPreloader(viewSizeProvider: { expectedSize })
        guard let first = preloader.newTab() else {
            XCTFail("newTab should not return nil")
            return
        }
        guard let second = preloader.newTab() else {
            XCTFail("newTab should not return nil")
            return
        }
        XCTAssertNotEqual(first, second)
    }

    func test_reload_whenSizeChanged_reloadsNextTab() {
        var size: CGSize? = CGSize(width: 640, height: 360)
        let preloader = NewTabPageTabPreloader(viewSizeProvider: { size })
        guard let initial = preloader.newTab() else {
            XCTFail("newTab should not return nil")
            return
        }
        size = CGSize(width: 800, height: 600)
        preloader.reloadTab()
        guard let reloaded = preloader.newTab() else {
            XCTFail("newTab should not return nil")
            return
        }
        XCTAssertNotEqual(initial.webViewSize, reloaded.webViewSize)
        XCTAssertEqual(reloaded.webViewSize, CGSize(width: 800, height: 600))
    }

    func test_reload_forceReloadsNextTab_evenIfSizeUnchanged() {
        let fixedSize = CGSize(width: 128, height: 256)
        let preloader = NewTabPageTabPreloader(viewSizeProvider: { fixedSize })
        guard let initial = preloader.newTab() else {
            XCTFail("newTab should not return nil")
            return
        }
        preloader.reloadTab(force: true)
        guard let forced = preloader.newTab() else {
            XCTFail("newTab should not return nil")
            return
        }
        XCTAssertNotEqual(initial, forced)
    }
}
