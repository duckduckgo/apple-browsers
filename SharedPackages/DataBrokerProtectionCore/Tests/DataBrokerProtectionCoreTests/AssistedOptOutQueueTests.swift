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
#if DEBUG
    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func debugExcludedBrokerNeverEntersNeedsYou() async throws {
        let fixture = Fixture(history: .optOutRequested)
        let suite = "AssistedDebugBrokerSelectionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        fixture.dependencies.dataBrokerProtectionSettings = DataBrokerProtectionSettings(defaults: defaults)
        defaults.set(["beenverified.com"], forKey: "dbp.debug.testBrokerURLs")
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        #expect(try await queue.assistedOptOuts().isEmpty)
        #expect(fixture.database.scopedProfileFetchCount == 0)
        defaults.set(["testbroker.com"], forKey: "dbp.debug.testBrokerURLs")
        queue.invalidate()
        #expect(try await queue.assistedOptOuts().count == 1)
    }
#endif

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [true, false])
    func interruptedOrNilDateRecordIsListedWithoutAWriteAndDashboardReadsReuseScopedSnapshot(interrupted: Bool) async throws {
        let fixture = Fixture(history: interrupted ? .optOutStarted : .optOutRequested, deprecated: true,
                              preferredRunDate: interrupted ? .distantFuture : nil)
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        let first = try await queue.assistedOptOutList().optOuts
        let second = try await queue.assistedOptOutList().optOuts
        #expect(first == second)
        #expect(first.map(\.state) == [.waiting])
        #expect(fixture.database.optOutEvents.isEmpty)
        #expect(fixture.database.scopedProfileFetchCount == 1)
        #expect(!fixture.database.wasFetchActiveBrokerProfileQueryDataCalled)
        #expect(!fixture.database.wasFetchAllBrokerProfileQueryDataCalled)
        #expect(!fixture.database.wasFetchAllDataBrokersCalled)
        #expect(!fixture.database.wasUpdatedPreferredRunDateForOptOutCalled)
        queue.invalidate()
        _ = try await queue.assistedOptOutList().optOuts
        #expect(fixture.database.scopedProfileFetchCount == 2)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func sameIdentityReopensIntroAndAnotherRecordCannotOpenOrRun() async throws {
        let fixture = Fixture(records: 2)
        let presenter = Presenter()
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        queue.presenter = presenter
        #expect(try await queue.assistedOptOutList().optOuts.map { AssistedOptOutID($0.id)?.extractedProfileId } == [1, 2])
        try await queue.start(id: fixture.id)
        let session = try #require(queue.activeSessions.first)
        try await queue.start(id: fixture.id)
        try await queue.start(id: .init(brokerId: 1, profileQueryId: 1, extractedProfileId: 2))
        #expect(queue.activeSessions.count == 1)
        #expect(presenter.presentations.count == 3)
        #expect(presenter.presentations.allSatisfy { $0 === session })
        #expect(session.phase == .ready)
        #expect(!fixture.dependencies.mockAssistedOptOutRunner.wasOptOutCalled)
        session.requestCancel()
        #expect(queue.activeSessions.isEmpty)
        #expect(presenter.dismissals.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func flagOffHidesTheListAndLoadFailuresThrow() async throws {
        let fixture = Fixture(history: .optOutStarted)
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        fixture.flagger.isUserAssistanceOn = false
        #expect(try await queue.assistedOptOutList().optOuts.isEmpty)
        fixture.flagger.isUserAssistanceOn = true
        fixture.database.scopedProfileFetchHandler = { _ in throw DataBrokerProtectionError.jobTimeout }
        await #expect(throws: DataBrokerProtectionError.self) { try await queue.assistedOptOutList().optOuts }
        fixture.database.scopedProfileFetchHandler = nil
        #expect(try await queue.assistedOptOutList().optOuts.count == 1)
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [SnapshotRead.list, .start])
    func readResumingAfterTheSignInCheckUsesCurrentRecords(operation: SnapshotRead) async throws {
        let fixture = Fixture(history: .optOutStarted)
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        let authentication = AuthenticationGate()
        fixture.dependencies.isAuthenticatedUserProvider = { await authentication.check() }
        let oldRead = Task {
            switch operation {
            case .list: _ = try await queue.assistedOptOutList().optOuts
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
        let currentID = AssistedOptOutID(brokerId: 1, profileQueryId: 1, extractedProfileId: 2)
        try await queue.start(id: currentID)
        let currentSession = try #require(queue.activeSessions.first)
        await authentication.release()
        try await oldRead.value
        #expect(queue.activeSessions.first === currentSession)
        #expect(queue.activeSessions.map(\.id) == [currentID])
        #expect(fixture.database.optOutEvents.isEmpty)
        queue.cancelAll()
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [Ending.cancelled, .flagOff, .revoked, .timedOut, .failed, .submitted])
    func outcomeIsRecordedAfterCancellationAndTeardown(ending: Ending) async throws {
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
            #expect(queue.activeSessions.count == 1)
            await teardownGate.release()
        }
        let finishedResult = await XCTWaiter.fulfillment(of: [finished], timeout: 5)
        #expect(finishedResult == .completed)
        #expect(metrics.starts == 1)
        #expect(metrics.outcomes == [ending.outcome])
        #expect(queue.activeSessions.map(\.phase) == (ending == .submitted ? [.submitted] : []))
        if ending == .submitted {
            session.requestCancel()
            #expect(queue.activeSessions.isEmpty)
        }
        if ending != .submitted {
            #expect(!fixture.database.wasUpdatedPreferredRunDateForOptOutCalled)
            #expect(fixture.database.optOutEvents.last?.type == .optOutAwaitingUserAssistance)
        }
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func submittedRecordIsListedAgainOnlyWhenItIsDue() async throws {
        let fixture = Fixture()
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        fixture.setHistory(.optOutRequested, preferredRunDate: .distantFuture)
        queue.invalidate()
        #expect(try await queue.assistedOptOutList().optOuts.isEmpty)
        fixture.setHistory(.optOutRequested, preferredRunDate: nil)
        queue.invalidate()
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
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func unauthenticatedQueueCannotListOrStart() async throws {
        let fixture = Fixture(history: .optOutStarted)
        fixture.dependencies.isAuthenticatedUserProvider = { false }
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        try await queue.start(id: fixture.id)
        #expect(try await queue.assistedOptOutList().optOuts.isEmpty)
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

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func slotsAreTheLowestRecordIDsUpToTheLimit() {
        let ids = [5, 2, 4, 1, 3].map { AssistedOptOutID(brokerId: $0 % 2, profileQueryId: 1, extractedProfileId: Int64($0)) }
        #expect(AssistedOptOutQueue.assistedSlots(among: ids, limit: 3).map(\.extractedProfileId) == [1, 2, 3])
        #expect(AssistedOptOutQueue.assistedSlots(among: ids, limit: nil).map(\.extractedProfileId) == [1, 2, 3, 4, 5])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func capIsTotalAcrossBrokersAndCountsIgnoreRecordsTheUserRemoved() async throws {
        let fixture = Fixture()
        fixture.setSettings(#"{"enabledBrokers":["testbroker.com","otherbroker.com"],"maxAssistedRecords":3}"#)
        fixture.setRecords([.init(broker: 1, id: 0, history: .matchRemovedByUser),
                            .init(broker: 1, id: 5), .init(broker: 1, id: 2), .init(broker: 1, id: 4),
                            .init(broker: 2, id: 1), .init(broker: 2, id: 3)])
        let list = try await AssistedOptOutQueue(dependencies: fixture.dependencies).assistedOptOutList()
        #expect(Set(list.optOuts.map { AssistedOptOutID($0.id)?.extractedProfileId }) == [1, 2, 3])
        #expect(list.assistedLimit == 3)
        #expect(list.brokers == [.init(url: "otherbroker.com", recordCount: 2), .init(url: "testbroker.com", recordCount: 3)])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func finishedRecordsKeepTheirSlotsSoNothingElseIsListed() async throws {
        let fixture = Fixture()
        fixture.setRecords([.init(broker: 1, id: 1, history: .optOutRequested, removedDate: .distantPast),
                            .init(broker: 1, id: 2, history: .optOutSubmittedAndAwaitingEmailConfirmation),
                            .init(broker: 1, id: 3, history: .optOutRequested, preferredRunDate: .distantFuture),
                            .init(broker: 1, id: 4), .init(broker: 1, id: 5)])
        let list = try await AssistedOptOutQueue(dependencies: fixture.dependencies).assistedOptOutList()
        #expect(list.optOuts.isEmpty)
        #expect(list.brokers == [.init(url: "testbroker.com", recordCount: 5)])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func recordTheBrokerDroppedBeforeAnyOptOutFreesItsSlot() async throws {
        let fixture = Fixture()
        fixture.setRecords([.init(broker: 1, id: 1, history: .matchesFound(count: 1), removedDate: .distantPast),
                            .init(broker: 1, id: 2), .init(broker: 1, id: 3), .init(broker: 1, id: 4)])
        let list = try await AssistedOptOutQueue(dependencies: fixture.dependencies).assistedOptOutList()
        #expect(list.optOuts.map { AssistedOptOutID($0.id)?.extractedProfileId } == [2, 3, 4])
        #expect(list.brokers == [.init(url: "testbroker.com", recordCount: 3)])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func recordTheBrokerDroppedAfterAnOptOutStartedKeepsItsSlot() async throws {
        let fixture = Fixture()
        fixture.setRecords([.init(broker: 1, id: 1, history: .optOutStarted, removedDate: .distantPast),
                            .init(broker: 1, id: 2), .init(broker: 1, id: 3), .init(broker: 1, id: 4)])
        let list = try await AssistedOptOutQueue(dependencies: fixture.dependencies).assistedOptOutList()
        #expect(list.optOuts.map { AssistedOptOutID($0.id)?.extractedProfileId } == [2, 3])
        #expect(list.brokers == [.init(url: "testbroker.com", recordCount: 4)])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func recordsFoundLaterDoNotTakeASlot() async throws {
        let fixture = Fixture()
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        fixture.setRecords([.init(broker: 1, id: 7), .init(broker: 1, id: 8), .init(broker: 1, id: 9)])
        #expect(try await queue.assistedOptOutList().optOuts.map { AssistedOptOutID($0.id)?.extractedProfileId } == [7, 8, 9])
        fixture.setRecords([.init(broker: 1, id: 7), .init(broker: 1, id: 8), .init(broker: 1, id: 9),
                            .init(broker: 1, id: 10), .init(broker: 1, id: 11)])
        queue.invalidate()
        #expect(try await queue.assistedOptOutList().optOuts.map { AssistedOptOutID($0.id)?.extractedProfileId } == [7, 8, 9])
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)))
    func changingTheCapInRemoteConfigTakesEffectWithoutAnInvalidation() async throws {
        let fixture = Fixture()
        let queue = AssistedOptOutQueue(dependencies: fixture.dependencies)
        fixture.setRecords((1...5).map { .init(broker: 1, id: Int64($0)) })

        fixture.setSettings(#"{"enabledBrokers":["testbroker.com"]}"#)
        let defaultList = try await queue.assistedOptOutList()
        #expect(defaultList.optOuts.count == 3)
        #expect(try encodedKeys(defaultList).contains("assistedLimit"))

        fixture.setSettings(#"{"enabledBrokers":["testbroker.com"],"maxAssistedRecords":2}"#)
        #expect(try await queue.assistedOptOutList().optOuts.map { AssistedOptOutID($0.id)?.extractedProfileId } == [1, 2])

        fixture.setSettings(#"{"enabledBrokers":["testbroker.com"],"maxAssistedRecords":-1}"#)
        let uncapped = try await queue.assistedOptOutList()
        #expect(uncapped.optOuts.count == 5)
        #expect(uncapped.assistedLimit == nil)
        #expect(try !encodedKeys(uncapped).contains("assistedLimit"))
    }

    @available(iOS 16, macOS 13, *)
    @Test(.timeLimit(.minutes(1)), arguments: [
        (#""#, 3), (#","maxAssistedRecords":-1"#, nil), (#","maxAssistedRecords":0"#, 0),
        (#","maxAssistedRecords":5"#, 5), (#","maxAssistedRecords":-5"#, 3), (#","maxAssistedRecords":"5""#, 3)
    ] as [(String, Int?)])
    func remoteCapDecodesToAnOptionalLimit(fragment: String, limit: Int?) throws {
        let json = #"{"enabledBrokers":["testbroker.com"]"# + fragment + "}"
        let config = try JSONDecoder().decode(UserAssistanceConfig.self, from: Data(json.utf8))
        #expect(config.maxAssistedRecords == limit)
        #expect(config.enabledBrokers == ["testbroker.com"])
    }

    private func encodedKeys(_ list: AssistedOptOutList) throws -> [String] {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(list)) as? [String: Any]
        return object.map { Array($0.keys) } ?? []
    }

    enum SnapshotRead: Sendable { case list, start }

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
    let privacyConfig = PrivacyConfigurationMock()
    let id = AssistedOptOutID(brokerId: 1, profileQueryId: 1, extractedProfileId: 1)

    init(history: HistoryEvent.EventType = .optOutAwaitingUserAssistance, records: Int = 1, deprecated: Bool = false, preferredRunDate: Date? = .distantPast) {
        dependencies.database = database
        dependencies.featureFlagger = flagger
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
        let broker = DataBroker(id: 1, name: "Test broker", url: "testbroker.com",
                                steps: [Step(type: .scan, actions: []), Step(type: .optOut, actions: [UserAssistAction(id: "assist")])],
                                version: "1.0", schedulingConfig: .mock, optOutUrl: "", eTag: "", removedAt: nil)
        database.brokerProfileQueryDataToReturn = [.init(dataBroker: broker, profileQuery: profile, scanJobData: .mock, optOutJobData: jobs)]
        database.dataBrokersToReturn = [broker]
        database.optOutToReturn = jobs.first
    }

    struct Record {
        let broker: Int64
        let id: Int64
        var history: HistoryEvent.EventType = .optOutAwaitingUserAssistance
        var preferredRunDate: Date? = .distantPast
        var removedDate: Date?
    }

    func setSettings(_ json: String) {
        privacyConfig.subfeatureSettings = json
    }

    func setRecords(_ records: [Record]) {
        let profile = ProfileQuery(id: 1, firstName: "a", lastName: "b", city: "c", state: "d", birthYear: 1980)
        let brokers = [(1, "testbroker.com"), (2, "otherbroker.com")].map { id, url in
            DataBroker(id: Int64(id), name: url, url: url,
                       steps: [Step(type: .scan, actions: []), Step(type: .optOut, actions: [UserAssistAction(id: "assist")])],
                       version: "1.0", schedulingConfig: .mock, optOutUrl: "", eTag: "", removedAt: nil)
        }
        database.dataBrokersToReturn = brokers
        database.brokerProfileQueryDataToReturn = brokers.map { broker in
            let jobs = records.filter { $0.broker == broker.id }.map { record in
                OptOutJobData(brokerId: record.broker, profileQueryId: 1, createdDate: .distantPast,
                              preferredRunDate: record.preferredRunDate,
                              historyEvents: [HistoryEvent(extractedProfileId: record.id, brokerId: record.broker, profileQueryId: 1,
                                                           type: record.history, date: .distantPast)],
                              attemptCount: 0,
                              extractedProfile: ExtractedProfile(id: record.id, name: "Jane Doe \(record.id)",
                                                                 addresses: [AddressCityState(city: "Austin", state: "TX")],
                                                                 profileUrl: "profile\(record.id)", age: "42",
                                                                 removedDate: record.removedDate))
            }
            return BrokerProfileQueryData(dataBroker: broker, profileQuery: profile, scanJobData: .mock, optOutJobData: jobs)
        }
        database.optOutToReturn = database.brokerProfileQueryDataToReturn.first?.optOutJobData.first
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
    nonisolated let entered = XCTestExpectation(description: "Authentication entered")
    private let gate = TeardownGate()

    func check() async -> Bool {
        entered.fulfill()
        await gate.wait()
        return true
    }

    func release() async { await gate.release() }
}
