//
//  BrokenSitePromoDelegateTests.swift
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

import BrokenSitePrompt
import Combine
import FeatureFlags_macOS
@_spi(Testing) import PixelKit
import PrivacyConfig
import SharedTestUtilities
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class BrokenSitePromoDelegateTests: XCTestCase {

    private static let promoId = "broken-site"
    private static let sevenDays: TimeInterval = 7 * 24 * 60 * 60

    private var featureFlagger: MockFeatureFlagger!
    private var configManager: MockPrivacyConfigurationManaging!
    private var limiterStore: MockBrokenSitePromptLimiterStore!
    private var limiter: BrokenSitePromptLimiter!
    private var windowControllersManager: WindowControllersManagerMock!
    private var pixelFiring: PixelKitMock!
    private var sut: BrokenSitePromoDelegate!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger(featuresStub: [FeatureFlag.promoQueueBrokenSitePromo.rawValue: true])
        configManager = MockPrivacyConfigurationManaging()
        // The limiter also gates on `.brokenSitePrompt` being enabled in the privacy config, independent
        // of the promo's own feature flag. `MockPrivacyConfiguration` treats every feature as enabled by
        // default, so this just documents that requirement rather than changing behavior.
        configManager.mockConfig.isFeatureEnabledCheck = { feature, _ in feature == .brokenSitePrompt }
        limiterStore = MockBrokenSitePromptLimiterStore()
        limiter = BrokenSitePromptLimiter(privacyConfigManager: configManager, store: limiterStore)
        windowControllersManager = WindowControllersManagerMock()
        pixelFiring = PixelKitMock()
        sut = BrokenSitePromoDelegate(featureFlagger: featureFlagger,
                                      limiter: limiter,
                                      windowControllersManager: windowControllersManager,
                                      pixelFiring: pixelFiring)
    }

    override func tearDown() {
        sut = nil
        pixelFiring = nil
        windowControllersManager = nil
        limiter = nil
        limiterStore = nil
        configManager = nil
        featureFlagger = nil
        super.tearDown()
    }

    private var history: PromoHistoryRecord { PromoHistoryRecord(id: Self.promoId) }

    // MARK: - Eligibility

    func testWhenFlagOnAndLimiterAllowsThenEligible() {
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenFlagOffThenNotEligible() {
        featureFlagger.featuresStub = [FeatureFlag.promoQueueBrokenSitePromo.rawValue: false]

        XCTAssertFalse(sut.isEligible)
    }

    /// The limiter stays the authority on receptiveness: within its cooldown, the promo is ineligible
    /// even though promo history is empty. This is what stops users mid-cooldown re-seeing the prompt
    /// on the release that migrates it.
    func testWhenLimiterWithinCooldownThenNotEligible() {
        limiter.didShowToast()

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenLimiterDismissStreakExceededThenNotEligible() {
        limiter.didDismissToast()
        limiter.didDismissToast()
        limiter.didDismissToast()
        limiterStore.lastToastShownDate = Date().addingTimeInterval(-Self.sevenDays - 1)

        XCTAssertFalse(sut.isEligible)
    }

    func testEligibilityPublisherReplaysCurrentValue() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        XCTAssertEqual(received, [true])
        cancellable.cancel()
    }

    // MARK: - Presentation failure

    /// Resolving on presentation failure matters: returning while still suspended would leak the awaiting task.
    func testWhenNoKeyWindowThenResolvesWithNoChangeAndDoesNotTouchLimiter() async {
        let result = await sut.show(history: history, force: false)

        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(limiterStore.lastToastShownDate, .distantPast)
        XCTAssertEqual(limiterStore.toastDismissStreakCounter, 0)
        XCTAssertTrue(pixelFiring.actualFireCalls.isEmpty)
    }

    // MARK: - hide()

    func testWhenHideCalledBeforeShowThenItIsANoOp() {
        sut.hide()
        sut.hide()

        XCTAssertEqual(limiterStore.toastDismissStreakCounter, 0)
    }

    // MARK: - Presentation-dependent paths
    //
    // `lastKeyMainWindowController` is a protocol extension computed over `mainWindowControllers`
    // (WindowControllersManager.swift:85-99), and `WindowControllersManagerMock.mainWindowControllers`
    // is a plain settable `var`. Populating it with a real `MainWindowController` built over a
    // `MockWindow` (whose `isKeyWindow` is `true` by default) makes `show()`'s guard pass with no
    // production seam, so the CTA, dismissal and retraction paths are exercisable after all.

    /// Tapping the CTA must resolve `.ignored(cooldown:)`, never `.actioned` — this is a recurring
    /// promo, and `.actioned` would silence it permanently for exactly the users who engaged. It must
    /// also not *also* record a dismissal: production's `onDismiss` still fires afterwards (SwiftUI's
    /// button calls `dismissAction` right after the tap action), and without the `isResolved`/session
    /// guard this would double-count as both an action and a dismissal.
    func testWhenCTATappedThenResolvesIgnoredAndDoesNotAlsoRecordDismissal() async throws {
        let mainWindowController = installKeyMainWindow(withTabURL: Self.nonDuckDuckGoURL)
        let showTask = Task { await self.sut.show(history: self.history, force: false) }
        let popover = try await waitForPopover(in: mainWindowController)

        popover.viewModel.buttonAction?()
        // Tapping the button also dismisses the popover in production: SwiftUI's `Button` calls
        // `viewModel.dismissAction?()` right after the action closure, which cascades into
        // `viewDidDisappear` — simulate that cascade directly rather than driving real AppKit dismissal.
        popover.viewDidDisappear()

        let result = await showTask.value
        XCTAssertEqual(result, .ignored(cooldown: limiter.coolDownInterval))
        XCTAssertEqual(limiterStore.toastDismissStreakCounter, 0, "the CTA must not also record a dismissal")
        XCTAssertEqual(pixelFiring.actualFireCalls.map(\.pixel.name),
                      [GeneralPixel.siteNotWorkingShown.name, GeneralPixel.siteNotWorkingWebsiteIsBroken.name])
    }

    /// The regression test for the `isResolved`-never-reset bug: a shared instance flag stayed `true`
    /// forever after the first resolution, so the second show's `onDismiss` bailed out silently —
    /// `didDismissToast()` never ran again, and the continuation it should have resolved was left
    /// suspended forever. Confirmed failing against the unfixed delegate first (see task-5-report.md).
    func testWhenShowsHappenTwiceEachDismissalIsRecordedAndResolved() async throws {
        let mainWindowController = installKeyMainWindow(withTabURL: Self.nonDuckDuckGoURL)

        let firstShow = Task { await self.sut.show(history: self.history, force: false) }
        let firstPopover = try await waitForPopover(in: mainWindowController)
        firstPopover.viewDidDisappear()
        let firstResult = await firstShow.value
        XCTAssertEqual(firstResult, .ignored(cooldown: limiter.coolDownInterval))
        XCTAssertEqual(limiterStore.toastDismissStreakCounter, 1)

        // The limiter's own cooldown/streak bookkeeping isn't what's under test here — clear it so
        // `isEligible` (and thus a second, independent `show()`) isn't blocked by the first show.
        limiterStore.lastToastShownDate = .distantPast

        let secondShow = Task { await self.sut.show(history: self.history, force: false) }
        let secondPopover = try await waitForPopover(in: mainWindowController)
        secondPopover.viewDidDisappear()
        let secondResult = await secondShow.value
        XCTAssertEqual(secondResult, .ignored(cooldown: limiter.coolDownInterval))
        XCTAssertEqual(limiterStore.toastDismissStreakCounter, 2, "the second dismissal must still be recorded")
    }

    /// A retraction (`PromoService` calling `hide()` mid-show, e.g. because a higher-priority promo
    /// pre-empted it) must resolve `.noChange` and tear the popover down without recording a
    /// dismissal — the user never acted on it either way.
    func testWhenHideCalledWhileShowingThenResolvesNoChangeAndDoesNotRecordDismissal() async throws {
        let mainWindowController = installKeyMainWindow(withTabURL: Self.nonDuckDuckGoURL)
        let showTask = Task { await self.sut.show(history: self.history, force: false) }
        let popover = try await waitForPopover(in: mainWindowController)

        sut.hide()

        let result = await showTask.value
        XCTAssertEqual(result, .noChange)
        XCTAssertEqual(limiterStore.toastDismissStreakCounter, 0)
        XCTAssertNil(popover.presentingViewController, "hide() must tear the popover down")
    }
}

