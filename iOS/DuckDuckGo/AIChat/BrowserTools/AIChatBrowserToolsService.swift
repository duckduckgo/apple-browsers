//
//  AIChatBrowserToolsService.swift
//  DuckDuckGo
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

import AIChat
import FeatureFlags_iOS
import Foundation
import Persistence
import PrivacyConfig

@MainActor
final class AIChatBrowserToolsService {
    let catalog: BrowserToolCatalog
    let invoker: BrowserToolInvoker
    let permissions: BrowserToolPermissionStoring
    let clientToolPermissions: ClientToolPermissionCoordinator
    private let configuration: AIChatBrowserToolsConfiguration

    init(featureFlagger: any FeatureFlagger,
         scopeProvider: @escaping BrowserToolScopeProvider = { _ in nil },
         permissionStorage: any KeyedStoring<BrowserToolPermissionStorageKeys> = UserDefaults.standard.keyedStoring()) {
        let configuration = AIChatBrowserToolsConfiguration(featureFlagger: featureFlagger)
        let catalog = BrowserToolCatalog(tools: [ListOpenTabsBrowserTool(scopeProvider: scopeProvider)],
                                         configuration: configuration, capabilities: [.listOpenTabs])
        let permissions = BrowserToolPermissionStore(storage: permissionStorage)
        let clientToolPermissions = ClientToolPermissionCoordinator(permissions: permissions)
        self.configuration = configuration
        self.catalog = catalog
        self.permissions = permissions
        self.clientToolPermissions = clientToolPermissions
        self.invoker = BrowserToolInvoker(catalog: catalog,
                                          clientToolPermissions: clientToolPermissions)
    }

    var isEnabled: Bool { configuration.isEnabled }

    var clientToolsConfiguration: ClientToolsConfiguration? {
        let capabilities = catalog.enabledClientToolCapabilities
        guard !capabilities.isEmpty,
              let configuration = try? ClientToolsConfiguration(capabilities: capabilities),
              ClientToolPayloadLimits.fits(configuration, within: ClientToolPayloadLimits.configBytes) else { return nil }
        return configuration
    }
}

@MainActor
private final class AIChatBrowserToolsConfiguration: BrowserToolsConfiguration {
    private let feature: ChatToBrowserToolCallingFeatureProviding
    private let featureFlagger: any FeatureFlagger

    init(featureFlagger: any FeatureFlagger) {
        self.featureFlagger = featureFlagger
        self.feature = ChatToBrowserToolCallingFeature(featureFlagger: featureFlagger)
    }

    var isEnabled: Bool { feature.isAvailable }

    func isToolEnabled(named name: String) -> Bool {
        guard isEnabled,
              let subfeature = AIChatBrowserToolsSubfeature(rawValue: name),
              let flag = Self.featureFlag(for: subfeature) else { return false }
        return featureFlagger.isFeatureOn(flag)
    }

    private static func featureFlag(for subfeature: AIChatBrowserToolsSubfeature) -> FeatureFlag? {
        switch subfeature {
        case .listOpenTabs:
            .aiChatBrowserToolListOpenTabs
        case .featureEnabled, .searchHistory, .switchToTab, .readTabContent, .findInPage, .highlightInPage:
            nil
        }
    }
}
