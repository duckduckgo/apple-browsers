//
//  LaunchActionHandlerTests.swift
//  DuckDuckGo
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

import UIKit
import Testing
import Core
@testable import DuckDuckGo

final class MockURLHandler: URLHandling {

    var handleURLCalled = false
    var lastHandledURL: URL?
    var shouldProcessDeepLinkResult = true

    func handleURL(_ url: URL) {
        handleURLCalled = true
        lastHandledURL = url
    }

    func shouldProcessDeepLink(_ url: URL) -> Bool {
        shouldProcessDeepLinkResult
    }

}

final class MockShortcutItemHandler: ShortcutItemHandling {

    var handleShortcutItemCalled = false
    var lastHandledShortcutItem: UIApplicationShortcutItem?

    func handleShortcutItem(_ item: UIApplicationShortcutItem) {
        handleShortcutItemCalled = true
        lastHandledShortcutItem = item
    }

}

final class MockKeyboardPresenter: KeyboardPresenting {

    var showKeyboardOnLaunchCalled = false
    var lastBackgroundDate: Date?

    func showKeyboardOnLaunch(lastBackgroundDate: Date?) {
        showKeyboardOnLaunchCalled = true
        self.lastBackgroundDate = lastBackgroundDate
    }

}

@MainActor
final class LaunchActionHandlerTests {

    let urlHandler = MockURLHandler()
    let shortcutItemHandler = MockShortcutItemHandler()
    let keyboardPresenter = MockKeyboardPresenter()
    let pixelFiringMock = PixelFiringMock.self
    lazy var launchActionHandler = LaunchActionHandler(
        urlHandler: urlHandler,
        shortcutItemHandler: shortcutItemHandler,
        keyboardPresenter: keyboardPresenter,
        pixelFiring: pixelFiringMock
    )

    deinit {
        pixelFiringMock.tearDown()
    }

    @Test("Open URL when LaunchAction is .openURL")
    func openURL() {
        let url = URL(string: "https://example.com")!
        let action = LaunchAction.openURL(url)

        launchActionHandler.handleLaunchAction(action)

        #expect(urlHandler.handleURLCalled)
        #expect(urlHandler.lastHandledURL == url)
    }

    @Test("Do not open URL when shouldProcessDeepLink returns false")
    func doNotOpenURLWhenShouldProcessDeepLinkReturnsFalse() {
        let url = URL(string: "https://example.com")!
        let action = LaunchAction.openURL(url)

        urlHandler.shouldProcessDeepLinkResult = false

        launchActionHandler.handleLaunchAction(action)

        #expect(!urlHandler.handleURLCalled)
    }

    @Test("Handle shortcut item when LaunchAction is .handleShortcutItem")
    func handleShortcutItem() {
        let shortcutItem = UIApplicationShortcutItem(type: "TestType", localizedTitle: "Test")
        let action = LaunchAction.handleShortcutItem(shortcutItem)

        launchActionHandler.handleLaunchAction(action)

        #expect(shortcutItemHandler.handleShortcutItemCalled)
        #expect(shortcutItemHandler.lastHandledShortcutItem == shortcutItem)
    }

    @Test("Show keyboard when LaunchAction is .showKeyboard")
    func showKeyboard() {
        let date = Date()
        let action = LaunchAction.showKeyboard(date)

        launchActionHandler.handleLaunchAction(action)

        #expect(keyboardPresenter.showKeyboardOnLaunchCalled)
        #expect(keyboardPresenter.lastBackgroundDate == date)
    }

    @Test(
        "Fire App Launched From external pixel when scheme is http or https",
        arguments: [
            "http://www.example.com",
            "https://www.example.com",
        ]
    )
    func fireAppLaunchedFromExternalPixelWhenSchemeIsHttpOrHttps(_ path: String) throws {
        // GIVEN
        let url = try #require(URL(string: path))
        let action = LaunchAction.openURL(url)
        #expect(pixelFiringMock.allPixelsFired.count == 0)

        // WHEN
        launchActionHandler.handleLaunchAction(action)

        // THEN
        #expect(pixelFiringMock.allPixelsFired.count == 1)
        #expect(pixelFiringMock.allPixelsFired.first?.pixelName == Pixel.Event.appLaunchFromExternalLink.name)
    }

    @Test(
        "Fire App Launched From external pixel when scheme is http or https",
        arguments: [
            "ddgQuickLink://http://www.example.com",
            "ddgQuickLink:/https://www.example.com",
        ]
    )
    func fireAppLaunchedFromExternalPixelWhenSchemeIsDDGQuickLink(_ path: String) throws {
        // GIVEN
        let url = try #require(URL(string: path))
        let action = LaunchAction.openURL(url)
        #expect(pixelFiringMock.allPixelsFired.count == 0)

        // WHEN
        launchActionHandler.handleLaunchAction(action)

        // THEN
        #expect(pixelFiringMock.allPixelsFired.count == 1)
        #expect(pixelFiringMock.allPixelsFired.first?.pixelName == Pixel.Event.appLaunchFromShareExtension.name)
    }

}
