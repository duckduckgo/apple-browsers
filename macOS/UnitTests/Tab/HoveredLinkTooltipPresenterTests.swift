//
//  HoveredLinkTooltipPresenterTests.swift
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

final class HoveredLinkTooltipPresenterTests: XCTestCase {

    private let size = NSSize(width: 300, height: 28)
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 900)
    private let host = NSRect(x: 100, y: 200, width: 1000, height: 600)

    func testWhenCursorIsAwayThenTooltipStaysInsideBottomLeft() {
        let frame = tooltipFrame(mouse: NSPoint(x: 700, y: 500))
        XCTAssertEqual(frame.origin, host.origin)
    }

    func testWhenCursorOverlapsThenTooltipMovesBelowParent() {
        let mouse = NSPoint(x: 150, y: 210)
        let frame = tooltipFrame(mouse: mouse)
        XCTAssertEqual(frame.maxY, host.minY)
        XCTAssertFalse(frame.contains(mouse))
        XCTAssertTrue(screen.contains(frame))
    }

    func testWhenCursorIsAtBottomRightThenTooltipDoesNotMove() {
        let frame = tooltipFrame(mouse: NSPoint(x: 900, y: 210))
        XCTAssertEqual(frame.origin, host.origin)
    }

    func testWhenCursorReturnsToRestingFrameThenTooltipKeepsAvoidingIt() {
        let mouse = NSPoint(x: 150, y: 210)
        let first = tooltipFrame(mouse: mouse)
        XCTAssertEqual(tooltipFrame(mouse: mouse), first)
        XCTAssertEqual(tooltipFrame(mouse: NSPoint(x: 700, y: 500)).origin, host.origin)
    }

    func testWhenOnlyEnoughRoomForTooltipThenItCanStillMoveBelow() {
        let host = NSRect(x: 100, y: 28, width: 1000, height: 600)
        let frame = tooltipFrame(mouse: NSPoint(x: 150, y: 40), host: host)
        XCTAssertEqual(frame.minY, screen.minY)
        XCTAssertEqual(frame.maxY, host.minY)
    }

    func testWhenWindowIsAtScreenBottomThenTooltipMovesAboveCursor() {
        let host = NSRect(x: 100, y: 0, width: 1000, height: 600)
        let mouse = NSPoint(x: 150, y: 10)
        let frame = tooltipFrame(mouse: mouse, host: host)
        XCTAssertGreaterThan(frame.minY, mouse.y)
        XCTAssertTrue(screen.contains(frame))
    }

    func testWhenWindowIsFullscreenThenTooltipStaysOnScreenAboveCursor() {
        let mouse = NSPoint(x: 50, y: 10)
        let frame = tooltipFrame(mouse: mouse, host: screen)
        XCTAssertGreaterThan(frame.minY, mouse.y)
        XCTAssertTrue(screen.contains(frame))
    }

    func testWhenScreenHasNegativeOriginThenTooltipCanMoveBelowWindow() {
        let screen = NSRect(x: -1440, y: -900, width: 1440, height: 900)
        let host = NSRect(x: -1300, y: -700, width: 1000, height: 600)
        let frame = tooltipFrame(mouse: NSPoint(x: -1250, y: -690), host: host, screen: screen)
        XCTAssertEqual(frame.maxY, host.minY)
        XCTAssertTrue(screen.contains(frame))
    }

    func testWhenWindowExtendsPastScreenThenTooltipIsClampedHorizontally() {
        let host = NSRect(x: -100, y: 200, width: 1000, height: 600)
        let frame = tooltipFrame(mouse: NSPoint(x: 700, y: 500), host: host)
        XCTAssertEqual(frame.minX, screen.minX)
        XCTAssertTrue(screen.contains(frame))
    }

    func testWhenParentIsLowerThanContentThenTooltipMovesBelowWholeWindow() {
        let parent = NSRect(x: 100, y: 150, width: 1000, height: 650)
        let frame = HoveredLinkTooltipPresenter.frame(size: size, hostFrame: host, parentFrame: parent,
                                                     screenFrame: screen, mouseLocation: NSPoint(x: 150, y: 210))
        XCTAssertEqual(frame.maxY, parent.minY)
    }

    func testWhenMouseMovePrecedesLinkExitThenTooltipDoesNotJumpBeforeHiding() {
        let harness = TooltipHarness()
        harness.showFirstLink()
        let tooltip = harness.tooltip!
        let originalFrame = tooltip.frame
        harness.pointer.location = NSPoint(x: originalFrame.minX + 20, y: originalFrame.minY + 10)

        harness.presenter.mouseDidMove()
        XCTAssertEqual(tooltip.frame, originalFrame, "Native movement must wait for WebKit's hover update")
        harness.presenter.update(url: nil)
        // Deliberately execute the cancelled move, as if it had already been enqueued.
        harness.scheduler.run(at: 1)
        harness.presenter.updatePosition()
        XCTAssertEqual(tooltip.frame, originalFrame, "An exiting link must not reposition its tooltip")
        harness.scheduler.run(at: 2)
        XCTAssertNil(harness.tooltip)
    }

    func testWhenMouseRemainsOnSameLinkThenTooltipStillMovesAwayFromPointer() {
        let harness = TooltipHarness()
        harness.showFirstLink()
        let tooltip = harness.tooltip!
        harness.pointer.location = NSPoint(x: tooltip.frame.minX + 20, y: tooltip.frame.minY + 10)

        harness.presenter.mouseDidMove()
        harness.scheduler.run(at: 1)
        XCTAssertEqual(tooltip.frame.maxY, harness.parent.frame.minY)
        XCTAssertFalse(tooltip.frame.contains(harness.pointer.location))
        XCTAssertEqual(harness.animator.movements.last?.duration,
                       NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12)
    }

    func testWhenTooltipAppearsThenInitialPlacementIsImmediate() {
        let harness = TooltipHarness()
        harness.showFirstLink()
        XCTAssertEqual(harness.animator.movements.last?.frame, harness.tooltip?.frame)
        XCTAssertEqual(harness.animator.movements.last?.duration, 0)
    }

    func testWhenPositionIsUpdatedRepeatedlyThenMovementIsNotRestartedAndCanReverse() {
        let harness = TooltipHarness()
        harness.showFirstLink()
        let originalFrame = harness.tooltip!.frame
        harness.pointer.location = NSPoint(x: originalFrame.minX + 20, y: originalFrame.minY + 10)
        harness.presenter.updatePosition()
        let movementCount = harness.animator.movements.count
        for _ in 0..<10 {
            harness.presenter.updatePosition()
        }
        XCTAssertEqual(harness.animator.movements.count, movementCount)

        harness.pointer.location = NSPoint(x: 600, y: 500)
        harness.presenter.updatePosition()
        XCTAssertEqual(harness.animator.movements.count, movementCount + 1)
        XCTAssertEqual(harness.animator.movements.last?.frame, originalFrame)
        XCTAssertEqual(harness.animator.movements.last?.duration,
                       NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12)
    }

    func testWhenCrossingLinksRepeatedlyThenOldHideCallbacksCannotHideNewLink() {
        let harness = TooltipHarness()
        harness.showFirstLink()
        for index in 1...20 {
            harness.presenter.update(url: nil)
            let hideIndex = harness.scheduler.actions.count - 1
            let url = URL(string: "https://example.com/link-\(index)")!
            harness.presenter.update(url: url)
            harness.scheduler.run(at: hideIndex)
            XCTAssertTrue(harness.tooltip?.isVisible == true)
            XCTAssertEqual(harness.label?.stringValue, url.absoluteString)
        }
    }

    func testWhenGapOutlastsHideDelayThenNextLinkAppearsWithoutRevealDelay() {
        let harness = TooltipHarness()
        harness.showFirstLink()
        harness.presenter.update(url: nil)
        harness.scheduler.run(at: 1)
        XCTAssertNil(harness.tooltip)

        let url = URL(string: "https://example.com/second")!
        harness.presenter.update(url: url)
        XCTAssertTrue(harness.tooltip?.isVisible == true)
        XCTAssertEqual(harness.label?.stringValue, url.absoluteString)
        XCTAssertEqual(harness.scheduler.actions.count, 2, "The next link must not schedule another initial reveal")
    }

    func testWhenLeavingLinkThenTextAndBackgroundRemainTogetherUntilFadeCompletes() {
        let harness = TooltipHarness()
        harness.animator.completesImmediately = false
        harness.showFirstLink()
        let tooltip = harness.tooltip!
        let label = harness.label!
        let url = label.stringValue

        harness.presenter.update(url: nil)
        XCTAssertEqual(label.stringValue, url)
        harness.scheduler.run(at: 1)
        XCTAssertTrue(tooltip.isVisible)
        XCTAssertTrue(tooltip.parent === harness.parent)
        XCTAssertEqual(label.stringValue, url)
        XCTAssertEqual(label.alphaValue, 1)
        XCTAssertEqual(tooltip.contentView?.alphaValue, 1)
        XCTAssertEqual(harness.animator.animations.last?.opacity, 0)
        XCTAssertEqual(harness.animator.animations.last?.duration, 0.1)

        harness.animator.complete(at: 0)
        XCTAssertNil(harness.tooltip)
        XCTAssertFalse(tooltip.isVisible)
    }

    func testWhenNewLinkArrivesDuringFadeThenOldCompletionCannotDismissIt() {
        let harness = TooltipHarness()
        harness.animator.completesImmediately = false
        harness.showFirstLink()
        harness.presenter.update(url: nil)
        harness.scheduler.run(at: 1)

        let url = URL(string: "https://example.com/second")!
        harness.presenter.update(url: url)
        XCTAssertEqual(harness.animator.animations.last?.opacity, 1)
        XCTAssertEqual(harness.animator.animations.last?.duration, 0)
        harness.animator.complete(at: 0)
        XCTAssertTrue(harness.tooltip?.isVisible == true)
        XCTAssertEqual(harness.tooltip?.alphaValue, 1)
        XCTAssertEqual(harness.label?.stringValue, url.absoluteString)

        harness.presenter.update(url: nil)
        harness.scheduler.run(at: 2)
        harness.animator.complete(at: 0)
        XCTAssertNotNil(harness.tooltip, "An old completion must not finish a newer fade")
        harness.animator.complete(at: 2)
        XCTAssertNil(harness.tooltip)
    }

    func testWhenResetDuringFadeThenCompletionCannotAffectNextTooltip() {
        let harness = TooltipHarness()
        harness.animator.completesImmediately = false
        harness.showFirstLink()
        harness.presenter.update(url: nil)
        harness.scheduler.run(at: 1)
        harness.presenter.reset()
        XCTAssertNil(harness.tooltip)

        harness.presenter.update(url: URL(string: "https://example.com/second")!)
        harness.scheduler.run(at: 2)
        harness.animator.complete(at: 0)
        XCTAssertTrue(harness.tooltip?.isVisible == true)
        XCTAssertEqual(harness.tooltip?.alphaValue, 1)
    }

    func testWhenResetOccursThenAlreadyQueuedRevealCannotShowTooltip() {
        let harness = TooltipHarness()
        harness.presenter.update(url: URL(string: "https://example.com/first")!)
        harness.presenter.reset()
        harness.scheduler.run(at: 0)
        XCTAssertNil(harness.tooltip)
    }

    func testWhenAppearanceChangesThenVisibleTooltipFollowsHostWithoutMouseMovement() {
        let harness = TooltipHarness()
        let host = harness.parent.contentView!
        host.appearance = NSAppearance(named: .aqua)
        harness.showFirstLink()
        let tooltip = harness.tooltip!
        XCTAssertEqual(tooltip.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .aqua)

        host.appearance = NSAppearance(named: .darkAqua)
        XCTAssertEqual(tooltip.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
    }

    func testWhenURLFitsThenDrawingCellIncludesTheLastGlyph() {
        let harness = TooltipHarness()
        harness.showFirstLink()
        harness.presenter.update(url: URL(string: "https://calendar.mail.ru/?selectedDate=2026-10-20")!)
        let label = harness.label!
        XCTAssertGreaterThanOrEqual(label.frame.width, ceil(label.cell!.cellSize.width))
        XCTAssertGreaterThanOrEqual(harness.tooltip!.frame.width - label.frame.maxX, 8)
    }

    func testWhenURLExceedsWindowWidthThenItTruncatesInsideRightPaddingAfterResize() {
        let harness = TooltipHarness()
        harness.showFirstLink()
        harness.presenter.update(url: URL(string: "https://example.com/" + String(repeating: "long-path/", count: 100))!)
        harness.parent.setContentSize(NSSize(width: 320, height: 400))
        harness.presenter.updatePosition()
        let tooltip = harness.tooltip!
        let label = harness.label!
        XCTAssertLessThanOrEqual(tooltip.frame.width, harness.parent.contentView!.bounds.width)
        XCTAssertLessThanOrEqual(label.frame.maxX, tooltip.frame.width - 8)
        XCTAssertEqual(label.lineBreakMode, .byTruncatingTail)
        XCTAssertTrue(label.cell!.truncatesLastVisibleLine)
    }

    func testWhenParentResignsKeyClosesOrMiniaturizesThenTooltipAndQueuedMovesAreDismissed() {
        for notification in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification, NSWindow.willMiniaturizeNotification] {
            let harness = TooltipHarness()
            harness.showFirstLink()
            harness.presenter.mouseDidMove()
            NotificationCenter.default.post(name: notification, object: harness.parent)
            harness.scheduler.run(at: 1)
            XCTAssertNil(harness.tooltip, "Tooltip must detach on \(notification.rawValue)")
        }
    }

    func testWhenPresenterIsReleasedThenQueuedCallbacksDoNotRetainItOrLeaveAChildWindow() {
        _ = NSApplication.shared
        let parent = TooltipParentWindow(contentRect: NSRect(x: 100, y: 200, width: 700, height: 400),
                                         styleMask: .borderless, backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        parent.contentView = host
        let scheduler = TooltipScheduler()
        var presenter: HoveredLinkTooltipPresenter? = HoveredLinkTooltipPresenter(
            hostView: host, backgroundColor: .windowBackgroundColor, makeWindow: { TooltipTestWindow() }, schedule: scheduler.schedule
        )
        let isPresenterReleased = { [weak presenter] in presenter == nil }
        presenter?.update(url: URL(string: "https://example.com/first")!)
        scheduler.run(at: 0)
        XCTAssertNotNil(parent.childWindows?.first)
        presenter?.mouseDidMove()

        presenter = nil
        XCTAssertTrue(isPresenterReleased())
        scheduler.run(at: 1)
        let cleanup = expectation(description: "Child window is detached after presenter deallocation")
        DispatchQueue.main.async {
            XCTAssertNil(parent.childWindows?.first)
            cleanup.fulfill()
        }
        waitForExpectations(timeout: 5)
        parent.orderOut(nil)
    }

    private func tooltipFrame(mouse: NSPoint, host: NSRect? = nil, screen: NSRect? = nil) -> NSRect {
        let host = host ?? self.host
        return HoveredLinkTooltipPresenter.frame(size: size, hostFrame: host, parentFrame: host,
                                                 screenFrame: screen ?? self.screen, mouseLocation: mouse)
    }
}

