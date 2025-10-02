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
import Networking
import PixelKit

public class AuthV2TokenRefreshWideEventData: WideEventData {
    #if DEBUG
    public static let pixelName = "auth_v2_token_refresh_debug"
    #else
    public static let pixelName = "auth_v2_token_refresh"
    #endif

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData

    public var failingStep: FailingStep?
    public var errorData: WideEventErrorData?

    public init(failingStep: FailingStep? = nil,
                errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData,
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.failingStep = failingStep
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }
}

extension AuthV2TokenRefreshWideEventData {

    public enum FailingStep: String, Codable, CaseIterable {
        case tokenRead = "token_read"
        case refreshAccessToken = "refresh_access_token"
        case fetchingJWKS = "fetch_jwks"
        case verifyingAccessToken = "verify_access_token"
        case verifyingRefreshToken = "verify_refresh_token"
        case tokenWrite = "token_write"
    }

    public enum StatusReason: String {
        case partialData = "partial_data"
    }

    public func pixelParameters() -> [String: String] {
        var parameters: [String: String] = [:]

        parameters[WideEventParameter.Feature.name] = "authv2-token-refresh"

        if let failingStep = failingStep {
            parameters[WideEventParameter.AuthV2RefreshFeature.failingStep] = failingStep.rawValue
        }

        return parameters
    }

    private func bucket(_ ms: Int) -> Int {
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

extension AuthV2TokenRefreshWideEventData {

    public static let authEventMapping: EventMapping<OAuthClientEvent> = .init { event, _, _, _ in
        let wideEvent = WideEvent()

        switch event {
        case .tokenRefreshStarted(let refreshID):
            let globalData = WideEventGlobalData(id: refreshID)
            let contextData = WideEventContextData(name: "token-refresh")
            let data = AuthV2TokenRefreshWideEventData(contextData: contextData, globalData: globalData)
            data.failingStep = .tokenRead
            wideEvent.startFlow(data)
        case .tokenRefreshRefreshingAccessToken(refreshID: let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (event: inout AuthV2TokenRefreshWideEventData) in
                event.failingStep = .refreshAccessToken
            }
        case .tokenRefreshFetchingJWKS(refreshID: let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (event: inout AuthV2TokenRefreshWideEventData) in
                event.failingStep = .fetchingJWKS
            }
        case .tokenRefreshVerifyingAccessToken(refreshID: let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (event: inout AuthV2TokenRefreshWideEventData) in
                event.failingStep = .verifyingAccessToken
            }
        case .tokenRefreshVerifyingRefreshToken(refreshID: let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (event: inout AuthV2TokenRefreshWideEventData) in
                event.failingStep = .verifyingRefreshToken
            }
        case .tokenRefreshSavingTokens(refreshID: let refreshID):
            wideEvent.updateFlow(globalID: refreshID) { (event: inout AuthV2TokenRefreshWideEventData) in
                event.failingStep = .tokenWrite
            }
        case .tokenRefreshSucceeded(let refreshID):
            if let data = wideEvent.getFlowData(AuthV2TokenRefreshWideEventData.self, globalID: refreshID) {
                data.failingStep = nil
                wideEvent.completeFlow(data, status: .success(reason: nil))
            }
        case .tokenRefreshFailed(let refreshID, let error):
            if let data = wideEvent.getFlowData(AuthV2TokenRefreshWideEventData.self, globalID: refreshID) {
                data.errorData = WideEventErrorData(error: error)
                wideEvent.updateFlow(data)
                wideEvent.completeFlow(data, status: .failure)
            }
        }
    }

}

extension WideEventParameter {

    public enum AuthV2RefreshFeature {
        static let failingStep = "feature.data.ext.failing_step"
    }

}
