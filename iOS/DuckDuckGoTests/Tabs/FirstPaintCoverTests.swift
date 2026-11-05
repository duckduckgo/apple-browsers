//
//  FirstPaintCoverTests.swift
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

import Testing
import UIKit
@testable import DuckDuckGo

@MainActor
struct FirstPaintCoverTests {

    private static let firstLayout: UInt = 1 << 0
    private static let firstVisuallyNonEmptyLayout: UInt = 1 << 1
    private static let didRenderSignificantAmountOfText: UInt = 1 << 7
    private static let firstMeaningfulPaint: UInt = 1 << 8

    /// Holds scheduled timeouts and pending fades so tests decide when each one fires.
    @MainActor
    private final class Harness {
        var timeouts: [(delay: TimeInterval, action: @MainActor () -> Void, isCancelled: Bool)] = []
        var pendingFades: [@MainActor () -> Void] = []
        var handoffs: [(snapshot: UIView?, destinationColor: UIColor?)] = []
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let webView = UIView()
        lazy var cover = FirstPaintCover(
            scheduler: { [unowned self] delay, action in
                let index = self.timeouts.count
                self.timeouts.append((delay, action, false))
                return { [unowned self] in self.timeouts[index].isCancelled = true }
            },
            fadeOut: { [unowned self] _, completion in
                self.pendingFades.append(completion)
                return nil
            },
            animateHandoff: { [unowned self] _, snapshot, destinationColor in
                self.handoffs.append((snapshot, destinationColor))
                return []
            })

        init() {
            container.addSubview(webView)
        }

        var isCoverInHierarchy: Bool { cover.coverView?.superview === container }

        func fireLatestTimeout() {
            guard let timeout = timeouts.last, !timeout.isCancelled else { return }
            timeout.action()
        }

        func finishFades() {
            let fades = pendingFades
            pendingFades = []
            fades.forEach { $0() }
        }
    }

