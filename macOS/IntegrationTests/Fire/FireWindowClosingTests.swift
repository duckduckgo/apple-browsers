//
//  FireWindowClosingTests.swift
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

import Combine
import XCTest

@testable import DuckDuckGo_Privacy_Browser

/// Fire Windows must play the fire animation before they disappear, no matter how the close was triggered.
///
/// `NSWindow.close()` doesn't invoke `windowShouldClose(_:)`, so every programmatic close has to go through
/// `MainWindowController.burnAndClose(_:)` — these tests cover the two paths that used to call `close()` directly.
///
/// Outside the `.normal` run type the Lottie animation view is never loaded, so `animateFireWhenClosing()`
/// flips `isAnimationPlaying` on and straight back off. That's enough to tell "the animation ran" from
/// "it was skipped", which is exactly what the popover button used to get wrong.
final class FireWindowClosingTests: XCTestCase {

    private var cancellables = Set<AnyCancellable>()
    private var initialFireAnimationEnabled = true

    @MainActor
    override func setUp() {
        initialFireAnimationEnabled = Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled
        Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled = true
    }

    @MainActor
    override func tearDown() {
        Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled = initialFireAnimationEnabled
        cancellables = []
        autoreleasepool {
            WindowsManager.closeWindows()
            for controller in Application.appDelegate.windowControllersManager.mainWindowControllers {
                Application.appDelegate.windowControllersManager.unregister(controller)
            }
        }
        // Allow WebKit IPC to settle after closing windows
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
    }

    // MARK: - Tests

    @MainActor
    func testWhenFirePopoverCloseButtonClicked_thenFireAnimationPlaysAndWindowCloses() async throws {
        let windowController = try openFireWindow()
        let window = try XCTUnwrap(windowController.window)

        var animationStates = [Bool]()
        subscribeToAnimationStates(of: windowController) { animationStates.append($0) }

        // Not going through `FireCoordinator.showFirePopover` on purpose: the coordinator holds on to the
        // popover for the lifetime of the app, so its views would outlive the test and trip the harness'
        // deallocation checks. The action doesn't touch the view hierarchy, so a bare controller is enough.
        let popoverViewController = FirePopoverViewController(
            fireViewModel: windowController.mainViewController.fireViewController.fireViewModel,
            tabCollectionViewModel: windowController.mainViewController.tabCollectionViewModel
        )

        let windowClosed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        popoverViewController.closeBurnerWindowButtonAction(self)
        await fulfillment(of: [windowClosed], timeout: 5)

        XCTAssertEqual(animationStates, [true, false])
    }

    @MainActor
    func testWhenLastTabOfFireWindowClosed_thenFireAnimationPlaysAndWindowCloses() async throws {
        let windowController = try openFireWindow()
        let window = try XCTUnwrap(windowController.window)

        var animationStates = [Bool]()
        subscribeToAnimationStates(of: windowController) { animationStates.append($0) }

        let windowClosed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        windowController.mainViewController.tabCollectionViewModel.remove(at: .unpinned(0))
        await fulfillment(of: [windowClosed], timeout: 5)

        XCTAssertEqual(animationStates, [true, false])
    }

    @MainActor
    func testWhenFireAnimationDisabled_thenFireWindowClosesWithoutAnimating() async throws {
        Application.appDelegate.dataClearingPreferences.isFireAnimationEnabled = false

        let windowController = try openFireWindow()
        let window = try XCTUnwrap(windowController.window)

        var animationStates = [Bool]()
        subscribeToAnimationStates(of: windowController) { animationStates.append($0) }

        let windowClosed = expectation(forNotification: NSWindow.willCloseNotification, object: window)
        windowController.burnAndClose(window)
        await fulfillment(of: [windowClosed], timeout: 5)

        XCTAssertEqual(animationStates, [])
    }

    // MARK: - Helpers

    @MainActor
    private func openFireWindow() throws -> MainWindowController {
        // `showWindow: false` would still open a window, but not activate it, which seems to upset CI
        _=WindowsManager.openNewWindow(with: URL(string: "data:,Hello%2C%20World%21")!, source: .ui, isBurner: true)
        let windowController = try XCTUnwrap(Application.appDelegate.windowControllersManager.mainWindowControllers.last)
        XCTAssertTrue(windowController.mainViewController.tabCollectionViewModel.isBurner)
        return windowController
    }

    @MainActor
    private func subscribeToAnimationStates(of windowController: MainWindowController, onChange: @escaping (Bool) -> Void) {
        windowController.mainViewController.fireViewController.fireViewModel.$isAnimationPlaying
            .dropFirst()
            .sink { onChange($0) }
            .store(in: &cancellables)
    }
}
