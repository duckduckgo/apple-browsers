//
//  DBPUIOutlookOptOutEmailProvider.swift
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

import DataBrokerProtectionCore
import Foundation

final class DBPUIOutlookOptOutEmailProvider: DBPUIOptOutEmailProvider {
    let providerName = "Outlook"
    let supportedMailHandlerBundleIdentifiers: Set<String> = [
        "com.microsoft.Outlook",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Canary"
    ]

    @MainActor
    func open(_ payload: DBPUIOptOutEmail, using workspace: DBPUIOptOutEmailWorkspace) -> DBPUIOptOutEmailOpenResult {
        guard let composeURL = composeURL(for: payload) else {
            return .failed(providerName: providerName, failure: .composeURLBuildFailed(providerName: providerName))
        }

        if workspace.open(composeURL) {
            return .opened(providerName: providerName)
        }

        return .failed(providerName: providerName, failure: .workspaceOpenFailed(providerName: providerName))
    }

    private func composeURL(for payload: DBPUIOptOutEmail) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "outlook.office.com"
        components.path = "/mail/deeplink/compose"
        components.queryItems = [
            URLQueryItem(name: "to", value: payload.to),
            URLQueryItem(name: "subject", value: payload.subject),
            URLQueryItem(name: "body", value: payload.body)
        ]
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")

        return components.url
    }
}
