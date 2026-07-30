//
//  PromptBarPresenterTests.swift
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
import XCTest
@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class PromptBarPresenterTests: XCTestCase {

    private var content: MockPromptBarContent!
    private var presenter: PromptBarPresenter!
    private var windows: [StubPromptBarWindow] = []

    override func setUp() {
        super.setUp()
        content = MockPromptBarContent()
        presenter = PromptBarPresenter(
            content: content,
            screenProvider: StubScreenProvider(),
            makeWindow: { [weak self] rect in
                let window = StubPromptBarWindow(contentRect: rect)
                self?.windows.append(window)
                return window
            }
        )
    }

    override func tearDown() {
        windows = []
        presenter = nil
        content = nil
        super.tearDown()
    }

    func testWhenShownThenTheBarIsVisibleAndPreparedOnce() {
        presenter.show()

        XCTAssertTrue(presenter.isVisible)
        XCTAssertEqual(content.prepareCount, 1)
    }

    func testWhenDismissedThenTheContentIsResetOnce() {
        presenter.show()

        presenter.dismiss()

        XCTAssertFalse(presenter.isVisible)
        XCTAssertEqual(content.resetCount, 1)
    }

    /// Submitting reports through both `requestsSubmissionOf` and `didSubmit`, so the host asks to
    /// dismiss twice. The second must not tear down an already-dismissed bar.
    func testWhenDismissedTwiceThenTheContentIsResetOnlyOnce() {
        presenter.show()

        presenter.dismiss()
        presenter.dismiss()

        XCTAssertEqual(content.resetCount, 1)
    }

    func testWhenDismissedWithoutBeingShownThenTheContentIsNotReset() {
        presenter.dismiss()

        XCTAssertEqual(content.resetCount, 0)
    }

    func testWhenShownAgainAfterDismissalThenItReusesTheWindowAndResetsAgainOnDismissal() {
        presenter.show()
        presenter.dismiss()

        presenter.show()
        presenter.dismiss()

        XCTAssertEqual(windows.count, 1, "The panel is reused rather than rebuilt per presentation")
        XCTAssertEqual(content.resetCount, 2)
    }
}

// MARK: - Stubs

/// The unit test target fatals on any window actually reaching the screen, so ordering is stubbed and
/// visibility tracked by hand.
private final class StubPromptBarWindow: PromptBarWindow {

    private var stubbedIsVisible = false

    override var isVisible: Bool {
        get { stubbedIsVisible }
        set { stubbedIsVisible = newValue }
    }

    override func orderFrontRegardless() {
        stubbedIsVisible = true
    }

    override func orderFront(_ sender: Any?) {
        stubbedIsVisible = true
    }

    override func makeKey() {}

    override func orderOut(_ sender: Any?) {
        stubbedIsVisible = false
    }
}

private struct StubScreenProvider: PromptBarScreenProviding {
    var targetVisibleFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
}

@MainActor
private final class MockPromptBarContent: PromptBarContentHosting {

    private(set) var prepareCount = 0
    private(set) var resetCount = 0
    private(set) var focusCount = 0

    let hostedViewController = NSViewController()

    var isPresentingAuxiliaryUI = false
    var preferredWindowContentSize = NSSize(width: 680, height: 80)
    var onPreferredWindowContentSizeChanged: ((NSSize) -> Void)?
    var onSubmit: (() -> Void)?

    var viewController: NSViewController { hostedViewController }

    func prepareForPresentation() {
        prepareCount += 1
    }

    func focusPromptEditor() {
        focusCount += 1
    }

    func resetAfterDismissal() {
        resetCount += 1
    }
}
