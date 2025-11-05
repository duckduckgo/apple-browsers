//
//  AutofillUserScript+SourceProvider.swift
//
//  Copyright © 2021 DuckDuckGo. All rights reserved.
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
import AutofillResources
import Common
import os.log

public protocol AutofillUserScriptSourceProvider {
    var source: String { get }
}

public class DefaultAutofillSourceProvider: AutofillUserScriptSourceProvider {

    private struct ProviderData {
        var privacyConfig: Data
        var userUnprotectedDomains: Data
        var userPreferences: Data
    }

    let privacyConfigurationManager: PrivacyConfigurationManaging
    let properties: ContentScopeProperties
    private var sourceStr: String = ""

    public var source: String {
        return sourceStr
    }

    public init(privacyConfigurationManager: PrivacyConfigurationManaging, properties: ContentScopeProperties, isDebug: Bool) {
        self.privacyConfigurationManager = privacyConfigurationManager
        self.properties = properties
    }

    public func loadJS(isDebug: Bool) throws {
        guard let replacements = buildReplacementsString() else {
            sourceStr = ""
            return
        }
        sourceStr = try AutofillUserScript.loadJS(isDebug ? "autofill-debug" : "autofill",
                                                  from: AutofillResources.bundle,
                                                  withReplacements: replacements)
    }

    public func buildRuntimeConfigResponse() -> String? {
        guard let providerData = buildReplacementsData(),
              let privacyConfigJson = String(data: providerData.privacyConfig, encoding: .utf8),
              let userUnprotectedDomainsString = String(data: providerData.userUnprotectedDomains, encoding: .utf8),
              let userPreferencesString = String(data: providerData.userPreferences, encoding: .utf8) else {
            return nil
        }

        return  """
                 {
                    "success": {
                        "contentScope": \(privacyConfigJson),
                        "userUnprotectedDomains": \(userUnprotectedDomainsString),
                        "userPreferences": \(userPreferencesString)
                    }
                }
            """
    }

    private func buildReplacementsString() -> [String: String]? {
        var replacements: [String: String] = [:]
#if os(macOS)
        replacements["// INJECT isApp HERE"] = "isApp = true;"
#endif

        if #available(iOS 14, macOS 11, *) {
            replacements["// INJECT hasModernWebkitAPI HERE"] = "hasModernWebkitAPI = true;"

#if os(macOS)
            replacements["// INJECT supportsTopFrame HERE"] = "supportsTopFrame = true;"
#endif
        }

        guard let providerData = buildReplacementsData(),
              let privacyConfigJson = String(data: providerData.privacyConfig, encoding: .utf8),
              let userUnprotectedDomainsString = String(data: providerData.userUnprotectedDomains, encoding: .utf8),
              let userPreferencesString = String(data: providerData.userPreferences, encoding: .utf8) else {
            return nil
        }

        replacements["// INJECT contentScope HERE"] = "contentScope = " + privacyConfigJson + ";"
        replacements["// INJECT userUnprotectedDomains HERE"] = "userUnprotectedDomains = " + userUnprotectedDomainsString + ";"
        replacements["// INJECT userPreferences HERE"] = "userPreferences = " + userPreferencesString + ";"
        return replacements
    }

    private func buildReplacementsData() -> ProviderData? {
        guard let filteredPrivacyConfigData = filteredDataFrom(configData: privacyConfigurationManager.currentConfig,
                                                               keepingTopLevelKeys: ["features", "unprotectedTemporary"],
                                                               andSubKey: "autofill",
                                                               inTopLevelKey: "features"),
              let userUnprotectedDomains = try? JSONEncoder().encode(privacyConfigurationManager.privacyConfig.userUnprotectedDomains),
              let jsonProperties = try? JSONEncoder().encode(properties) else {
            return nil
        }

        return ProviderData(privacyConfig: filteredPrivacyConfigData,
                            userUnprotectedDomains: userUnprotectedDomains,
                            userPreferences: jsonProperties)
    }

    /// `contentScope` only needs these properties from the privacy config, so creating a filtered version to improve performance
    ///  {
    ///     features: {
    ///         autofill: {
    ///             state: 'enabled',
    ///             exceptions: []
    ///         }
    ///     },
    ///     unprotectedTemporary: []
    /// }
    private func filteredDataFrom(configData: Data, keepingTopLevelKeys topLevelKeys: [String], andSubKey subKey: String, inTopLevelKey topLevelKey: String) -> Data? {
        do {
            if let jsonDict = try JSONSerialization.jsonObject(with: configData, options: []) as? [String: Any] {
                var filteredDict = [String: Any]()

                // Keep the specified top-level keys
                for key in topLevelKeys {
                    if let value = jsonDict[key] {
                        filteredDict[key] = value
                    }
                }

                // Handle the nested dictionary for a specific top-level key to keep only the sub-key
                if let nestedDict = jsonDict[topLevelKey] as? [String: Any],
                   let valueToKeep = nestedDict[subKey] {
                    filteredDict[topLevelKey] = [subKey: valueToKeep]
                }

                // Convert filtered dictionary back to Data
                let filteredData = try JSONSerialization.data(withJSONObject: filteredDict, options: [])
                return filteredData
            }
        } catch {
            Logger.autofill.error("Error during JSON serialization of privacy config: \(error.localizedDescription)")
        }

        return nil
    }

    public class Builder {
        private var privacyConfigurationManager: PrivacyConfigurationManaging
        private var properties: ContentScopeProperties
        private var isDebug: Bool = false
        private var sourceStr: String = ""
        private var shouldLoadJS: Bool = false

        public init(privacyConfigurationManager: PrivacyConfigurationManaging,
                    properties: ContentScopeProperties,
                    isDebug: Bool = false) {
            self.privacyConfigurationManager = privacyConfigurationManager
            self.properties = properties
            self.isDebug = isDebug
        }

        public func build() throws -> DefaultAutofillSourceProvider {
            let provider = DefaultAutofillSourceProvider(privacyConfigurationManager: privacyConfigurationManager,
                                                         properties: properties,
                                                         isDebug: isDebug)

            if shouldLoadJS {
                try provider.loadJS(isDebug: isDebug)
            }

            return provider
        }

        public func withJSLoading() -> Builder {
            self.shouldLoadJS = true
            return self
        }
    }
}
