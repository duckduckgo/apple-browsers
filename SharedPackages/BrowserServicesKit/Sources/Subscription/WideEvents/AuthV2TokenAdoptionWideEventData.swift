//
//  AuthV2TokenAdoptionWideEventData.swift
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

public class AuthV2TokenAdoptionWideEventData: WideEventData {
    public static let metadata = WideEventMetadata(
        pixelName: "auth_v2_token_adoption",
        featureName: "authv2-token-adoption",
        mobileMetaType: "ios-authv2-token-adoption",
        desktopMetaType: "macos-authv2-token-adoption",
        version: "1.2.0"
    )

    public enum FailingStep: String, Codable, CaseIterable {
        case adoptingToken = "token_adoption"
        case refreshingToken = "token_refresh"
    }

    /// What caused a token to be adopted. Distinguishes the main-app email-restore path from the
    /// VPN token-bridge path, which otherwise share the same `meta.type` and platform.
    public enum AdoptionSource: String, Codable {
        case webRestore = "web_restore"
        case vpn
    }

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData
    public var errorData: WideEventErrorData?

    public var failingStep: FailingStep?

    /// Optional: only set by the known entry points. Left absent (rather than defaulted) when unknown,
    /// so an un-annotated adoption reads as "unknown" rather than being misattributed.
    public var adoptionSource: AdoptionSource?

    public init(errorData: WideEventErrorData? = nil,
                contextData: WideEventContextData = WideEventContextData(),
                appData: WideEventAppData = WideEventAppData(),
                globalData: WideEventGlobalData = WideEventGlobalData()) {
        self.errorData = errorData
        self.contextData = contextData
        self.appData = appData
        self.globalData = globalData
    }
}

extension AuthV2TokenAdoptionWideEventData {

    public enum StatusReason: String {
        case partialData = "partial_data"
    }

    public func jsonParameters() -> [String: Encodable] {
        Dictionary(compacting: [
            (WideEventParameter.AuthV2AdoptionFeature.failingStep, failingStep?.rawValue),
            (WideEventParameter.AuthV2AdoptionFeature.adoptionSource, adoptionSource?.rawValue),
        ])
    }

}

extension WideEventParameter {

    public enum AuthV2AdoptionFeature {
        static let failingStep = "feature.data.ext.failing_step"
        static let adoptionSource = "feature.data.ext.adoption_source"
    }

}
