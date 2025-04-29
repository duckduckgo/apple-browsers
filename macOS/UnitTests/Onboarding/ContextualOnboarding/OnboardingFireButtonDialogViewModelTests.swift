//
//  OnboardingFireButtonDialogViewModelTests.swift
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

import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class OnboardingFireButtonDialogViewModelTests: XCTestCase {
    var viewModel: OnboardingFireButtonDialogViewModel!
    var reporter: CapturingOnboardingPixelReporter!
    var onGotItPressedCalled = false
    var onGotItPressed: (() -> Void)!
    var onDismissCalled = false
    var onDismiss: (() -> Void)!
    var onFireButtonPressedCalled = false
    var onFireButtonPressed: (() -> Void)!

    override func setUpWithError() throws {
        onGotItPressed = {
            self.onGotItPressedCalled = true
        }
        onDismiss = {
            self.onDismissCalled = true
        }
        onFireButtonPressed = {
            self.onFireButtonPressedCalled = true
        }

        reporter = CapturingOnboardingPixelReporter()
        viewModel = OnboardingFireButtonDialogViewModel(onboardingPixelReporter: reporter, onDismiss: onDismiss, onGotItPressed: onGotItPressed, onFireButtonPressed: onFireButtonPressed)
    }

    @MainActor
    override func tearDownWithError() throws {
        reporter = nil
        viewModel = nil
        WindowControllersManager.shared.lastKeyMainWindowController = nil
    }

    func testWhenHighFiveThenOnGotItAndOnDismissPressed() throws {
        viewModel.highFive()

        XCTAssertTrue(onDismissCalled)
        XCTAssertTrue(onGotItPressedCalled)
    }

    @MainActor
    func testWhenTryFireButtonThenOnFireButtonPressedCalledAndPixelSent() throws {
        let mainViewController = MainViewController(tabCollectionViewModel: TabCollectionViewModel(tabCollection: TabCollection(tabs: [])), autofillPopoverPresenter: DefaultAutofillPopoverPresenter())
        let window = MockWindow(isVisible: false)
        let mainWindowController = MainWindowController(window: window, mainViewController: mainViewController, popUp: false)
        mainWindowController.window = window
        WindowControllersManager.shared.lastKeyMainWindowController = mainWindowController

        window.isVisible = true
        viewModel.tryFireButton()

        XCTAssertTrue(onFireButtonPressedCalled)
        XCTAssertTrue(reporter.measureFireButtonTryItCalled)
    }

}
