//
//  AssistedOptOutQueueTests.swift
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

import DataBrokerProtectionCoreTestsUtils
import Foundation
import Testing
import WebKit
import XCTest
@testable import DataBrokerProtectionCore

@MainActor
struct AssistedOptOutQueueTests {
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func interruptedOrNilDateAttemptEntersAwaitingOnceAndDashboardReadsReuseScopedSnapshot(interrupted: Bool) async throws {
        let fixture = Fixture(history: interrupted ? .optOutStarted : .optOutRequested, deprecated: true,
                              preferredRunDate: interrupted ? .distantFuture : nil)
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        try await queue.refresh()
        try await queue.refresh()
        let first = try await queue.assistedOptOuts()
        let second = try await queue.assistedOptOuts()
        #expect(first == second)
        #expect(first.map(\.state) == [.waiting])
        #expect(fixture.database.optOutEvents.map(\.type) == [.optOutAwaitingUserAssistance])
        #expect(fixture.database.scopedProfileFetchCount == 1)
        #expect(!fixture.database.wasFetchActiveBrokerProfileQueryDataCalled)
        #expect(!fixture.database.wasFetchAllBrokerProfileQueryDataCalled)
        #expect(!fixture.database.wasUpdatedPreferredRunDateForOptOutCalled)
        queue.invalidate()
        _ = try await queue.assistedOptOuts()
        #expect(fixture.database.scopedProfileFetchCount == 2)
        #expect(fixture.database.optOutEvents.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sameIdentityReopensIntroAndAnotherRecordCannotOpenOrRun() async throws {
        let fixture = Fixture(records: 2)
        let presenter = Presenter()
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        queue.presenter = presenter
        #expect(try await queue.assistedOptOuts().map(\.extractedProfileId) == [1, 2])
        try await queue.start(id: fixture.id)
        let session = try #require(queue.activeSessions.first)
        try await queue.start(id: fixture.id)
        try await queue.start(id: .init(brokerId: 1, profileQueryId: 1, extractedProfileId: 2))
        #expect(queue.activeSessions.count == 1)
        #expect(presenter.presentations.count == 2)
        #expect(presenter.presentations.allSatisfy { $0 === session })
        #expect(session.phase == .ready)
        #expect(!fixture.dependencies.runningAssistedOptOuts.contains(fixture.id))
        #expect(!fixture.dependencies.mockAssistedOptOutRunner.wasOptOutCalled)
        session.requestCancel()
        #expect(queue.activeSessions.isEmpty)
        #expect(presenter.dismissals.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func flagOffDuringLoadCannotInstallSnapshotOrWriteAwaitingAndLoadFailuresThrow() async throws {
        let fixture = Fixture(history: .optOutStarted)
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        let entered = XCTestExpectation(description: "Scoped read entered")
        let release = DispatchSemaphore(value: 0)
        let data = fixture.database.brokerProfileQueryDataToReturn
        fixture.database.scopedProfileFetchHandler = { _ in
            #expect(!Thread.isMainThread)
            entered.fulfill()
            _ = release.wait(timeout: .now() + 10)
            return data
        }
        let refresh = Task { try await queue.refresh() }
        let enteredResult = await XCTWaiter.fulfillment(of: [entered], timeout: 5)
        #expect(enteredResult == .completed)
        fixture.flagger.isUserAssistanceOn = false
        queue.configurationDidChange()
        release.signal()
        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(fixture.database.optOutEvents.isEmpty)
        #expect(try await queue.assistedOptOuts().isEmpty)
        fixture.flagger.isUserAssistanceOn = true
        fixture.database.scopedProfileFetchHandler = { _ in throw DataBrokerProtectionError.jobTimeout }
        await #expect(throws: DataBrokerProtectionError.self) { try await queue.assistedOptOuts() }
        fixture.database.scopedProfileFetchHandler = nil
        try await queue.refresh()
        #expect(try await queue.assistedOptOuts().count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func invalidationDuringLoadDoesNotTreatSupersededSnapshotAsEmptyOrCancelOpenSession() async throws {
        let fixture = Fixture()
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        try await queue.start(id: fixture.id)
        let session = try #require(queue.activeSessions.first)
        queue.invalidate()
        let entered = XCTestExpectation(description: "Scoped read entered")
        let release = DispatchSemaphore(value: 0)
        let data = fixture.database.brokerProfileQueryDataToReturn
        fixture.database.scopedProfileFetchHandler = { _ in
            entered.fulfill()
            _ = release.wait(timeout: .now() + 10)
            return data
        }
        let refresh = Task { try await queue.refresh() }
        #expect(await XCTWaiter.fulfillment(of: [entered], timeout: 5) == .completed)
        queue.invalidate()
        release.signal()
        await #expect(throws: CancellationError.self) { try await refresh.value }
        #expect(queue.activeSessions.first === session)
        fixture.database.scopedProfileFetchHandler = nil
        #expect(try await queue.assistedOptOuts().count == 1)
        queue.cancelAll()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [SnapshotRead.refresh, .list, .start])
    func postLoadAuthenticationCannotConsumeSnapshotInvalidatedWhileItSuspends(operation: SnapshotRead) async throws {
        let fixture = Fixture(history: .optOutStarted)
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        let authentication = AuthenticationGate()
        fixture.dependencies.isAuthenticatedUserProvider = { await authentication.check() }
        let oldRead = Task {
            switch operation {
            case .refresh: try await queue.refresh()
            case .list: _ = try await queue.assistedOptOuts()
            case .start: try await queue.start(id: fixture.id)
            }
        }
        #expect(await XCTWaiter.fulfillment(of: [authentication.entered], timeout: 5) == .completed)
        fixture.dependencies.isAuthenticatedUserProvider = { true }
        let data = try #require(fixture.database.brokerProfileQueryDataToReturn.first)
        let job = OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: .distantPast, preferredRunDate: .distantPast,
                                historyEvents: [.init(extractedProfileId: 2, brokerId: 1, profileQueryId: 1,
                                                      type: .optOutAwaitingUserAssistance)],
                                attemptCount: 0, extractedProfile: ExtractedProfile(id: 2, name: "Other", profileUrl: "other"))
        fixture.database.brokerProfileQueryDataToReturn = [.init(dataBroker: data.dataBroker, profileQuery: data.profileQuery,
                                                                scanJobData: data.scanJobData, optOutJobData: [job])]
        fixture.database.optOutToReturn = job
        queue.invalidate()
        try await queue.refresh()
        let currentID = AssistedOptOutID(brokerId: 1, profileQueryId: 1, extractedProfileId: 2)
        try await queue.start(id: currentID)
        let currentSession = try #require(queue.activeSessions.first)
        await authentication.release()
        await #expect(throws: CancellationError.self) { try await oldRead.value }
        #expect(queue.activeSessions.first === currentSession)
        #expect(queue.activeSessions.map(\.id) == [currentID])
        #expect(fixture.database.optOutEvents.isEmpty)
        queue.cancelAll()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [Ending.cancelled, .flagOff, .revoked, .timedOut, .failed, .submitted])
    func runningRegistryOutlivesCancellationAndTeardownAndOutcomeIsRecorded(ending: Ending) async throws {
        let fixture = Fixture()
        let metrics = Metrics()
        let finished = XCTestExpectation(description: "Attempt finished")
        metrics.onEnd = { finished.fulfill() }
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies,
                                        attemptTimeout: ending == .timedOut ? 0.01 : 60, instrumentation: metrics)
        let entered = XCTestExpectation(description: "Runner entered")
        let tearingDown = XCTestExpectation(description: "Runner tearing down")
        let teardownGate = TeardownGate()
        fixture.dependencies.mockAssistedOptOutRunner.optOutHandler = {
            #expect(fixture.dependencies.runningAssistedOptOuts.contains(fixture.id))
            entered.fulfill()
            switch ending {
            case .failed: throw DataBrokerProtectionError.unknown("failed")
            case .submitted: return
            case .cancelled, .flagOff, .revoked, .timedOut:
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch {
                    tearingDown.fulfill()
                    await teardownGate.wait()
                    throw error
                }
            }
        }
        try await queue.start(id: fixture.id)
        let session = try #require(queue.activeSessions.first)
        session.begin()
        #expect(fixture.dependencies.runningAssistedOptOuts.contains(fixture.id))
        let enteredResult = await XCTWaiter.fulfillment(of: [entered], timeout: 5)
        #expect(enteredResult == .completed)
        if ending == .cancelled { session.requestCancel() }
        if ending == .flagOff {
            fixture.flagger.isUserAssistanceOn = false
            queue.configurationDidChange()
        }
        if ending == .revoked {
            fixture.manager.setRevokedBundleSigningKeyIDs(PrivacyConfigurationManagingMock.builtInBundleSigningKeyIDs)
            queue.configurationDidChange()
        }
        if ending == .cancelled || ending == .flagOff || ending == .revoked || ending == .timedOut {
            let teardownResult = await XCTWaiter.fulfillment(of: [tearingDown], timeout: 5)
            #expect(teardownResult == .completed)
            #expect(fixture.dependencies.runningAssistedOptOuts.contains(fixture.id))
            await teardownGate.release()
        }
        let finishedResult = await XCTWaiter.fulfillment(of: [finished], timeout: 5)
        #expect(finishedResult == .completed)
        #expect(!fixture.dependencies.runningAssistedOptOuts.contains(fixture.id))
        #expect(metrics.starts == 1)
        #expect(metrics.outcomes == [ending.outcome])
        #expect(queue.activeSessions.map(\.phase) == (ending == .submitted ? [.submitted] : []))
        if ending != .submitted {
            #expect(!fixture.database.wasUpdatedPreferredRunDateForOptOutCalled)
            #expect(fixture.database.optOutEvents.last?.type == .optOutAwaitingUserAssistance)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func enablingAssistanceLeavesLiveRegularRecordOwnedUntilItsRunnerFinishes() async throws {
        let fixture = Fixture(history: .optOutStarted)
        fixture.flagger.isUserAssistanceOn = false
        let data = try #require(fixture.database.brokerProfileQueryDataToReturn.first)
        let entered = XCTestExpectation(description: "Regular runner entered")
        let regularGate = TeardownGate()
        fixture.dependencies.mockOptOutRunner.optOutHandler = {
            entered.fulfill()
            await regularGate.wait()
        }
        let regular = Task {
            try await BrokerProfileOptOutSubJob(dependencies: fixture.dependencies).runOptOut(
                for: data.optOutJobData[0].extractedProfile, brokerProfileQueryData: data,
                showWebView: false, shouldRunNextStep: { true })
        }
        let enteredResult = await XCTWaiter.fulfillment(of: [entered], timeout: 5)
        #expect(enteredResult == .completed)
        fixture.flagger.isUserAssistanceOn = true
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        try await queue.refresh()
        try await queue.start(id: fixture.id)
        #expect(queue.activeSessions.isEmpty)
        #expect(try await queue.assistedOptOuts().isEmpty)
        #expect(fixture.database.optOutEvents.map(\.type) == [.optOutStarted])
        #expect(!fixture.dependencies.mockAssistedOptOutRunner.wasOptOutCalled)
        await regularGate.release()
        #expect(try await regular.value)
        #expect(!fixture.dependencies.runningAssistedOptOuts.contains(fixture.id))
        fixture.setHistory(.optOutRequested, preferredRunDate: .distantFuture)
        queue.invalidate()
        try await queue.refresh()
        #expect(try await queue.assistedOptOuts().isEmpty)
        fixture.setHistory(.optOutRequested, preferredRunDate: nil)
        queue.invalidate()
        try await queue.refresh()
        try await queue.start(id: fixture.id)
        #expect(queue.activeSessions.count == 1)
        queue.cancelAll()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func revokedSigningKeyPreventsOpeningAndBeginningAnAttempt() async throws {
        let fixture = Fixture()
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        fixture.manager.setRevokedBundleSigningKeyIDs(PrivacyConfigurationManagingMock.builtInBundleSigningKeyIDs)
        try await queue.start(id: fixture.id)
        #expect(queue.activeSessions.isEmpty)
        fixture.manager.setRevokedBundleSigningKeyIDs([])
        try await queue.start(id: fixture.id)
        let session = try #require(queue.activeSessions.first)
        fixture.manager.setRevokedBundleSigningKeyIDs(PrivacyConfigurationManagingMock.builtInBundleSigningKeyIDs)
        session.begin()
        #expect(queue.activeSessions.isEmpty)
        #expect(!fixture.dependencies.mockAssistedOptOutRunner.wasOptOutCalled)
        #expect(!fixture.dependencies.runningAssistedOptOuts.contains(fixture.id))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func productionRunnerClaimsCancellationButWaitsForInitializationAndWebViewTeardown(duringInitialization: Bool) async {
        let action = NavigateAction(id: "navigate", actionType: .navigate, url: "https://example.com")
        let runner = BrokerProfileOptOutSubJobWebRunner(
            privacyConfig: PrivacyConfigurationManagingMock(), prefs: .mock,
            context: BrokerProfileQueryData.mock(with: [Step(type: .optOut, actions: [action])]),
            emailConfirmationDataService: MockEmailConfirmationDataServiceProvider(), captchaService: CaptchaServiceMock(),
            featureFlagger: MockDBPFeatureFlagger(), operationAwaitTime: 0,
            stageCalculator: MockStageDurationCalculator(), pixelHandler: MockDataBrokerProtectionPixelsHandler(),
            executionConfig: BrokerJobExecutionConfig(), actionsHandlerMode: .optOut, shouldRunNextStep: { true })
        let handler = WebViewHandlerMock()
        let dispatched = XCTestExpectation(description: "Action dispatched")
        let tearingDown = XCTestExpectation(description: "Web view teardown entered")
        let teardownGate = TeardownGate()
        let initializationGate = TeardownGate()
        if duringInitialization {
            handler.initializeWebViewHandler = {
                dispatched.fulfill()
                await initializationGate.wait()
            }
        } else {
            handler.executeHandler = { dispatched.fulfill() }
        }
        handler.asyncFinishHandler = {
            if handler.finishCallCount == 1 { tearingDown.fulfill() }
            await teardownGate.wait()
        }
        var didFinish = false
        let task = Task { @MainActor in
            do {
                try await runner.run(inputValue: .mockWithoutRemovedDate, webViewHandler: handler,
                                     actionsHandler: nil, showWebView: false)
                Issue.record("Cancellation must win over late callbacks")
            } catch {
                #expect(error as? DataBrokerProtectionError == .cancelled)
            }
            didFinish = true
        }
        let dispatchedResult = await XCTWaiter.fulfillment(of: [dispatched], timeout: 5)
        #expect(dispatchedResult == .completed)
        task.cancel()
        await Task.yield()
        #expect(!didFinish)
        await initializationGate.release()
        let teardownResult = await XCTWaiter.fulfillment(of: [tearingDown], timeout: 5)
        #expect(teardownResult == .completed)
        runner.complete(())
        runner.failed(with: DataBrokerProtectionError.jobTimeout)
        #expect(!didFinish)
        await teardownGate.release()
        await task.value
        #expect(didFinish)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unauthenticatedQueueCannotEnrollListOrStart() async throws {
        let fixture = Fixture(history: .optOutStarted)
        fixture.dependencies.isAuthenticatedUserProvider = { false }
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        try await queue.refresh()
        try await queue.start(id: fixture.id)
        #expect(try await queue.assistedOptOuts().isEmpty)
        #expect(queue.activeSessions.isEmpty)
        #expect(fixture.database.optOutEvents.isEmpty)
        #expect(fixture.database.scopedProfileFetchCount == 0)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sessionDeduplicatesHandoffsAndMeasuresFirstAndCumulativeUserTurns() throws {
        let fixture = Fixture()
        let metrics = Metrics()
        var now = Date(timeIntervalSince1970: 100)
        let session = AssistedOptOutSession(id: fixture.id, broker: .init(name: "Broker", url: "broker.com"),
                                            steps: .init(titles: []), instrumentation: metrics, now: { now })
        session.begin()
        now.addTimeInterval(3)
        session.attemptNeedsUser(actionID: "a")
        now.addTimeInterval(5)
        session.attemptNeedsUser(actionID: "a")
        let action = ClickAction(id: "b", actionType: .click)
        session.attemptWillRun(action)
        now.addTimeInterval(2)
        session.attemptNeedsUser(actionID: "b")
        now.addTimeInterval(4)
        session.markSubmitted()
        session.finish(outcome: .submitted)
        session.finish(outcome: .failed)
        #expect(metrics.firstTurnDurations == [3])
        #expect(metrics.totalDurations == [14])
        #expect(metrics.userTurnDurations == [9])
        #expect(metrics.outcomes == [.submitted])
    }

    enum SnapshotRead: Sendable { case refresh, list, start }

    enum Ending: Sendable {
        case cancelled, flagOff, revoked, timedOut, failed, submitted

        var outcome: AssistedOptOutOutcome {
            switch self {
            case .cancelled, .flagOff, .revoked: return .cancelled
            case .timedOut: return .timedOut
            case .failed: return .failed
            case .submitted: return .submitted
            }
        }
    }
}

