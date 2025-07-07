//
//  BarsAnimatorTests.swift
//  DuckDuckGo
//
//  Copyright © 2022 DuckDuckGo. All rights reserved.
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
import PrivacyDashboard

@testable import DuckDuckGo

class BarsAnimatorTests: XCTestCase {

    func testDidStartScrollingUpdatesPositionCorrectly() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()
        let initialYposition = sut.draggingStartPosY

        scrollView.contentOffset.y = -100
        sut.didStartScrolling(in: scrollView)

        XCTAssertEqual(initialYposition, 0.0)
        XCTAssertEqual(sut.draggingStartPosY, -100)

        XCTAssertEqual(delegate.receivedMessages, [])
    }

    func testBarStateRevealedWhenScrollDownUpdatesToHiddenState() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = 200
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning)

        scrollView.contentOffset.y = 300
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0))

    }

    func testBarStateHiddenWhenScrollDownKeepsHiddenState() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = 200
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning)

        scrollView.contentOffset.y = 300
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)

        scrollView.contentOffset.y = 100
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)

        XCTAssertEqual(delegate.receivedMessages.count, 2)
        XCTAssertLessThan(delegate.receivedMessages.first?.percent ?? 2.0, 1.0, "Message should be .setBarsVisibility(< 1.0), got \(delegate.receivedMessages)")
        XCTAssertEqual(delegate.receivedMessages.last, .setBarsVisibility(0.0), "Message should be .setBarsVisibility(0.0), got \(delegate.receivedMessages)")
    }

    func testBarStateHiddenWhenScrollUpUpdatesToRevealedState() throws {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = 200
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning)

        scrollView.contentOffset.y = 400
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .hidden)

        scrollView.contentOffset.y = -100
        sut.didStartScrolling(in: scrollView)
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .transitioning)

        scrollView.contentOffset.y = -150
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        // Verify message pattern: first some 0.0 values, then some 1.0 values
        XCTAssertTrue(delegate.receivedMessages.count >= 4, "Expected at least 4 messages, got \(delegate.receivedMessages.count)")

        // Find where the transition from 0.0 to 1.0 happens
        let transitionIndex = delegate.receivedMessages.firstIndex {
            if case .setBarsVisibility(1.0) = $0 { return true } else { return false }
        }

        let index = try XCTUnwrap(transitionIndex, "Expected to find at least one .setBarsVisibility(1.0) message")

        // Check that all messages before transition are 0.0
        let beforeTransition = delegate.receivedMessages[0..<index]
        XCTAssertTrue(beforeTransition.allSatisfy { $0.percent ?? 2.0 <= 1 },
                      "All messages before transition should be .setBarsVisibility(<= 1), got \(beforeTransition)")

        // Check that all messages after and including transition are 1.0
        let afterTransition = delegate.receivedMessages[index...]
        XCTAssertTrue(afterTransition.allSatisfy { $0 == .setBarsVisibility(1.0) },
                      "All messages after transition should be .setBarsVisibility(1.0), got \(afterTransition)")
    }

    func testBarStateRevealedWhenScrollUpDoNotChangeCurrentState() {
        let (sut, delegate) = makeSUT()
        let scrollView = mockScrollView()

        scrollView.contentOffset.y = 100
        sut.didStartScrolling(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = 50
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        scrollView.contentOffset.y = -50
        sut.didScroll(in: scrollView)
        XCTAssertEqual(sut.barsState, .revealed)

        XCTAssertEqual(delegate.receivedMessages, [])
    }
}

// MARK: - Helpers

private func makeSUT() -> (sut: BarsAnimator, delegate: BrowserChromeDelegateMock) {
    let sut = BarsAnimator()
    let delegate = BrowserChromeDelegateMock()
    sut.delegate = delegate

    return (sut, delegate)
}

private func mockScrollView() -> UIScrollView {
    let scrollView = UIScrollView()
    scrollView.contentSize = .init(width: 300, height: 600)
    scrollView.bounds = .init(x: 0, y: 0, width: 300, height: 300)

    return scrollView
}

private class BrowserChromeDelegateMock: BrowserChromeDelegate {
    func setBarsHidden(_ hidden: Bool, animated: Bool, customAnimationDuration: CGFloat?) {
        setBarsHidden(hidden, animated: animated)
    }

    func setBarsVisibility(_ percent: CGFloat, animated: Bool, animationDuration: CGFloat?) {
        setBarsVisibility(percent, animated: animated)
    }

    enum Message: Equatable {
        case setBarsHidden(Bool)
        case setNavigationBarHidden(Bool)
        case setBarsVisibility(CGFloat)
        case setRefreshControlEnabled(Bool)

        var percent: CGFloat? {
            switch self {
            case .setBarsVisibility(let value):
                return value
            default:
                return nil
            }
        }
    }

    var receivedMessages: [Message] = []

    func setBarsHidden(_ hidden: Bool, animated: Bool) {
        receivedMessages.append(.setBarsHidden(hidden))
    }

    func setNavigationBarHidden(_ hidden: Bool) {
        receivedMessages.append(.setNavigationBarHidden(hidden))
    }

    func setBarsVisibility(_ percent: CGFloat, animated: Bool) {
        receivedMessages.append(.setBarsVisibility(percent))
    }

    func setRefreshControlEnabled(_ isEnabled: Bool) {
        receivedMessages.append(.setRefreshControlEnabled(isEnabled))
    }

    var canHideBars: Bool = false

    var isToolbarHidden: Bool = false

    var toolbarHeight: CGFloat = 0

    var barsMaxHeight: CGFloat = 0

    var omniBar: OmniBar = {
        let omniBar = MockOmniBar()
        omniBar.mockBarView.expectedHeight = 52
        return omniBar
    }()

    var tabBarContainer: UIView = UIView()
}