private final class TooltipHarness {
    let parent: TooltipParentWindow
    let pointer = TooltipPointer()
    let scheduler = TooltipScheduler()
    let animator = TooltipAnimator()
    let presenter: HoveredLinkTooltipPresenter

    var tooltip: NSWindow? { parent.childWindows?.first }
    var label: NSTextField? { (tooltip?.contentView as? NSBox)?.contentView?.subviews.first as? NSTextField }

    init() {
        _ = NSApplication.shared
        parent = TooltipParentWindow(contentRect: NSRect(x: 100, y: 200, width: 700, height: 400),
                                     styleMask: .borderless, backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        let hostView = NSView(frame: NSRect(x: 0, y: 0, width: 700, height: 400))
        parent.contentView = hostView
        let pointer = pointer
        let scheduler = scheduler
        let animator = animator
        presenter = HoveredLinkTooltipPresenter(hostView: hostView, backgroundColor: .windowBackgroundColor,
                                               makeWindow: { TooltipTestWindow() }, mouseLocation: { pointer.location },
                                               animate: animator.animate, move: animator.move, schedule: scheduler.schedule)
    }

    deinit {
        presenter.reset()
        parent.orderOut(nil)
    }

    func showFirstLink() {
        presenter.update(url: URL(string: "https://example.com/first")!)
        scheduler.run(at: 0)
        XCTAssertTrue(tooltip?.isVisible == true)
    }
}

private final class TooltipParentWindow: NSWindow {
    private var children = [NSWindow]()
    private var isOrderedIn = true

