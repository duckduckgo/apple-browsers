//
//  TabViewControllerSiteLoadingPixelTests.swift
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

import Navigation
import PrivacyDashboard
import WebKit
import XCTest
@testable import DuckDuckGo

final class TabViewControllerSiteLoadingPixelTests: XCTestCase {

    func test_safeNavigationType_mapsKnownCases() {
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .linkActivated), "linkActivated")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .formSubmitted), "formSubmitted")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .backForward), "backForward")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .reload), "reload")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .formResubmitted), "formResubmitted")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .other), "other")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .sessionRestoration), "sessionRestoration")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .alternateHtmlLoad), "alternateHtmlLoad")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .sameDocumentNavigation), "sameDocumentNavigation")
    }

    func test_safeNavigationType_mapsKnownCustomTypesAndDefaultsUnknown() {
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .custom(.init(rawValue: "userEnteredUrl"))), "custom.userEnteredUrl")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .custom(.init(rawValue: "bookmark"))), "custom.bookmark")
        XCTAssertEqual(SiteLoadingPixel.safeNavigationType(for: .custom(.init(rawValue: "leaked-pii"))), "custom.unknown")
    }

    func test_shouldFireSiteLoadingPixel_skipsJSRedirectsAndAlternateHtmlLoad() {
        XCTAssertFalse(SiteLoadingPixel.shouldFireSiteLoadingPixel(for: .redirect(.developer), isStartingFromErrorPage: false))
        XCTAssertFalse(SiteLoadingPixel.shouldFireSiteLoadingPixel(for: .redirect(.client(delay: 0)), isStartingFromErrorPage: false))
        XCTAssertFalse(SiteLoadingPixel.shouldFireSiteLoadingPixel(for: .alternateHtmlLoad, isStartingFromErrorPage: false))
        // Server-side redirects (.server) should still fire the pixel
        XCTAssertTrue(SiteLoadingPixel.shouldFireSiteLoadingPixel(for: .redirect(.server), isStartingFromErrorPage: false))
    }

    func test_shouldFireSiteLoadingPixel_skipsOtherWhenStartingFromErrorPage() {
        XCTAssertFalse(SiteLoadingPixel.shouldFireSiteLoadingPixel(for: .other, isStartingFromErrorPage: true))
        XCTAssertTrue(SiteLoadingPixel.shouldFireSiteLoadingPixel(for: .other, isStartingFromErrorPage: false))
        // The error-page guard intentionally only catches `.other`; explicit user-driven types still fire.
        XCTAssertTrue(SiteLoadingPixel.shouldFireSiteLoadingPixel(for: .linkActivated, isStartingFromErrorPage: true))
        XCTAssertTrue(SiteLoadingPixel.shouldFireSiteLoadingPixel(for: .reload, isStartingFromErrorPage: true))
    }
}
