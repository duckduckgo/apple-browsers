//
//  WebExtensionHandlerProvider+macOS.swift
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

import AppKit
import PrivacyConfig
import WebExtensions
import WebKit

@available(macOS 15.4, *)
final class WebExtensionHandlerProvider: WebExtensionHandlerProviding {

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    private let autoconsentPreferences: AutoconsentPreferencesProviding
    private let autoconsentMessageHandler: MacOSAutoconsentMessageHandlerDelegate
    private let darkReaderExcludedDomainsProvider: DarkReaderExcludedDomainsProviding?

    init(
        privacyConfigurationManager: PrivacyConfigurationManaging,
        autoconsentPreferences: AutoconsentPreferencesProviding,
        darkReaderExcludedDomainsProvider: DarkReaderExcludedDomainsProviding? = nil
    ) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.autoconsentPreferences = autoconsentPreferences
        self.autoconsentMessageHandler = MacOSAutoconsentMessageHandlerDelegate()
        self.darkReaderExcludedDomainsProvider = darkReaderExcludedDomainsProvider
    }

    func makeHandlers(for context: WKWebExtensionContext) -> [WebExtensionMessageHandler] {
        switch context.duckDuckGoWebExtensionType {
        case .embedded:
            return [AutoconsentWebExtensionMessageHandler(
                privacyConfigurationManager: privacyConfigurationManager,
                autoconsentPreferences: autoconsentPreferences,
                delegate: autoconsentMessageHandler
            )]
        case .darkReader:
            guard let provider = darkReaderExcludedDomainsProvider else { return [] }
            return [DarkReaderWebExtensionMessageHandler(excludedDomainsProvider: provider)]
        default:
            return []
        }
    }
}
