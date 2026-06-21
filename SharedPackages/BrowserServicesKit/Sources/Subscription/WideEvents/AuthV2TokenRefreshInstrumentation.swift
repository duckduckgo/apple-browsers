//
//  AuthV2TokenRefreshInstrumentation.swift
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

import Foundation
import Common
import Networking
import PixelKit

public protocol AuthV2TokenRefreshInstrumenting: AnyObject {
    var eventMapping: EventMapping<OAuthClientRefreshEvent> { get }

    func completeInvalidTokenRecovery(outcome: TokenRecoveryOutcome, error: Error?)
}

public final class DefaultAuthV2TokenRefreshInstrumentation: AuthV2TokenRefreshInstrumenting {

    private let wideEvent: WideEventManaging
    private let isFeatureEnabled: () -> Bool

    public init(wideEvent: WideEventManaging, isFeatureEnabled: @escaping () -> Bool) {
        self.wideEvent = wideEvent
        self.isFeatureEnabled = isFeatureEnabled
    }

    public var eventMapping: EventMapping<OAuthClientRefreshEvent> {
        .init { [weak self] event, _, _, _ in
            self?.handle(event)
        }
    }

    public func completeInvalidTokenRecovery(outcome: TokenRecoveryOutcome, error: Error?) {
        guard isFeatureEnabled(),
              let data = newestPendingRecoveryFlow() else {
            return
        }

        data.recoveryOutcome = outcome

        switch outcome {
        case .succeeded:
            // A restore ran and produced a valid token: the refresh journey recovered.
            data.recoveryDuration?.complete()
            data.errorData = nil
            data.failingStep = nil
            wideEvent.completeFlow(data, status: .success(reason: nil), onComplete: { _, _ in })

        case .failed:
            // A restore ran but did not yield a valid token. Record its error if one was provided,
            // otherwise keep the original invalid-token error already on the flow.
            data.recoveryDuration?.complete()
            if let error {
                data.errorData = WideEventErrorData(error: error)
            }
            wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })

        case .notAttempted:
            // No restore ran (no handler, or the platform can't restore), so the recovery latency
            // measured from invalid-token detection would be meaningless - drop it. Keep the
            // original invalid-token error/failing step that the flow already carries.
            data.recoveryDuration = nil
            wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
        }
    }

    private func handle(_ event: OAuthClientRefreshEvent) {
        guard isFeatureEnabled() else { return }

        switch event {
        case .tokenRefreshStarted(let refreshID, let trigger):
            let data = AuthV2TokenRefreshWideEventData(globalData: WideEventGlobalData(id: refreshID))
            data.failingStep = .tokenRead
            data.refreshTrigger = trigger
            wideEvent.startFlow(data)

        case .tokenRefreshRefreshingAccessToken(let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (data: inout AuthV2TokenRefreshWideEventData) in
                data.refreshTokenDuration = .startingNow()
                data.failingStep = .refreshAccessToken
            }

        case .tokenRefreshRefreshedAccessToken(let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (data: inout AuthV2TokenRefreshWideEventData) in
                data.refreshTokenDuration?.complete()
            }

        case .tokenRefreshFetchingJWKS(let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (data: inout AuthV2TokenRefreshWideEventData) in
                data.fetchJWKSDuration = .startingNow()
                data.failingStep = .fetchingJWKS
            }

        case .tokenRefreshFetchedJWKS(let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (data: inout AuthV2TokenRefreshWideEventData) in
                data.fetchJWKSDuration?.complete()
            }

        case .tokenRefreshVerifyingAccessToken(let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (data: inout AuthV2TokenRefreshWideEventData) in
                data.failingStep = .verifyingAccessToken
            }

        case .tokenRefreshVerifyingRefreshToken(let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (data: inout AuthV2TokenRefreshWideEventData) in
                data.failingStep = .verifyingRefreshToken
            }

        case .tokenRefreshSavingTokens(let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (data: inout AuthV2TokenRefreshWideEventData) in
                data.failingStep = .tokenWrite
            }

        case .tokenRefreshSucceeded(let refreshID):
            guard let data = wideEvent.getFlowData(AuthV2TokenRefreshWideEventData.self, globalID: refreshID) else { return }
            data.failingStep = nil
            wideEvent.completeFlow(data, status: .success(reason: nil), onComplete: { _, _ in })

        case .tokenRefreshFailed(let refreshID, let error):
            completeRefresh(refreshID: refreshID, error: error)
        }
    }

    private func completeRefresh(refreshID: String, error: Error) {
        guard let data = wideEvent.getFlowData(AuthV2TokenRefreshWideEventData.self, globalID: refreshID) else { return }

        data.errorData = WideEventErrorData(error: error)

        if case OAuthClientError.invalidTokenRequest = error,
           (data.refreshTrigger ?? .client) == .client {
            data.failingStep = .recoverInvalidToken
            data.recoveryDuration = .startingNow()
            wideEvent.updateFlow(data)
            return
        }

        wideEvent.updateFlow(data)
        wideEvent.completeFlow(data, status: .failure, onComplete: { _, _ in })
    }

    private func newestPendingRecoveryFlow() -> AuthV2TokenRefreshWideEventData? {
        wideEvent.getAllFlowData(AuthV2TokenRefreshWideEventData.self)
            .filter { $0.failingStep == .recoverInvalidToken }
            .max { ($0.recoveryDuration?.start ?? .distantPast) < ($1.recoveryDuration?.start ?? .distantPast) }
    }
}
