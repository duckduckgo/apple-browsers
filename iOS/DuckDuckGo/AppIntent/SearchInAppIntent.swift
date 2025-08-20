//
//  SearchInAppIntent.swift
//  DuckDuckGo
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

import SwiftUI
import AppIntents
import Core

@available(iOS 17.0, *)
struct SearchInAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Search privately in DuckDuckGo"
    static let description: LocalizedStringResource = "Search privately in DuckDuckGo"
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Query") var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search \(\.$query) in App")
    }
    
    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        guard let quickLinkURL = URL(string: AppDeepLinkSchemes.quickLink.appending(query)) else {
            return .result()
        }
        
        UIApplication.shared.open(quickLinkURL)
        
        return .result()
    }
}
