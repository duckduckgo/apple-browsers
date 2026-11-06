//
//  AIChatBrowserToolsService.swift
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
import FeatureFlags_macOS
import Foundation
import History
import Persistence
import PrivacyConfig
import WebKit

/// Owns the tool catalog, invocation and permissions shared by all chat surfaces.
@MainActor
final class AIChatBrowserToolsService {

    let catalog: BrowserToolCatalog
    let invoker: BrowserToolInvoker
    let permissions: BrowserToolPermissionStoring
    let clientToolPermissions: ClientToolPermissionCoordinator

    private let configuration: AIChatBrowserToolsConfiguration
    private let windowControllersManager: WindowControllersManagerProtocol
    private let pushers = NSHashTable<AnyObject>.weakObjects()

    /// Whether browser tools are enabled by the parent feature flag.
    var isEnabled: Bool { configuration.isEnabled }

    /// - Parameter tools: overridable so tests can register their own catalog.
    init(featureFlagger: FeatureFlagger,
         windowControllersManager: WindowControllersManagerProtocol,
         historyCoordinator: HistoryCoordinating,
         permissionStorage: any KeyedStoring<BrowserToolPermissionStorageKeys> = UserDefaults.standard.keyedStoring(),
         tools: [any BrowserTool]? = nil) {
        let configuration = AIChatBrowserToolsConfiguration(featureFlagger: featureFlagger)
        let catalog = BrowserToolCatalog(tools: tools ?? Self.defaultTools(windowControllersManager: windowControllersManager,
                                                                           historyCoordinator: historyCoordinator),
                                         configuration: configuration)
        let permissions = BrowserToolPermissionStore(storage: permissionStorage)
        let clientToolPermissions = ClientToolPermissionCoordinator(permissions: permissions)
        self.configuration = configuration
        self.windowControllersManager = windowControllersManager
        self.catalog = catalog
        self.permissions = permissions
        self.clientToolPermissions = clientToolPermissions
        self.invoker = BrowserToolInvoker(catalog: catalog,
                                          clientToolPermissions: clientToolPermissions)
    }

    /// Registration order determines the order of the advertised capabilities.
    private static func defaultTools(windowControllersManager: WindowControllersManagerProtocol,
                                     historyCoordinator: HistoryCoordinating) -> [any BrowserTool] {
        let reader = BrowserToolPageContentReader(windowControllersManager: windowControllersManager)
        return [
            ListOpenTabsBrowserTool(windowControllersManager: windowControllersManager),
            SwitchToTabBrowserTool(windowControllersManager: windowControllersManager),
            SearchHistoryBrowserTool(historyCoordinator: historyCoordinator),
            ReadTabContentBrowserTool(windowControllersManager: windowControllersManager, reader: reader),
            FindInPageBrowserTool(windowControllersManager: windowControllersManager, reader: reader),
            HighlightInPageBrowserTool(windowControllersManager: windowControllersManager, highlighter: WebViewPageHighlighter())
        ]
    }

    /// Advertised to Duck.ai in `getAIChatNativeConfigValues`. Nil when no tool is enabled.
    var clientToolsConfiguration: ClientToolsConfiguration? {
        let capabilities = catalog.enabledClientToolCapabilities
        guard !capabilities.isEmpty,
              let configuration = try? ClientToolsConfiguration(capabilities: capabilities),
              ClientToolPayloadLimits.fits(configuration, within: ClientToolPayloadLimits.configBytes) else { return nil }
        return configuration
    }

    // MARK: - Pushes

    /// Live chats that can receive native→FE pushes. Held weakly; a chat unregisters by going away.
    func register(_ pusher: AIChatBrowserToolsPushing) {
        pushers.add(pusher)
    }

    /// Tells the chats owned by `ownerTabID` that their tab navigated. Metadata only; the FE decides
    /// whether to re-read the page.
    func notifyTabChanged(ownerTabID: TabIdentifier, url: URL) {
        guard isEnabled else { return }
        let data = AIChatTabChangedData(tabId: ownerTabID,
                                        url: url.absoluteString,
                                        isAttachable: !AIChatTabMetadata.shouldExcludeFromTabPicker(url))
        for pusher in livePushers where AIChatTabPickerSource.ownerTabID(for: pusher.pushTargetWebView, in: windowControllersManager) == ownerTabID {
            pusher.pushTabChanged(data)
        }
    }

    private var livePushers: [AIChatBrowserToolsPushing] {
        pushers.allObjects.compactMap { $0 as? AIChatBrowserToolsPushing }
    }
}

/// A chat surface that native can push browser-tools events to.
@MainActor
protocol AIChatBrowserToolsPushing: AnyObject {

    /// The web view showing the chat; resolves which owner tab the surface belongs to.
    var pushTargetWebView: WKWebView? { get }

    func pushTabChanged(_ data: AIChatTabChangedData)
}

/// Maps browser-tools sub-features onto macOS feature flags. A tool's `name` is its sub-feature's
/// raw value, so adding a sub-feature is a compile error here until it is mapped.
@MainActor
final class AIChatBrowserToolsConfiguration: BrowserToolsConfiguration {

    private let featureFlagger: FeatureFlagger

    init(featureFlagger: FeatureFlagger) {
        self.featureFlagger = featureFlagger
    }

    var isEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatBrowserTools)
    }

    func isToolEnabled(named name: String) -> Bool {
        guard isEnabled,
              let subfeature = AIChatBrowserToolsSubfeature(rawValue: name),
              let flag = Self.featureFlag(for: subfeature) else { return false }
        return featureFlagger.isFeatureOn(flag)
    }

    private static func featureFlag(for subfeature: AIChatBrowserToolsSubfeature) -> FeatureFlag? {
        switch subfeature {
        case .featureEnabled: nil // The parent gate, not a tool.
        case .listOpenTabs: .aiChatBrowserToolListOpenTabs
        case .searchHistory: .aiChatBrowserToolSearchHistory
        case .switchToTab: .aiChatBrowserToolSwitchToTab
        case .readTabContent: .aiChatBrowserToolReadTabContent
        case .findInPage: .aiChatBrowserToolFindInPage
        case .highlightInPage: .aiChatBrowserToolHighlightInPage
        }
    }
}
