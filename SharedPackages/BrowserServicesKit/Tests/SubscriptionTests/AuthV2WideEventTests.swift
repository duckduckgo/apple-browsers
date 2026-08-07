//
//  AuthV2WideEventTests.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Networking
import PixelKit
import PixelKitTestingUtilities
@testable import Subscription

final class AuthV2WideEventTests: XCTestCase {

    // MARK: - AuthV2TokenRefreshWideEventData Tests

    func testPixelParameters_withMinimalData() {
        // Given
        let contextData = WideEventContextData(name: "test-context")
        let eventData = AuthV2TokenRefreshWideEventData(
            contextData: contextData
        )

        // When
        let parameters = eventData.pixelParameters()

        // Then
        XCTAssertNil(parameters["feature.data.ext.failing_step"])
        XCTAssertNil(parameters["feature.data.ext.application_state"])
        XCTAssertNil(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"])
        XCTAssertNil(parameters["feature.data.ext.fetch_jwks_latency_ms_bucketed"])
    }

    func testPixelParameters_withFailingStep() {
        // Given
        let contextData = WideEventContextData(name: "test-context")
        let eventData = AuthV2TokenRefreshWideEventData(
            failingStep: .refreshAccessToken,
            contextData: contextData
        )

        // When
        let parameters = eventData.pixelParameters()

        // Then
        XCTAssertEqual(parameters["feature.data.ext.failing_step"], "refresh_access_token")
    }

    func testPixelParameters_withAllFailingSteps() {
        let contextData = WideEventContextData(name: "test-context")

        for failingStep in AuthV2TokenRefreshWideEventData.FailingStep.allCases {
            // Given
            let eventData = AuthV2TokenRefreshWideEventData(
                failingStep: failingStep,
                contextData: contextData
            )

            // When
            let parameters = eventData.pixelParameters()

            // Then
            XCTAssertEqual(parameters["feature.data.ext.failing_step"], failingStep.rawValue)
        }
    }

    func testPixelParameters_withRefreshTokenDuration_bucketing() {
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()

        // Test each bucket threshold
        let testCases: [(milliseconds: Int, expectedBucket: String)] = [
            (500, "1000"),          // 0-1000ms → 1000
            (999, "1000"),          // 0-1000ms → 1000
            (1000, "5000"),         // 1000-5000ms → 5000
            (3000, "5000"),         // 1000-5000ms → 5000
            (5000, "10000"),        // 5000-10000ms → 10000
            (7500, "10000"),        // 5000-10000ms → 10000
            (10000, "30000"),       // 10000-30000ms → 30000
            (20000, "30000"),       // 10000-30000ms → 30000
            (30000, "60000"),       // 30000-60000ms → 60000
            (45000, "60000"),       // 30000-60000ms → 60000
            (60000, "300000"),      // 60000-300000ms → 300000
            (150000, "300000"),     // 60000-300000ms → 300000
            (300000, "600000"),     // 300000+ms → 600000
            (500000, "600000")      // 300000+ms → 600000
        ]

        for (milliseconds, expectedBucket) in testCases {
            // Given
            let eventData = AuthV2TokenRefreshWideEventData(contextData: contextData)
            let endDate = baseDate.addingTimeInterval(TimeInterval(milliseconds) / 1000.0)
            eventData.refreshTokenDuration = WideEvent.MeasuredInterval(start: baseDate, end: endDate)

            // When
            let parameters = eventData.pixelParameters()

            // Then
            XCTAssertEqual(
                parameters["feature.data.ext.refresh_token_latency_ms_bucketed"],
                expectedBucket,
                "Expected bucket \(expectedBucket) for \(milliseconds)ms"
            )
        }
    }

    func testPixelParameters_withFetchJWKSDuration_bucketing() {
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()

        // Test a few key buckets for fetchJWKSDuration
        let testCases: [(milliseconds: Int, expectedBucket: String)] = [
            (100, "1000"),          // 0-1000ms → 1000
            (2000, "5000"),         // 1000-5000ms → 5000
            (8000, "10000"),        // 5000-10000ms → 10000
            (25000, "30000")        // 10000-30000ms → 30000
        ]

        for (milliseconds, expectedBucket) in testCases {
            // Given
            let eventData = AuthV2TokenRefreshWideEventData(contextData: contextData)
            let endDate = baseDate.addingTimeInterval(TimeInterval(milliseconds) / 1000.0)
            eventData.fetchJWKSDuration = WideEvent.MeasuredInterval(start: baseDate, end: endDate)

            // When
            let parameters = eventData.pixelParameters()

            // Then
            XCTAssertEqual(
                parameters["feature.data.ext.fetch_jwks_latency_ms_bucketed"],
                expectedBucket,
                "Expected bucket \(expectedBucket) for \(milliseconds)ms"
            )
        }
    }

    func testPixelParameters_withIncompleteInterval() {
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()

        let eventData = AuthV2TokenRefreshWideEventData(contextData: contextData)
        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(start: baseDate, end: nil)
        var parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"])

        // Test with only end date
        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(start: nil, end: baseDate)
        parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"])

        // Test with no dates
        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(start: nil, end: nil)
        parameters = eventData.pixelParameters()
        XCTAssertNil(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"])
    }

    func testPixelParameters_withAllParametersSet() {
        // Given
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()
        let eventData = AuthV2TokenRefreshWideEventData(
            failingStep: .verifyingAccessToken,
            contextData: contextData
        )

        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(
            start: baseDate,
            end: baseDate.addingTimeInterval(2.5) // 2500ms → bucket 5000
        )

        eventData.fetchJWKSDuration = WideEvent.MeasuredInterval(
            start: baseDate,
            end: baseDate.addingTimeInterval(0.5) // 500ms → bucket 1000
        )

        // When
        let parameters = eventData.pixelParameters()

        // Then
        XCTAssertEqual(parameters["feature.data.ext.failing_step"], "verify_access_token")
        XCTAssertEqual(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"], "5000")
        XCTAssertEqual(parameters["feature.data.ext.fetch_jwks_latency_ms_bucketed"], "1000")
    }

    func testPixelParameters_withNegativeInterval() {
        // Given - end date before start date
        let contextData = WideEventContextData(name: "test-context")
        let baseDate = Date()
        let eventData = AuthV2TokenRefreshWideEventData(contextData: contextData)
        eventData.refreshTokenDuration = WideEvent.MeasuredInterval(
            start: baseDate,
            end: baseDate.addingTimeInterval(-5.0) // Negative interval
        )

        // When
        let parameters = eventData.pixelParameters()

        // Then - should be bucketed to 1000 (max(0, negative) = 0, which falls in 0-1000 range)
        XCTAssertEqual(parameters["feature.data.ext.refresh_token_latency_ms_bucketed"], "1000")
    }

    // MARK: - Invalid-token recovery schema

    func testPixelParameters_recoverInvalidTokenStep() {
        let eventData = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken)

        let parameters = eventData.pixelParameters()

        XCTAssertEqual(parameters["feature.data.ext.failing_step"], "recover_invalid_token")
    }

    func testPixelParameters_recoveryLatency_bucketing() {
        let baseDate = Date()
        let eventData = AuthV2TokenRefreshWideEventData()
        eventData.recoveryDuration = WideEvent.MeasuredInterval(start: baseDate,
                                                                end: baseDate.addingTimeInterval(3)) // 3000ms

        let parameters = eventData.pixelParameters()

        XCTAssertEqual(parameters["feature.data.ext.recovery_latency_ms_bucketed"], "5000")
    }

    func testPixelParameters_recoveryOutcome_emittedOnlyWhenSet() {
        let noRecovery = AuthV2TokenRefreshWideEventData()
        XCTAssertNil(noRecovery.pixelParameters()["feature.data.ext.recovery_outcome"])

        let recovered = AuthV2TokenRefreshWideEventData()
        recovered.recoveryOutcome = .succeeded
        XCTAssertEqual(recovered.pixelParameters()["feature.data.ext.recovery_outcome"], "succeeded")

        let notAttempted = AuthV2TokenRefreshWideEventData()
        notAttempted.recoveryOutcome = .notAttempted
        XCTAssertEqual(notAttempted.pixelParameters()["feature.data.ext.recovery_outcome"], "not_attempted")
    }

    func testDecoding_withoutRecoveryOutcome_defaultsToNil() throws {
        let eventData = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken)
        eventData.recoveryDuration = .startingNow()

        let encoded = try JSONEncoder().encode(eventData)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "recoveryOutcome")

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AuthV2TokenRefreshWideEventData.self, from: legacyData)

