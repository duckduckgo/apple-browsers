//
//  WebExtensionManagerTests.swift
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
import WebExtensions
@testable import DuckDuckGo_Privacy_Browser

// MARK: - macOS-Specific WebExtension Tests
//
// Note: Core WebExtensionManager tests have been migrated to the shared
// WebExtensions package at SharedPackages/WebExtensions/Tests/WebExtensionsTests/.
//
// This file should contain tests for:
// - WebExtensionManagerFactory
// - WebExtensionWindowTabProvider (macOS-specific implementation)
// - macOS UI-specific behavior (toolbar buttons, popovers, etc.)

//@available(macOS 15.4, *)
//final class WebExtensionManagerFactoryTests: XCTestCase {
//
//    @MainActor
//    func testThatMakeManager_ReturnsConfiguredManager() {
//        let manager = WebExtensionManagerFactory.makeManager()
//
//        XCTAssertNotNil(manager)
//        XCTAssertNotNil(manager.windowTabProvider)
//        XCTAssertNotNil(manager.lifecycleDelegate)
//    }
//}
