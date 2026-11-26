//
//  CPMMessagingHealthMonitorProgressTests.swift
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

/// The init marks of a page: how far its init got, reported in the silent tab's breakage pixel.
@available(macOS 15.4, iOS 18.4, *)
@MainActor
final class CPMMessagingHealthMonitorProgressTests: XCTestCase {

    private var date = Date(timeIntervalSince1970: 1_000_000)
    private let pixels = StageCapturingPixels()
    private var isInitProgressEnabled = true
    private lazy var monitor = CPMMessagingHealthMonitor(pixelFiring: pixels,
                                                         isUnmeasuredPage: { _ in false },
                                                         silenceWindow: 30,
                                                         messageTolerance: 2,
                                                         isInitProgressEnabled: { [unowned self] in self.isInitProgressEnabled },
                                                         now: { [unowned self] in self.date })

    // MARK: - After the commit

    func testReportCarriesTheFurthestStageOfTheSilentTab() {
        commit("a", path: "a")
        mark(.backgroundReceived, path: "a")
        mark(.configRead, path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.configRead), tabs: .one)])
    }

    func testReportHasNoStageWhileTheSubfeatureIsOff() {
        isInitProgressEnabled = false
        commit("a", path: "a")
        mark(.configRead, path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .notMeasured, tabs: .one)])
    }

    func testStageReturnsWhenTheSubfeatureIsTurnedOnAgain() {
        isInitProgressEnabled = false
        commit("a", path: "a")
        mark(.configRead, path: "a")
        isInitProgressEnabled = true
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.configRead), tabs: .one)])
    }

    func testReportWithoutMarksHasNoStage() {
        commit("a", path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .noMark, tabs: .one)])
    }

    func testLaterMarkOfAnEarlierStageDoesNotLowerTheStage() {
        commit("a", path: "a")
        mark(.siteChecked, path: "a")
        mark(.backgroundReceived, path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.siteChecked), tabs: .one)])
    }

    func testMarksOfAnotherPageDoNotReachTheTab() {
        commit("a", path: "a")
        commit("b", path: "b")
        mark(.responseSent, path: "b")
        silence()

        XCTAssertEqual(Set(pixels.reports), [Report(stage: .noMark, tabs: .many), Report(stage: .reached(.responseSent), tabs: .many)])
    }

    func testMarkOfAPageTwoTabsShowGoesToBoth() {
        commit("a", path: "same")
        commit("b", path: "same")
        mark(.settingsChecked, path: "same")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.settingsChecked), tabs: .many), Report(stage: .reached(.settingsChecked), tabs: .many)])
    }

    func testMarkOfThePageBeforeIsNotCountedForTheNewPage() {
        commit("a", path: "old")
        advance(10)
        commit("a", path: "new")
        mark(.responseSent, path: "old")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .noMark, tabs: .one)])
    }

    func testMarkIsNotAnAnswer() {
        commit("a", path: "a")
        mark(.responseSent, path: "a")
        silence()

        XCTAssertEqual(pixels.reports.count, 1, "the page that got every mark but no message is still silent")
    }

    func testMarkDoesNotEndTheSeries() {
        commit("a", path: "a")
        advance(31)
        monitor.handle(.interruptionEnded)
        commit("b", path: "b")
        mark(.responseSent, path: "b")
        silence()

        XCTAssertEqual(pixels.persistentCount, 1, "a mark does not end the series")
        XCTAssertEqual(pixels.reports.count, 2)
    }

    func testTabTheExtensionCannotAnswerIsReportedWithItsStage() {
        commit("a", path: "a")
        mark(.siteChecked, path: "a")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: false))
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.siteChecked), tabs: .one)])
    }

    func testMarksFromAnOldExtensionAreIgnored() {
        monitor.isCurrentEmbeddedExtension = { $0 == "current" }
        commit("a", path: "a")
        monitor.handle(.initProgress(url: url("a"), stage: .backgroundReceived, extensionIdentifier: "old"))
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .noMark, tabs: .one)])
    }

    func testMarksDuringSimulationAreCountedAndAnswersAreDropped() {
        monitor.setBreakageSimulationEnabled(true)
        commit("a", path: "a")
        mark(.responseSent, path: "a")
        monitor.handle(.dashboardResponse(url: url("a"), isAnswer: true))
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.responseSent), tabs: .one)])
    }

    func testClosedTabForgetsItsMarks() {
        commit("a", path: "a")
        mark(.siteChecked, path: "a")
        monitor.handle(.tabClosed(tabIdentifier: "a"))
        commit("a", path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .noMark, tabs: .one)])
    }

    func testStagesAreRankedInTheOrderTheChainRuns() {
        let stages = CPMInitStage.allCases
        XCTAssertEqual(stages.map(\.rank), Array(0..<stages.count))
        XCTAssertEqual(stages.map(\.rawValue), ["background_received", "config_read", "settings_checked",
                                                "site_checked", "response_sent"])
    }

    // MARK: - Before the commit

    func testMarkThatArrivesBeforeItsPageCommitsCountsForThePage() {
        mark(.configRead, path: "a")
        commit("a", path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.configRead), tabs: .one)])
    }

    func testMarksBeforeTheCommitKeepTheFurthestStage() {
        mark(.backgroundReceived, path: "a")
        mark(.siteChecked, path: "a")
        mark(.configRead, path: "a")
        commit("a", path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.siteChecked), tabs: .one)])
    }

    func testMarkOlderThanTheToleranceBeforeTheCommitIsIgnored() {
        mark(.configRead, path: "a")
        advance(3)
        commit("a", path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .noMark, tabs: .one)])
    }

    func testReloadOfAWaitingPageTakesTheMarkThatArrivesBeforeItsCommit() {
        commit("a", path: "x")
        advance(10)
        mark(.backgroundReceived, path: "x")
        commit("a", path: "x")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.backgroundReceived), tabs: .one)])
    }

    func testSecondTabOnAWaitingPageTakesTheMarkThatArrivesBeforeItsCommit() {
        commit("a", path: "x")
        advance(10)
        mark(.configRead, path: "x")
        commit("b", path: "x")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .reached(.configRead), tabs: .many), Report(stage: .reached(.configRead), tabs: .many)])
    }

    func testMarkBeforeTheCommitOfAnotherPageIsNotTaken() {
        mark(.siteChecked, path: "other")
        commit("a", path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .noMark, tabs: .one)])
    }

    func testExtensionReloadForgetsMarksThatWaitForACommit() {
        mark(.siteChecked, path: "a")
        monitor.handle(.extensionLifecycle(.reloaded(identifier: "embedded", type: .embedded, trigger: .explicit)))
        commit("a", path: "a")
        silence()

        XCTAssertEqual(pixels.reports, [Report(stage: .noMark, tabs: .one)])
    }

    // MARK: - Helpers

    private func url(_ path: String) -> URL {
        URL(string: "https://example.com/\(path)")!
    }

    private func commit(_ tab: String, path: String) {
        monitor.handle(.navigationCommitted(tabIdentifier: tab, url: url(path), navigationKind: .other, extensionIsLoaded: true))
    }

    private func mark(_ stage: CPMInitStage, path: String) {
        monitor.handle(.initProgress(url: url(path), stage: stage))
    }

    private func advance(_ seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
    }

    /// Lets the window pass and runs the check.
    private func silence() {
        advance(31)
        monitor.handle(.interruptionEnded)
    }
}

private struct Report: Hashable {
    let stage: CPMLastStage
    let tabs: CPMSilentTabs
}

@available(macOS 15.4, iOS 18.4, *)
private final class StageCapturingPixels: WebExtensionPixelFiring {
    private(set) var reports: [Report] = []
    private(set) var persistentCount = 0

    func fire(_ event: WebExtensionPixelEvent) {
        switch event {
        case .cpmMessagingBreakage(let lastStage, let tabs):
            reports.append(Report(stage: lastStage, tabs: tabs))
        case .cpmMessagingBreakagePersistent:
            persistentCount += 1
        default:
            break
        }
    }
}
