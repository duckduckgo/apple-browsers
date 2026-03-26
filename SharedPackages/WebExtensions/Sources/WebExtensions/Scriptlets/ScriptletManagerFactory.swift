//
//  ScriptletManagerFactory.swift
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
import Networking
import PrivacyConfig

@available(macOS 15.4, iOS 18.4, *)
public enum ScriptletManagerFactory {

    public static func makeManager(
        extensionType: DuckDuckGoWebExtensionType,
        privacyConfigManager: PrivacyConfigurationManaging,
        apiService: APIService,
        baseDirectory: URL,
        defaults: UserDefaults = .standard
    ) -> ScriptletManager {

        let configProvider = ScriptletConfigProvider(
            privacyConfigManager: privacyConfigManager
        )

        let fetcher = ScriptletFetcher(apiService: apiService)

        let validator = StubScriptletValidator()

        let store = ScriptletStore(
            baseDirectory: baseDirectory,
            defaults: defaults
        )

        return ScriptletManager(
            extensionType: extensionType,
            configProvider: configProvider,
            fetcher: fetcher,
            validator: validator,
            store: store
        )
    }
}
