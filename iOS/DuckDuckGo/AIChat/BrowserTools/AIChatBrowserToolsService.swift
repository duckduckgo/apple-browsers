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
import Combine
import Core
import FeatureFlags_iOS
import Foundation
import Persistence
import PrivacyConfig
import UserScript

@MainActor
protocol AIChatBrowserToolsPushing: AnyObject {
    var browserToolsScope: BrowserToolScope? { get }
    var browserToolsSurface: AIChatBrowserToolsService.Surface { get }
    var browserToolsChatID: String? { get }
    func allowsBrowserTools(for message: UserScriptMessage) -> Bool
    func pushToolsListChanged()
    func pushTabChanged(_ data: AIChatTabChangedData)
}

extension AIChatBrowserToolsPushing {
    var browserToolsChatID: String? { nil }
    func allowsBrowserTools(for message: UserScriptMessage) -> Bool { false }
}

@MainActor
final class AIChatBrowserToolsService {
    static let serverName = "ios-browser"

    enum Surface: String {
        case contextual
        case fullTab
    }

    let sessions = AIChatMCPSessionStore()
    let catalog: BrowserToolCatalog
    let invoker: BrowserToolInvoker
    let permissions: BrowserToolPermissionStore
    let elicitations: AIChatElicitationCoordinator

    private let configuration: AIChatBrowserToolsConfiguration
    private let pushers: NSHashTable<AnyObject>
    private var catalogChangeNotifier: BrowserToolCatalogChangeNotifier?
    private var calls: [UUID: Call] = [:]
    private var clearingScopes: [UUID: ClearingScope] = [:]

    private struct Call {
        weak var source: (any AIChatBrowserToolsPushing)?
        let scope: BrowserToolScope
        let targetTabID: String?
        let task: Task<BrowserToolResult, Never>
        var promptIDs: Set<String> = []
    }

    private enum ClearingScope {
        case browsingModes(Set<Bool>)
        case chats(Set<String>?, isFireMode: Bool, affectedScopes: [BrowserToolScope])

        func includes(isFireMode: Bool) -> Bool {
            switch self {
            case .browsingModes(let modes): modes.contains(isFireMode)
            case .chats(_, let mode, _): mode == isFireMode
            }
        }
    }

    var isEnabled: Bool { configuration.isEnabled }

    init(historyManager: HistoryManaging, featureFlagger: any FeatureFlagger) {
        let configuration = AIChatBrowserToolsConfiguration(featureFlagger: featureFlagger)
        let pushers = NSHashTable<AnyObject>.weakObjects()
        let scopeProvider: BrowserToolScopeProvider = { context in
            pushers.allObjects.compactMap { ($0 as? any AIChatBrowserToolsPushing)?.browserToolsScope }
                .first { $0.accepts(context) }
        }
        let catalog = BrowserToolCatalog(tools: Self.defaultTools(historyManager: historyManager, scopeProvider: scopeProvider),
                                         configuration: configuration)
        let permissions = BrowserToolPermissionStore(storage: UserDefaults.standard.keyedStoring())
        let elicitations = AIChatElicitationCoordinator()
        self.configuration = configuration
        self.pushers = pushers
        self.catalog = catalog
        self.permissions = permissions
        self.elicitations = elicitations
        invoker = BrowserToolInvoker(catalog: catalog, configuration: configuration,
                                      permissions: permissions, elicitations: elicitations)
        catalogChangeNotifier = BrowserToolCatalogChangeNotifier(
            changes: featureFlagger.updatesPublisher,
            signature: { catalog.enabledTools.map(\.name) },
            onChange: { [weak self] in self?.pushToolsListChanged() }
        )
    }

