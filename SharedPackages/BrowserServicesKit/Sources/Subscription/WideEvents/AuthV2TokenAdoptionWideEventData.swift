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
import Networking
import PixelKit

public class AuthV2TokenAdoptionWideEventData: WideEventData {
    public static let metadata = WideEventMetadata(
        pixelName: "auth_v2_token_adoption",
        featureName: "authv2-token-adoption",
        mobileMetaType: "ios-authv2-token-adoption",
        desktopMetaType: "macos-authv2-token-adoption",
        version: "1.0.0"
    )

    public enum FailingStep: String, Codable, CaseIterable {
        case adoptingToken = "token_adoption"
        case refreshingToken = "token_refresh"
    }

    public var globalData: WideEventGlobalData
    public var contextData: WideEventContextData
    public var appData: WideEventAppData
    public var errorData: WideEventErrorData?

    public var failingStep: FailingStep?

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

    public func pixelParameters() -> [String: String] {
        Dictionary(compacting: [
            (WideEventParameter.AuthV2AdoptionFeature.failingStep, failingStep?.rawValue),
        ])
    }

}

extension WideEventParameter {

    public enum AuthV2AdoptionFeature {
        static let failingStep = "feature.data.ext.failing_step"
    }

}
