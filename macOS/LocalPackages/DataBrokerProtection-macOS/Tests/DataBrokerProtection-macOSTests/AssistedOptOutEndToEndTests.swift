//
//  AssistedOptOutEndToEndTests.swift
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
import Foundation
import WebKit
import XCTest
@testable import DataBrokerProtection_macOS
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

/// Runs the fake assisted broker's opt-out through a real web view, the bundled C-S-S, the assisted queue and the agent's
/// real attempt window, with a scripted user acting on the page or the window at each hand-off.
///
/// Skipped unless `PIR_FAKE_ASSISTED_BROKER_E2E=1`. Serves `FakeAssistedBroker` on port 3001 unless something already does.
/// Screenshots of the window go to `PIR_FAKE_ASSISTED_BROKER_SHOTS` when it's set.
@MainActor
final class AssistedOptOutEndToEndTests: XCTestCase {

    private static let brokerURL = URL(string: "http://localhost:3001/optout.html")!
    private static let fakeBrokerDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("FakeAssistedBroker")
    static let windowTitle = "Removing you from DDG Fake Assisted Broker"

    private var server: Process?
    private var defaults: UserDefaults!
    private var runs: [Run] = []
    private let preferredRunDate = Date().addingTimeInterval(-3600)

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIR_FAKE_ASSISTED_BROKER_E2E"] == "1",
                          "Set PIR_FAKE_ASSISTED_BROKER_E2E=1 to run the fake assisted broker end-to-end test")
        _ = NSApplication.shared
        defaults = UserDefaults(suiteName: "AssistedOptOutEndToEndTests-\(UUID().uuidString)")
        try await startServerIfNeeded()
    }

    override func tearDown() async throws {
        runs.forEach { $0.queue.cancelAll() }
        runs = []
        NSApp?.windows.filter { $0.title == Self.windowTitle }.forEach { $0.close() }
        server?.terminate()
        server?.waitUntilExit()
        server = nil
        try await super.tearDown()
    }

    func testScriptedUserCompletesEveryHandOff() async throws {
        let run = try makeRun()
        let shots = WindowShooter()
        var statusAtHandOffs: [Int: [String]] = [:]
        run.user.onUserTurn = { session, turn in
            let (script, name) = switch turn {
            case 1: ("document.getElementById('fake-turnstile').click()", "04-handoff-turnstile")
            case 2: ("document.getElementById('fake-hcaptcha').click()", "05-handoff-hcaptcha")
            default: ("document.getElementById('remove-button').click()", "06-handoff-remove")
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await shots.shoot(name, window: run.user.anyWindow, webView: session.webView)
                statusAtHandOffs[turn] = WindowControls.texts(in: run.user.anyWindow)
                _ = try? await session.webView?.evaluateJavaScript(script)
            }
        }

        run.record()
        run.queue.start(id: run.id)
        let window = try XCTUnwrap(run.user.windows.first)
        let session = try XCTUnwrap(run.session)
        try await Task.sleep(nanoseconds: 800_000_000)
        await shots.shoot("01-intro", window: window, webView: session.webView)
        let introTexts = WindowControls.texts(in: window)
        XCTAssertEqual(session.phase, .ready)
        XCTAssertNil(session.webView, "Nothing runs before Start request")
        XCTAssertEqual(run.events, [])

        run.begin(viaWindow: true)
        XCTAssertNotEqual(session.phase, .ready)
        try await Task.sleep(nanoseconds: 250_000_000)
        await shots.shoot("02-after-begin", window: window, webView: session.webView)

        try await waitForFirstPageLoad(session)
        for index in 0..<40 where session.phase == .agentInControl {
            try await Task.sleep(nanoseconds: 250_000_000)
            run.record()
            await shots.shoot(String(format: "03-agent-in-control-%02d", index + 1), window: window, webView: session.webView)
        }
        let agentTexts = WindowControls.texts(in: window)

        try await run.waitUntil { $0.last?.state == .submitted }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        await shots.shoot("07-submitted", window: window, webView: session.webView)
        let submittedTexts = WindowControls.texts(in: window)

        print("[e2e] shots:\n" + shots.log.joined(separator: "\n"))
        print("[e2e] intro texts: \(introTexts)")
        print("[e2e] agent texts: \(agentTexts)")
        print("[e2e] hand-off texts: \(statusAtHandOffs.sorted { $0.key < $1.key })")
        print("[e2e] submitted texts: \(submittedTexts)")
        print("[e2e] begin pressed via: \(run.beginMethod ?? "-")")
        print("[e2e] window sizes: open \(String(describing: run.user.openSize)), hand-offs \(run.user.handOffSizes), end \(window.frame.size)")

        XCTAssertEqual(run.user.turns.map(\.step), ["Searching for your record", "Prove you’re human", "Review and submit"])
        XCTAssertEqual(run.visitedSteps, ["Entering your name", "Searching for your record", "Selecting your record",
                                          "Prove you’re human", "Review and submit"])
        XCTAssertEqual(run.states.first, .waiting)
        XCTAssertEqual(run.states.last, .submitted)
        XCTAssertEqual(run.events.first, .optOutStarted)
        XCTAssertEqual(run.events.last, .optOutRequested)
        XCTAssertFalse(run.hasErrorEvent)
        XCTAssertEqual(run.user.windows.first, window)
        XCTAssertEqual(run.queue.assistedOptOuts(droppingSubmitted: true), [])

        let openSize = try XCTUnwrap(run.user.openSize)
        XCTAssertEqual(run.user.handOffSizes.count, 3)
        for size in run.user.handOffSizes {
            XCTAssertEqual(size, openSize, "The window resized during the attempt")
        }
        XCTAssertEqual(window.frame.size, openSize, "The window resized during the attempt")

        if !introTexts.isEmpty {
            XCTAssertTrue(introTexts.contains("Not started"), "Intro texts: \(introTexts)")
            XCTAssertTrue(agentTexts.contains("DuckDuckGo is in control"), "Agent texts: \(agentTexts)")
            for (turn, texts) in statusAtHandOffs {
                XCTAssertTrue(texts.contains("DuckDuckGo is waiting for you"), "Hand-off \(turn) texts: \(texts)")
            }
            XCTAssertTrue(submittedTexts.contains("Finished"), "Submitted texts: \(submittedTexts)")
            XCTAssertTrue(submittedTexts.contains("Back to dashboard"), "Submitted texts: \(submittedTexts)")
        }
    }

    // MARK: - Edge cases

    func testClosingTheWindowOnTheIntroCancelsTheAttempt() async throws {
        let run = try makeRun()
        run.record()
        run.queue.start(id: run.id)
        let window = try XCTUnwrap(run.user.windows.first)
        window.performClose(nil)

        XCTAssertFalse(window.isVisible)
        XCTAssertTrue(run.queue.activeSessions.isEmpty)
        XCTAssertTrue(run.user.windows.isEmpty)
        XCTAssertEqual(run.user.dismissed, 1)
        XCTAssertEqual(run.events, [])
        run.syncHistory()
        XCTAssertEqual(run.queue.assistedOptOuts().map(\.state), [.waiting])
    }

    func testClosingTheWindowMidAttemptHidesItAndTheAttemptKeepsGoing() async throws {
        let run = try makeRun()
        var afterClose: (window: NSWindow?, visible: Bool, sessions: Int, phase: AssistedAttemptPhase?, dismissed: Int,
                         state: AssistedOptOut.State?)?
        var visibleAtSecondHandOff: Bool?
        run.user.onUserTurn = { session, turn in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if turn == 1 {
                    let window = run.user.windows.first
                    window?.performClose(nil)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    run.syncHistory()
                    afterClose = (window: window, visible: window?.isVisible == true, sessions: run.queue.activeSessions.count,
                                  phase: run.session?.phase, dismissed: run.user.dismissed,
                                  state: run.queue.assistedOptOuts().first?.state)
                    _ = try? await session.webView?.evaluateJavaScript("document.getElementById('fake-turnstile').click()")
                } else {
                    visibleAtSecondHandOff = run.user.anyWindow?.isVisible
                    session.requestCancel()
                }
            }
        }

        run.record()
        run.startAndBegin()
        try await run.waitUntil { _ in run.user.turns.count == 2 && run.queue.activeSessions.isEmpty && run.states.last == .waiting }
        try await waitForAttemptEnd(run)

        let closed = try XCTUnwrap(afterClose)
        XCTAssertNotNil(closed.window)
        XCTAssertFalse(closed.visible, "Closing mid-attempt hides the window")
        XCTAssertEqual(closed.sessions, 1, "The attempt is still open after closing the window")
        XCTAssertEqual(closed.phase, .userTurn)
        XCTAssertEqual(closed.dismissed, 0)
        XCTAssertEqual(closed.state, .needsUser)
        XCTAssertEqual(run.user.turns.map(\.step), ["Searching for your record", "Prove you’re human"],
                       "The hidden attempt carried on to the next hand-off")
        XCTAssertEqual(visibleAtSecondHandOff, true, "The next hand-off brings the hidden window back")
        XCTAssertTrue(run.user.windows.isEmpty)
        XCTAssertEqual(run.user.dismissed, 1)
        XCTAssertEqual(run.events, [.optOutStarted, .optOutAwaitingUserAssistance])
        XCTAssertFalse(run.hasErrorEvent)
        XCTAssertFalse(run.database.wasUpdatedPreferredRunDateForOptOutCalled)
        run.syncHistory()
        XCTAssertEqual(run.queue.assistedOptOuts().map(\.state), [.waiting])
    }

    func testStoppingMidAttemptPutsTheOptOutBackToWaiting() async throws {
        let run = try makeRun()
        var stoppedVia: String?
        run.user.onUserTurn = { session, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if WindowControls.press("Stop", in: run.user.windows.first) {
                    stoppedVia = "Stop button"
                } else {
                    stoppedVia = "session.requestCancel()"
                    session.requestCancel()
                }
            }
        }

        run.record()
        run.startAndBegin()
        try await run.waitUntil { _ in run.user.turns.count == 1 && run.queue.activeSessions.isEmpty && run.states.last == .waiting }
        try await waitForAttemptEnd(run)
        print("[e2e] stopped via: \(stoppedVia ?? "-")")

        XCTAssertNotNil(stoppedVia)
        XCTAssertTrue(run.user.windows.isEmpty)
        XCTAssertEqual(run.user.dismissed, 1)
        assertWentBackToWaiting(run)
    }

    func testPressingStartTwiceBringsTheSameWindowForwardWithoutASecondAttempt() async throws {
        let run = try makeRun()
        var checks: (sameWindow: Bool, visible: Bool, windowCount: Int, sessions: Int, presentedBefore: Int, presentedAfter: Int)?
        run.user.onUserTurn = { session, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let window = run.user.windows.first
                window?.orderOut(nil)
                let presentedBefore = run.user.presented
                run.queue.start(id: run.id)
                checks = (sameWindow: run.user.windows.first === window && window != nil,
                          visible: window?.isVisible == true,
                          windowCount: run.user.windows.count,
                          sessions: run.queue.activeSessions.count,
                          presentedBefore: presentedBefore,
                          presentedAfter: run.user.presented)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                session.requestCancel()
            }
        }

        run.record()
        run.queue.start(id: run.id)
        run.queue.start(id: run.id)
        XCTAssertEqual(run.queue.activeSessions.count, 1)
        run.begin()
        try await run.waitUntil { _ in run.user.turns.count == 1 && run.queue.activeSessions.isEmpty && run.states.last == .waiting }

        let result = try XCTUnwrap(checks)
        XCTAssertTrue(result.sameWindow)
        XCTAssertTrue(result.visible)
        XCTAssertEqual(result.windowCount, 1)
        XCTAssertEqual(result.sessions, 1)
        XCTAssertEqual(result.presentedAfter, result.presentedBefore + 1)
        XCTAssertEqual(run.events.filter { $0 == .optOutStarted }.count, 1)
        assertWentBackToWaiting(run)
    }

    func testLeavingAHandOffAloneTimesOutAndPutsTheOptOutBackToWaiting() async throws {
        let timeout: TimeInterval = 20
        let run = try makeRun(attemptTimeout: timeout)
        var userTurnAt: Date?
        run.user.onUserTurn = { _, _ in userTurnAt = Date() }

        run.record()
        let startedAt = Date()
        run.startAndBegin()
        try await run.waitUntil(timeout: 60) { _ in run.queue.activeSessions.isEmpty && run.states.last == .waiting }
        let endedAt = Date()

        XCTAssertLessThan(try XCTUnwrap(userTurnAt).timeIntervalSince(startedAt), timeout)
        XCTAssertGreaterThanOrEqual(endedAt.timeIntervalSince(startedAt), timeout)
        XCTAssertLessThan(endedAt.timeIntervalSince(startedAt), timeout + 10)
        XCTAssertTrue(run.user.windows.isEmpty)
        XCTAssertEqual(run.user.dismissed, 1)
        assertWentBackToWaiting(run)

        run.queue.start(id: run.id)
        XCTAssertEqual(run.queue.activeSessions.count, 1, "A timed-out opt-out can be started again")
        run.queue.cancelAll()
        try await run.waitUntil { _ in run.queue.activeSessions.isEmpty }
    }

    func testTurningTheFlagOffMidAttemptHandsTheOptOutBackToTheRegularQueue() async throws {
        let run = try makeRun()
        run.user.onUserTurn = { _, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                run.dependencies.featureFlagger = MockDBPFeatureFlagger(isUserAssistanceOn: false)
                run.queue.refresh()
            }
        }

        run.record()
        run.startAndBegin()
        try await run.waitUntil { _ in run.user.turns.count == 1 && run.queue.activeSessions.isEmpty }
        try await waitForAttemptEnd(run)

        XCTAssertTrue(run.user.windows.isEmpty)
        XCTAssertEqual(run.user.dismissed, 1)
        XCTAssertEqual(run.events, [.optOutStarted, .optOutAwaitingUserAssistance])
        XCTAssertFalse(run.hasErrorEvent)
        XCTAssertFalse(run.database.wasUpdatedPreferredRunDateForOptOutCalled)
        run.syncHistory()
        XCTAssertEqual(run.queue.assistedOptOuts(), [], "Needs you is empty while the flag is off")

        let optOutEventsBefore = run.database.optOutEvents.count
        await runRegularJob(run.dependencies)
        XCTAssertTrue(run.dependencies.mockOptOutRunner.wasOptOutCalled, "The regular queue runs the opt-out")
        XCTAssertEqual(run.database.optOutEvents.dropFirst(optOutEventsBefore).first?.type, .optOutStarted)
    }

    func testRegularQueueLeavesTheOptOutAloneUntilTheAttemptHasStopped() async throws {
        let run = try makeRun()
        var ranBeforeTheAttemptStopped: Bool?
        run.user.onUserTurn = { _, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                run.dependencies.featureFlagger = MockDBPFeatureFlagger(isUserAssistanceOn: false)
                await self.runRegularJob(run.dependencies)
                ranBeforeTheAttemptStopped = run.dependencies.mockOptOutRunner.wasOptOutCalled
                run.queue.refresh()
            }
        }

        run.startAndBegin()
        try await run.waitUntil { _ in ranBeforeTheAttemptStopped != nil && run.queue.activeSessions.isEmpty }
        try await waitForAttemptEnd(run)

        XCTAssertEqual(ranBeforeTheAttemptStopped, false)
        // The mock scan finds no match, so the regular job's scan also records optOutConfirmed.
        XCTAssertEqual(run.events.filter { $0 != .optOutConfirmed }, [.optOutStarted, .optOutAwaitingUserAssistance])
        run.syncHistory()
        await runRegularJob(run.dependencies)
        XCTAssertTrue(run.dependencies.mockOptOutRunner.wasOptOutCalled)
    }

    func testNeedsYouShowsOneRowPerBrokerAndHidesItWhileItsWindowIsOpen() async throws {
        let run = try makeRun(extraProfiles: 1)
        run.syncHistory()
        let before = run.queue.assistedOptOuts()
        XCTAssertEqual(before.map(\.state), [.waiting])
        XCTAssertEqual(before.map(\.recordCount), [2])

        run.queue.start(id: run.id)
        let open = run.queue.assistedOptOuts()
        XCTAssertEqual(open.count, 1, "Only the open session's row, not a waiting row for the same broker: \(open)")
        XCTAssertEqual(open.first?.id, run.id.description)
        XCTAssertEqual(run.session?.recordCount, 2)

        run.queue.cancelAll()
        XCTAssertEqual(run.queue.assistedOptOuts().map(\.recordCount), [2])
    }

    // MARK: - Helpers

    private func assertWentBackToWaiting(_ run: Run, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(run.user.turns.map(\.step), ["Searching for your record"], file: file, line: line)
        XCTAssertEqual(run.states.count, 4, "States: \(run.states)", file: file, line: line)
        XCTAssertEqual(Array(run.states.prefix(2)), [.waiting, .agentInControl], file: file, line: line)
        XCTAssertTrue([.needsUser, .userInControl].contains(run.states.dropFirst(2).first), "States: \(run.states)", file: file, line: line)
        XCTAssertEqual(run.states.last, .waiting, file: file, line: line)
        XCTAssertEqual(run.events, [.optOutStarted, .optOutAwaitingUserAssistance], file: file, line: line)
        XCTAssertFalse(run.hasErrorEvent, file: file, line: line)
        XCTAssertFalse(run.database.wasUpdatedPreferredRunDateForOptOutCalled, file: file, line: line)
        run.syncHistory()
        XCTAssertEqual(run.queue.assistedOptOuts().map(\.state), [.waiting], file: file, line: line)
        XCTAssertNil(run.queue.assistedOptOuts().first?.step, file: file, line: line)
    }

    /// The queue drops the session before the runner has written its last event, so wait for that too.
    private func waitForAttemptEnd(_ run: Run) async throws {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, run.events.last != .optOutAwaitingUserAssistance {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func waitForFirstPageLoad(_ session: AssistedOptOutSession) async throws {
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if let webView = session.webView, !webView.isLoading, ["http", "https"].contains(webView.url?.scheme) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("The broker's first page never finished loading")
    }

    private func makeRun(attemptTimeout: TimeInterval = 240, extraProfiles: Int = 0) throws -> Run {
        let settings = DataBrokerProtectionSettings(defaults: defaults)
        settings.userAssistanceEnabledBrokersOverride = ["fakeassistedbroker.com"]

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let json = try Data(contentsOf: Self.fakeBrokerDirectory.appendingPathComponent("fakeassistedbroker.com.json"))
        let broker = try decoder.decode(DataBroker.self, from: json).with(id: 1)
        let profileQuery = ProfileQuery(id: 1, firstName: "Jane", lastName: "Doe", city: "Austin", state: "TX", birthYear: 1980)
        let optOuts = (0...extraProfiles).map { index -> OptOutJobData in
            let profileId = Int64(index + 1)
            let awaiting = HistoryEvent(extractedProfileId: profileId, brokerId: 1, profileQueryId: 1, type: .optOutAwaitingUserAssistance,
                                        date: Date().addingTimeInterval(-60))
            return OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: Date(), preferredRunDate: preferredRunDate,
                                 historyEvents: [awaiting], attemptCount: 0,
                                 extractedProfile: ExtractedProfile(id: profileId, name: "Jane Doe", profileUrl: "jane-doe-\(profileId)"))
        }
        let data = BrokerProfileQueryData(dataBroker: broker, profileQuery: profileQuery,
                                          scanJobData: ScanJobData(brokerId: 1, profileQueryId: 1, preferredRunDate: .distantFuture,
                                                                   historyEvents: []),
                                          optOutJobData: optOuts)

        let database = MockDatabase()
        database.brokerProfileQueryDataToReturn = [data]

        let privacyConfig = PrivacyConfigurationManagingMock()
        privacyConfig.currentConfig = Data(#"{ "features": {}, "unprotectedTemporary": [] }"#.utf8)
        let dependencies = MockBrokerProfileJobDependencies()
        dependencies.database = database
        dependencies.privacyConfig = privacyConfig
        dependencies.dataBrokerProtectionSettings = settings

        let queue = AssistedOptOutQueue(dependencies: dependencies, attemptTimeout: attemptTimeout)
        let user = ScriptedUser()
        queue.presenter = user
        let run = Run(queue: queue, user: user, database: database, dependencies: dependencies, initialData: data,
                      id: AssistedOptOutID(brokerId: 1, profileQueryId: 1, extractedProfileId: 1))
        runs.append(run)
        return run
    }

    private func runRegularJob(_ dependencies: MockBrokerProfileJobDependencies) async {
        let job = BrokerProfileJob(dataBrokerID: 1, jobType: .all, showWebView: false,
                                   statusReportingDelegate: MockBrokerProfileJobStatusReportingDelegate(), jobDependencies: dependencies)
        let finished = XCTestExpectation(description: "Job finished")
        job.completionBlock = { finished.fulfill() }
        job.start()
        await fulfillment(of: [finished], timeout: 15)
    }

    private func startServerIfNeeded() async throws {
        if await Self.isServing() { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = ["-m", "http.server", "3001", "--bind", "127.0.0.1"]
        process.currentDirectoryURL = Self.fakeBrokerDirectory
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        server = process
        for _ in 0..<50 {
            if await Self.isServing() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw XCTSkip("The fake assisted broker didn't start on port 3001")
    }

    private static func isServing() async -> Bool {
        let request = URLRequest(url: brokerURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData)
        let response = try? await URLSession(configuration: .ephemeral).data(for: request).1 as? HTTPURLResponse
        return response?.statusCode == 200
    }
}

@MainActor
private final class Run {
    let queue: AssistedOptOutQueue
    let user: ScriptedUser
    let database: MockDatabase
    let dependencies: MockBrokerProfileJobDependencies
    let initialData: BrokerProfileQueryData
    let id: AssistedOptOutID
    private(set) var states: [AssistedOptOut.State] = []
    private(set) var visitedSteps: [String] = []
    private(set) var beginMethod: String?
    private var history: [AssistedOptOut] = []

    init(queue: AssistedOptOutQueue, user: ScriptedUser, database: MockDatabase, dependencies: MockBrokerProfileJobDependencies,
         initialData: BrokerProfileQueryData, id: AssistedOptOutID) {
        self.queue = queue
        self.user = user
        self.database = database
        self.dependencies = dependencies
        self.initialData = initialData
        self.id = id
    }

    var session: AssistedOptOutSession? { queue.activeSessions.first { $0.id == id } }

    var events: [HistoryEvent.EventType] { database.optOutEvents.map(\.type) }

    var hasErrorEvent: Bool {
        events.contains { if case .error = $0 { return true } else { return false } }
    }

    /// Opens the window on its intro and presses Start request straight away, without recording the intro's state.
    func startAndBegin() {
        queue.start(id: id)
        begin()
    }

    func begin(viaWindow: Bool = false) {
        if viaWindow, WindowControls.press("Start request", in: user.windows.first) {
            beginMethod = "Start request button"
        } else {
            beginMethod = "session.begin()"
            session?.begin()
        }
    }

    /// MockDatabase doesn't fold added events back into what it returns, so do that here.
    func syncHistory() {
        let synced = initialData.optOutJobData.map { job in
            OptOutJobData(brokerId: job.brokerId, profileQueryId: job.profileQueryId, createdDate: job.createdDate,
                          preferredRunDate: job.preferredRunDate,
                          historyEvents: job.historyEvents + database.optOutEvents.filter { $0.extractedProfileId == job.extractedProfile.id },
                          attemptCount: job.attemptCount, extractedProfile: job.extractedProfile)
        }
        database.brokerProfileQueryDataToReturn = [BrokerProfileQueryData(dataBroker: initialData.dataBroker,
                                                                          profileQuery: initialData.profileQuery,
                                                                          scanJobData: initialData.scanJobData,
                                                                          optOutJobData: synced)]
    }

    /// Reads the Needs you list the way the dashboard's poll does, recording each distinct state and step.
    func record() {
        syncHistory()
        guard let item = queue.assistedOptOuts().first else { return }
        if item.state != states.last { states.append(item.state) }
        if let step = item.step?.title, step != visitedSteps.last { visitedSteps.append(step) }
        history.append(item)
    }

    func waitUntil(timeout: TimeInterval = 240, _ isDone: ([AssistedOptOut]) -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            record()
            if isDone(history) { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail("Timed out; states so far: \(states), steps: \(visitedSteps), events: \(events)")
    }
}

/// Forwards to the agent's real window presenter, recording what it's asked to do and acting as the user at each hand-off.
@MainActor
private final class ScriptedUser: AssistedOptOutPresenting {
    struct Turn {
        let state: AssistedOptOut.State
        let step: String?
    }

    private let presenter = AssistedOptOutWindowPresenter()
    var onUserTurn: ((AssistedOptOutSession, Int) -> Void)?
    private(set) var turns: [Turn] = []
    private(set) var presented = 0
    private(set) var dismissed = 0
    private(set) var openSize: NSSize?
    private(set) var handOffSizes: [NSSize] = []

    var windows: [NSWindow] {
        NSApp.windows.filter { $0.title == AssistedOptOutEndToEndTests.windowTitle && $0.isVisible }
    }

    /// Includes a hidden window.
    var anyWindow: NSWindow? {
        windows.first ?? NSApp.windows.first { $0.title == AssistedOptOutEndToEndTests.windowTitle }
    }

    func present(_ session: AssistedOptOutSession) {
        presented += 1
        presenter.present(session)
        if openSize == nil {
            openSize = windows.first?.frame.size
        }
    }

    func userTurnStarted(in session: AssistedOptOutSession) {
        presenter.userTurnStarted(in: session)
        if let size = anyWindow?.frame.size {
            handOffSizes.append(size)
        }
        let item = session.dashboardItem
        turns.append(Turn(state: item.state, step: item.step?.title))
        onUserTurn?(session, turns.count)
    }

    func dismiss(_ session: AssistedOptOutSession) {
        dismissed += 1
        presenter.dismiss(session)
    }
}

/// Finds the window's SwiftUI controls and text through its accessibility tree.
@MainActor
private enum WindowControls {
    static func press(_ title: String, in window: NSWindow?) -> Bool {
        guard let root = window?.contentView else { return false }
        var pressed = false
        walk(root) { element in
            guard !pressed, role(of: element) == .button, labels(of: element).contains(title) else { return }
            pressed = element.accessibilityPerformPress()
        }
        return pressed
    }

    static func texts(in window: NSWindow?) -> [String] {
        guard let root = window?.contentView else { return [] }
        var texts: [String] = []
        walk(root) { element in
            for label in labels(of: element) where !texts.contains(label) {
                texts.append(label)
            }
        }
        return texts
    }

    private static func role(of element: NSAccessibilityProtocol) -> NSAccessibility.Role? {
        let role: (() -> NSAccessibility.Role?)? = element.accessibilityRole
        return role?() ?? nil
    }

    private static func labels(of element: NSAccessibilityProtocol) -> [String] {
        let label: (() -> String?)? = element.accessibilityLabel
        let title: (() -> String?)? = element.accessibilityTitle
        let value: (() -> Any?)? = element.accessibilityValue
        return [label?() ?? nil, title?() ?? nil, (value?() ?? nil) as? String]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
    }

    private static func walk(_ element: NSAccessibilityProtocol, depth: Int = 0, _ visit: (NSAccessibilityProtocol) -> Void) {
        guard depth < 60 else { return }
        visit(element)
        let childrenOf: (() -> [Any]?)? = element.accessibilityChildren
        var children = (childrenOf?() ?? nil) ?? []
        if let view = element as? NSView {
            children += view.subviews.filter { subview in !children.contains { ($0 as AnyObject) === subview } }
        }
        for child in children {
            guard let child = child as? NSAccessibilityProtocol else { continue }
            if let view = child as? NSView, view.isHidden { continue }
            walk(child, depth: depth + 1, visit)
        }
    }
}

/// Saves PNGs of the whole window: CGWindowListCreateImage when it works, otherwise the content view composited with
/// a WKWebView snapshot (which loses anything drawn outside the content view, like the window shadow).
@MainActor
private final class WindowShooter {
    private static let directory: URL? = ProcessInfo.processInfo.environment["PIR_FAKE_ASSISTED_BROKER_SHOTS"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }
    private(set) var log: [String] = []

    func shoot(_ name: String, window: NSWindow?, webView: WKWebView?) async {
        guard let directory = Self.directory else { return }
        guard let window else {
            log.append("\(name): no window")
            return
        }
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let windowImage = Self.windowListImage(of: window)
        var image = windowImage
        var method = "CGWindowListCreateImage"
        if image == nil || image.map(Self.isBlank) == true {
            method = image == nil ? "composite (window list image nil)" : "composite (window list image blank)"
            image = await Self.composite(window, webView: webView)
        } else if let windowImage, let overlaid = await Self.overlayingWebSnapshot(on: windowImage, window: window, webView: webView) {
            // An occluded window's web view stops painting on screen, so its page is drawn from a snapshot instead.
            method = "CGWindowListCreateImage + WKWebView snapshot over the page"
            image = overlaid
            if let raw = NSBitmapImageRep(cgImage: windowImage).representation(using: .png, properties: [:]) {
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try? raw.write(to: directory.appendingPathComponent("\(name)-window-only.png"))
            }
        }
        guard let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            log.append("\(name): failed (\(method))")
            return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        do {
            try png.write(to: url)
            log.append("\(url.path): \(method) \(image.width)x\(image.height), window \(window.frame.size), visible \(window.isVisible)")
            if let webView {
                let state = try? await webView.evaluateJavaScript(Self.pageStateScript)
                log.append("  page: loading \(webView.isLoading), \(state ?? "-")")
                log.append("  app active \(NSApp.isActive), window key \(window.isKeyWindow), occlusion visible \(window.occlusionState.contains(.visible)), "
                           + "screen \(window.screen.map { "\($0.frame)" } ?? "nil"), frame \(window.frame)")
                log.append("  view: inWindow \(webView.window === window), hidden \(webView.isHiddenOrHasHiddenAncestor), alpha \(webView.alphaValue), "
                           + "frame \(webView.frame), superview \(webView.superview.map { String(describing: type(of: $0)) } ?? "nil"), "
                           + "siblings \(webView.superview?.subviews.map { "\(type(of: $0))\($0.isHidden ? "(hidden)" : "")" } ?? [])")
            }
        } catch {
            log.append("\(name): write failed \(error)")
        }
    }

    private static let pageStateScript = """
    JSON.stringify({ url: location.href, readyState: document.readyState, visibility: document.visibilityState,
                     text: document.body ? document.body.innerText.replace(/\\s+/g, ' ').slice(0, 80) : null,
                     inputs: [...document.querySelectorAll('input')].map(i => i.name + '=' + (i.type === 'checkbox' ? i.checked : i.value)).join(' '),
                     assistHost: !!document.querySelector('ddg-pir-assist') })
    """

    private typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    // Looked up at runtime because newer SDKs mark CGWindowListCreateImage unavailable.
    private static func windowListImage(of window: NSWindow) -> CGImage? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let create = unsafeBitCast(symbol, to: CreateImage.self)
        return create(.null, CGWindowListOption.optionIncludingWindow.rawValue, CGWindowID(window.windowNumber),
                      CGWindowImageOption([.bestResolution, .boundsIgnoreFraming]).rawValue)?.takeRetainedValue()
    }

    private static func overlayingWebSnapshot(on image: CGImage, window: NSWindow, webView: WKWebView?) async -> CGImage? {
        guard let webView, webView.window === window, !webView.isHiddenOrHasHiddenAncestor, !isCovered(webView),
              let snapshot = try? await webView.takeSnapshot(configuration: nil),
              let webImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let scale = CGFloat(image.width) / window.frame.width
        let rect = webView.convert(webView.bounds, to: nil)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.saveGState()
        let target = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        let radius = (webView.superview?.layer?.cornerRadius ?? 0) * scale
        context.addPath(CGPath(roundedRect: target, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(webImage, in: target)
        context.restoreGState()
        return context.makeImage()
    }

    private static func isBlank(_ image: CGImage) -> Bool {
        let size = 64
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              image.width > 1, image.height > 1 else { return true }
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return true }
        var distinct = Set<UInt32>()
        for index in 0..<(size * size) {
            let pixel = data.advanced(by: index * 4)
            distinct.insert(UInt32(pixel[0] >> 3) << 15 | UInt32(pixel[1] >> 3) << 10 | UInt32(pixel[2] >> 3) << 5 | UInt32(pixel[3] >> 3))
        }
        return distinct.count < 8
    }

    private static func composite(_ window: NSWindow, webView: WKWebView?) async -> CGImage? {
        guard let content = window.contentView,
              let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: rep)
        guard let base = rep.cgImage else { return nil }
        guard let webView, webView.window === window, !isCovered(webView),
              let snapshot = try? await webView.takeSnapshot(configuration: nil),
              let webImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let context = CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return base }
        let scale = CGFloat(base.width) / content.bounds.width
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        var rect = webView.convert(webView.bounds, to: content)
        if content.isFlipped {
            rect.origin.y = content.bounds.height - rect.maxY
        }
        context.draw(webImage, in: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale))
        return context.makeImage()
    }

    private static func isCovered(_ webView: WKWebView) -> Bool {
        guard let siblings = webView.superview?.subviews, let index = siblings.firstIndex(of: webView) else { return false }
        return siblings[(index + 1)...].contains { !$0.isHidden }
    }
}
