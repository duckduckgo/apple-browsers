//
//  AIChatInitialPromptSessionTests.swift
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

import AIChat
import XCTest
@testable import DuckDuckGo

@MainActor
final class AIChatInitialPromptSessionTests: XCTestCase {
    private let prompt = AIChatNativePrompt.queryPrompt("initial", autoSubmit: true)

    func testInactiveSessionUsesSharedSource() {
        let session = AIChatInitialPromptSession()
        assertSharedHandler(session.consumeInitialPrompt())
        XCTAssertFalse(session.isProtectedFromCacheEviction)
    }

    func testPreparationValidatesContextsAndMeasuresOnlyConsumption() async throws {
        let session = AIChatInitialPromptSession()
        let kept = context("kept")
        var consumed = 0
        let reservation = InitialPromptTestReservation()
        var submissions: [MultiTabAttachmentRequest.SubmissionResult] = []
        let prepared = expectation(description: "Prompt prepared")
        var delivery: AIChatInitialPromptDelivery?
        session.prepare(prompt, request: .init(contexts: { [kept, self.context("closed")] },
                                               didConsume: { consumed += 1 }, cancel: { reservation.release() },
                                               validate: { $0.filter { $0.tabId == "kept" } },
                                               didDispatch: { submissions.append($0) })) {
            delivery = $0
            XCTAssertFalse(session.isProtectedFromCacheEviction)
            XCTAssertTrue(reservation.isReleased)
            prepared.fulfill()
        }
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        await fulfillment(of: [prepared], timeout: 1)
        XCTAssertEqual(consumed, 1)
        XCTAssertTrue(reservation.isReleased)
        XCTAssertTrue(submissions.isEmpty)
        session.install(try XCTUnwrap(delivery))
        XCTAssertEqual(consume(session), .queryPrompt("initial", autoSubmit: true, pageContext: .multiple([kept])))
        XCTAssertNil(consume(session))
        XCTAssertEqual(submissions.count, 1)
        XCTAssertEqual(submissions.first?.totalTabCount, 1)
        XCTAssertEqual(submissions.first?.deliveredAttachmentCount, 1)
        XCTAssertEqual(reservation.releaseCount, 1)
    }

    func testPreparationWithoutSurvivingContextsStillDeliversPrompt() async {
        let session = AIChatInitialPromptSession()
        let prepared = expectation(description: "Prompt prepared without contexts")
        session.prepare(prompt, request: .init(contexts: { [self.context("closed")] }, didConsume: {}, validate: { _ in [] })) {
            XCTAssertNotNil($0)
            if let delivery = $0 { session.install(delivery) }
            prepared.fulfill()
        }
        await fulfillment(of: [prepared], timeout: 1)
        XCTAssertEqual(consume(session), prompt)
    }

    func testSecondPreparationIsRejectedWithoutReplacingFirst() async {
        let session = AIChatInitialPromptSession()
        let gate = PreparationGate(started: expectation(description: "First preparation started"))
        let prepared = expectation(description: "First preparation completed")
        session.prepare(prompt, request: .init(contexts: { await gate.wait() }, didConsume: {})) {
            XCTAssertNotNil($0)
            if let delivery = $0 { session.install(delivery) }
            prepared.fulfill()
        }
        await fulfillment(of: [gate.started], timeout: 1)
        var rejected = 0
        var released = 0
        session.prepare(.queryPrompt("duplicate", autoSubmit: true), request: .init(contexts: {
            XCTFail("Rejected request must not collect contexts")
            return []
        }, didConsume: {}, cancel: { released += 1 })) {
            XCTAssertNil($0)
            rejected += 1
        }
        XCTAssertEqual(rejected, 1)
        XCTAssertEqual(released, 1)
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        gate.resume()
        await fulfillment(of: [prepared], timeout: 1)
        XCTAssertEqual(consume(session), prompt)
    }