    private static func defaultTools(historyManager: HistoryManaging, scopeProvider: @escaping BrowserToolScopeProvider) -> [any BrowserTool] {
        let reader = BrowserToolPageContentReader()
        return [
            ListOpenTabsBrowserTool(scopeProvider: scopeProvider),
            SwitchToTabBrowserTool(scopeProvider: scopeProvider),
            SearchHistoryBrowserTool(historyManager: historyManager, scopeProvider: scopeProvider),
            ReadTabContentBrowserTool(scopeProvider: scopeProvider, reader: reader),
            FindInPageBrowserTool(scopeProvider: scopeProvider, reader: reader),
            HighlightInPageBrowserTool(scopeProvider: scopeProvider, highlighter: WebViewPageHighlighter())
        ]
    }

    func isAvailable(in scope: BrowserToolScope?) -> Bool {
        guard let scope else { return false }
        return isEnabled && scope.isValid && !scope.isBurner
            && !clearingScopes.values.contains { $0.includes(isFireMode: scope.isBurner) }
    }

    func register(_ pusher: any AIChatBrowserToolsPushing) {
        pushers.add(pusher)
    }

    func unregister(_ pusher: any AIChatBrowserToolsPushing) {
        for id in calls.keys.filter({ calls[$0]?.source === pusher }) {
            cancelCall(id)
        }
        pushers.remove(pusher)
        if let scope = pusher.browserToolsScope { removeSessionIfUnused(ownerTabID: scope.ownerTabID) }
    }

    func notifyTabChanged(ownerTabID: String, url: URL, isAttachable: Bool) {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        for pusher in livePushers where pusher.browserToolsSurface == .contextual {
            guard let scope = pusher.browserToolsScope, scope.ownerTabID == ownerTabID, isAvailable(in: scope) else { continue }
            pusher.pushTabChanged(AIChatTabChangedData(tabId: ownerTabID, url: url.absoluteString,
                                                       isAttachable: isAttachable && scope.isAttachableURL(url)))
        }
    }

    private func pushToolsListChanged() {
        for pusher in livePushers where pusher.browserToolsScope?.isValid == true {
            pusher.pushToolsListChanged()
        }
    }

    private var livePushers: [any AIChatBrowserToolsPushing] {
        pushers.allObjects.compactMap { $0 as? any AIChatBrowserToolsPushing }
    }

    private var scopes: [BrowserToolScope] {
        livePushers.compactMap(\.browserToolsScope) + calls.values.map(\.scope)
    }
}

extension AIChatBrowserToolsService {
    func resetSession(forOwnerTabID ownerTabID: String) {
        for id in calls.keys.filter({ calls[$0]?.scope.ownerTabID == ownerTabID }) {
            cancelCall(id)
        }
        sessions.removeSession(forOwnerTabID: ownerTabID)
    }

    func cancelOperations(for scope: BrowserToolScope) {
        for id in calls.keys.filter({ calls[$0]?.scope === scope }) {
            cancelCall(id)
        }
        removeSessionIfUnused(ownerTabID: scope.ownerTabID, excluding: scope)
    }

    func invalidate(scope: BrowserToolScope) {
        scope.revoke()
        cancelOperations(for: scope)
    }

    func invoke(request: InvokeBrowserToolRequest, context: BrowserToolCallContext, scope: BrowserToolScope,
                source: any AIChatBrowserToolsPushing, elicitationPusher: (any AIChatElicitationPushing)?) async -> BrowserToolResult {
        guard isAvailable(in: scope), source.browserToolsScope === scope, pushers.contains(source) else { return .failure(.unavailable) }
        let id = UUID()
        let relay = ElicitationPusher(service: self, callID: id, destination: elicitationPusher)
        let invoker = invoker
        let task = Task { @MainActor [weak self] in
            await invoker.invoke(toolNamed: request.name, arguments: request.arguments, context: context,
                                 elicitationPusher: relay, isContextValid: { self?.canContinue(id) == true })
        }
        var targetTabID: String?
        if ["readTabContent", "findInPage", "highlightInPage", "switchToTab"].contains(request.name) {
            let target = request.arguments?["tabId"]?.stringValue?.trimmingCharacters(in: .whitespaces)
            targetTabID = target.flatMap { $0.isEmpty ? nil : $0 } ?? scope.ownerTabID
        }
        calls[id] = Call(source: source, scope: scope, targetTabID: targetTabID, task: task)
        defer { cancelCall(id) }
        let result = await withTaskCancellationHandler(operation: { await task.value }, onCancel: { [weak self] in
            task.cancel()
            Task { @MainActor in self?.cancelCall(id) }
        })
        guard !Task.isCancelled, canContinue(id) else { return .failure(.cancelled) }
        guard catalog.tool(named: request.name) != nil else { return .failure(.unavailable) }
        return result
    }