@MainActor
private struct Fixture {
    let dependencies = MockBrokerProfileJobDependencies()
    let database = MockDatabase()
    let flagger = MockDBPFeatureFlagger(isUserAssistanceOn: true)
    let manager = PrivacyConfigurationManagingMock()
    let id = AssistedOptOutID(brokerId: 1, profileQueryId: 1, extractedProfileId: 1)

    init(history: HistoryEvent.EventType = .optOutAwaitingUserAssistance, records: Int = 1, deprecated: Bool = false, preferredRunDate: Date? = .distantPast) {
        dependencies.database = database
        dependencies.featureFlagger = flagger
        let privacyConfig = PrivacyConfigurationMock()
        privacyConfig.subfeatureSettings = #"{"enabledBrokers":["testbroker.com"]}"#
        manager.privacyConfig = privacyConfig
        dependencies.privacyConfig = manager
        let jobs = (1...records).map { index in
            OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: .distantPast, preferredRunDate: preferredRunDate,
                          historyEvents: [HistoryEvent(extractedProfileId: Int64(index), brokerId: 1, profileQueryId: 1,
                                                       type: history, date: .distantPast)],
                          attemptCount: 0, extractedProfile: ExtractedProfile(id: Int64(index), name: "Name", profileUrl: "profile"))
        }
        let profile = ProfileQuery(id: 1, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1980, deprecated: deprecated)
        database.brokerProfileQueryDataToReturn = [.init(dataBroker: .mock, profileQuery: profile, scanJobData: .mock, optOutJobData: jobs)]
        database.dataBrokersToReturn = [.mock]
        database.optOutToReturn = jobs.first
    }

    func setHistory(_ history: HistoryEvent.EventType, preferredRunDate: Date?) {
        guard let data = database.brokerProfileQueryDataToReturn.first, let job = data.optOutJobData.first else { return }
        let updated = OptOutJobData(brokerId: 1, profileQueryId: 1, createdDate: job.createdDate,
                                    preferredRunDate: preferredRunDate,
                                    historyEvents: [.init(extractedProfileId: 1, brokerId: 1, profileQueryId: 1, type: history)],
                                    attemptCount: 0, extractedProfile: job.extractedProfile)
        database.brokerProfileQueryDataToReturn = [.init(dataBroker: data.dataBroker, profileQuery: data.profileQuery,
                                                        scanJobData: data.scanJobData, optOutJobData: [updated])]
        database.optOutToReturn = updated
    }
}

