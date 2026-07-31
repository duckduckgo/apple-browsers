//
//  DuckAIPromptSurfaceTests.swift
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
@testable import DuckDuckGo_Privacy_Browser

/// Pins the capability matrix, so switching a Prompt Bar capability on has to be a deliberate edit
/// to a test rather than a side effect of another change.
final class DuckAIPromptSurfaceTests: XCTestCase {

    func testWhenSurfaceIsAddressBarThenEveryCapabilityIsAvailable() {
        let surface = DuckAIPromptSurface.addressBar

        XCTAssertTrue(surface.supportsPageContext)
        XCTAssertTrue(surface.supportsCustomizeResponses)
        XCTAssertTrue(surface.supportsSuggestions)
        XCTAssertTrue(surface.supportsSubscriptionUpsell)
    }

    func testWhenSurfaceIsAddressBarThenItRelaysOnTheBrowserWindowForChromeAndSubmission() {
        let surface = DuckAIPromptSurface.addressBar

        XCTAssertFalse(surface.drawsOwnChrome)
        XCTAssertFalse(surface.showsBrandLogo)
        XCTAssertFalse(surface.routesSubmissionThroughHost)
    }

    func testWhenSurfaceIsPromptBarThenWindowDependentCapabilitiesAreUnavailable() {
        let surface = DuckAIPromptSurface.promptBar

        XCTAssertFalse(surface.supportsPageContext)
        XCTAssertFalse(surface.supportsSuggestions)
    }

    func testWhenSurfaceIsPromptBarThenBrowserChromeFeaturesAreUnavailable() {
        let surface = DuckAIPromptSurface.promptBar

        XCTAssertFalse(surface.supportsCustomizeResponses)
        XCTAssertFalse(surface.supportsSubscriptionUpsell)
    }

    func testWhenSurfaceIsPromptBarThenItOwnsItsChromeAndRoutesSubmissionItself() {
        let surface = DuckAIPromptSurface.promptBar

        XCTAssertTrue(surface.drawsOwnChrome)
        XCTAssertTrue(surface.showsBrandLogo)
        XCTAssertTrue(surface.routesSubmissionThroughHost)
    }
}
