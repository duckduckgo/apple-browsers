//
//  OverlayWindowPresenterTests.swift
//  DuckDuckGoTests
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

import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
final class OverlayWindowPresenterTests {

    @available(iOS 16.0, *)
    @Test("Revealing a blank snapshot does not change the key window", .timeLimit(.minutes(1)))
    func revealBlankSnapshotWindow() {
        let mainWindow = WindowSpy()
        mainWindow.isHidden = false
        let overlayWindow = WindowSpy()
        let presenter = OverlayWindowPresenter(mainWindow: mainWindow)

        presenter.revealBlankSnapshotWindow(overlayWindow)

        #expect(!overlayWindow.isHidden)
        #expect(overlayWindow.makeKeyAndVisibleCallCount == 0)
        #expect(!mainWindow.isHidden)
        #expect(mainWindow.makeKeyAndVisibleCallCount == 0)
    }

    @available(iOS 16.0, *)
    @Test("Revealing an interactive overlay makes it key and hides the main window", .timeLimit(.minutes(1)))
    func revealInteractiveWindow() {
        let mainWindow = WindowSpy()
        mainWindow.isHidden = false
        let overlayWindow = WindowSpy()
        let presenter = OverlayWindowPresenter(mainWindow: mainWindow)

        presenter.revealInteractiveWindow(overlayWindow)

        #expect(overlayWindow.makeKeyAndVisibleCallCount == 1)
        #expect(mainWindow.isHidden)
    }

    @available(iOS 16.0, *)
    @Test("Removing a blank snapshot does not re-key the visible main window", .timeLimit(.minutes(1)))
    func removeBlankSnapshotWindow() {
        let mainWindow = WindowSpy()
        mainWindow.isHidden = false
        let overlayWindow = WindowSpy()
        overlayWindow.isHidden = false
        let presenter = OverlayWindowPresenter(mainWindow: mainWindow)

        presenter.removeWindow(overlayWindow)

        #expect(overlayWindow.isHidden)
        #expect(mainWindow.makeKeyAndVisibleCallCount == 0)
    }

    @available(iOS 16.0, *)
    @Test("Removing an interactive overlay restores the hidden main window", .timeLimit(.minutes(1)))
    func removeInteractiveWindow() {
        let mainWindow = WindowSpy()
        mainWindow.isHidden = true
        let overlayWindow = WindowSpy()
        overlayWindow.isHidden = false
        let presenter = OverlayWindowPresenter(mainWindow: mainWindow)

        presenter.removeWindow(overlayWindow)

        #expect(overlayWindow.isHidden)
        #expect(mainWindow.makeKeyAndVisibleCallCount == 1)
    }

}

private final class WindowSpy: UIWindow {

    private(set) var makeKeyAndVisibleCallCount = 0

    override func makeKeyAndVisible() {
        makeKeyAndVisibleCallCount += 1
        isHidden = false
    }

}
