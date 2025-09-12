//
//  AIChatIntent.swift
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
struct AIChatIntent: AppIntent {
    static var title: LocalizedStringResource = "Chat with Duck.ai on DuckDuckGo"
    static let description: LocalizedStringResource = "Open a private chat with Duck.ai"
    static let openAppWhenRun: Bool = true
    static let isDiscoverable: Bool = true
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    public static var parameterSummary: some ParameterSummary {
        Summary("Open a private chat with Duck.ai")
    }
    
    @MainActor
    public func perform() async throws -> some IntentResult & OpensIntent {
        Pixel.fire(pixel: .appIntentPerformed, withAdditionalParameters: ["type": "duckai"])
        await UIApplication.shared.open(AppDeepLinkSchemes.openAIChat.url)
        return .result()
    }
}
