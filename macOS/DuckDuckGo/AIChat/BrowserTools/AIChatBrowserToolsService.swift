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
import Combine
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
    private let activitySubject = PassthroughSubject<AIChatBrowserToolActivity, Never>()
    private var reportedCalls: [String: ReportedCall] = [:]
    private let pushers = NSHashTable<AnyObject>.weakObjects()
    private var lastClientToolsConfiguration: ClientToolsConfiguration?
    private var featureFlagChanges: AnyCancellable?

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
        self.lastClientToolsConfiguration = Self.clientToolsConfiguration(for: catalog)
        self.featureFlagChanges = featureFlagger.updatesPublisher.sink { [weak self] in
            Task { @MainActor in
                self?.pushClientToolsChangedIfNeeded()
            }
        }
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
        Self.clientToolsConfiguration(for: catalog)
    }

    private static func clientToolsConfiguration(for catalog: BrowserToolCatalog) -> ClientToolsConfiguration? {
        let capabilities = catalog.enabledClientToolCapabilities
        guard !capabilities.isEmpty,
              let configuration = try? ClientToolsConfiguration(capabilities: capabilities),
              ClientToolPayloadLimits.fits(configuration, within: ClientToolPayloadLimits.configBytes) else { return nil }
        return configuration
    }

    // MARK: - Calls

    /// What Duck.ai does in the browser, call by call, for whoever wants to show it. Fire Windows report nothing.
    var activity: AnyPublisher<AIChatBrowserToolActivity, Never> {
        activitySubject.eraseToAnyPublisher()
    }

    /// Runs a call through the invoker, reporting to `activity` when it starts, waits on the user and ends.
    func invoke(_ request: ExecuteClientToolRequest,
                context: BrowserToolCallContext,
                permissionPusher: (any ClientToolPermissionPushing)?) async -> ExecuteClientToolResponse {
        guard !context.isBurner else {
            return await invoker.invokeClientTool(request, context: context, permissionPusher: permissionPusher)
        }
        let call = ReportedCall(name: request.capability.name,
                                subject: subject(ofToolNamed: request.capability.name, arguments: request.input, context: context))
        reportedCalls[request.callId] = call
        report(call, callID: request.callId, phase: .started)
        let response = await invoker.invokeClientTool(request, context: context, permissionPusher: permissionPusher)
        reportedCalls[request.callId] = nil
        if case .success = response {
            report(call, callID: request.callId, phase: .finished(succeeded: true))
        } else {
            report(call, callID: request.callId, phase: .finished(succeeded: false))
        }
        return response
    }

    /// Called once a chat has shown a permission prompt for `callID`.
    func permissionWasRequested(forCallID callID: String) {
        guard let call = reportedCalls[callID] else { return }
        report(call, callID: callID, phase: .awaitingPermission)
    }

    private func report(_ call: ReportedCall, callID: String, phase: AIChatBrowserToolActivity.Phase) {
        activitySubject.send(AIChatBrowserToolActivity(callID: callID, toolName: call.name, subject: call.subject, phase: phase))
    }

    /// Tools that act on the chat's own page when no tab is named.
    private static let pageToolNames: Set<String> = ["readTabContent", "findInPage", "highlightInPage"]

    /// What a call is about: the words searched for, or the title of the tab it acts on.
    private func subject(ofToolNamed name: String, arguments: JSONValue?, context: BrowserToolCallContext) -> String? {
        if let query = arguments?["query"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            return query
        }
        let namedTabID = arguments?["tabId"]?.stringValue?.trimmingCharacters(in: .whitespaces)
        guard let tabID = namedTabID.flatMap({ $0.isEmpty ? nil : $0 }) ?? (Self.pageToolNames.contains(name) ? context.ownerTabID : nil),
              let token = context.ownerWindowToken,
              let collection = AIChatTabPickerSource.tabCollectionViewModel(forWindowToken: token, in: windowControllersManager) else {
            return nil
        }
        let tabs = (collection.pinnedTabsCollection?.tabs ?? []) + collection.tabCollection.tabs
        guard let tab = tabs.first(where: { $0.uuid == tabID }), case .url(let url, _, _) = tab.content, !url.isDuckAIURL else {
            return nil
        }
        return tab.title ?? url.host
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

    private func pushClientToolsChangedIfNeeded() {
        let configuration = clientToolsConfiguration
        guard configuration != lastClientToolsConfiguration else { return }
        lastClientToolsConfiguration = configuration
        let data = ClientToolsChangedData(clientTools: configuration)
        for pusher in livePushers {
            pusher.pushClientToolsChanged(data)
        }
    }

    private var livePushers: [AIChatBrowserToolsPushing] {
        pushers.allObjects.compactMap { $0 as? AIChatBrowserToolsPushing }
    }
}

/// One step of a browser tool call Duck.ai made.
struct AIChatBrowserToolActivity: Equatable {

    enum Phase: Equatable {
        case started
        /// The user's OK was asked for in the chat.
        case awaitingPermission
        case finished(succeeded: Bool)
    }

    let callID: String
    let toolName: String
    /// The words searched for, or the title of the tab acted on, when there is one.
    let subject: String?
    let phase: Phase
}

/// A call reported to `activity`, kept until it ends.
private struct ReportedCall {
    let name: String
    let subject: String?
}

/// A chat surface that native can push browser-tools events to.
@MainActor
protocol AIChatBrowserToolsPushing: AnyObject {

    /// The web view showing the chat; resolves which owner tab the surface belongs to.
    var pushTargetWebView: WKWebView? { get }

    func pushClientToolsChanged(_ data: ClientToolsChangedData)
    func pushTabChanged(_ data: AIChatTabChangedData)
}

struct ClientToolsChangedData: Encodable, Equatable {
    let clientTools: ClientToolsConfiguration?

    private enum CodingKeys: String, CodingKey {
        case clientTools
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(clientTools, forKey: .clientTools)
    }
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