    func testCancellationCompletesOnceAndLateResultDoesNotClearNewPreparation() async {
        let session = AIChatInitialPromptSession()
        let oldGate = PreparationGate(started: expectation(description: "Old preparation started"))
        let newGate = PreparationGate(started: expectation(description: "New preparation started"))
        let prepared = expectation(description: "New preparation completed")
        var oldCompletions = 0
        let reservation = InitialPromptTestReservation()
        session.prepare(prompt, request: .init(contexts: { await oldGate.wait() }, didConsume: {
            XCTFail("Cancelled contexts must not be consumed")
        }, cancel: { reservation.release() })) {
            XCTAssertNil($0)
            XCTAssertTrue(reservation.isReleased)
            oldCompletions += 1
        }
        await fulfillment(of: [oldGate.started], timeout: 1)
        session.cancel()
        session.cancel()
        XCTAssertEqual(oldCompletions, 1)
        XCTAssertTrue(reservation.isReleased)
        XCTAssertFalse(session.isProtectedFromCacheEviction)
        session.prepare(prompt, request: .init(contexts: { await newGate.wait() }, didConsume: {})) {
            if let delivery = $0 { session.install(delivery) }
            prepared.fulfill()
        }
        await fulfillment(of: [newGate.started], timeout: 1)
        oldGate.resume()
        await fulfillment(of: [oldGate.returned], timeout: 1)
        XCTAssertEqual(reservation.releaseCount, 1)
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        XCTAssertEqual(oldCompletions, 1)
        newGate.resume()
        await fulfillment(of: [prepared], timeout: 1)
        XCTAssertEqual(consume(session), prompt)
    }

    func testHandoffReleasesSenderBeforeCompletionAndRecipientSurvivesSenderCancellation() async {
        let sender = AIChatInitialPromptSession()
        let recipient = AIChatInitialPromptSession()
        let prepared = expectation(description: "Prompt handed over")
        sender.prepare(prompt, request: .init(contexts: { [] }, didConsume: {})) {
            XCTAssertFalse(sender.isProtectedFromCacheEviction)
            if let delivery = $0 { recipient.install(delivery) }
            prepared.fulfill()
        }
        await fulfillment(of: [prepared], timeout: 1)
        sender.cancel()
        XCTAssertEqual(consume(recipient), prompt)
        assertSharedHandler(sender.consumeInitialPrompt())
    }

    func testSameSessionCanInstallDeliveryInsidePreparationCompletion() async {
        let session = AIChatInitialPromptSession()
        let prepared = expectation(description: "Same recipient installed")
        session.prepare(prompt, request: .init(contexts: { [] }, didConsume: {})) {
            XCTAssertFalse(session.isProtectedFromCacheEviction)
            if let delivery = $0 { session.install(delivery) }
            prepared.fulfill()
        }
        await fulfillment(of: [prepared], timeout: 1)
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        XCTAssertEqual(consume(session), prompt)
    }

    func testExpectedNavigationPreservesPromptAndNextStartResetsRouting() {
        let session = installedSession()
        XCTAssertFalse(session.didStartNavigation(DummyWKNavigation()))
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        XCTAssertTrue(session.didStartNavigation(DummyWKNavigation()))
        XCTAssertFalse(session.isProtectedFromCacheEviction)
        assertSharedHandler(session.consumeInitialPrompt())
    }

    func testInternalRetryIgnoresFailureBeforeAndAfterReplacementStart() {
        let session = installedSession()
        let oldNavigation = DummyWKNavigation()
        let replacementNavigation = DummyWKNavigation()
        session.didStartNavigation(oldNavigation)
        XCTAssertFalse(session.willLoad(isInternalRetry: true))
        XCTAssertFalse(session.didFailNavigation(oldNavigation))
        XCTAssertFalse(session.didStartNavigation(replacementNavigation))
        XCTAssertFalse(session.didFailNavigation(oldNavigation))
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        XCTAssertEqual(consume(session), prompt)
    }

    func testMatchingFailurePreservesPromptForRetryAndSingleConsumption() {
        let session = AIChatInitialPromptSession()
        var consumptionCount = 0
        session.install(AIChatInitialPromptDelivery(prompt: prompt) { consumptionCount += 1 })
        let failedNavigation = DummyWKNavigation()
        session.didStartNavigation(failedNavigation)

        XCTAssertTrue(session.didFailNavigation(failedNavigation))
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        XCTAssertTrue(session.willRetryFailedNavigation())
        XCTAssertFalse(session.didStartNavigation(DummyWKNavigation()))
        XCTAssertFalse(session.didFailNavigation(failedNavigation))

        XCTAssertEqual(consume(session), prompt)
        XCTAssertNil(consume(session))
        XCTAssertEqual(consumptionCount, 1)
        XCTAssertFalse(session.isProtectedFromCacheEviction)
    }

