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

import FeatureFlags_macOS
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class HistoryMenuTests: XCTestCase {

    @MainActor
    func testWhenDataImportHistoryIsOff_ThenImportHistoryMenuItemIsHidden() {
        let sut = makeHistoryMenu(featureFlagger: MockFeatureFlagger())

        sut.update()

        XCTAssertEqual(importHistoryMenuItem(in: sut)?.isHidden, true)
    }

    @MainActor
    func testWhenDataImportHistoryIsOn_ThenImportHistoryMenuItemOpensDataImport() throws {
        let sut = makeHistoryMenu(featureFlagger: MockFeatureFlagger(featuresStub: [FeatureFlag.dataImportHistory.rawValue: true]))

        sut.update()

        let item = try XCTUnwrap(importHistoryMenuItem(in: sut))
        XCTAssertFalse(item.isHidden)
        XCTAssertEqual(item.title, UserText.mainMenuHistoryImportHistory)
        XCTAssertEqual(item.action, #selector(AppDelegate.openImportBrowserDataWindow))
    }

    @MainActor
    func testWhenDataImportHistoryChangesWhileRunning_ThenImportHistoryMenuItemFollowsOnNextUpdate() {
        let featureFlagger = MockFeatureFlagger()
        let sut = makeHistoryMenu(featureFlagger: featureFlagger)
        sut.update()
        featureFlagger.featuresStub = [FeatureFlag.dataImportHistory.rawValue: true]

        sut.update()

        XCTAssertEqual(importHistoryMenuItem(in: sut)?.isHidden, false)
    }

    @MainActor
    func testMoreOptionsHistoryMenuHasNoImportHistoryMenuItem() {
        let featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.dataImportHistory.rawValue: true])
        let sut = makeHistoryMenu(location: .moreOptionsMenu, featureFlagger: featureFlagger)

        sut.update()

        XCTAssertNil(importHistoryMenuItem(in: sut))
    }

    @MainActor
    private func makeHistoryMenu(location: HistoryMenu.Location = .mainMenu, featureFlagger: FeatureFlagger) -> HistoryMenu {
        HistoryMenu(
            location: location,
            historyGroupingDataSource: HistoryCoordinatingMock(),
            recentlyClosedCoordinator: RecentlyClosedCoordinatorMock(),
            featureFlagger: featureFlagger
        )
    }

    private func importHistoryMenuItem(in menu: NSMenu) -> NSMenuItem? {
        menu.items.first { $0.accessibilityIdentifier() == "HistoryMenu.importHistory" }
    }
}
