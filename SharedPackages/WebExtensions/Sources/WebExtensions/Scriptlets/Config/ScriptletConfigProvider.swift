//
//  ScriptletConfigProvider.swift
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

import Combine
import Foundation
import PrivacyConfig
import os.log

@available(macOS 15.4, iOS 18.4, *)
public final class ScriptletConfigProvider: ScriptletConfigProviding {

    private let privacyConfigManager: PrivacyConfigurationManaging

    public init(privacyConfigManager: PrivacyConfigurationManaging) {
        self.privacyConfigManager = privacyConfigManager
    }

    public func currentManifest(for extensionType: DuckDuckGoWebExtensionType) -> ScriptletManifest? {
        guard let feature = privacyFeature(for: extensionType) else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No privacy feature mapping for '\(extensionType.rawValue)'")
            return nil
        }

        let settings = privacyConfigManager.privacyConfig.settings(for: feature)

        guard let version = settings["version"] as? String,
              let scriptletsDict = settings["scriptlets"] as? [String: [String: Any]] else {
            Logger.webExtensions.debug("[Scriptlets] ⏭️ No scriptlet manifest in privacy config for '\(extensionType.rawValue)'")
            return nil
        }

        let descriptors = scriptletsDict.compactMap { (name, scriptletDict) -> ScriptletDescriptor? in
            guard let urlString = scriptletDict["url"] as? String,
                  let url = URL(string: urlString),
                  let signature = scriptletDict["signature"] as? String else {
                return nil
            }
            return ScriptletDescriptor(name: name, url: url, signature: signature)
        }

        guard !descriptors.isEmpty else {
            Logger.webExtensions.warning("[Scriptlets] ⚠️ Scriptlet manifest found but no valid descriptors for '\(extensionType.rawValue)'")
            return nil
        }

        Logger.webExtensions.debug("[Scriptlets] ✓ Manifest retrieved for '\(extensionType.rawValue)': v\(version) with \(descriptors.count) descriptor(s)")
        return ScriptletManifest(version: version, scriptlets: descriptors)
    }

    public var configUpdatedPublisher: AnyPublisher<Void, Never> {
        privacyConfigManager.updatesPublisher
    }

    private func privacyFeature(for extensionType: DuckDuckGoWebExtensionType) -> PrivacyFeature? {
        switch extensionType {
        case .adBlockingExtension:
            return .adBlockingExtension
        case .embedded, .darkReader:
            return nil
        }
    }
}
