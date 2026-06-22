//
//  AuthV2TokenRefreshWideEventData.swift
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

import Foundation
import Common
import FoundationExtensions
import Networking
import PixelKit

#if canImport(UIKit)
import UIKit
#endif

public class AuthV2TokenRefreshWideEventData: WideEventData {
    public static let launchCleanupTimeout: TimeInterval = .minutes(5)

    public static let metadata = WideEventMetadata(
        pixelName: "auth_v2_token_refresh",
        featureName: "authv2-token-refresh",
        mobileMetaType: "ios-authv2-token-refresh",
        desktopMetaType: "macos-authv2-token-refresh",
        version: "1.2.0"
    )

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public var refreshTokenDuration: WideEvent.MeasuredInterval?
    public var fetchJWKSDuration: WideEvent.MeasuredInterval?
    public var recoveryDuration: WideEvent.MeasuredInterval?
    public var recoveryOutcome: TokenRecoveryOutcome?

    public var failingStep: FailingStep?
    public var errorData: WideEventErrorData?

    public var refreshTrigger: TokenRefreshTrigger?
    public var startedAt: Date?

    private enum CodingKeys: String, CodingKey {
        case globalData, contextData, appData
        case refreshTokenDuration, fetchJWKSDuration, recoveryDuration, recoveryOutcome
        case failingStep, errorData, refreshTrigger, startedAt
    }

    public init(failingStep: FailingStep? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData = WideEventContextData(),
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData(),
                startedAt: Date? = Date()) {
        self.failingStep = failingStep
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
        self.startedAt = startedAt
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        globalData = try container.decode(WideEventGlobalData.self, forKey: .globalData)
        contextData = try container.decode(WideEventContextData.self, forKey: .contextData)
        appData = try container.decode(WideEventAppData.self, forKey: .appData)
        refreshTokenDuration = try container.decodeIfPresent(WideEvent.MeasuredInterval.self, forKey: .refreshTokenDuration)
        fetchJWKSDuration = try container.decodeIfPresent(WideEvent.MeasuredInterval.self, forKey: .fetchJWKSDuration)
        recoveryDuration = try container.decodeIfPresent(WideEvent.MeasuredInterval.self, forKey: .recoveryDuration)
        recoveryOutcome = try container.decodeIfPresent(TokenRecoveryOutcome.self, forKey: .recoveryOutcome)
        failingStep = try container.decodeIfPresent(FailingStep.self, forKey: .failingStep)
        errorData = try container.decodeIfPresent(WideEventErrorData.self, forKey: .errorData)
        refreshTrigger = try container.decodeIfPresent(TokenRefreshTrigger.self, forKey: .refreshTrigger)
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(globalData, forKey: .globalData)
        try container.encode(contextData, forKey: .contextData)
        try container.encode(appData, forKey: .appData)
        try container.encodeIfPresent(refreshTokenDuration, forKey: .refreshTokenDuration)
        try container.encodeIfPresent(fetchJWKSDuration, forKey: .fetchJWKSDuration)
        try container.encodeIfPresent(recoveryDuration, forKey: .recoveryDuration)
        try container.encodeIfPresent(recoveryOutcome, forKey: .recoveryOutcome)
        try container.encodeIfPresent(failingStep, forKey: .failingStep)
        try container.encodeIfPresent(errorData, forKey: .errorData)
        try container.encodeIfPresent(refreshTrigger, forKey: .refreshTrigger)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
    }
}

/// The outcome of an invalid-token recovery within a token refresh journey.
///
/// `notAttempted` is distinct from `failed`: recovery is only ever *attempted* for App Store
/// subscriptions with a recovery handler configured. On other platforms (or with no handler) the
/// recovery path bails before any restore runs, which must not be conflated with a restore that ran
/// and failed.
public enum TokenRecoveryOutcome: String, Codable, CaseIterable {
    case notAttempted = "not_attempted"
    case succeeded
    case failed
}

extension AuthV2TokenRefreshWideEventData {

    public enum FailingStep: String, Codable, CaseIterable {
        case tokenRead = "token_read"
        case refreshAccessToken = "refresh_access_token"
        case fetchingJWKS = "fetch_jwks"
        case verifyingAccessToken = "verify_access_token"
        case verifyingRefreshToken = "verify_refresh_token"
        case tokenWrite = "token_write"
        case recoverInvalidToken = "recover_invalid_token"
    }

    public enum StatusReason: String {
        case partialData = "partial_data"
    }

    public func jsonParameters() -> [String: Encodable] {
        let bucket: DurationBucket = .bucketed(Self.bucket)

        var parameters: [String: Encodable] = Dictionary(compacting: [
            (WideEventParameter.AuthV2RefreshFeature.failingStep, failingStep?.rawValue),
            // Always emitted: a refresh always has an origin, so fall back to `.client` rather than dropping it.
            (WideEventParameter.AuthV2RefreshFeature.refreshTrigger, (refreshTrigger ?? .client).rawValue),
            (WideEventParameter.AuthV2RefreshFeature.refreshTokenLatency, refreshTokenDuration?.intValue(bucket)),
            (WideEventParameter.AuthV2RefreshFeature.fetchJWKSLatency, fetchJWKSDuration?.intValue(bucket)),
            (WideEventParameter.AuthV2RefreshFeature.recoveryLatency, recoveryDuration?.intValue(bucket)),
        ])
        // Emit only when the recovery path was reached (this event's params are sparse - absent means no recovery).
        if let recoveryOutcome {
            parameters[WideEventParameter.AuthV2RefreshFeature.recoveryOutcome] = recoveryOutcome.rawValue
        }
        return parameters
    }

    public func completionDecision(for trigger: WideEventCompletionTrigger) async -> WideEventCompletionDecision {
        // A refresh flow still pending at app launch never reached a terminal point - for example a
        // invalid-token refresh on the recovery-less API refresher path, or a process kill mid-refresh.
        // Reconcile it as UNKNOWN rather than leaving it pending forever.
        switch trigger {
        case .appLaunch:
            guard let startedAt else {
                return .complete(.unknown(reason: StatusReason.partialData.rawValue))
            }

            if Date() >= startedAt.addingTimeInterval(Self.launchCleanupTimeout) {
                return .complete(.unknown(reason: StatusReason.partialData.rawValue))
            }

            return .keepPending
        }
    }

    private static func bucket(_ ms: Int) -> Int {
        switch ms {
        case 0..<1000: return 1000
        case 1000..<5000: return 5000
        case 5000..<10000: return 10000
        case 10000..<30000: return 30000
        case 30000..<60000: return 60000
        case 60000..<300000: return 300000
        default: return 600000
        }
    }

}

extension WideEventParameter {

    public enum AuthV2RefreshFeature {
        static let failingStep = "feature.data.ext.failing_step"
        static let refreshTrigger = "feature.data.ext.refresh_trigger"
        static let refreshTokenLatency = "feature.data.ext.refresh_token_latency_ms_bucketed"
        static let fetchJWKSLatency = "feature.data.ext.fetch_jwks_latency_ms_bucketed"
        static let recoveryLatency = "feature.data.ext.recovery_latency_ms_bucketed"
        static let recoveryOutcome = "feature.data.ext.recovery_outcome"
    }

}
