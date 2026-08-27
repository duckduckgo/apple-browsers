//
//  NSMenuItemExtensionTests.swift
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
@testable import AppKitExtensions

final class NSMenuItemExtensionTests: XCTestCase {

    func testWithImageAppliesDefaultVisibilityPolicy() {
        let image = NSImage(size: NSSize(width: 12, height: 12))

        let item = NSMenuItem().withImage(image)

#if compiler(>=6.4)
        XCTAssertIdentical(item.image, image)
        if #available(macOS 27.0, *) {
            XCTAssertEqual(item.preferredImageVisibility, .hidden)
        }
#else
        if #available(macOS 27.0, *) {
            XCTAssertNil(item.image)
        } else {
            XCTAssertIdentical(item.image, image)
        }
#endif
    }

    func testWithImageKeepsImageWhenVisibleOnMacOS27IsRequested() {
        let image = NSImage(size: NSSize(width: 12, height: 12))

        let item = NSMenuItem().withImage(image, visibleOnMacOS27: true)

        XCTAssertIdentical(item.image, image)
#if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            XCTAssertEqual(item.preferredImageVisibility, .visible)
        }
#endif
    }
}