        XCTAssertNil(decoded.recoveryOutcome)
        XCTAssertEqual(decoded.failingStep, .recoverInvalidToken)
        XCTAssertNotNil(decoded.recoveryDuration?.start)
    }

    func testDecoding_withoutStartedAt_defaultsToNil() throws {
        let eventData = AuthV2TokenRefreshWideEventData()

        let encoded = try JSONEncoder().encode(eventData)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        json.removeValue(forKey: "startedAt")

        let legacyData = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AuthV2TokenRefreshWideEventData.self, from: legacyData)

        XCTAssertNil(decoded.startedAt)
    }

    func testEncodingAndDecoding_preservesStartedAt() throws {
        let startedAt = Date()
        let eventData = AuthV2TokenRefreshWideEventData(startedAt: startedAt)

        let encoded = try JSONEncoder().encode(eventData)
        let decoded = try JSONDecoder().decode(AuthV2TokenRefreshWideEventData.self, from: encoded)
        let decodedStartedAt = try XCTUnwrap(decoded.startedAt)

        XCTAssertEqual(decodedStartedAt.timeIntervalSince1970, startedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    // MARK: - Refresh trigger

    func testPixelParameters_refreshTrigger_alwaysEmitted_defaultsToClient() {
        let eventData = AuthV2TokenRefreshWideEventData()

        XCTAssertEqual(eventData.pixelParameters()["feature.data.ext.refresh_trigger"], "client")
    }

    func testPixelParameters_refreshTrigger_emitsSetValue() {
        let eventData = AuthV2TokenRefreshWideEventData()
        eventData.refreshTrigger = .createIfNeeded

        XCTAssertEqual(eventData.pixelParameters()["feature.data.ext.refresh_trigger"], "create_if_needed")
    }

    func testRefreshEventMapping_startCarriesTrigger() {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock)

        instrumentation.eventMapping.fire(.tokenRefreshStarted(refreshID: "refresh-trigger", trigger: .tokenAdoption))

        let pending = mock.getAllFlowData(AuthV2TokenRefreshWideEventData.self)
        XCTAssertEqual(pending.first?.refreshTrigger, .tokenAdoption)
        XCTAssertEqual(pending.first?.pixelParameters()["feature.data.ext.refresh_trigger"], "token_adoption")
    }

    func testCompletionDecision_appLaunch_recentRefreshKeepsPending() async {
        let eventData = AuthV2TokenRefreshWideEventData()

        let decision = await eventData.completionDecision(for: .appLaunch)

        guard case .keepPending = decision else {
            return XCTFail("Expected recent refresh to stay pending, got \(decision)")
        }
    }

    func testCompletionDecision_appLaunch_staleRefreshReconcilesToUnknown() async {
        let staleStart = Date().addingTimeInterval(-AuthV2TokenRefreshWideEventData.launchCleanupTimeout - 1)
        let eventData = AuthV2TokenRefreshWideEventData(startedAt: staleStart)

        let decision = await eventData.completionDecision(for: .appLaunch)

        guard case .complete(.unknown(let reason)) = decision else {
            return XCTFail("Expected stale refresh to reconcile to UNKNOWN, got \(decision)")
        }
        XCTAssertEqual(reason, "partial_data")
    }

    func testCompletionDecision_appLaunch_legacyRefreshWithoutStartedAtReconcilesToUnknown() async {
        let eventData = AuthV2TokenRefreshWideEventData(startedAt: nil)

        let decision = await eventData.completionDecision(for: .appLaunch)

        guard case .complete(.unknown(let reason)) = decision else {
            return XCTFail("Expected legacy refresh to reconcile to UNKNOWN, got \(decision)")
        }
        XCTAssertEqual(reason, "partial_data")
    }

    // MARK: - Event mapping: deferral on invalid_token_request

    func testRefreshEventMapping_invalidTokenRequest_defersCompletionAndMarksStep() {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock)
        let refreshID = "refresh-1"

        instrumentation.eventMapping.fire(.tokenRefreshStarted(refreshID: refreshID, trigger: .client))
        instrumentation.eventMapping.fire(.tokenRefreshRefreshingAccessToken(refreshID: refreshID))
        instrumentation.eventMapping.fire(.tokenRefreshFailed(refreshID: refreshID, error: OAuthClientError.invalidTokenRequest(.reused)))

        XCTAssertTrue(mock.completions.isEmpty)
        let pending = mock.getAllFlowData(AuthV2TokenRefreshWideEventData.self)
        XCTAssertEqual(pending.first?.failingStep, .recoverInvalidToken)
        XCTAssertNotNil(pending.first?.recoveryDuration?.start)
    }

    func testRefreshEventMapping_invalidTokenRequest_completesFailureWhenRecoveryWillNotRun() throws {
        for trigger in [TokenRefreshTrigger.backend, .createIfNeeded, .tokenAdoption] {
            let mock = WideEventMock()
            let instrumentation = makeRefreshInstrumentation(wideEvent: mock)
            let refreshID = "refresh-\(trigger.rawValue)"

            instrumentation.eventMapping.fire(.tokenRefreshStarted(refreshID: refreshID, trigger: trigger))
            instrumentation.eventMapping.fire(.tokenRefreshRefreshingAccessToken(refreshID: refreshID))
            instrumentation.eventMapping.fire(.tokenRefreshFailed(refreshID: refreshID, error: OAuthClientError.invalidTokenRequest(.reused)))

            XCTAssertEqual(mock.completions.count, 1)
            XCTAssertEqual(mock.completions.first?.1, .failure)
            XCTAssertTrue(mock.getAllFlowData(AuthV2TokenRefreshWideEventData.self).isEmpty)

            let completedData = try XCTUnwrap(mock.completions.first?.0 as? AuthV2TokenRefreshWideEventData)
            XCTAssertEqual(completedData.refreshTrigger, trigger)
            XCTAssertEqual(completedData.failingStep, .refreshAccessToken)
            XCTAssertNil(completedData.recoveryDuration)
        }
    }

    func testRefreshEventMapping_otherError_completesFailure() {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock)
        let refreshID = "refresh-2"

        instrumentation.eventMapping.fire(.tokenRefreshStarted(refreshID: refreshID, trigger: .client))
        instrumentation.eventMapping.fire(.tokenRefreshFailed(refreshID: refreshID, error: OAuthClientError.unknownAccount))

        XCTAssertEqual(mock.completions.count, 1)
        guard case .failure = mock.completions.first?.1 else {
            return XCTFail("Expected FAILURE completion for a non-recoverable error")
        }
    }

    func testRefreshEventMapping_otherError_discardsFailureWhenSuppressed() {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock, shouldSuppressFailure: { true })
        let refreshID = "refresh-suppressed"

        instrumentation.eventMapping.fire(.tokenRefreshStarted(refreshID: refreshID, trigger: .client))
        instrumentation.eventMapping.fire(.tokenRefreshFailed(refreshID: refreshID, error: OAuthClientError.unknownAccount))

        XCTAssertTrue(mock.completions.isEmpty)
        XCTAssertEqual(mock.discarded.count, 1)
        XCTAssertTrue(mock.getAllFlowData(AuthV2TokenRefreshWideEventData.self).isEmpty)
    }

    func testRefreshEventMapping_successCompletesWhenFailureSuppressionIsActive() {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock, shouldSuppressFailure: { true })
        let refreshID = "refresh-success"

        instrumentation.eventMapping.fire(.tokenRefreshStarted(refreshID: refreshID, trigger: .client))
        instrumentation.eventMapping.fire(.tokenRefreshSucceeded(refreshID: refreshID))

        XCTAssertEqual(mock.completions.count, 1)
        XCTAssertEqual(mock.completions.first?.1, .success(reason: nil))
        XCTAssertTrue(mock.discarded.isEmpty)
    }

    func testRefreshInstrumentation_recoverySuccessCompletesNewestFlowWithoutError() throws {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock)
        let staleFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                        globalData: WideEventGlobalData(id: "stale"))
        staleFlow.recoveryDuration = WideEvent.MeasuredInterval(start: Date(timeIntervalSinceNow: -120), end: nil)
        mock.startFlow(staleFlow)

        let freshFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                        globalData: WideEventGlobalData(id: "fresh"))
        freshFlow.errorData = WideEventErrorData(error: OAuthClientError.invalidTokenRequest(.reused))
        freshFlow.recoveryDuration = .startingNow()
        mock.startFlow(freshFlow)

        instrumentation.completeInvalidTokenRecovery(outcome: .succeeded, error: nil)

        XCTAssertEqual(mock.completions.count, 1)
        let (data, status) = try XCTUnwrap(mock.completions.first)
        XCTAssertEqual(data.globalData.id, "fresh")
        XCTAssertEqual(status, .success(reason: nil))

        let refreshData = try XCTUnwrap(data as? AuthV2TokenRefreshWideEventData)
        XCTAssertEqual(refreshData.recoveryOutcome, .succeeded)
        XCTAssertNil(refreshData.errorData)
        XCTAssertNil(refreshData.failingStep)
        XCTAssertNotNil(refreshData.recoveryDuration?.end)
    }

    func testRefreshInstrumentation_recoveryFailureCompletesFlowWithError() throws {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock)
        let pendingFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                          globalData: WideEventGlobalData(id: "refresh-1"))
        pendingFlow.recoveryDuration = .startingNow()
        mock.startFlow(pendingFlow)

        instrumentation.completeInvalidTokenRecovery(outcome: .failed, error: SubscriptionManagerError.noTokenAvailable)

        XCTAssertEqual(mock.completions.count, 1)
        let (data, status) = try XCTUnwrap(mock.completions.first)
        XCTAssertEqual(status, .failure)

        let refreshData = try XCTUnwrap(data as? AuthV2TokenRefreshWideEventData)
        XCTAssertEqual(refreshData.recoveryOutcome, .failed)
        XCTAssertNotNil(refreshData.errorData)
        XCTAssertEqual(refreshData.failingStep, .recoverInvalidToken)
        XCTAssertNotNil(refreshData.recoveryDuration?.end)
    }

    func testRefreshInstrumentation_recoveryFailureDiscardsWhenSuppressed() {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock, shouldSuppressFailure: { true })
        let pendingFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                          globalData: WideEventGlobalData(id: "refresh-suppressed"))
        pendingFlow.recoveryDuration = .startingNow()
        mock.startFlow(pendingFlow)

        instrumentation.completeInvalidTokenRecovery(outcome: .failed, error: SubscriptionManagerError.noTokenAvailable)

        XCTAssertTrue(mock.completions.isEmpty)
        XCTAssertEqual(mock.discarded.count, 1)
        XCTAssertTrue(mock.getAllFlowData(AuthV2TokenRefreshWideEventData.self).isEmpty)
    }

    func testRefreshInstrumentation_recoveryNotAttempted_dropsLatencyAndKeepsOriginalError() throws {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock)
        let pendingFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                          globalData: WideEventGlobalData(id: "refresh-1"))
        pendingFlow.errorData = WideEventErrorData(error: OAuthClientError.invalidTokenRequest(.reused))
        pendingFlow.recoveryDuration = .startingNow()
        mock.startFlow(pendingFlow)

        instrumentation.completeInvalidTokenRecovery(outcome: .notAttempted, error: nil)

        XCTAssertEqual(mock.completions.count, 1)
        let (data, status) = try XCTUnwrap(mock.completions.first)
        XCTAssertEqual(status, .failure)

        let refreshData = try XCTUnwrap(data as? AuthV2TokenRefreshWideEventData)
        XCTAssertEqual(refreshData.recoveryOutcome, .notAttempted)
        // No restore ran, so the recovery latency would be meaningless and must be dropped, while the
        // original invalid-token error/step is preserved for debugging.
        XCTAssertNil(refreshData.recoveryDuration)
        XCTAssertNotNil(refreshData.errorData)
        XCTAssertEqual(refreshData.failingStep, .recoverInvalidToken)
    }

    func testRefreshInstrumentation_recoveryNotAttemptedDiscardsWhenSuppressed() {
        let mock = WideEventMock()
        let instrumentation = makeRefreshInstrumentation(wideEvent: mock, shouldSuppressFailure: { true })
        let pendingFlow = AuthV2TokenRefreshWideEventData(failingStep: .recoverInvalidToken,
                                                          globalData: WideEventGlobalData(id: "refresh-suppressed"))
        pendingFlow.recoveryDuration = .startingNow()
        mock.startFlow(pendingFlow)

        instrumentation.completeInvalidTokenRecovery(outcome: .notAttempted, error: nil)

        XCTAssertTrue(mock.completions.isEmpty)
        XCTAssertEqual(mock.discarded.count, 1)
        XCTAssertTrue(mock.getAllFlowData(AuthV2TokenRefreshWideEventData.self).isEmpty)
    }

    // MARK: - Token adoption source

    func testAdoptionPixelParameters_adoptionSource_absentWhenUnset() {
        let data = AuthV2TokenAdoptionWideEventData()

        XCTAssertNil(data.pixelParameters()["feature.data.ext.adoption_source"])
    }

    func testAdoptionPixelParameters_adoptionSource_emitsSetValue() {
        let webRestore = AuthV2TokenAdoptionWideEventData()
        webRestore.adoptionSource = .webRestore
        XCTAssertEqual(webRestore.pixelParameters()["feature.data.ext.adoption_source"], "web_restore")

        let vpn = AuthV2TokenAdoptionWideEventData()
        vpn.adoptionSource = .vpn
        XCTAssertEqual(vpn.pixelParameters()["feature.data.ext.adoption_source"], "vpn")
    }

    private func makeRefreshInstrumentation(wideEvent: WideEventManaging,
                                            isFeatureEnabled: @escaping () -> Bool = { true },
                                            shouldSuppressFailure: @escaping () -> Bool = { false }) -> AuthV2TokenRefreshInstrumenting {
        DefaultAuthV2TokenRefreshInstrumentation(wideEvent: wideEvent,
                                                 isFeatureEnabled: isFeatureEnabled,
                                                 shouldSuppressFailure: shouldSuppressFailure)
    }
}
