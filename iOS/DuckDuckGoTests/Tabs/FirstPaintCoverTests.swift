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
        /// Stands in for the WKNavigation of the covered load.
        let navigation = NSObject()
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

        func startAndCommit() {
            cover.didStartNavigation(navigation)
            cover.didCommit(navigation)
        }

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

    @available(iOS 16, macOS 13, *)
    @Test("Arming covers the web view straight away", .timeLimit(.minutes(1)))
    func armingCoversWebView() {
        let harness = Harness()

        harness.cover.arm(in: harness.container, above: harness.webView)

        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.isCoverInHierarchy)
        #expect(harness.container.subviews.last === harness.cover.coverView)
        #expect(harness.cover.coverView?.frame == harness.container.bounds)
        #expect(harness.cover.coverView?.alpha == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Paint milestones before commit belong to the old page and are ignored", .timeLimit(.minutes(1)))
    func paintBeforeCommitIsIgnored() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.renderingProgressDidChange(Self.firstVisuallyNonEmptyLayout)

        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.pendingFades.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("First visually non-empty layout starts a short wait for real content", .timeLimit(.minutes(1)),
          arguments: [firstVisuallyNonEmptyLayout, firstLayout | firstVisuallyNonEmptyLayout])
    func firstLayoutStartsGrace(events: UInt) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.startAndCommit()

        harness.cover.renderingProgressDidChange(events)

        #expect(harness.cover.phase == .awaitingMeaningfulPaint)
        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.meaningfulPaintGrace)
        #expect(harness.pendingFades.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Meaningful content after first layout reveals the page", .timeLimit(.minutes(1)),
          arguments: [firstMeaningfulPaint, didRenderSignificantAmountOfText])
    func meaningfulContentAfterFirstLayoutReveals(events: UInt) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.startAndCommit()
        harness.cover.renderingProgressDidChange(Self.firstVisuallyNonEmptyLayout)

        harness.cover.renderingProgressDidChange(events)

        #expect(harness.cover.phase == .idle)
        #expect(harness.pendingFades.count == 1)
        #expect(harness.isCoverInHierarchy, "stays up while fading")

        harness.finishFades()
        #expect(!harness.isCoverInHierarchy)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Meaningful content without a first-layout event still reveals", .timeLimit(.minutes(1)),
          arguments: [firstMeaningfulPaint, firstVisuallyNonEmptyLayout | firstMeaningfulPaint])
    func meaningfulContentAloneReveals(events: UInt) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.startAndCommit()

        harness.cover.renderingProgressDidChange(events)

        #expect(harness.cover.phase == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The grace window reveals when meaningful paint never arrives", .timeLimit(.minutes(1)))
    func graceWindowReveals() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.startAndCommit()
        harness.cover.renderingProgressDidChange(Self.firstVisuallyNonEmptyLayout)

        harness.fireLatestTimeout()

        #expect(harness.cover.phase == .idle)
        #expect(harness.pendingFades.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("First layout alone keeps the cover", .timeLimit(.minutes(1)), arguments: [firstLayout])
    func firstLayoutKeepsCover(events: UInt) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.startAndCommit()

        harness.cover.renderingProgressDidChange(events)

        #expect(harness.cover.phase == .awaitingPaint)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A cancelled navigation keeps the cover for the load that replaces it", .timeLimit(.minutes(1)))
    func cancelledNavigationKeepsCover() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didStartNavigation(harness.navigation)

        harness.cover.navigationDidFail(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled), navigation: harness.navigation)

        #expect(harness.cover.phase == .awaitingCommit)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A failed navigation reveals so the error page can show", .timeLimit(.minutes(1)),
          arguments: [NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
                      NSError(domain: "WebKitErrorDomain", code: 102)])
    func failedNavigationReveals(error: NSError) {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didStartNavigation(harness.navigation)

        harness.cover.navigationDidFail(error, navigation: harness.navigation)

        #expect(harness.cover.phase == .idle)
        #expect(harness.pendingFades.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The timeout reveals when no paint arrives", .timeLimit(.minutes(1)))
    func timeoutReveals() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.fireLatestTimeout()

        #expect(harness.cover.phase == .idle)
        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.commitTimeout)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Commit swaps the long commit wait for the shorter paint wait", .timeLimit(.minutes(1)))
    func commitRestartsTimeout() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.startAndCommit()

        #expect(harness.timeouts.count == 3)
        let earlierCancelled = harness.timeouts.dropLast().allSatisfy { $0.isCancelled }
        #expect(earlierCancelled)
        #expect(harness.timeouts.last?.isCancelled == false)
        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.paintTimeout)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A load that hasn't committed gets longer than the paint wait, since revealing would show the old page", .timeLimit(.minutes(1)))
    func commitWaitOutlastsPaintWait() {
        let harness = Harness()

        harness.cover.arm(in: harness.container, above: harness.webView)

        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.commitTimeout)
        #expect(FirstPaintCover.Constants.commitTimeout > FirstPaintCover.Constants.paintTimeout)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Each start, including a re-issued request, restarts the commit wait", .timeLimit(.minutes(1)))
    func startRestartsCommitWait() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.didStartNavigation(harness.navigation)
        harness.cover.didStartNavigation(NSObject())

        #expect(harness.timeouts.count == 3)
        let earlierCancelled = harness.timeouts.dropLast().allSatisfy { $0.isCancelled }
        #expect(earlierCancelled)
        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.commitTimeout)
        #expect(harness.cover.phase == .awaitingCommit)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Revealing cancels the pending timeout", .timeLimit(.minutes(1)))
    func revealCancelsTimeout() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.startAndCommit()

        harness.cover.renderingProgressDidChange(Self.firstMeaningfulPaint)

        let allCancelled = harness.timeouts.allSatisfy { $0.isCancelled }
        #expect(allCancelled)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Re-arming mid-fade keeps the cover up at full opacity", .timeLimit(.minutes(1)))
    func rearmDuringFadeKeepsCover() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.startAndCommit()
        harness.cover.renderingProgressDidChange(Self.firstMeaningfulPaint)
        harness.cover.coverView?.alpha = 0.4

        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.finishFades()

        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.isCoverInHierarchy)
        #expect(harness.cover.coverView?.alpha == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Cancel removes the cover at once", .timeLimit(.minutes(1)))
    func cancelRemovesImmediately() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.cancel()

        #expect(harness.cover.phase == .idle)
        #expect(!harness.isCoverInHierarchy)
        #expect(harness.pendingFades.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The exit snapshot sits on the cover where the panel was, and the hand-off gets the page colour", .timeLimit(.minutes(1)))
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

    @available(iOS 16, macOS 13, *)
    @Test("Arming starts from the panel colour so the hand-off is invisible", .timeLimit(.minutes(1)))
    func armStartsFromPanelColor() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.coverView?.backgroundColor = .blue

        harness.cover.arm(in: harness.container, above: harness.webView)

        #expect(harness.cover.coverView?.backgroundColor == FirstPaintCover.Constants.baseColor)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Re-arming replaces the previous exit snapshot", .timeLimit(.minutes(1)))
    func rearmReplacesSnapshot() {
        let harness = Harness()
        let first = UIView()
        let second = UIView()

        harness.cover.arm(in: harness.container, above: harness.webView, handoff: .init(exitSnapshot: first))
        harness.cover.arm(in: harness.container, above: harness.webView, handoff: .init(exitSnapshot: second))

        #expect(first.superview == nil)
        #expect(second.superview === harness.cover.coverView)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Revealing removes the exit snapshot with the cover", .timeLimit(.minutes(1)),
          arguments: [true, false])
    func revealRemovesSnapshot(animated: Bool) {
        let harness = Harness()
        let snapshot = UIView()
        harness.cover.arm(in: harness.container, above: harness.webView, handoff: .init(exitSnapshot: snapshot))

        if animated {
            harness.startAndCommit()
            harness.cover.renderingProgressDidChange(Self.firstMeaningfulPaint)
            harness.finishFades()
        } else {
            harness.cover.cancel()
        }

        #expect(snapshot.superview == nil)
        #expect(harness.cover.exitSnapshotView == nil)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A commit from the previous page's navigation is ignored", .timeLimit(.minutes(1)))
    func previousNavigationCommitIsIgnored() {
        let harness = Harness()
        let previous = NSObject()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.didCommit(previous)
        #expect(harness.cover.phase == .awaitingCommit, "before the covered load starts")

        harness.cover.didStartNavigation(harness.navigation)
        harness.cover.didCommit(previous)
        #expect(harness.cover.phase == .awaitingCommit, "after the covered load starts")

        harness.cover.didCommit(harness.navigation)
        #expect(harness.cover.phase == .awaitingPaint)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The previous page's paint can't reveal when its commit lands after arming", .timeLimit(.minutes(1)))
    func previousPageCannotReveal() {
        let harness = Harness()
        let previous = NSObject()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didStartNavigation(harness.navigation)

        harness.cover.didCommit(previous)
        harness.cover.renderingProgressDidChange(Self.firstVisuallyNonEmptyLayout | Self.firstMeaningfulPaint)

        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.pendingFades.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Failures from the previous page's navigation keep the cover", .timeLimit(.minutes(1)))
    func previousNavigationFailureKeepsCover() {
        let harness = Harness()
        let previous = NSObject()
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.navigationDidFail(error, navigation: previous)
        harness.cover.didStartNavigation(harness.navigation)
        harness.cover.navigationDidFail(error, navigation: previous)

        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.pendingFades.isEmpty)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A re-issued request takes over from the cancelled one", .timeLimit(.minutes(1)))
    func reissuedRequestTakesOver() {
        let harness = Harness()
        let reissued = NSObject()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didStartNavigation(harness.navigation)
        harness.cover.navigationDidFail(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled), navigation: harness.navigation)

        harness.cover.didStartNavigation(reissued)
        harness.cover.didCommit(harness.navigation)
        #expect(harness.cover.phase == .awaitingCommit, "the cancelled request no longer counts")

        harness.cover.didCommit(reissued)
        #expect(harness.cover.phase == .awaitingPaint)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Navigations WebKit reports without an object still count", .timeLimit(.minutes(1)))
    func nilNavigationsCount() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.didStartNavigation(nil)
        harness.cover.didCommit(nil)

        #expect(harness.cover.phase == .awaitingPaint)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Re-arming forgets the previous load's navigation", .timeLimit(.minutes(1)))
    func rearmForgetsNavigation() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didStartNavigation(harness.navigation)

        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didCommit(harness.navigation)

        #expect(harness.cover.phase == .awaitingCommit)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A policy cancel with nothing re-issued reveals after a short grace", .timeLimit(.minutes(1)))
    func policyCancelWithoutReissueReveals() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.willDecidePolicy()
        harness.cover.didDecidePolicy(allowed: false, isSameDocument: false)

        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.noNavigationGrace)
        #expect(FirstPaintCover.Constants.noNavigationGrace < FirstPaintCover.Constants.paintTimeout)
        harness.fireLatestTimeout()
        #expect(harness.cover.phase == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A policy cancel that re-issues the request keeps the cover for the new load", .timeLimit(.minutes(1)))
    func policyCancelWithReissueKeepsCover() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.willDecidePolicy()
        harness.cover.didDecidePolicy(allowed: false, isSameDocument: false)

        harness.cover.willDecidePolicy()

        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.commitTimeout)
        harness.cover.didDecidePolicy(allowed: true, isSameDocument: false)
        harness.cover.didStartNavigation(harness.navigation)
        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.timeouts.last?.delay == FirstPaintCover.Constants.commitTimeout)
    }

    @available(iOS 16, macOS 13, *)
    @Test("A same-document navigation reveals straight away", .timeLimit(.minutes(1)))
    func sameDocumentNavigationReveals() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)

        harness.cover.willDecidePolicy()
        harness.cover.didDecidePolicy(allowed: true, isSameDocument: true)

        #expect(harness.cover.phase == .idle)
        #expect(harness.pendingFades.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Policy decisions after the covered load starts don't shorten its wait", .timeLimit(.minutes(1)))
    func policyDecisionsAfterStartAreIgnored() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didStartNavigation(harness.navigation)
        let timeoutCount = harness.timeouts.count

        harness.cover.willDecidePolicy()
        harness.cover.didDecidePolicy(allowed: false, isSameDocument: false)
        harness.cover.didDecidePolicy(allowed: true, isSameDocument: true)

        #expect(harness.cover.phase == .awaitingCommit)
        #expect(harness.timeouts.count == timeoutCount)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Finishing the covered load reveals while still waiting for paint", .timeLimit(.minutes(1)))
    func finishRevealsCoveredLoad() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.startAndCommit()

        harness.cover.didFinish(NSObject())
        #expect(harness.cover.phase == .awaitingPaint, "another navigation's finish is ignored")

        harness.cover.didFinish(harness.navigation)
        #expect(harness.cover.phase == .idle)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Finishing before commit keeps the cover", .timeLimit(.minutes(1)))
    func finishBeforeCommitKeepsCover() {
        let harness = Harness()
        harness.cover.arm(in: harness.container, above: harness.webView)
        harness.cover.didStartNavigation(harness.navigation)

        harness.cover.didFinish(harness.navigation)

        #expect(harness.cover.phase == .awaitingCommit)
    }

    @available(iOS 16, macOS 13, *)
    @Test("The cover asks WebKit for every milestone it reacts to", .timeLimit(.minutes(1)))
    func observedEventsIncludeMilestones() {
        let observed = FirstPaintCover.Constants.observedEvents

        #expect(observed & Self.firstVisuallyNonEmptyLayout != 0)
        #expect(observed & Self.didRenderSignificantAmountOfText != 0)
        #expect(observed & Self.firstMeaningfulPaint != 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test("Callbacks without an armed cover do nothing", .timeLimit(.minutes(1)))
    func idleCallbacksDoNothing() {
        let harness = Harness()

        harness.startAndCommit()
        harness.cover.renderingProgressDidChange(Self.firstVisuallyNonEmptyLayout)
        harness.cover.willDecidePolicy()
        harness.cover.didDecidePolicy(allowed: true, isSameDocument: true)
        harness.cover.didFinish(harness.navigation)
        harness.cover.navigationDidFail(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut), navigation: harness.navigation)
        harness.cover.cancel()

        #expect(harness.cover.phase == .idle)
        #expect(harness.cover.coverView == nil)
        #expect(harness.timeouts.isEmpty)
    }
}
