//
//  SERPUserScriptHandler.swift
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
import UserScript

protocol SERPUserScriptHandling {
    func handshake(params: Any, message: UserScriptMessage) async throws -> SERPUserScript.DataModel.HandshakeResponse
    func getInstallOriginVariant(params: Any, message: UserScriptMessage) async throws -> GetInstallOriginVariantResponse
}

final class SERPUserScriptHandler: SERPUserScriptHandling {

    private let platform: SERPUserScript.DataModel.Platform
    private let installOriginEnabled: Bool
    private let installOriginVariantProvider: InstallOriginVariantProviding?

    init(platform: SERPUserScript.DataModel.Platform,
         installOriginEnabled: Bool,
         installOriginVariantProvider: InstallOriginVariantProviding?) {
        self.platform = platform
        self.installOriginEnabled = installOriginEnabled
        self.installOriginVariantProvider = installOriginVariantProvider
    }

    func handshake(params: Any, message: UserScriptMessage) async throws -> SERPUserScript.DataModel.HandshakeResponse {
        SERPUserScript.DataModel.HandshakeResponse(
            platform: platform,
            installOrigin: installOriginEnabled
        )
    }

    func getInstallOriginVariant(params: Any, message: UserScriptMessage) async throws -> GetInstallOriginVariantResponse {
        let request: GetInstallOriginVariantRequest? = {
            guard let paramsDict = params as? [String: Any],
                  let jsonData = try? JSONSerialization.data(withJSONObject: paramsDict) else { return nil }
            return try? JSONDecoder().decode(GetInstallOriginVariantRequest.self, from: jsonData)
        }()

        guard installOriginEnabled, let installOriginVariantProvider else {
            return GetInstallOriginVariantResponse(variant: nil)
        }

        let variant = installOriginVariantProvider.installOriginVariant(forCampaign: request?.campaign)
        return GetInstallOriginVariantResponse(variant: variant)
    }
}
