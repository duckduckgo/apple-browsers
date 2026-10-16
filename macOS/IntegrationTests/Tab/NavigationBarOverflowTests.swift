//
//  NavigationBarOverflowTests.swift
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

import SharedTestUtilities
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class NavigationBarOverflowTests: XCTestCase {

    var window: NSWindow!
    var originallyPinnedViews: [PinnableView]!

    var navigationBar: NavigationBarViewController {
        (window.contentViewController as! MainViewController).navigationBarViewController
    }

    var pinningManager: PinningManager {
        NSApp.delegateTyped.pinningManager
    }

    @MainActor
    override func setUp() {
        originallyPinnedViews = PinnableView.allCases.filter(pinningManager.isPinned)
        PinnableView.allCases.forEach(pinningManager.pin)
    }

    @MainActor
    override func tearDown() {
        autoreleasepool {
            window?.close()
            window = nil
        }
        for view in PinnableView.allCases {
            if originallyPinnedViews.contains(view) {
                pinningManager.pin(view)
            } else {
                pinningManager.unpin(view)
            }
        }
        originallyPinnedViews = nil
    }

    @MainActor
    func testWhenAllButtonsArePinned_ThenWindowShrinksToMinimumWidthUsingOverflowMenu() {
        openWindow()
        addExtraToolbarButtons()

        resizeWindow(toWidth: MainWindow.minWindowWidth)

        XCTAssertEqual(window.frame.width, MainWindow.minWindowWidth, "The window couldn't shrink to its minimum width")
        XCTAssertFalse(navigationBar.overflowButton.isHidden, "No pinned buttons moved to the overflow menu")
        assertRequiredHorizontalSpacingIsSatisfied()
    }

    @MainActor
    func testWhenWindowIsWidenedAgain_ThenPinnedButtonsLeaveOverflowMenu() {
        openWindow()
        addExtraToolbarButtons()
        resizeWindow(toWidth: MainWindow.minWindowWidth)

        resizeWindow(toWidth: 1200)

        XCTAssertTrue(navigationBar.overflowButton.isHidden, "Pinned buttons stayed in the overflow menu")
        assertRequiredHorizontalSpacingIsSatisfied()
    }

    // MARK: - Helpers

    @MainActor
    private func openWindow() {
        let viewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: [Tab(content: .newtab)]))
        window = WindowsManager.openNewWindow(with: viewModel)!
        waitForWorkQueuedOnMainQueue()
        resizeWindow(toWidth: 1200)
    }

    /// Opening a window queues part of its setup on the main queue; let it run before laying out.
    @MainActor
    private func waitForWorkQueuedOnMainQueue() {
        let queuedWorkDone = expectation(description: "Work queued on the main queue has run")
        DispatchQueue.main.async {
            queuedWorkDone.fulfill()
        }
        wait(for: [queuedWorkDone], timeout: 5)
    }

    /// Adds buttons that can't move to the overflow menu to ensure that pinned buttons
    /// never fit at the minimum window width and need the overflow menu.
    @MainActor
    private func addExtraToolbarButtons() {
        let menuButtons = navigationBar.menuButtons!
        for _ in 0..<3 {
            let button = NSButton(title: "", target: nil, action: nil)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            menuButtons.insertArrangedSubview(button, at: menuButtons.arrangedSubviews.count - 1)
        }
    }

    @MainActor
    private func resizeWindow(toWidth width: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        var frame = window.frame
        frame.size.width = width
        window.setFrame(frame, display: true)
        settleLayout(file: file, line: line)
    }

    private struct LayoutState: Equatable {
        let windowWidth: CGFloat
        let stackFrames: [NSRect]
        let hiddenArrangedSubviews: [[Bool]]
        let isOverflowButtonHidden: Bool
    }

    @MainActor
    private var layoutState: LayoutState {
        let stacks: [NSStackView] = [navigationBar.navigationButtons, navigationBar.addressBarStack, navigationBar.menuButtons]
        return LayoutState(windowWidth: window.frame.width,
                           stackFrames: stacks.map(\.frame),
                           hiddenArrangedSubviews: stacks.map { $0.arrangedSubviews.map(\.isHidden) },
                           isOverflowButtonHidden: navigationBar.overflowButton.isHidden)
    }

    /// Moving buttons in or out of the overflow menu happens during layout and needs further layout passes,
    /// so lay out until a pass changes nothing.
    @MainActor
    private func settleLayout(file: StaticString, line: UInt) {
        var previousState = layoutState
        for _ in 0..<10 {
            window.layoutIfNeeded()
            let state = layoutState
            if state == previousState {
                return
            }
            previousState = state
        }
        XCTFail("Navigation bar layout didn't settle", file: file, line: line)
    }

    @MainActor
    private func assertRequiredHorizontalSpacingIsSatisfied(file: StaticString = #filePath, line: UInt = #line) {
        let tolerance: CGFloat = 0.5
        let sideSpacing: CGFloat = 12
        let navigationButtons = navigationBar.navigationButtons.frame
        let addressBar = navigationBar.addressBarStack.frame
        let menuButtons = navigationBar.menuButtons.frame

        XCTAssertGreaterThanOrEqual(addressBar.minX - navigationButtons.maxX, sideSpacing - tolerance,
                                    "Address bar overlaps the navigation buttons", file: file, line: line)
        XCTAssertGreaterThanOrEqual(menuButtons.minX - addressBar.maxX, sideSpacing - tolerance,
                                    "Pinned buttons overlap the address bar", file: file, line: line)
        XCTAssertGreaterThanOrEqual(navigationBar.view.bounds.width - menuButtons.maxX, sideSpacing - tolerance,
                                    "Pinned buttons are clipped at the trailing edge", file: file, line: line)
    }
}
