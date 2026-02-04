//
//  OnboardingNavigatingTests.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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
import PrivacyConfig
import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class OnboardingNavigatingTests: XCTestCase {

    var onboardingNavigation: OnboardingNavigating!
    var fireCoordinator: FireCoordinator!

    @MainActor
    override func setUp() {
        super.setUp()
        onboardingNavigation = Application.appDelegate.windowControllersManager
        fireCoordinator = FireCoordinator(tld: TLD(),
                                          featureFlagger: Application.appDelegate.featureFlagger,
                                          historyCoordinating: HistoryCoordinatingMock(),
                                          visualizeFireAnimationDecider: nil,
                                          onboardingContextualDialogsManager: nil,
                                          fireproofDomains: MockFireproofDomains(),
                                          faviconManagement: FaviconManagerMock(),
                                          windowControllersManager: WindowControllersManagerMock(),
                                          pixelFiring: nil,
                                          historyProvider: MockHistoryViewDataProvider())
        assert(Application.appDelegate.windowControllersManager.mainWindowControllers.isEmpty)
    }

    @MainActor
    override func tearDown() {
        onboardingNavigation = nil
        fireCoordinator = nil
        super.tearDown()
    }

    @MainActor
    func testOnImportData_DataImportViewShown() throws {
        // Given
        let mockWindow = MockWindow(isVisible: false)
        let mvc = MainWindowController(
            window: mockWindow,
            mainViewController: MainViewController(tabCollectionViewModel: TabCollectionViewModel(isPopup: false), autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()), aiChatSidebarProvider: AIChatSidebarProvider(featureFlagger: MockFeatureFlagger()), fireCoordinator: fireCoordinator),
            fireViewModel: fireCoordinator.fireViewModel,
            themeManager: MockThemeManager())
        mvc.window = mockWindow
        Application.appDelegate.windowControllersManager.register(mvc)
        defer {
            Application.appDelegate.windowControllersManager.unregister(mvc)
        }

        // When
        onboardingNavigation.showImportDataView()

        // Then
        XCTAssertTrue(mockWindow.beginSheetCalled, "A sheet should be begun on the window")
    }

    @MainActor
    func testOnFocusOnAddressBar_AddressBarIsFocussed() throws {
        // Given
        let mockWindow = MockWindow(isVisible: false)
        let mvc = MainWindowController(
            window: mockWindow,
            mainViewController: MainViewController(tabCollectionViewModel: TabCollectionViewModel(isPopup: false), autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()), aiChatSidebarProvider: AIChatSidebarProvider(featureFlagger: MockFeatureFlagger()), fireCoordinator: fireCoordinator),
            fireViewModel: fireCoordinator.fireViewModel,
            themeManager: MockThemeManager()
        )
        mvc.window = mockWindow
        Application.appDelegate.windowControllersManager.register(mvc)
        defer {
            Application.appDelegate.windowControllersManager.unregister(mvc)
        }

        // When
        onboardingNavigation.focusOnAddressBar()

        // Then
        let mainVC = try XCTUnwrap(Application.appDelegate.windowControllersManager.lastKeyMainWindowController?.mainViewController)
        XCTAssertTrue(mainVC.navigationBarViewController.addressBarViewController?.addressBarTextField.stringValue.isEmpty ?? false)
        XCTAssertTrue(mainVC.navigationBarViewController.addressBarViewController?.addressBarTextField.isFirstResponder ?? false)
    }

}
