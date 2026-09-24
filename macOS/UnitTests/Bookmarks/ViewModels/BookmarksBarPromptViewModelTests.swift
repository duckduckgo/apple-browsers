//
//  BookmarksBarPromptViewModelTests.swift
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

import PrivacyConfig
import PrivacyConfigTestsUtils
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class BookmarksBarPromptViewModelTests: XCTestCase {

    private var prefs: AppearancePreferences!
    private var sut: BookmarksBarPromptViewModel!
    private var dismissResults: [PromoResult] = []

    override func setUp() {
        super.setUp()
        prefs = AppearancePreferences(
            persistor: MockAppearancePreferencesPersistor(),
            privacyConfigurationManager: MockPrivacyConfigurationManager(),
            featureFlagger: MockFeatureFlagger(),
            aiChatMenuConfig: MockAIChatConfig()
        )
        sut = BookmarksBarPromptViewModel(prefs: prefs)
        dismissResults = []
        sut.onDismiss = { [weak self] in self?.dismissResults.append($0) }
    }

    override func tearDown() {
        sut = nil
        prefs = nil
        dismissResults = []
        super.tearDown()
    }

    func testAcceptBookmarksBar_turnsBarOnAndResolvesActioned() {
        sut.acceptBookmarksBar()

        XCTAssertTrue(prefs.showBookmarksBar)
        XCTAssertEqual(dismissResults, [.actioned])
    }

    func testRejectBookmarksBar_turnsBarOffAndResolvesActioned() {
        sut.rejectBookmarksBar()

        XCTAssertFalse(prefs.showBookmarksBar)
        XCTAssertEqual(dismissResults, [.actioned])
    }

    func testRejectBookmarksBar_whenNotExplicit_turnsBarOffAndResolvesIgnored() {
        sut.rejectBookmarksBar(wasExplicit: false)

        XCTAssertFalse(prefs.showBookmarksBar)
        XCTAssertEqual(dismissResults, [.ignored()])
    }

    func testOnDismissFiresExactlyOnce() {
        sut.acceptBookmarksBar()

        XCTAssertEqual(dismissResults.count, 1)
    }
}
