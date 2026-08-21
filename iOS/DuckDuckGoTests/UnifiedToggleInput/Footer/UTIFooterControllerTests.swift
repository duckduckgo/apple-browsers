//
//  UTIFooterControllerTests.swift
//  DuckDuckGo
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

import XCTest
@testable import DuckDuckGo

@MainActor
final class UTIFooterControllerTests: XCTestCase {

    private var provider: FakeUTIFooterWarningProvider!
    private var presenter: SpyUTIFooterPresenter!
    private var animationCount = 0
    private var sut: UTIFooterController!

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private lazy var fiftyPercent = UTIFooterWarning.usageThreshold(window: .weekly, threshold: .fifty, resetsAt: now.addingTimeInterval(172_800))
    private lazy var seventyFivePercent = UTIFooterWarning.usageThreshold(window: .weekly, threshold: .seventyFive, resetsAt: now.addingTimeInterval(172_800))

    override func setUp() {
        super.setUp()
        provider = FakeUTIFooterWarningProvider()
        presenter = SpyUTIFooterPresenter()
        animationCount = 0
        sut = UTIFooterController(provider: provider,
                                  dateProvider: { [unowned self] in now },
                                  animator: { [unowned self] changes in
                                      animationCount += 1
                                      changes()
                                  })
        sut.presenter = presenter
    }

    override func tearDown() {
        sut = nil
        presenter = nil
        provider = nil
        super.tearDown()
    }

    // MARK: - Refresh

    func test_refresh_presentsAMessageForTheResolvedWarning() {
        provider.warning = fiftyPercent

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("50%") ?? false)
    }

    func test_refresh_presentsNothingWhenThereIsNoWarning() {
        provider.warning = nil

        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.isEmpty)
    }

    func test_refresh_doesNotReapplyAnUnchangedMessage() {
        provider.warning = fiftyPercent

        sut.refresh()
        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertEqual(animationCount, 1)
    }

    func test_refresh_animatesEveryVisibleChange() {
        provider.warning = fiftyPercent
        sut.refresh()

        provider.warning = seventyFivePercent
        sut.refresh()

        XCTAssertEqual(animationCount, 2)
    }

    // MARK: - Dismissal

    func test_dismissCurrent_hidesTheFooter() {
        provider.warning = fiftyPercent
        sut.refresh()

        sut.dismissCurrent()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_dismissCurrent_keepsTheSameWarningHiddenOnTheNextRefresh() {
        provider.warning = fiftyPercent
        sut.refresh()
        sut.dismissCurrent()

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_dismissCurrent_doesNotHideADifferentWarning() {
        provider.warning = fiftyPercent
        sut.refresh()
        sut.dismissCurrent()

        provider.warning = seventyFivePercent
        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("75%") ?? false)
    }

    // MARK: - Suppression

    func test_setSuppressed_hidesTheFooterWithoutForgettingTheWarning() {
        provider.warning = fiftyPercent
        sut.refresh()

        sut.setSuppressed(true)

        XCTAssertEqual(presenter.appliedMessages.last, .some(nil))
    }

    func test_setSuppressed_restoresTheWarningWithoutReadingTheProviderAgain() {
        provider.warning = fiftyPercent
        sut.refresh()
        sut.setSuppressed(true)
        provider.readCount = 0

        sut.setSuppressed(false)

        XCTAssertEqual(provider.readCount, 0)
        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("50%") ?? false)
    }

    func test_refresh_presentsNothingWhileSuppressed() {
        sut.setSuppressed(true)
        provider.warning = fiftyPercent

        sut.refresh()

        XCTAssertTrue(presenter.appliedMessages.allSatisfy { $0 == nil })
    }

    // MARK: - Pose changes

    func test_resetForPoseChange_neverAppliesOrAnimatesAMessage() {
        provider.warning = fiftyPercent
        sut.refresh()

        sut.resetForPoseChange()

        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertEqual(animationCount, 1)
    }

    func test_resetForPoseChange_dropsTheViewsPendingMessage() {
        provider.warning = fiftyPercent
        sut.refresh()

        sut.resetForPoseChange()

        XCTAssertEqual(presenter.pendingClearCount, 1)
    }

    func test_refresh_afterAPoseResetWithTheWarningGone_hasNothingLeftToResurrect() {
        provider.warning = fiftyPercent
        sut.refresh()
        sut.resetForPoseChange()

        provider.warning = nil
        sut.refresh()

        // No second apply is needed precisely because the reset already dropped the view's pending copy.
        XCTAssertEqual(presenter.appliedMessages.count, 1)
        XCTAssertEqual(presenter.pendingClearCount, 1)
        XCTAssertNil(sut.currentMessage)
    }

    func test_resetForPoseChange_reappliesTheWarningOnTheNextRefresh() {
        provider.warning = fiftyPercent
        sut.refresh()
        sut.resetForPoseChange()

        sut.refresh()

        XCTAssertEqual(presenter.appliedMessages.count, 2)
        XCTAssertTrue(presenter.appliedMessages.last??.title.contains("50%") ?? false)
    }

    // MARK: - Actions

    func test_performPrimaryAction_forwardsTheMappedAction() {
        var received: [UTIFooterAction] = []
        sut.onAction = { received.append($0) }
        provider.warning = .limitReached(window: .weekly, resetsAt: now.addingTimeInterval(604_800))
        sut.refresh()

        sut.performPrimaryAction()

        XCTAssertEqual(received, [.switchModel])
    }

    func test_performPrimaryAction_doesNothingWithoutAMessage() {
        var received: [UTIFooterAction] = []
        sut.onAction = { received.append($0) }

        sut.performPrimaryAction()

        XCTAssertTrue(received.isEmpty)
    }
}

// MARK: - Test doubles

private final class FakeUTIFooterWarningProvider: UTIFooterWarningProviding {
    var warning: UTIFooterWarning?
    var readCount = 0

    func currentWarning() -> UTIFooterWarning? {
        readCount += 1
        return warning
    }
}

@MainActor
private final class SpyUTIFooterPresenter: UTIFooterPresenting {
    private(set) var appliedMessages: [UTIFooterMessage?] = []
    private(set) var pendingClearCount = 0

    func applyFooterMessage(_ message: UTIFooterMessage?) {
        appliedMessages.append(message)
    }

    func clearPendingFooterMessage() {
        pendingClearCount += 1
    }
}