    override var isKeyWindow: Bool { true }
    override var isVisible: Bool { isOrderedIn }

    override func orderOut(_ sender: Any?) {
        isOrderedIn = false
    }
    override var childWindows: [NSWindow]? { children.isEmpty ? nil : children }

    override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
        // AppKit orders child windows through a private path that bypasses orderFront.
        // Record the relationship instead of invoking that native ordering group.
        children.append(childWin)
        childWin.parent = self
    }

    override func removeChildWindow(_ childWin: NSWindow) {
        children.removeAll { $0 === childWin }
        childWin.parent = nil
    }
}

private final class TooltipPointer {
    var location = NSPoint(x: 600, y: 500)
}

private final class TooltipScheduler {
    private(set) var actions = [() -> Void]()

    func schedule(after delay: TimeInterval, action: @escaping () -> Void) -> DispatchWorkItem {
        actions.append(action)
        return DispatchWorkItem(block: action)
    }

    func run(at index: Int) {
        // Run even cancelled actions to verify state guards independently of GCD cancellation.
        actions[index]()
    }
}

private final class TooltipAnimator {
    var completesImmediately = true
    private(set) var animations = [(opacity: CGFloat, duration: TimeInterval, completion: () -> Void)]()
    private(set) var movements = [(frame: NSRect, duration: TimeInterval)]()

    func move(window: NSWindow, frame: NSRect, duration: TimeInterval) {
        movements.append((frame, duration))
        window.setFrame(frame, display: true)
    }

    func animate(window: NSWindow, opacity: CGFloat, duration: TimeInterval, completion: @escaping () -> Void) {
        window.alphaValue = opacity
        animations.append((opacity, duration, completion))
        if completesImmediately {
            completion()
        }
    }

    func complete(at index: Int) {
        animations[index].completion()
    }
}

/// Records presentation while keeping unit tests off screen, like the other presenter tests.
private final class TooltipTestWindow: NSWindow {
    private var isOrderedIn = false
    private weak var testParent: NSWindow?

    override var parent: NSWindow? {
        get { testParent }
        set { testParent = newValue }
    }

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
    }

    override var isVisible: Bool { isOrderedIn }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func orderFront(_ sender: Any?) {
        isOrderedIn = true
    }

    override func orderFrontRegardless() {
        isOrderedIn = true
    }

    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        isOrderedIn = place != .out
    }

    override func orderOut(_ sender: Any?) {
        isOrderedIn = false
    }
}