    func completeElicitation(_ response: AIChatElicitationResponseRequest, source: any AIChatBrowserToolsPushing) {
        guard let scope = source.browserToolsScope, isAvailable(in: scope),
              let id = calls.first(where: {
                  $0.value.source === source && $0.value.scope === scope && $0.value.promptIDs.contains(response.id)
              })?.key, canContinue(id) else { return }
        calls[id]?.promptIDs.remove(response.id)
        elicitations.complete(id: response.id, result: response.result ?? .cancel)
    }

    private func canContinue(_ id: UUID) -> Bool {
        guard let call = calls[id], let source = call.source else { return false }
        return call.scope.isValid && source.browserToolsScope === call.scope && pushers.contains(source)
    }

    private func cancelCall(_ id: UUID) {
        guard let call = calls.removeValue(forKey: id) else { return }
        call.task.cancel()
        for promptID in call.promptIDs {
            elicitations.complete(id: promptID, result: .cancel)
        }
    }

    private func removeSessionIfUnused(ownerTabID: String, excluding scope: BrowserToolScope? = nil) {
        guard !livePushers.contains(where: {
            guard let current = $0.browserToolsScope else { return false }
            return current !== scope && current.ownerTabID == ownerTabID && current.isValid
        }) else { return }
        sessions.removeSession(forOwnerTabID: ownerTabID)
    }

    private final class ElicitationPusher: AIChatElicitationPushing {
        private weak var service: AIChatBrowserToolsService?
        private weak var destination: (any AIChatElicitationPushing)?
        private let callID: UUID

        init(service: AIChatBrowserToolsService, callID: UUID, destination: (any AIChatElicitationPushing)?) {
            self.service = service
            self.callID = callID
            self.destination = destination
        }

        func pushElicitationCreate(_ params: MCPElicitationCreateParams) -> Bool {
            guard let service, service.canContinue(callID), let call = service.calls[callID],
                  service.isAvailable(in: call.scope) else { return false }
            service.calls[callID]?.promptIDs.insert(params.id)
            return destination?.pushElicitationCreate(params) ?? false
        }
    }
}

extension AIChatBrowserToolsService {
    func beginClearing(for request: FireRequest) -> UUID {
        let modes: Set<Bool>
        switch request.scope {
        case .all: modes = [false, true]
        case .normalMode: modes = [false]
        case .fireMode: modes = [true]
        case .tab(let viewModel): modes = [viewModel.tab.fireTab]
        }
        let id = UUID()
        clearingScopes[id] = .browsingModes(modes)
        invalidate(for: request)
        return id
    }

    func beginClearingChats(_ chatIDs: Set<String>? = nil, isFireMode: Bool) -> UUID {
        let id = UUID()
        let affected = livePushers.compactMap { source -> BrowserToolScope? in
            guard let scope = source.browserToolsScope, scope.isBurner == isFireMode else { return nil }
            if let chatIDs {
                guard let chatID = source.browserToolsChatID, chatIDs.contains(chatID) else { return nil }
            }
            return scope
        }
        clearingScopes[id] = .chats(chatIDs, isFireMode: isFireMode, affectedScopes: affected)
        cancelCalls(isFireMode: isFireMode)
        for scope in affected { sessions.removeSession(forOwnerTabID: scope.ownerTabID) }
        return id
    }

