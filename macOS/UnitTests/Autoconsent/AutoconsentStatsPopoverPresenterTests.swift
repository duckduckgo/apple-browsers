//
//  AutoconsentStatsPopoverPresenterTests.swift
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

import AutoconsentStats
import BrowserServicesKit
import Combine
import Common
import SharedTestUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class MockAutoconsentStatsForPresenter: AutoconsentStatsCollecting {
    let statsUpdatePublisher: AnyPublisher<Void, Never> = Empty<Void, Never>().eraseToAnyPublisher()

    var totalCookiePopUpsBlocked: Int64 = 0

    func recordAutoconsentAction(clicksMade: Int64, timeSpent: TimeInterval) async {}
    func fetchTotalCookiePopUpsBlocked() async -> Int64 {
        return totalCookiePopUpsBlocked
    }
    func fetchAutoconsentDailyUsagePack() async -> AutoconsentDailyUsagePack {
        AutoconsentDailyUsagePack(
            totalCookiePopUpsBlocked: totalCookiePopUpsBlocked,
            totalClicksMadeBlockingCookiePopUps: 0,
            totalTotalTimeSpentBlockingCookiePopUps: 0
        )
    }
    func clearAutoconsentStats() async {}
    func isEnabled() async -> Bool { true }
}

@MainActor
final class AutoconsentStatsPopoverPresenterTests: XCTestCase {
    var presenter: AutoconsentStatsPopoverPresenter!
    var mockAutoconsentStats: MockAutoconsentStatsForPresenter!
    var mockWindowControllersManager: WindowControllersManagerMock!

    override func setUpWithError() throws {
        try super.setUpWithError()

        mockAutoconsentStats = MockAutoconsentStatsForPresenter()
        mockWindowControllersManager = WindowControllersManagerMock()
    }

    override func tearDown() {
        presenter = nil
        mockAutoconsentStats = nil
        mockWindowControllersManager = nil
        super.tearDown()
    }

    func makePresenter() -> AutoconsentStatsPopoverPresenter {
        return AutoconsentStatsPopoverPresenter(
            autoconsentStats: mockAutoconsentStats,
            windowControllersManager: mockWindowControllersManager
        )
    }

    @MainActor
    func testIsPopoverBeingPresented_ReturnsFalse_WhenNoPopover() {
        presenter = makePresenter()

        XCTAssertFalse(presenter.isPopoverBeingPresented())
    }

    @MainActor
    func testDismissPopover_DoesNothing_WhenNoPopover() {
        presenter = makePresenter()

        presenter.dismissPopover()

        XCTAssertFalse(presenter.isPopoverBeingPresented())
    }

    @MainActor
    func testShowPopover_DoesNotShow_WhenNoMainWindowController() async {
        presenter = makePresenter()
        mockWindowControllersManager.mainWindowControllers = []
        var onCloseCalled = false
        var onClickCalled = false
        var onAutoDismissCalled = false

        await presenter.showPopover(
            onClose: { onCloseCalled = true },
            onClick: { onClickCalled = true },
            onAutoDismiss: { onAutoDismissCalled = true }
        )

        XCTAssertFalse(presenter.isPopoverBeingPresented())
        XCTAssertFalse(onCloseCalled)
        XCTAssertFalse(onClickCalled)
        XCTAssertFalse(onAutoDismissCalled)
    }
}
