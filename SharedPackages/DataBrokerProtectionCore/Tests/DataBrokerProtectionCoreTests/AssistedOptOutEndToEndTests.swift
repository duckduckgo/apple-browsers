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

import Combine
import Foundation
import WebKit
import XCTest
@testable import DataBrokerProtectionCore
import DataBrokerProtectionCoreTestsUtils

/// Runs the fake assisted broker's opt-out through a real web view, the bundled C-S-S and the assisted queue,
/// with a scripted user acting on the page at each hand-off.
///
/// Needs network access to localhost and is skipped unless `PIR_FAKE_ASSISTED_BROKER_E2E=1`
/// (`TEST_RUNNER_PIR_FAKE_ASSISTED_BROKER_E2E=1` with xcodebuild). It starts
/// `macOS/LocalPackages/DataBrokerProtection-macOS/FakeAssistedBroker` on port 3001 unless something already serves it.
@MainActor
final class AssistedOptOutEndToEndTests: XCTestCase {

    private static let brokerURL = URL(string: "http://localhost:3001/optout.html")!
    private static let fakeBrokerDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("macOS/LocalPackages/DataBrokerProtection-macOS/FakeAssistedBroker")

    private var server: Process?
    private var defaults: UserDefaults!
    private let preferredRunDate = Date().addingTimeInterval(-3600)