    func testRepeatedFailedRetriesPreserveTheSamePrompt() {
        let session = installedSession()
        var navigation = DummyWKNavigation()
        session.didStartNavigation(navigation)

        for _ in 0..<3 {
            XCTAssertTrue(session.didFailNavigation(navigation))
            XCTAssertTrue(session.willRetryFailedNavigation())
            let retry = DummyWKNavigation()
            XCTAssertFalse(session.didFailNavigation(navigation))
            XCTAssertFalse(session.didStartNavigation(retry))
            XCTAssertFalse(session.didFailNavigation(navigation))
            navigation = retry
        }

        XCTAssertEqual(consume(session), prompt)
        XCTAssertNil(consume(session))
    }

    func testReloadWithoutFailureDoesNotPreserveUnconsumedPrompt() {
        let session = AIChatInitialPromptSession()
        let delivery = AIChatInitialPromptDelivery(prompt: prompt) {}
        session.install(delivery)
        session.didStartNavigation(DummyWKNavigation())

        XCTAssertFalse(session.willRetryFailedNavigation())
        XCTAssertTrue(session.didStartNavigation(DummyWKNavigation()))

        XCTAssertNil(delivery.consume())
        assertSharedHandler(session.consumeInitialPrompt())
        XCTAssertFalse(session.isProtectedFromCacheEviction)
    }

    func testExplicitLoadAfterFailureCancelsPromptAndPreventsRetry() {
        let session = AIChatInitialPromptSession()
        let delivery = AIChatInitialPromptDelivery(prompt: prompt) {}
        session.install(delivery)
        let navigation = DummyWKNavigation()
        session.didStartNavigation(navigation)
        session.didFailNavigation(navigation)

        XCTAssertTrue(session.willLoad(isInternalRetry: false))
        XCTAssertFalse(session.willRetryFailedNavigation())
        XCTAssertTrue(session.didStartNavigation(DummyWKNavigation()))

        XCTAssertNil(delivery.consume())
        assertSharedHandler(session.consumeInitialPrompt())
        XCTAssertFalse(session.isProtectedFromCacheEviction)
    }

    func testNavigationAfterFailureWithoutRetryDiscardsPrompt() {
        let session = AIChatInitialPromptSession()
        let delivery = AIChatInitialPromptDelivery(prompt: prompt) {}
        session.install(delivery)
        let navigation = DummyWKNavigation()
        session.didStartNavigation(navigation)
        session.didFailNavigation(navigation)

        XCTAssertTrue(session.didStartNavigation(DummyWKNavigation()))

        XCTAssertFalse(session.willRetryFailedNavigation())
        XCTAssertNil(delivery.consume())
        assertSharedHandler(session.consumeInitialPrompt())
    }

    func testConsumedPromptIsNotRestoredAfterFailure() {
        let session = installedSession()
        let navigation = DummyWKNavigation()
        session.didStartNavigation(navigation)
        XCTAssertEqual(consume(session), prompt)

        XCTAssertTrue(session.didFailNavigation(navigation))
        XCTAssertFalse(session.willRetryFailedNavigation())

        XCTAssertNil(consume(session))
        XCTAssertFalse(session.isProtectedFromCacheEviction)
    }

    func testCancellationAfterFailurePreventsRetry() {
        let session = installedSession()
        let navigation = DummyWKNavigation()
        session.didStartNavigation(navigation)
        session.didFailNavigation(navigation)

        session.cancel()

        XCTAssertFalse(session.willRetryFailedNavigation())
        XCTAssertFalse(session.isProtectedFromCacheEviction)
        XCTAssertNil(consume(session))
    }

    func testTimeoutAfterFailureDiscardsPromptAndPreventsRetry() async throws {
        let session = AIChatInitialPromptSession()
        session.install(AIChatInitialPromptDelivery(prompt: prompt, consumptionTimeout: 0) {
            XCTFail("Timed-out prompt must not be consumed")
        })
        let navigation = DummyWKNavigation()
        session.didStartNavigation(navigation)
        session.didFailNavigation(navigation)
        let connection = session.connect()
        let wait = try XCTUnwrap(connection.captureInitialPromptWait())

        let canContinue = await wait()

        XCTAssertTrue(canContinue)
        XCTAssertFalse(session.willRetryFailedNavigation())
        XCTAssertNil(consume(session))
        XCTAssertFalse(session.isProtectedFromCacheEviction)
    }

    func testForeignAndNilFailuresPreserveDelivery() {
        let session = installedSession()
        session.didStartNavigation(DummyWKNavigation())
        XCTAssertFalse(session.didFailNavigation(DummyWKNavigation()))
        XCTAssertFalse(session.didFailNavigation(nil))
        XCTAssertEqual(consume(session), prompt)
    }

