//
//  TabSwitcherPageViewControllerTests.swift
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

import Core
import XCTest
@testable import DuckDuckGo

@MainActor
final class TabSwitcherPageViewControllerTests: XCTestCase {

    func testWhenTabsBeforeTheCurrentOneCloseWhileOpenThenTheSelectedTabStaysTheCurrentOne() async {
        let closing = Tab(link: Link(title: nil, url: URL(string: "https://example.com/closing")!))
        let other = Tab(link: Link(title: nil, url: URL(string: "https://example.com/other")!))
        let current = Tab(link: Link(title: nil, url: URL(string: "https://example.com/current")!))
        let model = TabsModel(tabs: [closing, other, current], currentIndex: 2, desktop: false)
        let previewsSource = MockTabPreviewsSource()
        let sut = TabSwitcherPageViewController(browsingMode: .normal,
                                                tabsModel: model,
                                                previewsSource: previewsSource,
                                                tabSwitcherSettings: StubTabSwitcherSettings(),
                                                trackerCountViewModel: nil,
                                                isFireModeEnabled: false,
                                                duckAIGridContentProvider: nil,
                                                duckAIVoiceSessionTracker: nil)
        sut.loadViewIfNeeded()

        model.remove(tab: closing)
        let updated = expectation(description: "Tab change delivered")
        DispatchQueue.main.async { updated.fulfill() }
        await fulfillment(of: [updated], timeout: 1)

        XCTAssertTrue(sut.selectedTab === current)
    }
}

private final class StubTabSwitcherSettings: TabSwitcherSettings {
    var isGridViewEnabled = true
    var hasSeenNewLayout = true
    var showTrackerCountInTabSwitcher = false
    var lastTrackerCountInTabSwitcher: Int64?
}
