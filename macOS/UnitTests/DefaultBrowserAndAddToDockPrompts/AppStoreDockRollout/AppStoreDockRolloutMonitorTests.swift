//
//  AppStoreDockRolloutMonitorTests.swift
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

import AppKit
@_spi(Testing) import PixelKit
import XCTest
@testable import DuckDuckGo_Privacy_Browser

final class AppStoreDockRolloutMonitorTests: XCTestCase {

    private let shownDate = Date(timeIntervalSince1970: 1_700_000_000)
    private let sevenDays: TimeInterval = 7 * 24 * 60 * 60

    private var dockCustomizer: DockCustomizerMock!
    private var store: InMemoryRolloutStore!
    private var center: NotificationCenter!
    private var now: Date!
    private var pixelFiring: PixelKitMock!

    override func setUp() {
        super.setUp()
        dockCustomizer = DockCustomizerMock()
        dockCustomizer.supportsAddingToDock = false
        dockCustomizer.dockStatus = false
        store = InMemoryRolloutStore()
        center = NotificationCenter()
        now = shownDate
        pixelFiring = PixelKitMock()
    }

    override func tearDown() {
        pixelFiring = nil
        now = nil
        center = nil
        store = nil
        dockCustomizer = nil
        super.tearDown()
    }

    private func makeMonitor() -> AppStoreDockRolloutMonitor {
        AppStoreDockRolloutMonitor(store: store,
                                   dockCustomization: dockCustomizer,
                                   notificationCenter: center,
                                   dateProvider: { [unowned self] in now },
                                   pixelFiring: pixelFiring)
    }

    private var firedPixels: [AppStoreDockRolloutPixel] {
        pixelFiring.actualFireCalls.compactMap { $0.pixel as? AppStoreDockRolloutPixel }
    }