    func testExplicitLoadCancelsEvenBeforeExpectedNavigation() {
        let session = installedSession()
        XCTAssertTrue(session.willLoad(isInternalRetry: false))
        XCTAssertFalse(session.isProtectedFromCacheEviction)
        XCTAssertNil(consume(session))
    }

    func testInternalRetryDoesNotPreservePreparationWithoutDelivery() async {
        let session = AIChatInitialPromptSession()
        let gate = PreparationGate(started: expectation(description: "Preparation started"))
        var cancelled = 0
        session.prepare(prompt, request: .init(contexts: { await gate.wait() }, didConsume: {})) {
            XCTAssertNil($0)
            cancelled += 1
        }
        await fulfillment(of: [gate.started], timeout: 1)
        XCTAssertTrue(session.willLoad(isInternalRetry: true))
        XCTAssertEqual(cancelled, 1)
        XCTAssertFalse(session.isProtectedFromCacheEviction)
        gate.resume()
    }

    func testConsumptionIsSingleUseAcrossConnections() {
        let session = AIChatInitialPromptSession()
        var measured = 0
        session.install(AIChatInitialPromptDelivery(prompt: prompt) { measured += 1 })
        let first = session.connect()
        XCTAssertEqual(consume(first), prompt)
        let second = session.connect()
        XCTAssertNil(consume(second))
        XCTAssertNil(consume(first))
        XCTAssertEqual(measured, 1)
        XCTAssertFalse(session.isProtectedFromCacheEviction)
    }

    func testOldConnectionCannotConsumeCancelOrDisconnectNewConnection() {
        let session = installedSession()
        let old = session.connect()
        let current = session.connect()
        old.cancel()
        old.disconnect()
        XCTAssertNil(consume(old))
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        XCTAssertEqual(consume(current), prompt)
    }

    func testDisconnectAndConnectionDestructionPreservePrompt() {
        let session = installedSession()
        var connection: AIChatInitialPromptSession.Connection? = session.connect()
        connection?.disconnect()
        connection = nil
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        XCTAssertEqual(consume(session.connect()), prompt)
    }

    func testCancelIsIdempotentAndDoesNotRestoreSharedRouting() {
        let session = AIChatInitialPromptSession()
        var measured = 0
        session.install(AIChatInitialPromptDelivery(prompt: prompt) { measured += 1 })
        session.cancel()
        session.cancel()
        XCTAssertNil(consume(session))
        XCTAssertEqual(measured, 0)
        XCTAssertFalse(session.isProtectedFromCacheEviction)
    }

    func testWaitingAfterConsumptionSucceeds() async throws {
        let session = installedSession()
        let connection = session.connect()
        let wait = try XCTUnwrap(connection.captureInitialPromptWait())
        XCTAssertEqual(consume(connection), prompt)
        let maySubmit = await wait()
        XCTAssertTrue(maySubmit)
    }

    func testCancellationStopsWaitingSubmission() async throws {
        let session = installedSession()
        let connection = session.connect()
        let wait = try XCTUnwrap(connection.captureInitialPromptWait())
        session.cancel()
        let maySubmit = await wait()
        XCTAssertFalse(maySubmit)
    }

    func testTimeoutDiscardsPromptAndAllowsFollowingSubmissionWithoutSharedFallback() async throws {
        let session = AIChatInitialPromptSession()
        session.install(AIChatInitialPromptDelivery(prompt: prompt, consumptionTimeout: 0) {
            XCTFail("Timed-out prompt must not be measured")
        })
        let connection = session.connect()
        let wait = try XCTUnwrap(connection.captureInitialPromptWait())
        let maySubmit = await wait()
        XCTAssertTrue(maySubmit)
        XCTAssertNil(consume(connection))
        XCTAssertFalse(session.isProtectedFromCacheEviction)
    }

    func testCapturedWaitCannotSwitchToNewDelivery() async throws {
        let session = installedSession()
        let connection = session.connect()
        let wait = try XCTUnwrap(connection.captureInitialPromptWait())
        let replacement = AIChatNativePrompt.queryPrompt("replacement", autoSubmit: true)
        session.install(AIChatInitialPromptDelivery(prompt: replacement) {})
        let maySubmit = await wait()
        XCTAssertFalse(maySubmit)
        XCTAssertEqual(consume(connection), replacement)
    }

