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
    func testWhenDataImportHistoryTurnsOnWhileRunning_ThenImportHistoryMenuItemAppearsBelowShowAllHistory() throws {
        let featureFlagger = MockFeatureFlagger()
        let sut = HistoryMenu(
            historyGroupingDataSource: HistoryCoordinatingMock(),
            recentlyClosedCoordinator: RecentlyClosedCoordinatorMock(),
            featureFlagger: featureFlagger
        )
        sut.update()
        let item = try XCTUnwrap(sut.items.first { $0.action == #selector(AppDelegate.openImportBrowserDataWindow) })
        featureFlagger.featuresStub = [FeatureFlag.dataImportHistory.rawValue: true]

        sut.update()

        XCTAssertFalse(item.isHidden)
        XCTAssertEqual(sut.item(at: sut.index(of: item) - 2)?.title, UserText.mainMenuHistoryShowAllHistory)
    }
}