private enum BrokenSitePromoDelegateTestsError: Error {
    case timedOutWaitingForPopover
}

private extension BrokenSitePromoDelegateTests {

    static let nonDuckDuckGoURL = URL(string: "https://broken-site.example")!

    /// Builds a real `MainWindowController` over a `MockWindow` (key by default, per
    /// `MockWindow.isKeyWindow`) and registers it as the mock manager's only window, so
    /// `show()`'s `lastKeyMainWindowController` guard passes and popover presentation is real —
    /// mirrors `FireDialogViewModelTests.registerMainWindow`.
    @MainActor
    func installKeyMainWindow(withTabURL url: URL) -> MainWindowController {
        let tab = Tab(content: .url(url, source: .link))
        let tabCollectionViewModel = TabCollectionViewModel(tabCollection: TabCollection(tabs: [tab]))
        let mainViewController = MainViewController(
            tabCollectionViewModel: tabCollectionViewModel,
            autofillPopoverPresenter: DefaultAutofillPopoverPresenter(pinningManager: MockPinningManager()),
            aiChatSessionStore: AIChatSessionStore(featureFlagger: MockFeatureFlagger())
        )
        let window = MockWindow(isVisible: false)
        let mainWindowController = MainWindowController(
            window: window,
            mainViewController: mainViewController,
            fireViewModel: Application.appDelegate.fireCoordinator.fireViewModel,
            themeManager: MockThemeManager()
        )
        windowControllersManager.mainWindowControllers = [mainWindowController]
        return mainWindowController
    }

    /// Polls for the popover `show()` presents, since presentation happens synchronously inside
    /// `show()` before it suspends, but the `Task` wrapping that `await` call is scheduled, not run,
    /// by the time control returns to the test.
    @MainActor
    func waitForPopover(in mainWindowController: MainWindowController, timeout: TimeInterval = 2) async throws -> PopoverMessageViewController {
        let navigationBarViewController = mainWindowController.mainViewController.navigationBarViewController
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let popover = navigationBarViewController.presentedViewControllers?
                .compactMap({ $0 as? PopoverMessageViewController }).first {
                return popover
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw BrokenSitePromoDelegateTestsError.timedOutWaitingForPopover
    }
}
