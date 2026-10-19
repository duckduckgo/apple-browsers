//
//  BookmarksBarShownTriggerTests.swift
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

import Common
import History
import HistoryView
import PrivacyConfig
import SharedTestUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BookmarksBarShownTriggerTests: XCTestCase {

    private var mainViewController: MainViewController!
    private var observer: NSObjectProtocol?
    private var postCount = 0

    override func setUp() {
        super.setUp()
        mainViewController = makeMainViewController()
        // Loading the view attaches the bookmarks bar before its visibility is decided.
        _ = mainViewController.view
        postCount = 0
        observer = NotificationCenter.default.addObserver(forName: .bookmarksBarShown, object: mainViewController, queue: nil) { [weak self] _ in
            MainActor.assumeMainThread {
                self?.postCount += 1
            }
        }
    }

    override func tearDown() {
        observer.map(NotificationCenter.default.removeObserver)
        observer = nil
        mainViewController = nil
        super.tearDown()
    }

    func testWhenBarIsFirstShownThenTriggerIsPosted() {
        // When
        mainViewController.updateBookmarksBarViewVisibility(visible: true)

        // Then
        XCTAssertEqual(postCount, 1)
    }

    func testWhenBarIsAlreadyShownThenTriggerIsNotPostedAgain() {
        // Given
        mainViewController.updateBookmarksBarViewVisibility(visible: true)

        // When
        mainViewController.updateBookmarksBarViewVisibility(visible: true)

        // Then
        XCTAssertEqual(postCount, 1)
    }

    func testWhenBarIsHiddenThenTriggerIsNotPosted() {
        // When
        mainViewController.updateBookmarksBarViewVisibility(visible: false)

        // Then
        XCTAssertEqual(postCount, 0)
    }

    func testWhenBarIsShownAgainAfterBeingHiddenThenTriggerIsPostedAgain() {
        // Given
        mainViewController.updateBookmarksBarViewVisibility(visible: true)
        mainViewController.updateBookmarksBarViewVisibility(visible: false)

        // When
        mainViewController.updateBookmarksBarViewVisibility(visible: true)

        // Then
        XCTAssertEqual(postCount, 2)
    }

    private func makeMainViewController() -> MainViewController {
        let windowControllersManager = WindowControllersManagerMock()
        let featureFlagger = MockFeatureFlagger()
        let fireproofDomains = MockFireproofDomains()
        let faviconManager = FaviconManagerMock()
        let dataClearingPreferences = DataClearingPreferences(persistor: MockFireButtonPreferencesPersistor(),
                                                              fireproofDomains: fireproofDomains,
                                                              faviconManager: faviconManager,
                                                              windowControllersManager: windowControllersManager,
                                                              featureFlagger: featureFlagger,
                                                              aiChatHistoryCleaner: MockAIChatHistoryCleaner())
        let fireCoordinator = FireCoordinator(tld: TLD(),
                                              featureFlagger: featureFlagger,
                                              historyCoordinating: HistoryCoordinatingMock(),
                                              visualizeFireAnimationDecider: nil,
                                              onboardingContextualDialogsManager: nil,
                                              fireproofDomains: fireproofDomains,
                                              faviconManagement: faviconManager,
                                              windowControllersManager: windowControllersManager,
                                              dataClearingPreferences: dataClearingPreferences,
                                              pixelFiring: nil,
                                              historyProvider: MockHistoryViewDataProvider())
        return MainViewController(
            tabCollectionViewModel: TabCollectionViewModel(isPopup: false, windowControllersManager: windowControllersManager),
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
            aiChatSessionStore: AIChatSessionStore(featureFlagger: featureFlagger),
            fireCoordinator: fireCoordinator
        )
    }
}