    func testWaitFromOldConnectionCannotContinueAfterReplacement() async throws {
        let session = installedSession()
        let old = session.connect()
        let wait = try XCTUnwrap(old.captureInitialPromptWait())
        let current = session.connect()
        XCTAssertEqual(consume(current), prompt)
        let maySubmit = await wait()
        XCTAssertFalse(maySubmit)
    }

    func testProtectionExpiryDoesNotDiscardOrTimeOutPrompt() async {
        let session = AIChatInitialPromptSession()
        var now = Date(timeIntervalSince1970: 0)
        let delivery = AIChatInitialPromptDelivery(prompt: prompt, consumptionTimeout: 0,
                                                   now: { now }) {}
        session.install(delivery)
        now.addTimeInterval(29)
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        now.addTimeInterval(1)
        XCTAssertFalse(session.isProtectedFromCacheEviction)
        XCTAssertEqual(consume(session), prompt)
        let result = await delivery.waitUntilConsumed()
        XCTAssertEqual(result, .consumed)
    }

    func testSuspendedWaitResumesWhenConsumedOrCancelled() async throws {
        for consumesPrompt in [true, false] {
            let session = installedSession()
            let connection = session.connect()
            let wait = try XCTUnwrap(connection.captureInitialPromptWait())
            let started = expectation(description: "Wait started")
            let task = Task { @MainActor in
                started.fulfill()
                return await wait()
            }
            await fulfillment(of: [started], timeout: 1)
            if consumesPrompt {
                XCTAssertEqual(consume(connection), prompt)
            } else {
                session.cancel()
            }
            let maySubmit = await task.value
            XCTAssertEqual(maySubmit, consumesPrompt)
            XCTAssertFalse(session.isProtectedFromCacheEviction)
        }
    }

    func testCancellingOldWaitDoesNotCancelDeliveryForNewConnection() async throws {
        let session = installedSession()
        let connection = session.connect()
        let wait = try XCTUnwrap(connection.captureInitialPromptWait())
        let started = expectation(description: "Old wait started")
        let task = Task { @MainActor in
            started.fulfill()
            return await wait()
        }
        await fulfillment(of: [started], timeout: 1)
        task.cancel()
        let maySubmit = await task.value
        XCTAssertFalse(maySubmit)
        XCTAssertTrue(session.isProtectedFromCacheEviction)
        XCTAssertEqual(consume(session.connect()), prompt)
    }

    private func installedSession() -> AIChatInitialPromptSession {
        let session = AIChatInitialPromptSession()
        session.install(AIChatInitialPromptDelivery(prompt: prompt) {})
        return session
    }

    private func consume(_ session: AIChatInitialPromptSession) -> AIChatNativePrompt? {
        tabSessionPrompt(session.consumeInitialPrompt())
    }

    private func consume(_ connection: AIChatInitialPromptSession.Connection) -> AIChatNativePrompt? {
        tabSessionPrompt(connection.consumeInitialPrompt())
    }

    private func tabSessionPrompt(_ source: AIChatInitialPromptSession.PromptSource) -> AIChatNativePrompt? {
        guard case .tabSession(let prompt) = source else {
            XCTFail("Recipient must never fall back to shared prompt")
            return nil
        }
        return prompt
    }

    private func assertSharedHandler(_ source: AIChatInitialPromptSession.PromptSource) {
        guard case .sharedHandler = source else {
            XCTFail("Ordinary prompt must use shared source")
            return
        }
    }

    private func context(_ tabID: String) -> AIChatPageContextData {
        AIChatPageContextData(title: tabID, favicon: [], url: "https://example.com", content: "content",
                              truncated: false, fullContentLength: 7, tabId: tabID)
    }
}

@MainActor
private final class InitialPromptTestReservation {
    private var resource: (() -> Void)?
    private(set) var releaseCount = 0

    init() {
        resource = { [weak self] in self?.releaseCount += 1 }
    }

    var isReleased: Bool { resource == nil }

    func release() {
        let resource = resource
        self.resource = nil
        resource?()
    }
}

@MainActor
private final class PreparationGate {
    let started: XCTestExpectation
    let returned = XCTestExpectation(description: "Context provider returned")
    private var continuation: CheckedContinuation<[AIChatPageContextData], Never>?

    init(started: XCTestExpectation) {
        self.started = started
    }

    func wait() async -> [AIChatPageContextData] {
        let contexts = await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
        returned.fulfill()
        return contexts
    }

    func resume() {
        continuation?.resume(returning: [])
        continuation = nil
    }
}