    override func setUp() async throws {
        try await super.setUp()
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PIR_FAKE_ASSISTED_BROKER_E2E"] == "1",
                          "Set PIR_FAKE_ASSISTED_BROKER_E2E=1 to run the fake assisted broker end-to-end test")
        defaults = UserDefaults(suiteName: "AssistedOptOutEndToEndTests-\(UUID().uuidString)")
        try await startServerIfNeeded()
    }

    override func tearDown() async throws {
        server?.terminate()
        server?.waitUntilExit()
        server = nil
        try await super.tearDown()
    }

    func testScriptedUserCompletesEveryHandOff() async throws {
        let run = try makeRun()
        run.user.onUserTurn = { session, turn in
            let script: String
            switch turn {
            case 1: script = "document.getElementById('fake-turnstile').click()"
            case 2: script = "document.getElementById('fake-hcaptcha').click()"
            default: script = "document.getElementById('remove-button').click()"
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                _ = try? await session.webView?.evaluateJavaScript(script)
            }
        }

        run.record()
        run.queue.start(id: run.id)
        try await run.waitUntil { $0.last?.state == .submitted }

        let session = try XCTUnwrap(run.queue.activeSessions.first)
        XCTAssertEqual(run.user.turns.map(\.state), [.needsUser, .needsUser, .needsUser])
        XCTAssertEqual(run.user.turns.map(\.step), ["Searching for your record", "Prove you’re human", "Review and submit"])
        XCTAssertEqual(run.visitedSteps, ["Entering your name", "Searching for your record", "Selecting your record",
                                          "Prove you’re human", "Review and submit"])
        XCTAssertEqual(run.states, [.waiting, .agentInControl, .needsUser, .agentInControl, .needsUser, .agentInControl, .needsUser,
                                    .agentInControl, .submitted])
        XCTAssertEqual(run.user.turns.map(\.visualizesActions), [true, true, true])
        XCTAssertEqual(session.webView?.url?.lastPathComponent, "confirm.html")

        let events = run.database.optOutEvents.map(\.type)
        XCTAssertEqual(events.first, .optOutStarted)
        XCTAssertEqual(events.last, .optOutRequested)
        XCTAssertFalse(events.contains { if case .error = $0 { return true } else { return false } })
        let nextRun = try OperationPreferredDateCalculator().dateForOptOutOperation(currentPreferredRunDate: preferredRunDate,
                                                                                    optOutHistoryEvents: run.database.optOutEvents,
                                                                                    extractedProfileID: 1,
                                                                                    schedulingConfig: run.broker.schedulingConfig,
                                                                                    attemptCount: 0)
        XCTAssertGreaterThan(try XCTUnwrap(nextRun), Date())
    }

    func testCancellingAtTheFirstHandOffWaitsForTheUserAgain() async throws {
        let run = try makeRun()
        run.user.onUserTurn = { session, _ in
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                session.requestCancel()
            }
        }

        run.record()
        run.queue.start(id: run.id)
        try await run.waitUntil { $0.last?.state == .waiting && run.user.turns.count == 1 && run.queue.activeSessions.isEmpty }

        XCTAssertEqual(run.user.turns.map(\.step), ["Searching for your record"])
        XCTAssertEqual(run.database.optOutEvents.map(\.type), [.optOutStarted, .optOutAwaitingUserAssistance])
        XCTAssertFalse(run.database.wasUpdatedPreferredRunDateForOptOutCalled)
        let nextRun = try OperationPreferredDateCalculator().dateForOptOutOperation(currentPreferredRunDate: preferredRunDate,
                                                                                    optOutHistoryEvents: run.database.optOutEvents,
                                                                                    extractedProfileID: 1,
                                                                                    schedulingConfig: run.broker.schedulingConfig,
                                                                                    attemptCount: 0)
        XCTAssertEqual(nextRun, preferredRunDate)
        XCTAssertEqual(run.user.dismissed, 1)
        XCTAssertEqual(run.states, [.waiting, .agentInControl, .needsUser, .waiting])
    }

    // MARK: - Helpers

    private func makeRun() throws -> Run {
        let settings = DataBrokerProtectionSettings(defaults: defaults)
        settings.userAssistanceEnabledBrokersOverride = ["fakeassistedbroker.com"]

        let file = try XCTUnwrap(UserAssistanceTestBrokers.files.first { $0.lastPathComponent == "fakeassistedbroker.com.json" })
        let broker = try UserAssistanceTestBrokers.resource(from: file).broker.with(id: 1)
        let profileQuery = ProfileQuery(id: 1, firstName: "Jane", lastName: "Doe", city: "Austin", state: "TX", birthYear: 1980)
        let awaiting = HistoryEvent(extractedProfileId: 1, brokerId: 1, profileQueryId: 1, type: .optOutAwaitingUserAssistance,
                                    date: Date().addingTimeInterval(-60))
        let optOut = OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: Date(), preferredRunDate: preferredRunDate,
                                   historyEvents: [awaiting], attemptCount: 0,
                                   extractedProfile: ExtractedProfile(id: 1, name: "Jane Doe", profileUrl: "jane-doe"))

        let database = MockDatabase()
        database.brokerProfileQueryDataToReturn = [
            BrokerProfileQueryData(dataBroker: broker, profileQuery: profileQuery,
                                   scanJobData: ScanJobData(brokerId: 1, profileQueryId: 1, preferredRunDate: Date(), historyEvents: []),
                                   optOutJobData: [optOut])
        ]

        let privacyConfig = PrivacyConfigurationManagingMock()
        privacyConfig.currentConfig = Data(#"{ "features": {}, "unprotectedTemporary": [] }"#.utf8)
        let dependencies = MockBrokerProfileJobDependencies()
        dependencies.database = database
        dependencies.privacyConfig = privacyConfig
        dependencies.dataBrokerProtectionSettings = settings

        let queue = AssistedOptOutQueue(dependencies: dependencies, attemptTimeout: 240)
        let user = ScriptedUser()
        queue.presenter = user
        return Run(queue: queue, user: user, database: database, broker: broker,
                   id: AssistedOptOutID(brokerId: 1, profileQueryId: 1, extractedProfileId: 1))
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
    let broker: DataBroker
    let id: AssistedOptOutID
    private(set) var states: [AssistedOptOut.State] = []
    private(set) var visitedSteps: [String] = []

    init(queue: AssistedOptOutQueue, user: ScriptedUser, database: MockDatabase, broker: DataBroker, id: AssistedOptOutID) {
        self.queue = queue
        self.user = user
        self.database = database
        self.broker = broker
        self.id = id
    }

    private var history: [AssistedOptOut] = []

    /// Reads the Needs you list the way the dashboard's poll does, recording each distinct state and step.
    func record() {
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
        XCTFail("Timed out; states so far: \(states), steps: \(visitedSteps)")
    }
}

@MainActor
private final class ScriptedUser: AssistedOptOutPresenting {
    struct Turn {
        let state: AssistedOptOut.State
        let step: String?
        let visualizesActions: Bool
    }

    var onUserTurn: ((AssistedOptOutSession, Int) -> Void)?
    private(set) var turns: [Turn] = []
    private(set) var dismissed = 0

    func present(_ session: AssistedOptOutSession) {}

    func userTurnStarted(in session: AssistedOptOutSession) {
        let item = session.dashboardItem
        turns.append(Turn(state: item.state, step: item.step?.title, visualizesActions: session.webView?.injectsVisualizeActions == true))
        onUserTurn?(session, turns.count)
    }

    func dismiss(_ session: AssistedOptOutSession) {
        dismissed += 1
    }
}

private extension WKWebView {
    var injectsVisualizeActions: Bool {
        configuration.userContentController.userScripts.contains {
            // The config is embedded as a JSON string literal, so its quotes are escaped.
            $0.source.filter { !$0.isWhitespace && $0 != "\\" }.contains(#""visualizeActions":"enabled""#)
        }
    }
}
