//
//  DuckAiNativeStorageBaseURLTests.swift
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

import AppKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class DuckAiNativeStorageBaseURLTests: XCTestCase {

    private let systemApplicationSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

    func testProductionBundleUsesSystemApplicationSupport() {
        XCTAssertEqual(AppDelegate.duckAiNativeStorageBaseURL(isSandboxed: false, bundleID: "com.duckduckgo.macos.browser"),
                       systemApplicationSupportURL)
    }

    func testSandboxedBundleUsesSystemApplicationSupport() {
        XCTAssertEqual(AppDelegate.duckAiNativeStorageBaseURL(isSandboxed: true, bundleID: "com.duckduckgo.macos.browser.review"),
                       systemApplicationSupportURL)
    }

    func testNonProductionUnsandboxedBundleUsesPerBundleContainer() throws {
        try XCTSkipIf(NSApp.isSandboxed, "URL.sandboxApplicationSupportURL collapses to Application Support in a sandboxed host")

        let url = AppDelegate.duckAiNativeStorageBaseURL(isSandboxed: false, bundleID: "com.duckduckgo.macos.browser.review")
        XCTAssertEqual(url, URL.sandboxApplicationSupportURL)
        XCTAssertNotEqual(url, systemApplicationSupportURL)
    }
}