    func endClearingChats(_ id: UUID, result: Result<Void, Error>) {
        guard let clearingScope = clearingScopes[id],
              case .chats(let chatIDs, let isFireMode, let affectedScopes) = clearingScope else { return }
        defer { clearingScopes[id] = nil }
        guard case .success = result else { return }
        for scope in affectedScopes {
            invalidate(scope: scope)
            sessions.removeSession(forOwnerTabID: scope.ownerTabID)
        }
        if let chatIDs {
            invalidateChats(chatIDs, isFireMode: isFireMode)
        } else {
            invalidateAll(isFireMode: isFireMode)
        }
    }

    func endClearing(_ id: UUID) {
        clearingScopes[id] = nil
    }

    func invalidate(for request: FireRequest) {
        switch request.scope {
        case .all: invalidateAll()
        case .normalMode: invalidateAll(isFireMode: false)
        case .fireMode: invalidateAll(isFireMode: true)
        case .tab(let viewModel):
            for scope in scopes where scope.ownerTabID == viewModel.tab.uid { invalidate(scope: scope) }
            cancelCalls(isFireMode: viewModel.tab.fireTab)
            sessions.removeSession(forOwnerTabID: viewModel.tab.uid)
        }
    }

    func invalidate(tabID: String) {
        for scope in scopes where scope.ownerTabID == tabID { invalidate(scope: scope) }
        for id in calls.keys.filter({ calls[$0]?.targetTabID == tabID }) { cancelCall(id) }
        sessions.removeSession(forOwnerTabID: tabID)
    }

    func invalidateChats(_ chatIDs: Set<String>, isFireMode: Bool) {
        let affected = livePushers.compactMap { source -> BrowserToolScope? in
            guard let scope = source.browserToolsScope, scope.isBurner == isFireMode,
                  let chatID = source.browserToolsChatID, chatIDs.contains(chatID) else { return nil }
            return scope
        }
        for scope in affected {
            invalidate(scope: scope)
            sessions.removeSession(forOwnerTabID: scope.ownerTabID)
        }
        cancelCalls(isFireMode: isFireMode)
    }

    private func cancelCalls(isFireMode: Bool) {
        for id in calls.keys.filter({ calls[$0]?.scope.isBurner == isFireMode }) { cancelCall(id) }
    }

    private func invalidateAll(isFireMode: Bool? = nil) {
        for scope in scopes where isFireMode == nil || scope.isBurner == isFireMode {
            invalidate(scope: scope)
            sessions.removeSession(forOwnerTabID: scope.ownerTabID)
        }
        if isFireMode == nil { sessions.removeAllSessions() }
    }
}

@MainActor
private final class AIChatBrowserToolsConfiguration: BrowserToolsConfiguration {
    private let featureFlagger: any FeatureFlagger
    private let feature: ChatToBrowserToolCallingFeature

    init(featureFlagger: any FeatureFlagger) {
        self.featureFlagger = featureFlagger
        feature = ChatToBrowserToolCallingFeature(featureFlagger: featureFlagger)
    }

    var isEnabled: Bool {
        feature.isAvailable
    }

    func isToolEnabled(named name: String) -> Bool {
        guard isEnabled, let subfeature = AIChatBrowserToolsSubfeature(rawValue: name) else { return false }
        let flag: FeatureFlag
        switch subfeature {
        case .featureEnabled: return false
        case .listOpenTabs: flag = .aiChatBrowserToolListOpenTabs
        case .switchToTab: flag = .aiChatBrowserToolSwitchToTab
        case .searchHistory: flag = .aiChatBrowserToolSearchHistory
        case .readTabContent: flag = .aiChatBrowserToolReadTabContent
        case .findInPage: flag = .aiChatBrowserToolFindInPage
        case .highlightInPage: flag = .aiChatBrowserToolHighlightInPage
        }
        return featureFlagger.isFeatureOn(flag)
    }
}
