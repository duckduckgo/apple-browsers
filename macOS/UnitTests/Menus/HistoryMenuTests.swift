//
//  HistoryMenuTests.swift
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

final class HistoryMenuTests: XCTestCase {

    var sut: HistoryMenu!

    @MainActor
    override func setUp() {
        sut = makeHistoryMenu(location: .mainMenu)
    }

    @MainActor
    override func tearDown() {
        sut = nil
    }

    @MainActor
    func testImportHistoryMenuItemOpensDataImport() throws {
        sut.update()

        let item = try XCTUnwrap(importHistoryMenuItem(in: sut))
        XCTAssertFalse(item.isHidden)
        XCTAssertEqual(item.title, UserText.mainMenuHistoryImportHistory)
        XCTAssertEqual(item.action, #selector(AppDelegate.openImportBrowserDataWindow))
    }

    @MainActor
    func testMoreOptionsHistoryMenuShowsImportHistoryBelowShowAllHistory() throws {
        let moreOptionsHistoryMenu = makeHistoryMenu(location: .moreOptionsMenu)

        moreOptionsHistoryMenu.update()

        let item = try XCTUnwrap(importHistoryMenuItem(in: moreOptionsHistoryMenu))
        XCTAssertFalse(item.isHidden)
        XCTAssertEqual(moreOptionsHistoryMenu.items.firstIndex(of: item), 1)
    }

    @MainActor
    private func makeHistoryMenu(location: HistoryMenu.Location) -> HistoryMenu {
        HistoryMenu(
            location: location,
            historyGroupingDataSource: HistoryCoordinatingMock(),
            recentlyClosedCoordinator: RecentlyClosedCoordinatorMock()
        )
    }

    private func importHistoryMenuItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.accessibilityIdentifier() == "HistoryMenu.importHistory" }
    }
}
