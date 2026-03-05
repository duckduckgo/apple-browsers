//
//  SparkleUpdateMenuItemFactoryTests.swift
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

import AppUpdaterShared
import Cocoa
import Combine
import Navigation
import Persistence
import PixelKit
import UserScript
import WebKit
import XCTest

@testable import DuckDuckGo_Privacy_Browser

final class SparkleUpdateMenuItemFactoryTests: XCTestCase {

    private var mockController: MockSparkleUpdateController!

    override func setUp() {
        super.setUp()
        mockController = MockSparkleUpdateController()
    }

    override func tearDown() {
        mockController = nil
        super.tearDown()
    }

    // MARK: - Title Tests

    func testMenuItemTitle_WhenNotAtRestartCheckpoint_ShowsNewVersionAvailable() {
        mockController.isAtRestartCheckpoint = false

        let menuItem = SparkleUpdateMenuItemFactory.menuItem(for: mockController)

        XCTAssertEqual(menuItem.title, UserText.updateNewVersionAvailableMenuItem)
    }

    func testMenuItemTitle_WhenAtRestartCheckpoint_ShowsUpdateReady() {
        mockController.isAtRestartCheckpoint = true

        let menuItem = SparkleUpdateMenuItemFactory.menuItem(for: mockController)

        XCTAssertEqual(menuItem.title, UserText.updateReadyMenuItem)
    }

    // MARK: - Target & Action Tests

    func testMenuItemTarget_IsThePassedInController() {
        let menuItem = SparkleUpdateMenuItemFactory.menuItem(for: mockController)

        XCTAssertTrue(menuItem.target === mockController)
    }

    func testMenuItemAction_IsRunUpdateFromMenuItem() {
        let menuItem = SparkleUpdateMenuItemFactory.menuItem(for: mockController)

        XCTAssertEqual(menuItem.action, #selector(SparkleUpdateControllerObjC.runUpdateFromMenuItem))
    }

    // MARK: - Image Test

    func testMenuItemImage_IsUpdateMenuItemIcon() {
        let menuItem = SparkleUpdateMenuItemFactory.menuItem(for: mockController)

        XCTAssertEqual(menuItem.image?.pngData(), NSImage.updateMenuItemIcon.pngData())
    }
}

// MARK: - Mock

private final class MockSparkleUpdateController: NSObject, SparkleUpdateControlling {

    var isAtRestartCheckpoint = false

    // MARK: - SparkleUpdateControlling

    var willRelaunchAppPublisher: AnyPublisher<Void, Never> {
        Empty().eraseToAnyPublisher()
    }

    func checkForUpdateRespectingRollout() { fatalError("Not expected") }
    func checkNewApplicationVersionIfNeeded(updateProgress: UpdateCycleProgress) { fatalError("Not expected") }
    func log() {}

    func makeReleaseNotesNavigationResponder(
        releaseNotesURL: URL,
        scriptsPublisher: some Publisher<any ReleaseNotesUserScriptProvider, Never>,
        webViewPublisher: some Publisher<WKWebView, Never>
    ) -> any NavigationResponder & AnyObject {
        fatalError("Not expected")
    }

    func makeReleaseNotesUserScript(
        pixelFiring: PixelFiring?,
        keyValueStore: ThrowingKeyValueStoring,
        releaseNotesURL: URL
    ) -> Subfeature {
        fatalError("Not expected")
    }

    // MARK: - SparkleUpdateControllerObjC

    func runUpdateFromMenuItem() { fatalError("Not expected") }

    // MARK: - UpdateController

    @Published var latestUpdate: Update?
    var latestUpdatePublisher: Published<Update?>.Publisher { $latestUpdate }

    @Published var hasPendingUpdate = false
    var hasPendingUpdatePublisher: Published<Bool>.Publisher { $hasPendingUpdate }

    var mustShowUpdateIndicators = false
    var needsNotificationDot = false
    var notificationDotPublisher: AnyPublisher<Bool, Never> { Just(false).eraseToAnyPublisher() }
    var clearsNotificationDotOnMenuOpen = true
    var lastUpdateCheckDate: Date?
    var lastUpdateNotificationShownDate = Date.distantPast

    @Published var updateProgress: UpdateCycleProgress = .updateCycleNotStarted
    var updateProgressPublisher: Published<UpdateCycleProgress>.Publisher { $updateProgress }

    var areAutomaticUpdatesEnabled = false
    var notificationPresenter: any UpdateNotificationPresenting = MockUpdateNotificationPresenter()

    func runUpdate() { fatalError("Not expected") }
    func checkForUpdateSkippingRollout() { fatalError("Not expected") }

    // MARK: - UpdateControllerObjC

    func openUpdatesPage() { fatalError("Not expected") }
    func handleAppTermination() {}
}

private final class MockUpdateNotificationPresenter: UpdateNotificationPresenting {
    func showUpdateNotification(for status: AppUpdateStatus) {}
    func showUpdateNotification(for type: Update.UpdateType, areAutomaticUpdatesEnabled: Bool) {}
    func dismissIfPresented() {}
    func openUpdatesPage() {}
}