@MainActor
private final class Presenter: AssistedOptOutPresenting {
    var presentations: [AssistedOptOutSession] = []
    var dismissals: [AssistedOptOutSession] = []
    func present(_ session: AssistedOptOutSession) { presentations.append(session) }
    func userTurnStarted(in session: AssistedOptOutSession) {}
    func dismiss(_ session: AssistedOptOutSession) { dismissals.append(session) }
}

@MainActor
private final class Metrics: AssistedOptOutInstrumentation {
    var starts = 0
    var firstTurnDurations: [TimeInterval] = []
    var totalDurations: [TimeInterval] = []
    var userTurnDurations: [TimeInterval] = []
    var outcomes: [AssistedOptOutOutcome] = []
    var onEnd: (() -> Void)?
    func started() { starts += 1 }
    func reachedUserTurn(after duration: TimeInterval) { firstTurnDurations.append(duration) }
    func ended(outcome: AssistedOptOutOutcome, totalDuration: TimeInterval, userTurnDuration: TimeInterval) {
        outcomes.append(outcome)
        totalDurations.append(totalDuration)
        userTurnDurations.append(userTurnDuration)
        onEnd?()
    }
}

private actor TeardownGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

private actor AuthenticationGate {
    nonisolated let entered = XCTestExpectation(description: "Post-load authentication entered")
    private let gate = TeardownGate()
    private var calls = 0

    func check() async -> Bool {
        calls += 1
        if calls == 2 {
            entered.fulfill()
            await gate.wait()
        }
        return true
    }

    func release() async { await gate.release() }
}
