//
//  VPNApplicationShortcutItemManagerTests.swift
//  DuckDuckGo
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
@testable import DuckDuckGo

final class VPNApplicationShortcutItemManagerTests: XCTestCase {

    let manager = VPNApplicationShortcutItemManager(application: UIApplication.shared)
    let testItem = UIApplicationShortcutItem(type: "test.type", localizedTitle: "")

    func test_WhenExistingItemsIsEmptyAndNoShortcut_ThenItemsStaysEmpty() {
        XCTAssertEqual([], manager.items(existingItems: [], showShortcut: false))
    }

    func test_WhenExistingItemsIsNotEmptyAndNoShortcut_ThenItemsStaysUnchanged() {
        XCTAssertEqual([
            testItem
        ], manager.items(existingItems: [
            testItem
        ], showShortcut: false))
    }

    func test_WhenExistingItemsIsEmptyAndShowShortcut_ThenNewItemAdded() {
        let items = manager.items(existingItems: [], showShortcut: true)
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(items.contains(where: { $0.type == ShortcutKey.openVPNSettings }))
    }

    func test_WhenExistingItemsIsNotEmptyAndShowShortcut_ThenNewItemAdded() {
        let items = manager.items(existingItems: [testItem], showShortcut: true)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains(where: { $0.type == ShortcutKey.openVPNSettings }))
        XCTAssertTrue(items.contains(where: { $0.type == "test.type" }))
    }

}
