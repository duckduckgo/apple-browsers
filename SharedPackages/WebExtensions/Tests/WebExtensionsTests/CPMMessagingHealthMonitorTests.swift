//
//  CPMMessagingHealthMonitorTests.swift
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

@testable import WebExtensions

@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingHealthMonitorTests: XCTestCase {

    private var date = Date(timeIntervalSince1970: 1_000_000)
    private let pixels = CapturingWebExtensionPixelFiring()
    private lazy var monitor = CPMMessagingHealthMonitor(pixelFiring: pixels,
                                                         silenceWindow: 30,
                                                         now: { [unowned self] in self.date })

    // MARK: - Silence

    func testPageThatHeardNothingIsReportedOnTheFirstEventAfterTheWindow() {
        commit("a")
        advance(29)
        monitor.handle(.interruptionEnded)
        XCTAssertTrue(pixels.breakages.isEmpty)

        advance(1)
        monitor.handle(.interruptionEnded)
        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testSilentPageIsReportedOnce() {
        commit("a")
        advance(60)
        monitor.handle(.interruptionEnded)
        advance(60)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages.count, 1)
    }

    func testSlowAnswerIsNotReported() {
        commit("a", path: "a")
        advance(300)
        monitor.handle(.dashboardResponse(url: url("a")))

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    func testMessageLongBeforeTheCommitDoesNotAnswerIt() {
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a")))
        advance(10)
        commit("a", path: "b")
        advance(30)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testNavigationAfterTheWindowReportsTheReplacedPage() {
        commit("a", path: "a")
        advance(31)
        commit("a", path: "b")

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testNavigationBeforeTheWindowReportsNothing() {
        commit("a", path: "a")
        advance(29)
        commit("a", path: "b")
        advance(29)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    func testClosingTheTabAfterTheWindowReportsItAndBeforeItDoesNot() {
        commit("late")
        advance(31)
        monitor.handle(.tabClosed(tabIdentifier: "late"))
        XCTAssertEqual(pixels.breakages.count, 1)

        commit("early", path: "b")
        advance(5)
        monitor.handle(.tabClosed(tabIdentifier: "early"))
        advance(100)
        monitor.handle(.interruptionEnded)
        XCTAssertEqual(pixels.breakages.count, 1)
    }

    func testProcessTerminationIsNotReported() {
        commit("a")
        monitor.handle(.webContentProcessTerminated(tabIdentifier: "a"))
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    // MARK: - Pages that are not measured

    func testPagesThatCannotRunTheExtensionAreNotMeasured() {
        let kinds: [CPMNavigationKind] = [.errorPage, .backForward, .sessionRestoration]
        for kind in kinds {
            commit("a", path: "a", kind: kind)
        }
        monitor.handle(.navigationCommitted(tabIdentifier: "a", url: URL(string: "duck://newtab")!, navigationKind: .other, extensionIsLoaded: true))
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    func testIneligibleCommitEndsTheWaitForThePageBefore() {
        commit("a", path: "a")
        advance(10)
        commit("a", path: "b", kind: .errorPage)
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    func testWaitsEndWhenTheEmbeddedExtensionIsRemoved() {
        commit("a", path: "a")
        commit("b", path: "b")
        advance(10)

        monitor.handle(.embeddedExtensionRemoved)
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty, "an uninstalled or upgraded extension is gone, not broken")
    }

    func testNonHTMLDocumentIsNotMeasured() {
        commit("a", path: "file.pdf", kind: .nonHTMLDocument)
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    func testOnlyAnOrdinaryNavigationBecomesANonHTMLDocument() {
        XCTAssertEqual(CPMNavigationKind.other.resolved(forMimeType: "application/pdf"), .nonHTMLDocument)
        XCTAssertEqual(CPMNavigationKind.other.resolved(forMimeType: "text/html"), .other)
        XCTAssertEqual(CPMNavigationKind.other.resolved(forMimeType: nil), .other)
        for kind in [CPMNavigationKind.sessionRestoration, .backForward, .errorPage, .nonHTMLDocument] {
            XCTAssertEqual(kind.resolved(forMimeType: "application/pdf"), kind)
            XCTAssertEqual(kind.resolved(forMimeType: "text/html"), kind)
        }
    }

    func testOnlyHTMLResponsesAreHTMLDocuments() {
        XCTAssertTrue(CPMNavigationKind.isHTMLDocument(mimeType: "text/html"))
        XCTAssertTrue(CPMNavigationKind.isHTMLDocument(mimeType: "TEXT/HTML"))
        XCTAssertTrue(CPMNavigationKind.isHTMLDocument(mimeType: "application/xhtml+xml"))
        XCTAssertTrue(CPMNavigationKind.isHTMLDocument(mimeType: nil), "an unknown type is measured")
        XCTAssertTrue(CPMNavigationKind.isHTMLDocument(mimeType: ""))
        XCTAssertFalse(CPMNavigationKind.isHTMLDocument(mimeType: "application/pdf"))
        XCTAssertFalse(CPMNavigationKind.isHTMLDocument(mimeType: "image/png"))
        XCTAssertFalse(CPMNavigationKind.isHTMLDocument(mimeType: "video/mp4"))
        XCTAssertFalse(CPMNavigationKind.isHTMLDocument(mimeType: "text/plain"))
        XCTAssertFalse(CPMNavigationKind.isHTMLDocument(mimeType: "application/json"))
    }

    func testPageCommittedWithoutTheExtensionLoadedIsNotMeasured() {
        monitor.handle(.navigationCommitted(tabIdentifier: "a", url: url("a"), navigationKind: .other, extensionIsLoaded: false))
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    // MARK: - Suspension

    func testSuspendedTimeDoesNotCount() {
        commit("a")
        advance(20)
        monitor.handle(.interruptionBegan)
        advance(3600)
        monitor.handle(.interruptionEnded)
        XCTAssertTrue(pixels.breakages.isEmpty)

        advance(9)
        monitor.handle(.interruptionEnded)
        XCTAssertTrue(pixels.breakages.isEmpty)

        advance(1)
        monitor.handle(.interruptionEnded)
        XCTAssertEqual(pixels.breakages.count, 1)
    }

    func testNothingIsReportedWhileSuspended() {
        commit("a")
        advance(20)
        monitor.handle(.interruptionBegan)
        advance(3600)
        monitor.handle(.tabClosed(tabIdentifier: "other"))

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    // MARK: - Attribution

    func testMessageFromAnotherTabDoesNotAnswerThisTab() {
        commit("a", path: "a")
        commit("b", path: "b")
        monitor.handle(.dashboardResponse(url: url("b")))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testMessageGoesOnlyToTheWaitingTabsShowingItsPage() {
        commit("c", path: "y")
        monitor.handle(.dashboardResponse(url: url("y")))
        commit("a", path: "y")
        commit("b", path: "x")
        monitor.handle(.dashboardResponse(url: url("y")))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)], "a got the message, b waits on another page")
    }

    func testMessageThatMatchesTwoTabsAnswersBoth() {
        commit("a", path: "same")
        commit("b", path: "same")
        monitor.handle(.dashboardResponse(url: url("same")))
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    func testMessageWithoutATabAnswersTheTabsItMatches() {
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a")))
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    func testSimulationHidesMessagesSoTheTabIsReported() {
        monitor.setBreakageSimulationEnabled(true)
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a")))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testMessageFromAnOldExtensionDoesNotAnswer() {
        monitor.isCurrentEmbeddedExtension = { $0 == "current" }
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a"), extensionIdentifier: "old"))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages.count, 1)
    }

    func testExtensionReloadForgetsPendingPages() {
        commit("a")
        monitor.handle(.extensionLifecycle(.willReload(identifier: "embedded", type: .embedded, trigger: .explicit)))
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    // MARK: - One tab or many

    func testSecondSilentTabIsManyAndReportsPersistentOnce() {
        commit("a", path: "a")
        commit("b", path: "b")
        commit("c", path: "c")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.many), report(.many), report(.many)],
                       "tabs found silent together are not a single-tab breakage")
        XCTAssertEqual(pixels.persistentCount, 1)
    }

    func testSecondSilentTabInALaterCheckIsManyAndThirdIsMany() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)
        commit("c", path: "c")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.many), report(.many)])
        XCTAssertEqual(pixels.persistentCount, 1)
    }

    func testSilenceOfASingleTabIsNeverPersistent() {
        commit("a", path: "a")
        advance(31)
        commit("a", path: "b")
        advance(31)
        commit("a", path: "c")

        XCTAssertEqual(pixels.breakages, [report(.one), report(.one)])
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    func testAnyMessageEndsTheSeries() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        monitor.handle(.dashboardResponse(url: url("other")))
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.one)])
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    func testSecondSeriesReportsPersistentAgain() {
        for series in 0..<2 {
            commit("a\(series)", path: "a")
            commit("b\(series)", path: "b")
            advance(31)
            monitor.handle(.interruptionEnded)
            monitor.handle(.dashboardResponse(url: url("none")))
        }

        XCTAssertEqual(pixels.persistentCount, 2)
    }

    func testSilentTabThatWasClosedStillCountsForTheSeries() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.tabClosed(tabIdentifier: "a"))
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.many)])
        XCTAssertEqual(pixels.persistentCount, 1)
    }

    // MARK: - Message for another page

    func testMessageForAPageNoTabShowsAnswersNobody() {
        commit("a", path: "x")
        advance(1)
        monitor.handle(.dashboardResponse(url: url("y")))
        advance(40)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testMessageOfAnotherHostDoesNotAnswerTheWaitingTab() {
        commit("a", path: "x")
        advance(1)
        monitor.handle(.dashboardResponse(url: URL(string: "https://other.example/x")!))
        advance(40)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    // MARK: - Messages that are not answers

    func testRefreshThatCannotAnswerLeavesThePageSilent() {
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: false))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testRefreshThatCannotAnswerStillShowsTheCurrentExtensionIsAlive() {
        var healthyCount = 0
        monitor.onHealthyResponse = { healthyCount += 1 }
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: false))

        XCTAssertEqual(healthyCount, 1)
    }

    func testRefreshThatCannotAnswerDoesNotEndTheSeries() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        monitor.handle(.dashboardResponse(url: url("other"), isAnswer: false))
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.many)])
        XCTAssertEqual(pixels.persistentCount, 1)
    }

    func testTabsTheExtensionCannotAnswerAreReportedButNeverPersistent() {
        commit("a", path: "a")
        commit("b", path: "b")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: false))
        monitor.handle(.dashboardResponse(url: url("b"), isAnswer: false))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.one)],
                       "the extension is running, so the tabs are not many")
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    func testTabNextToATabTheExtensionCannotAnswerIsOneAndNotPersistent() {
        commit("a", path: "a")
        commit("b", path: "b")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: false))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.one)])
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    func testTabTheExtensionCannotAnswerStaysOutOfALaterSeries() {
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: false))
        advance(31)
        monitor.handle(.interruptionEnded)
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.one)])
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    func testTabTheExtensionCannotAnswerIsNotReportedWhenAnAnswerFollows() {
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: false))
        monitor.handle(.dashboardResponse(url: url("a")))
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    func testCannotAnswerMarkEndsWithTheNextCommitOfTheTab() {
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: false))
        commit("a", path: "a2")
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.many), report(.many)])
        XCTAssertEqual(pixels.persistentCount, 1)
    }

    func testCannotAnswerMarkEndsWithTheTabAndTheExtensionReload() {
        commit("a", path: "a")
        commit("b", path: "b")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: false))
        monitor.handle(.dashboardResponse(url: url("b"), isAnswer: false))
        monitor.handle(.tabClosed(tabIdentifier: "a"))
        monitor.handle(.extensionLifecycle(.reloaded(identifier: "embedded", type: .embedded, trigger: .explicit)))
        commit("c", path: "c")
        commit("d", path: "d")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.many), report(.many)])
        XCTAssertEqual(pixels.persistentCount, 1)
    }

    // MARK: - More sequences

    func testSimulationSwitchedOffAnswersAgain() {
        monitor.setBreakageSimulationEnabled(true)
        monitor.setBreakageSimulationEnabled(false)
        commit("a", path: "a")
        monitor.handle(.dashboardResponse(url: url("a")))
        advance(100)
        monitor.handle(.interruptionEnded)

        XCTAssertTrue(pixels.breakages.isEmpty)
    }

    func testPageCommittedAfterACrashIsMeasured() {
        commit("a", path: "a")
        monitor.handle(.webContentProcessTerminated(tabIdentifier: "a"))
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testPageCommittedWhileSuspendedStartsWaitingWhenTheAppResumes() {
        monitor.handle(.interruptionBegan)
        advance(3600)
        commit("a", path: "a")
        advance(10)
        monitor.handle(.interruptionEnded)
        advance(29)
        monitor.handle(.interruptionEnded)
        XCTAssertTrue(pixels.breakages.isEmpty)

        advance(1)
        monitor.handle(.interruptionEnded)
        XCTAssertEqual(pixels.breakages.count, 1)
    }

    func testSilentPageIsReportedWhenTheAppIsAboutToSuspend() {
        commit("a")
        advance(31)
        monitor.handle(.interruptionBegan)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testExtensionReloadEndsTheSeries() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        monitor.handle(.extensionLifecycle(.reloaded(identifier: "embedded", type: .embedded, trigger: .explicit)))
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.one)])
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    func testMessageThatAnswersAPageBeforeTheCheckAppliesFirst() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.dashboardResponse(url: url("a")))

        XCTAssertTrue(pixels.breakages.isEmpty, "the answer is applied before the check")
    }

    // MARK: - Extension lifecycle of other extensions

    func testLifecycleOfAnotherExtensionDoesNotEndWaitsOrTheSeries() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        commit("b", path: "b")
        for type in [DuckDuckGoWebExtensionType.darkReader, .adBlockingExtension, .searchToken] {
            monitor.handle(.extensionLifecycle(.willReload(identifier: "x", type: type, trigger: .explicit)))
            monitor.handle(.extensionLifecycle(.reloaded(identifier: "x", type: type, trigger: .explicit)))
        }
        monitor.handle(.extensionLifecycle(.willReload(identifier: "y", type: nil, trigger: .explicit)))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.many)])
        XCTAssertEqual(pixels.persistentCount, 1)
    }

    func testEmbeddedLoadedAndFailedReloadDoNotEndWaits() {
        commit("a", path: "a")
        monitor.handle(.extensionLifecycle(.loaded(identifier: "embedded", type: .embedded)))
        monitor.handle(.extensionLifecycle(.reloadFailed(identifier: "embedded", type: .embedded, trigger: .explicit)))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    // MARK: - Suspension edge cases

    func testResumeWithoutSuspensionChangesNothing() {
        commit("a")
        advance(20)
        monitor.handle(.interruptionEnded)
        advance(10)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testSecondSuspensionBeginKeepsTheFirstStart() {
        commit("a")
        advance(20)
        monitor.handle(.interruptionBegan)
        advance(600)
        monitor.handle(.interruptionBegan)
        advance(600)
        monitor.handle(.interruptionEnded)
        advance(9)
        monitor.handle(.interruptionEnded)
        XCTAssertTrue(pixels.breakages.isEmpty, "the whole suspension is excluded, not only the last part")

        advance(1)
        monitor.handle(.interruptionEnded)
        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    func testClosingAnUnknownTabChangesNothing() {
        commit("a")
        monitor.handle(.tabClosed(tabIdentifier: "unknown"))
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
    }

    // MARK: - Interleaved tabs and answers

    func testAnswerToOneOfTwoWaitingTabsLeavesTheOtherAloneAndNotPersistent() {
        commit("a", path: "a")
        commit("b", path: "b")
        advance(10)
        monitor.handle(.dashboardResponse(url: url("a")))
        advance(21)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one)])
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    func testAnswerForAThirdTabBetweenTwoSilentTabsEndsTheEpisode() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        commit("c", path: "c")
        monitor.handle(.dashboardResponse(url: url("c")))
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.one)])
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    func testAnswerBetweenTheReportsOfTwoOverlappingTabsEndsTheEpisode() {
        commit("a", path: "a")
        advance(10)
        commit("b", path: "b")
        advance(21)
        monitor.handle(.interruptionEnded)
        monitor.handle(.dashboardResponse(url: url("none")))
        advance(10)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.one)])
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    func testAnswerFromAnOldExtensionDoesNotEndTheEpisode() {
        monitor.isCurrentEmbeddedExtension = { $0 == "current" }
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        monitor.handle(.dashboardResponse(url: url("none"), extensionIdentifier: "old"))
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.many)])
        XCTAssertEqual(pixels.persistentCount, 1)
    }

    func testAnswerHiddenBySimulationDoesNotEndTheEpisode() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        monitor.setBreakageSimulationEnabled(true)
        monitor.handle(.dashboardResponse(url: url("none")))
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.many)])
        XCTAssertEqual(pixels.persistentCount, 1)
    }

    func testRemovalOfTheEmbeddedExtensionEndsTheEpisode() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        monitor.handle(.embeddedExtensionRemoved)
        commit("b", path: "b")
        advance(31)
        monitor.handle(.interruptionEnded)

        XCTAssertEqual(pixels.breakages, [report(.one), report(.one)])
        XCTAssertEqual(pixels.persistentCount, 0)
    }

    // MARK: - Helpers

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    private func commit(_ tab: String, path: String = "page", kind: CPMNavigationKind = .other) {
        monitor.handle(.navigationCommitted(tabIdentifier: tab, url: url(path), navigationKind: kind, extensionIsLoaded: true))
    }

    private func advance(_ seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }

    private func report(_ tabs: CPMSilentTabs) -> CPMMessagingBreakageReport {
        CPMMessagingBreakageReport(tabs: tabs)
    }
}

@available(macOS 15.4, iOS 18.4, *)
private final class CapturingWebExtensionPixelFiring: WebExtensionPixelFiring {
    private(set) var breakages: [CPMMessagingBreakageReport] = []
    private(set) var persistentCount = 0

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .cpmMessagingBreakage(let report):
            breakages.append(report)
        case .cpmMessagingBreakagePersistent:
            persistentCount += 1
        default:
            break
        }
    }
}
