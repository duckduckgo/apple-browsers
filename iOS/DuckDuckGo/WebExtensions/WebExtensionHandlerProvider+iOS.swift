//
//  WebExtensionHandlerProvider+iOS.swift
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

import UIKit
import WebExtensions
import WebKit
import PrivacyConfig

@available(iOS 18.4, *)
final class WebExtensionHandlerProvider: WebExtensionHandlerProviding {

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let autoconsentPreferences: AutoconsentPreferencesProviding

    init(
        privacyConfigurationManager: PrivacyConfigurationManaging,
        autoconsentPreferences: AutoconsentPreferencesProviding
    ) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.autoconsentPreferences = autoconsentPreferences
    }

    func makeHandlers(for context: WKWebExtensionContext) -> [WebExtensionMessageHandler] {
        switch context.duckDuckGoExtensionType {
        case .ddgInternalExtension:
            return [AutoconsentWebExtensionMessageHandler(
                privacyConfigurationManager: privacyConfigurationManager,
                autoconsentPreferences: autoconsentPreferences
            )]
        default:
            return [AutoconsentWebExtensionMessageHandler(
                privacyConfigurationManager: privacyConfigurationManager,
                autoconsentPreferences: autoconsentPreferences
            )]
        }
    }
}