    private func becomeActive() {
        center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    // MARK: - Prompt shown

    func testWhenCombinedPromptShownThenCombinedShownPixelFires() {
        let sut = makeMonitor()

        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        XCTAssertEqual(firedPixels, [.promptShown(.combined)])
        let call = pixelFiring.actualFireCalls.first
        XCTAssertEqual(call?.pixel.name, "app-store-dock-rollout_combined_prompt-shown_macos")
        XCTAssertEqual(call?.pixel.namePrefix, PixelKitNamePrefix.none)
        XCTAssertNil(call?.pixel.parameters)
        XCTAssertEqual(call?.frequency, .standard)
    }

    func testWhenSetAsDefaultPromptShownToUserNotInDockThenSetAsDefaultShownPixelFires() {
        let sut = makeMonitor()

        sut.promptShown(.setAsDefaultPrompt, promptID: "popover")

        XCTAssertEqual(firedPixels, [.promptShown(.setAsDefault)])
        XCTAssertEqual(pixelFiring.actualFireCalls.first?.pixel.name, "app-store-dock-rollout_set-as-default_prompt-shown_macos")
    }

    func testWhenUserAlreadyInDockThenNothingFires() {
        dockCustomizer.dockStatus = true
        let sut = makeMonitor()

        sut.promptShown(.setAsDefaultPrompt, promptID: "popover")
        sut.setAsDefaultRequested()

        XCTAssertTrue(firedPixels.isEmpty)
        XCTAssertNil(store.pendingCheck)
    }

    func testWhenBuildSupportsAddingToDockThenNothingFires() {
        dockCustomizer.supportsAddingToDock = true
        let sut = makeMonitor()

        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")
        sut.setAsDefaultRequested()

        XCTAssertTrue(firedPixels.isEmpty)
    }

    func testWhenAddToDockOnlyPromptShownThenNothingFires() {
        let sut = makeMonitor()

        sut.promptShown(.addToDockPrompt, promptID: "popover")
        sut.setAsDefaultRequested()

        XCTAssertTrue(firedPixels.isEmpty)
    }

    func testWhenSamePromptShownAgainThenShownPixelFiresOnce() {
        let sut = makeMonitor()

        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "banner-1")
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "banner-1")
        makeMonitor().promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "banner-1")
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "banner-2")

        XCTAssertEqual(firedPixels, [.promptShown(.combined), .promptShown(.combined)])
    }

    func testWhenSamePromptShownWithOtherContentThenShownPixelFiresForEachArm() {
        let sut = makeMonitor()

        sut.promptShown(.setAsDefaultPrompt, promptID: "banner-1")
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "banner-1")
        sut.setAsDefaultRequested()

        XCTAssertEqual(firedPixels, [.promptShown(.setAsDefault), .promptShown(.combined), .setAsDefaultRequested(.combined)])
    }

    // MARK: - Set as Default requested

    func testWhenSetAsDefaultRequestedThenRequestedPixelFiresForShownArm() {
        let sut = makeMonitor()
        sut.promptShown(.setAsDefaultPrompt, promptID: "popover")

        sut.setAsDefaultRequested()

        XCTAssertEqual(firedPixels, [.promptShown(.setAsDefault), .setAsDefaultRequested(.setAsDefault)])
        XCTAssertEqual(pixelFiring.actualFireCalls.last?.pixel.name, "app-store-dock-rollout_set-as-default_default-requested_macos")
    }

    func testWhenAlreadyCountedPromptShownAfterRelaunchThenRequestCountsForItsArm() {
        makeMonitor().promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "banner-1")

        let relaunched = makeMonitor()
        relaunched.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "banner-1")
        relaunched.setAsDefaultRequested()

        XCTAssertEqual(firedPixels, [.promptShown(.combined), .setAsDefaultRequested(.combined)])
    }

    func testWhenUserAddsToDockDuringVideoThenRequestStillCountsForCombinedArm() {
        let sut = makeMonitor()
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        dockCustomizer.dockStatus = true
        sut.setAsDefaultRequested()

        XCTAssertEqual(firedPixels.last, .setAsDefaultRequested(.combined))
        XCTAssertEqual(pixelFiring.actualFireCalls.last?.pixel.name, "app-store-dock-rollout_combined_default-requested_macos")
    }

    func testWhenSetAsDefaultRequestedTwiceForOnePromptThenRequestedPixelFiresOnce() {
        let sut = makeMonitor()
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        sut.setAsDefaultRequested()
        sut.setAsDefaultRequested()

        XCTAssertEqual(firedPixels, [.promptShown(.combined), .setAsDefaultRequested(.combined)])
    }

    func testWhenNoPromptShownThenRequestDoesNotFire() {
        let sut = makeMonitor()

        sut.setAsDefaultRequested()

        XCTAssertTrue(firedPixels.isEmpty)
    }

    // MARK: - Dock status after 7 days

    func testWhenActivatedBeforeSevenDaysThenNoDockStatusPixel() {
        let sut = makeMonitor()
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        now = shownDate.addingTimeInterval(sevenDays - 1)
        becomeActive()

        XCTAssertEqual(firedPixels, [.promptShown(.combined)])
    }

    func testWhenActivatedAfterSevenDaysInDockThenInDockPixelFiresOnce() {
        let sut = makeMonitor()
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        dockCustomizer.dockStatus = true
        now = shownDate.addingTimeInterval(sevenDays)
        becomeActive()
        becomeActive()

        XCTAssertEqual(firedPixels, [.promptShown(.combined), .inDockAfterSevenDays(.combined)])
        XCTAssertEqual(pixelFiring.actualFireCalls.last?.pixel.name, "app-store-dock-rollout_combined_in-dock-7d_macos")
    }

    func testWhenActivatedAfterSevenDaysNotInDockThenNotInDockPixelFires() {
        let sut = makeMonitor()
        sut.promptShown(.setAsDefaultPrompt, promptID: "popover")

        now = shownDate.addingTimeInterval(sevenDays + 60)
        becomeActive()

        XCTAssertEqual(firedPixels, [.promptShown(.setAsDefault), .notInDockAfterSevenDays(.setAsDefault)])
        XCTAssertEqual(pixelFiring.actualFireCalls.last?.pixel.name, "app-store-dock-rollout_set-as-default_not-in-dock-7d_macos")
    }

    func testWhenAppRelaunchesThenPendingDockCheckSurvives() {
        makeMonitor().promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        let relaunched = makeMonitor()
        now = shownDate.addingTimeInterval(sevenDays)
        becomeActive()

        XCTAssertEqual(firedPixels.last, .notInDockAfterSevenDays(.combined))
        withExtendedLifetime(relaunched) {}
    }

    func testWhenAnotherPromptShownBeforeCheckIsDueThenFirstPromptKeepsItsCheck() {
        let sut = makeMonitor()
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "banner-1")

        now = shownDate.addingTimeInterval(sevenDays / 2)
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "win-back-modal")
        now = shownDate.addingTimeInterval(sevenDays)
        becomeActive()

        XCTAssertEqual(firedPixels, [.promptShown(.combined), .promptShown(.combined), .notInDockAfterSevenDays(.combined)])
    }

    func testWhenNextPromptShownAfterCheckIsDueThenDueCheckFiresAndNewCheckStarts() {
        let sut = makeMonitor()
        sut.promptShown(.setAsDefaultPrompt, promptID: "popover")

        now = shownDate.addingTimeInterval(sevenDays * 2)
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "banner-1")

        XCTAssertEqual(firedPixels, [.promptShown(.setAsDefault), .promptShown(.combined), .notInDockAfterSevenDays(.setAsDefault)])

        now = shownDate.addingTimeInterval(sevenDays * 3)
        becomeActive()

        XCTAssertEqual(firedPixels.last, .notInDockAfterSevenDays(.combined))
    }

    func testWhenResumedAfterCheckIsDueThenDockStatusPixelFires() {
        makeMonitor().promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        now = shownDate.addingTimeInterval(sevenDays)
        makeMonitor().resume()

        XCTAssertEqual(firedPixels, [.promptShown(.combined), .notInDockAfterSevenDays(.combined)])
    }

    func testWhenResumedBeforeCheckIsDueThenNoDockStatusPixel() {
        makeMonitor().promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        now = shownDate.addingTimeInterval(sevenDays - 1)
        makeMonitor().resume()

        XCTAssertEqual(firedPixels, [.promptShown(.combined)])
    }

    // MARK: - Cancel

    func testWhenCancelledThenPendingCheckAndShownPromptAreCleared() {
        let sut = makeMonitor()
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        sut.cancel()
        sut.setAsDefaultRequested()
        now = shownDate.addingTimeInterval(sevenDays)
        becomeActive()
        sut.promptShown(.bothDefaultBrowserAndDockPrompt, promptID: "popover")

        XCTAssertEqual(firedPixels, [.promptShown(.combined), .promptShown(.combined)])
        XCTAssertEqual(store.pendingCheck, AppStoreDockRolloutPendingCheck(arm: .combined, shownDate: now))
    }
}

private final class InMemoryRolloutStore: AppStoreDockRolloutStoring {
    var pendingCheck: AppStoreDockRolloutPendingCheck?
    var lastShownPromptID: String?
}