    @Test("Arming covers the web view straight away")
    func armingCoversWebView() {
        let harness = Harness()

        harness.cover.arm(in: harness.container, above: harness.webView)

        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.isCoverInHierarchy)
        #expect(harness.container.subviews.last === harness.cover.coverView)
        #expect(harness.cover.coverView?.frame == harness.container.bounds)
        #expect(harness.cover.coverView?.alpha == 1)
    }

    @Test("Paint milestones before commit belong to the old page and are ignored")
    func paintBeforeCommitIsIgnored() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.renderingProgressDidChange(Self.firstVisuallyNonEmptyLayout)

        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.pendingFades.isEmpty)
    }

    @Test("First visually non-empty layout starts a short wait for real content",
          arguments: [firstVisuallyNonEmptyLayout, firstLayout | firstVisuallyNonEmptyLayout])
    func firstLayoutStartsGrace(events: UInt) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didCommit()

        harness.cover.renderingProgressDidChange(events)

        #expect(harness.cover.phase == .awaitingMeaningfulPaint)
        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.meaningfulPaintGrace)
        #expect(harness.pendingFades.isEmpty)
    }

    @Test("Meaningful content after first layout reveals the page",
          arguments: [firstMeaningfulPaint, didRenderSignificantAmountOfText])
    func meaningfulContentAfterFirstLayoutReveals(events: UInt) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didCommit()
        harness.cover.renderingProgressDidChange(Self.firstVisuallyNonEmptyLayout)

        harness.cover.renderingProgressDidChange(events)

        #expect(harness.cover.phase == .idle)
        #expect(harness.pendingFades.count == 1)
        #expect(harness.isCoverInHierarchy, "stays up while fading")

        harness.finishFades()
        #expect(!harness.isCoverInHierarchy)
    }

    @Test("Meaningful content without a first-layout event still reveals",
          arguments: [firstMeaningfulPaint, firstVisuallyNonEmptyLayout | firstMeaningfulPaint])
    func meaningfulContentAloneReveals(events: UInt) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didCommit()

        harness.cover.renderingProgressDidChange(events)

        #expect(harness.cover.phase == .idle)
    }

    @Test("The grace window reveals when meaningful paint never arrives")
    func graceWindowReveals() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didCommit()
        harness.cover.renderingProgressDidChange(Self.firstVisuallyNonEmptyLayout)

        harness.fireLatestTimeout()

        #expect(harness.cover.phase == .idle)
        #expect(harness.pendingFades.count == 1)
    }

    @Test("First layout alone keeps the cover", arguments: [firstLayout])
    func firstLayoutKeepsCover(events: UInt) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didCommit()

        harness.cover.renderingProgressDidChange(events)

        #expect(harness.cover.phase == .awaitingPaint)
    }

    @Test("A cancelled navigation keeps the cover for the load that replaces it")
    func cancelledNavigationKeepsCover() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.navigationDidFail(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))

        #expect(harness.cover.phase == .awaitingCommit)
    }

    @Test("A failed navigation reveals so the error page can show",
          arguments: [NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
                      NSError(domain: "WebKitErrorDomain", code: 102)])
    func failedNavigationReveals(error: NSError) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.navigationDidFail(error)

        #expect(harness.cover.phase == .idle)
        #expect(harness.pendingFades.count == 1)
    }

    @Test("The timeout reveals when no paint arrives")
    func timeoutReveals() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.fireLatestTimeout()

        #expect(harness.cover.phase == .idle)
        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.timeout)
    }

    @Test("Commit restarts the timeout and cancels the earlier one")
    func commitRestartsTimeout() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.didCommit()

        #expect(harness.timeouts.count == 2)
        #expect(harness.timeouts[0].isCancelled)
        #expect(!harness.timeouts[1].isCancelled)
    }

    @Test("Revealing cancels the pending timeout")
    func revealCancelsTimeout() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didCommit()

        harness.cover.renderingProgressDidChange(Self.firstMeaningfulPaint)

        let allCancelled = harness.timeouts.allSatisfy { $0.isCancelled }
        #expect(allCancelled)
    }

    @Test("Re-arming mid-fade keeps the cover up at full opacity")
    func rearmDuringFadeKeepsCover() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didCommit()
        harness.cover.renderingProgressDidChange(Self.firstMeaningfulPaint)
        harness.cover.coverView?.alpha = 0.4

        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.finishFades()

        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.isCoverInHierarchy)
        #expect(harness.cover.coverView?.alpha == 1)
    }

    @Test("Cancel removes the cover at once")
    func cancelRemovesImmediately() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.cancel()

        #expect(harness.cover.phase == .idle)
        #expect(!harness.isCoverInHierarchy)
        #expect(harness.pendingFades.isEmpty)
    }

    @Test("The exit snapshot sits on the cover where the panel was, and the hand-off gets the page colour")
    func handoffPlacesSnapshotAndPassesColor() {
        let harness = Harness()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 900))
        window.addSubview(harness.container)
        harness.container.frame.origin = CGPoint(x: 0, y: 100)
        let snapshot = UIView()
        let panelFrame = CGRect(x: 0, y: 60, width: 400, height: 840)

        harness.cover.arm(in: harness.container, above: harness.webView,
                          handoff: .init(exitSnapshot: snapshot, exitSnapshotWindowFrame: panelFrame, destinationColor: .red))

        #expect(snapshot.superview === harness.cover.coverView)
        #expect(snapshot.frame == CGRect(x: 0, y: -40, width: 400, height: 840))
        #expect(harness.handoffs.count == 1)
        #expect(harness.handoffs.first?.snapshot === snapshot)
        #expect(harness.handoffs.first?.destinationColor == .red)
    }

    @Test("Arming starts from the panel colour so the hand-off is invisible")
    func armStartsFromPanelColor() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.coverView?.backgroundColor = .blue

        harness.cover.arm(in: harness.container, above: harness.webView)

        #expect(harness.cover.coverView?.backgroundColor == FirstPaintCover.Constants.baseColor)
    }

    @Test("Re-arming replaces the previous exit snapshot")
    func rearmReplacesSnapshot() {
        let harness = Harness()
        let first = UIView()
        let second = UIView()

        harness.cover.arm(in: harness.container, above: harness.webView, handoff: .init(exitSnapshot: first))
        harness.cover.arm(in: harness.container, above: harness.webView, handoff: .init(exitSnapshot: second))

        #expect(first.superview == nil)
        #expect(second.superview === harness.cover.coverView)
    }

    @Test("Revealing removes the exit snapshot with the cover",
          arguments: [true, false])
    func revealRemovesSnapshot(animated: Bool) {
        let harness = Harness()
        let snapshot = UIView()
        harness.cover.arm(in: harness.container, above: harness.webView, handoff: .init(exitSnapshot: snapshot))

        if animated {
            harness.cover.didCommit()
            harness.cover.renderingProgressDidChange(Self.firstMeaningfulPaint)
            harness.finishFades()
        } else {
            harness.cover.cancel()
        }

        #expect(snapshot.superview == nil)
        #expect(harness.cover.exitSnapshotView == nil)
    }

    @Test("Callbacks without an armed cover do nothing")
    func idleCallbacksDoNothing() {
        let harness = Harness()

        harness.cover.didCommit()
        harness.cover.renderingProgressDidChange(Self.firstVisuallyNonEmptyLayout)
        harness.cover.navigationDidFail(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut))
        harness.cover.cancel()

        #expect(harness.cover.phase == .idle)
        #expect(harness.cover.coverView == nil)
        #expect(harness.timeouts.isEmpty)
    }
}
