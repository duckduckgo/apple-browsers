//
//  AutofillToolbarPinningPromoDelegateTests.swift
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
import FeatureFlags_macOS
import PrivacyConfig
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class AutofillToolbarPinningPromoDelegateTests: XCTestCase {

    private static let promoID = "autofill-toolbar-pinning"

    private var featureFlagger: MockFeatureFlagger!
    private var pinningManager: MockPinningManager!
    private var presenter: MockAutofillToolbarPinningPromoPresenter!
    private var sut: AutofillToolbarPinningPromoDelegate!

    override func setUp() {
        super.setUp()
        featureFlagger = MockFeatureFlagger(
            featuresStub: [FeatureFlag.promoQueueAutofillToolbarPinningPromo.rawValue: true])
        pinningManager = MockPinningManager()
        presenter = MockAutofillToolbarPinningPromoPresenter()
        sut = makeSUT(presenter: presenter)
    }

    override func tearDown() {
        sut = nil
        presenter = nil
        pinningManager = nil
        featureFlagger = nil
        super.tearDown()
    }

    private func makeSUT(presenter: MockAutofillToolbarPinningPromoPresenter?,
                         pinningManager: PinningManager? = nil) -> AutofillToolbarPinningPromoDelegate {
        let resolvedPinningManager: PinningManager = pinningManager ?? self.pinningManager
        return AutofillToolbarPinningPromoDelegate(featureFlagger: featureFlagger,
                                                   pinningManager: resolvedPinningManager,
                                                   presenterProvider: { presenter })
    }

    private func record() -> PromoHistoryRecord {
        PromoHistoryRecord(id: Self.promoID)
    }

    /// `async let` gives no guarantee the child task has reached `presentAutofillToolbarPinningPromo`
    /// by the time a single `Task.yield()` returns. Driving the mock before then leaves the
    /// continuation unresumed and the test hangs forever, so wait for the presentation to land —
    /// bounded, so a genuine regression fails fast instead of hanging CI.
    private func awaitPresentation(expectedCallCount: Int = 1,
                                   file: StaticString = #filePath,
                                   line: UInt = #line) async {
        var attempts = 0
        while presenter.presentCallCount < expectedCallCount && attempts < 1_000 {
            await Task.yield()
            attempts += 1
        }
        XCTAssertEqual(presenter.presentCallCount, expectedCallCount, "Delegate never presented", file: file, line: line)
    }

    // MARK: - Eligibility

    func testWhenFlagOnAndNotPinnedThenEligible() {
        XCTAssertTrue(sut.isEligible)
    }

    func testWhenFlagOffThenNotEligible() {
        featureFlagger.featuresStub = [FeatureFlag.promoQueueAutofillToolbarPinningPromo.rawValue: false]

        XCTAssertFalse(sut.isEligible)
    }

    /// The promo offers a shortcut the user already has, so it must not be shown once autofill is pinned.
    func testWhenAlreadyPinnedThenNotEligible() {
        pinningManager.pin(.autofill)

        XCTAssertFalse(sut.isEligible)
    }

    func testWhenFlagChangesThenEligibilityPublisherEmits() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        featureFlagger.featuresStub = [FeatureFlag.promoQueueAutofillToolbarPinningPromo.rawValue: false]
        featureFlagger.triggerUpdate()

        cancellable.cancel()
        XCTAssertEqual(received, [true, false])
    }

    /// Pinning from the toolbar's context menu while the popover is up must retract it.
    func testWhenPinnedThenEligibilityPublisherEmitsFalse() {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.sink { received.append($0) }

        pinningManager.pin(.autofill)
        NotificationCenter.default.post(name: .PinnedViewsChanged, object: nil)

        cancellable.cancel()
        XCTAssertEqual(received, [true, false])
    }

    // MARK: - Resolution paths

    /// Permanently dismissed: this promo is one-shot, so the CTA path must not leave it eligible.
    func testWhenAddShortcutPressedThenActioned() async {
        async let result = sut.show(history: record(), force: false)
        await awaitPresentation()

        presenter.complete(with: .actioned(pin: true))

        let value = await result
        XCTAssertEqual(value, .actioned)
        XCTAssertTrue(pinningManager.isPinned(.autofill))
    }

    /// "No Thanks" is still an interaction, so it resolves the same way as "Add Shortcut".
    func testWhenNoThanksPressedThenActionedAndNothingIsPinned() async {
        async let result = sut.show(history: record(), force: false)
        await awaitPresentation()

        presenter.complete(with: .actioned(pin: false))

        let value = await result
        XCTAssertEqual(value, .actioned)
        XCTAssertFalse(pinningManager.isPinned(.autofill))
    }

    /// Bare `.ignored()` is permanent, which is what the spec asks for on an outside click.
    func testWhenDismissedWithoutInteractionThenIgnoredPermanently() async {
        async let result = sut.show(history: record(), force: false)
        await awaitPresentation()

        presenter.complete(with: .dismissed)

        let value = await result
        XCTAssertEqual(value, .ignored())
    }

    /// The user never saw it, so record nothing and leave it eligible for a later trigger.
    func testWhenPresentationFailsThenShowReturnsNoChange() async {
        async let result = sut.show(history: record(), force: false)
        await awaitPresentation()

        presenter.complete(with: .notPresented)

        let value = await result
        XCTAssertEqual(value, .noChange)
    }

    /// Nothing to anchor to: end the session rather than leave the queue awaiting a continuation forever.
    func testWhenNoPresenterThenShowReturnsNoChange() async {
        sut = makeSUT(presenter: nil)

        let result = await sut.show(history: record(), force: false)

        XCTAssertEqual(result, .noChange)
    }

    /// A retraction records no state change, leaving the promo eligible on a later trigger.
    func testWhenHiddenWhileShowingThenShowReturnsNoChange() async {
        async let result = sut.show(history: record(), force: false)
        await awaitPresentation()

        sut.hide()

        let value = await result
        XCTAssertEqual(value, .noChange)
        XCTAssertEqual(presenter.dismissCallCount, 1)
    }

    /// `PromoService` calls `hide()` after recording any result, so it lands on delegates that never showed.
    func testWhenHiddenWithoutShowingThenNoCrash() {
        sut.hide()

        XCTAssertEqual(presenter.dismissCallCount, 1)
    }

    func testWhenHiddenTwiceThenNoCrash() {
        sut.hide()
        sut.hide()

        XCTAssertEqual(presenter.dismissCallCount, 2)
    }

    // MARK: - Regressions

    /// Accepting the CTA pins autofill, and `LocalPinningManager` posts `.PinnedViewsChanged`
    /// synchronously from `pin(_:)`. That drives `isEligible` to false, and `PromoService` reads a
    /// retraction as `.noChange` on its state queue — which, being first-write-wins, would land ahead
    /// of the `.actioned` result and file the promo's success as a no-op. So the delegate must not
    /// emit a retraction for a pin it performed itself.
    func testWhenAddShortcutPressedThenSelfInflictedRetractionIsNotEmitted() async {
        let notifyingPinningManager = NotifyingPinningManager()
        sut = makeSUT(presenter: presenter, pinningManager: notifyingPinningManager)

        var received: [Bool] = []
        // `PromoService.performShow` drops the current value and acts only on later emissions.
        let cancellable = sut.isEligiblePublisher.dropFirst().sink { received.append($0) }
        defer { cancellable.cancel() }

        async let result = sut.show(history: record(), force: false)
        await awaitPresentation()

        presenter.complete(with: .actioned(pin: true))

        let value = await result
        XCTAssertEqual(value, .actioned)
        XCTAssertTrue(notifyingPinningManager.isPinned(.autofill), "Add Shortcut must still pin autofill")
        XCTAssertTrue(notifyingPinningManager.didPostPinnedViewsChanged, "Test double must reproduce the synchronous notification")
        XCTAssertEqual(received, [], "The CTA's own pin must not be published as an eligibility retraction")
    }

    /// A retraction the user actually caused — pinning from the toolbar's context menu while the
    /// popover is up — must still reach the queue. Only self-inflicted ones are swallowed.
    func testWhenPinnedExternallyWhileShowingThenRetractionIsStillEmitted() async {
        var received: [Bool] = []
        let cancellable = sut.isEligiblePublisher.dropFirst().sink { received.append($0) }
        defer { cancellable.cancel() }

        async let result = sut.show(history: record(), force: false)
        await awaitPresentation()

        pinningManager.pin(.autofill)
        NotificationCenter.default.post(name: .PinnedViewsChanged, object: nil)

        XCTAssertEqual(received, [false])

        sut.hide()
        _ = await result
    }

    /// The popover can go away without a CTA: the window closes, or the view controller deallocates.
    /// This promo is `.semiModal`, which has no timeout, so a dropped completion would leave the queue
    /// awaiting a continuation that never resumes and block every medium+ promo for the session.
    func testWhenPresenterTearsDownWhileShowingThenShowResolvesAndPromoStaysEligible() async {
        async let result = sut.show(history: record(), force: false)
        await awaitPresentation()

        presenter.simulateTeardown()

        let value = await result
        XCTAssertEqual(value, .noChange)
        XCTAssertTrue(sut.isEligible, "The user made no choice, so the promo must remain eligible")

        // The queue is unblocked: a later trigger can show the promo again.
        async let secondResult = sut.show(history: record(), force: false)
        await awaitPresentation(expectedCallCount: 2)
        presenter.complete(with: .dismissed)
        let secondValue = await secondResult
        XCTAssertEqual(secondValue, .ignored())
    }

    /// The debug menu's `forceShow` bypasses the "no active session" guard that trigger evaluation
    /// applies, so `show()` can be re-entered while a continuation is live. Overwriting an unresumed
    /// `CheckedContinuation` traps, so the first show has to be resolved first.
    func testWhenShownAgainWhileShowingThenFirstShowResolves() async {
        async let firstResult = sut.show(history: record(), force: false)
        await awaitPresentation()

        async let secondResult = sut.show(history: record(), force: false)
        await awaitPresentation(expectedCallCount: 2)

        let firstValue = await firstResult
        XCTAssertEqual(firstValue, .noChange)

        presenter.complete(with: .actioned(pin: false))
        let secondValue = await secondResult
        XCTAssertEqual(secondValue, .actioned)
    }
}

/// `MockPinningManager` never posts `.PinnedViewsChanged`; `LocalPinningManager` posts it
/// synchronously from `pin(_:)`, which is the ordering the promo has to survive.
private final class NotifyingPinningManager: PinningManager {

    private(set) var didPostPinnedViewsChanged = false
    private var pinnedViews: Set<PinnableView> = []

    func togglePinning(for view: PinnableView) {
        if pinnedViews.contains(view) {
            unpin(view)
        } else {
            pin(view)
        }
    }

    func isPinned(_ view: PinnableView) -> Bool {
        pinnedViews.contains(view)
    }

    func wasManuallyToggled(_ view: PinnableView) -> Bool {
        false
    }

    func pin(_ view: PinnableView) {
        pinnedViews.insert(view)
        postPinnedViewsChanged()
    }

    func unpin(_ view: PinnableView) {
        pinnedViews.remove(view)
        postPinnedViewsChanged()
    }

    func shortcutTitle(for view: PinnableView) -> String {
        ""
    }

    private func postPinnedViewsChanged() {
        didPostPinnedViewsChanged = true
        NotificationCenter.default.post(name: .PinnedViewsChanged, object: nil)
    }
}
