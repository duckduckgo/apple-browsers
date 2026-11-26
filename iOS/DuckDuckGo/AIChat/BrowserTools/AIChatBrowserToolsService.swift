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
import FoundationExtensions
import Persistence
import PrivacyConfig
import SitePermissions

@MainActor
final class AIChatBrowserToolsService {
    private var lastClientToolsConfiguration: ClientToolsConfiguration?
    private var featureFlagChanges: AnyCancellable?
    private var bindings: [ObjectIdentifier: AIChatBrowserToolsBinding] = [:]
    private var clearing: [UUID: AIChatBrowserToolsClearing] = [:]
#if DEBUG || ALPHA
    private var debugSessions: [ObjectIdentifier: BrowserToolsDebugSession] = [:]
#endif
    private let injectedScopeProvider: BrowserToolScopeProvider?
    private(set) lazy var catalog = BrowserToolCatalog(
        tools: makeTools(),
        configuration: configuration, capabilities: supportedCapabilities)
    private(set) lazy var invoker = BrowserToolInvoker(
        catalog: catalog,
        clientToolPermissions: AIChatNativePermissionCoordinator(base: clientToolPermissions) { [weak self] toolName, requiresRequestAccess, prompter in
#if DEBUG || ALPHA
            if let source = prompter as? BrowserToolsDebugSession {
                guard let self else { return .unavailable }
                return self.debugAdmissionFailure(toolName: toolName, requiresRequestAccess: requiresRequestAccess, from: source)
            }
#endif
            guard let source = prompter as? AIChatUserScript else { return nil }
            guard let self else { return .unavailable }
            return self.permissionAdmissionFailure(toolName: toolName, requiresRequestAccess: requiresRequestAccess, from: source)
        })
    let permissions: BrowserToolSitePermissions
    let clientToolPermissions: ClientToolPermissionCoordinator
    private let bookmarksDatabase: CoreDataDatabase?
    private let historyManager: HistoryManaging
    private let configuration: AIChatBrowserToolsConfiguration

    private var supportedCapabilities: [ClientToolCapability] = [
        .listOpenTabs,
        .switchToTab,
        .readTabContent,
        .searchHistory,
        .findInPage,
        .searchBookmarks
    ]

    init(featureFlagger: any FeatureFlagger,
         historyManager: HistoryManaging,
         bookmarksDatabase: CoreDataDatabase? = nil,
         scopeProvider: BrowserToolScopeProvider? = nil,
         sitePermissionsStore: SitePermissionsStore? = nil,
         capabilities: [ClientToolCapability]? = nil) {
        self.bookmarksDatabase = bookmarksDatabase
        self.historyManager = historyManager
        configuration = AIChatBrowserToolsConfiguration(featureFlagger: featureFlagger)
        injectedScopeProvider = scopeProvider
        if let capabilities {
            self.supportedCapabilities = capabilities
        }
        let store = sitePermissionsStore ?? SitePermissionsStore(storage: UserDefaults.standard.keyedStoring())
        let permissions = BrowserToolSitePermissions(store: store)
        self.permissions = permissions
        clientToolPermissions = ClientToolPermissionCoordinator(permissions: permissions)
        lastClientToolsConfiguration = clientToolsConfiguration
        featureFlagChanges = featureFlagger.updatesPublisher.sink { [weak self] in
            Task { @MainActor in
                self?.pushClientToolsChangedIfNeeded()
            }
        }
    }

    private func makeTools() -> [any BrowserTool] {
        let scopeProvider: BrowserToolScopeProvider = { [weak self] context in
            self?.scope(for: context)
        }
        let reader = BrowserToolPageContentReader()
        var tools: [any BrowserTool] = [
            ListOpenTabsBrowserTool(scopeProvider: scopeProvider),
            SwitchToTabBrowserTool(scopeProvider: scopeProvider),
            ReadTabContentBrowserTool(scopeProvider: scopeProvider, reader: reader),
            SearchHistoryBrowserTool(historyManager: historyManager, scopeProvider: scopeProvider),
            FindInPageBrowserTool(scopeProvider: scopeProvider, reader: reader)
        ]
        if let bookmarksDatabase {
            tools.append(SearchBookmarksBrowserTool(bookmarksDatabase: bookmarksDatabase) { [weak self] context in
                guard let self, self.configuration.isToolEnabled(named: ClientToolCapability.searchBookmarks.name) else { return nil }
                return self.scope(for: context)
            })
        }
        return tools
    }
}

// MARK: - Configuration

extension AIChatBrowserToolsService {
    var isEnabled: Bool { configuration.isEnabled }

    var clientToolsConfiguration: ClientToolsConfiguration? {
        catalog.clientToolsConfiguration
    }

    func configuration(for source: AIChatUserScript) -> ClientToolsConfiguration? {
        guard admittedScope(for: source) != nil else {
            if isEnabled, !clearing.isEmpty {
                binding(for: source)?.pendingConfigurationRefresh = true
            }
            return nil
        }
        return clientToolsConfiguration
    }

    func canPushConfiguration(from source: AIChatUserScript) -> Bool {
        configurationScope(for: source) != nil
    }

    private func pushClientToolsChangedIfNeeded() {
        let configuration = clientToolsConfiguration
        guard configuration != lastClientToolsConfiguration else { return }
        lastClientToolsConfiguration = configuration
        for binding in bindings.values {
            binding.pendingConfigurationRefresh = true
            pushPendingConfiguration(for: binding)
        }
    }

    private func pushPendingConfiguration(for binding: AIChatBrowserToolsBinding) {
        guard binding.pendingConfigurationRefresh, clearing.isEmpty else { return }
        guard let source = binding.source, canPushConfiguration(from: source) else {
            binding.pendingConfigurationRefresh = false
            return
        }
        if source.pushClientToolsChanged(ClientToolsChangedData(clientTools: clientToolsConfiguration)) {
            binding.pendingConfigurationRefresh = false
        }
    }
}

// MARK: - Source lifecycle

extension AIChatBrowserToolsService {
    func attach(_ source: AIChatUserScript, owner: Tab, presenter: (any AIChatNativePermissionPresenting)? = nil, makeScope: @escaping @MainActor () -> BrowserToolScope?) {
        detach(source)
        bindings[ObjectIdentifier(source)] = AIChatBrowserToolsBinding(source: source, owner: owner, scope: makeScope(), presenter: presenter, makeScope: makeScope)
    }

    func detach(_ source: AIChatUserScript) {
        guard let binding = bindings.removeValue(forKey: ObjectIdentifier(source)), binding.source === source else { return }
        binding.pendingConfigurationRefresh = false
        revoke(binding, document: .awaitingCommit)
        clientToolPermissions.cancelRequests(from: source)
        binding.presenter?.withdrawActive {}
        source.browserToolsService = nil
    }

    func detachSources(ownerTabID: String) {
#if DEBUG || ALPHA
        for session in debugSessions.values.filter({ $0.scope.ownerTabID == ownerTabID }) { session.close() }
#endif
        guard !bindings.isEmpty else { return }
        let sources = bindings.values.filter { $0.ownerTabID == ownerTabID }.compactMap(\.source)
        for source in sources { detach(source) }
    }

    func documentDidCommit(_ source: AIChatUserScript) {
        guard let binding = binding(for: source) else { return }
        binding.pendingConfigurationRefresh = false
        revoke(binding, document: .ready(nil))
        clientToolPermissions.cancelRequests(from: source)
    }

    func documentProcessDidTerminate(_ source: AIChatUserScript) {
        guard let binding = binding(for: source) else { return }
        binding.pendingConfigurationRefresh = false
        revoke(binding, document: .awaitingCommit)
        clientToolPermissions.cancelRequests(from: source)
    }
}

// MARK: - Tool calls and permissions

extension AIChatBrowserToolsService {
    func invoke(_ request: ExecuteClientToolRequest, from source: AIChatUserScript) async -> ExecuteClientToolResponse {
        guard let scope = admittedScope(for: source) else {
            return .failure(callId: request.callId, error: .unavailable)
        }
        if request.capability == .requestAccess,
           let failure = permissionAdmissionFailure(toolName: request.capability.name, from: source) {
            return .failure(callId: request.callId, error: failure.clientToolError)
        }
        let context = BrowserToolCallContext(ownerTabID: scope.ownerTabID, ownerWindowToken: scope.token,
                                             isBurner: scope.isBurner)
        return await invoker.invokeClientTool(request, context: context, permissionPrompter: source)
    }

    private func isPermissionAvailable(toolName: String, requiresRequestAccess: Bool) -> Bool {
        if toolName == ClientToolCapability.requestAccess.name { return catalog.offersRequestAccess }
        return catalog.tool(named: toolName) != nil && (!requiresRequestAccess || catalog.offersRequestAccess)
    }

    private func permissionAdmissionFailure(toolName: String, requiresRequestAccess: Bool = false,
                                            from source: AIChatUserScript) -> AIChatNativePermissionFailure? {
        guard admittedScope(for: source) != nil,
              isPermissionAvailable(toolName: toolName, requiresRequestAccess: requiresRequestAccess) else { return .unavailable }
        return binding(for: source)?.presenter?.isSurfaceAvailable == true ? nil : .cancelled
    }

    func presentPermissionPrompt(_ prompt: ClientToolPermissionPrompt, from source: AIChatUserScript) -> Bool {
        guard permissionAdmissionFailure(toolName: prompt.toolName, requiresRequestAccess: prompt.offersAllowForChat, from: source) == nil,
              let binding = binding(for: source) else { return false }
        return binding.presenter?.present(prompt) { [weak self, weak source, weak binding] decision in
            guard let self, let source, let binding, self.binding(for: source) === binding else { return }
            let failure = self.permissionAdmissionFailure(toolName: prompt.toolName, requiresRequestAccess: prompt.offersAllowForChat, from: source)
            self.clientToolPermissions.respond(to: prompt, decision: failure == nil ? decision : .dismiss, from: source)
        } ?? false
    }

    func withdrawPermissionPrompt(requestID: String, from source: AIChatUserScript) {
        binding(for: source)?.presenter?.withdraw(requestID: requestID) {}
    }

    func sourceWillDisappear(_ source: AIChatUserScript) {
        clientToolPermissions.cancelPendingRequests(from: source)
    }
}

// MARK: - Clearing

extension AIChatBrowserToolsService {
    func beginFireClearing(_ target: AIChatBrowserToolsClearingTarget) -> AIChatBrowserToolsClearingToken? {
        let token = isEnabled ? beginClearing(target) : nil
        clientToolPermissions.revokeChatGrants()
        return token
    }

    func beginClearing(_ target: AIChatBrowserToolsClearingTarget) -> AIChatBrowserToolsClearingToken {
        let token = AIChatBrowserToolsClearingToken(id: UUID())
        let snapshots = bindings.values.compactMap { binding -> AIChatBrowserToolsClearingSnapshot? in
            guard !binding.isBurner, let source = binding.source,
                  target.includes(ownerTabID: binding.ownerTabID,
                                  chatID: source.browserToolsDocumentURL?.duckAIChatID) else { return nil }
            let scope: BrowserToolScope?
            if case .ready(let current) = binding.document { scope = current } else { scope = nil }
            return AIChatBrowserToolsClearingSnapshot(binding: binding, scope: scope, chatID: source.browserToolsDocumentURL?.duckAIChatID)
        }
        clearing[token.id] = AIChatBrowserToolsClearing(target: target, snapshots: snapshots)
#if DEBUG || ALPHA
        for session in Array(debugSessions.values) { session.close() }
#endif
        for snapshot in snapshots { revoke(snapshot.binding, document: renewedDocument(snapshot.binding)) }
        for snapshot in snapshots {
            if let source = snapshot.binding.source { clientToolPermissions.cancelRequests(from: source) }
        }
        return token
    }

    func didClear(_ token: AIChatBrowserToolsClearingToken, target: AIChatBrowserToolsClearingTarget? = nil) {
        guard let operation = clearing[token.id] else { return }
        let affected = target ?? operation.target
        for binding in bindings.values {
            guard !binding.isBurner, let source = binding.source else { continue }
            let chatID = source.browserToolsDocumentURL?.duckAIChatID
            let currentMatches = affected.includes(ownerTabID: binding.ownerTabID, chatID: chatID)
            let capturedMatches = operation.snapshots.contains { snapshot in
                snapshot.binding === binding &&
                affected.includes(ownerTabID: binding.ownerTabID, chatID: snapshot.chatID) &&
                currentScope(binding) === snapshot.scope
            }
            guard currentMatches || capturedMatches else { continue }
            revoke(binding, document: renewedDocument(binding))
            clientToolPermissions.cancelRequests(from: source)
        }
    }

    func endClearing(_ token: AIChatBrowserToolsClearingToken) {
        clearing.removeValue(forKey: token.id)
        for binding in bindings.values { pushPendingConfiguration(for: binding) }
    }
}

// MARK: - Notifications

extension AIChatBrowserToolsService {
    func canPushMetadata(from source: AIChatUserScript) -> Bool {
        admittedScope(for: source) != nil
    }

    func ownerDidNavigate(tabID: String, url: URL?) {
        guard isEnabled else { return }
        for binding in bindings.values where binding.ownerTabID == tabID {
            binding.source?.pushBrowserToolsTabChanged(AIChatTabChangedData(
                tabId: tabID, url: url?.absoluteString, isAttachable: url.map { !AIChatTabMetadata.shouldExcludeFromTabPicker($0) }))
        }
    }
}

// MARK: - Scope resolution

private extension AIChatBrowserToolsService {
    func binding(for source: AIChatUserScript) -> AIChatBrowserToolsBinding? {
        guard let binding = bindings[ObjectIdentifier(source)], binding.source === source else { return nil }
        return binding
    }

    func currentScope(_ binding: AIChatBrowserToolsBinding) -> BrowserToolScope? {
        if case .ready(let scope) = binding.document { return scope }
        return nil
    }

    func renewedDocument(_ binding: AIChatBrowserToolsBinding) -> AIChatBrowserToolsBinding.Document {
        if case .awaitingCommit = binding.document { return .awaitingCommit }
        return .ready(nil)
    }

    func revoke(_ binding: AIChatBrowserToolsBinding, document: AIChatBrowserToolsBinding.Document) {
        currentScope(binding)?.revoke()
        binding.document = document
    }

    func admittedScope(for source: AIChatUserScript) -> BrowserToolScope? {
        guard isEnabled else { return nil }
        return configurationScope(for: source)
    }

    func configurationScope(for source: AIChatUserScript) -> BrowserToolScope? {
        guard let binding = binding(for: source), !binding.isBurner,
              clearing.isEmpty,
              source.browserToolsDocumentURL != nil,
              case .ready(let existing) = binding.document else { return nil }
        if let existing {
            guard existing.ownerTabID == binding.ownerTabID, existing.isBurner == binding.isBurner, existing.isValid else { return nil }
            return existing
        }
        guard let scope = binding.makeScope(), scope.ownerTabID == binding.ownerTabID,
              scope.isBurner == binding.isBurner, scope.isValid else { return nil }
        binding.document = .ready(scope)
        return scope
    }

    func scope(for context: BrowserToolCallContext) -> BrowserToolScope? {
        guard isEnabled, !context.isBurner, clearing.isEmpty else { return nil }
        for binding in bindings.values {
            guard binding.ownerTabID == context.ownerTabID,
                  let existing = currentScope(binding), existing.token == context.ownerWindowToken,
                  let source = binding.source,
                  let scope = admittedScope(for: source), scope.accepts(context) else { continue }
            return scope
        }
#if DEBUG || ALPHA
        for session in debugSessions.values where session.scope.accepts(context) {
            guard debugAdmissionFailure(from: session) == nil else { continue }
            return session.scope
        }
#endif
        return injectedScopeProvider?(context)
    }
}

#if DEBUG || ALPHA
extension AIChatBrowserToolsService {
    func registerDebugSession(_ session: BrowserToolsDebugSession) {
        debugSessions[ObjectIdentifier(session)] = session
    }

    func closeDebugSession(_ session: BrowserToolsDebugSession) {
        debugSessions.removeValue(forKey: ObjectIdentifier(session))
        session.scope.revoke()
        clientToolPermissions.cancelRequests(from: session)
        session.presenter.withdrawActive {}
    }

    private func debugAdmissionFailure(toolName: String? = nil, requiresRequestAccess: Bool = false,
                                       from session: BrowserToolsDebugSession) -> AIChatNativePermissionFailure? {
        guard debugSessions[ObjectIdentifier(session)] === session,
              isEnabled, clearing.isEmpty, session.scope.isValid, session.isNormalMode(),
              toolName.map({ isPermissionAvailable(toolName: $0, requiresRequestAccess: requiresRequestAccess) }) ?? true else { return .unavailable }
        return session.presenter.isSurfaceAvailable ? nil : .cancelled
    }

    func invoke(_ request: ExecuteClientToolRequest, from session: BrowserToolsDebugSession) async -> ExecuteClientToolResponse {
        guard debugAdmissionFailure(toolName: request.capability.name, from: session) == nil else {
            return .failure(callId: request.callId, error: .unavailable)
        }
        let scope = session.scope
        let context = BrowserToolCallContext(ownerTabID: scope.ownerTabID, ownerWindowToken: scope.token, isBurner: scope.isBurner)
        return await invoker.invokeClientTool(request, context: context, permissionPrompter: session)
    }

    func presentPermissionPrompt(_ prompt: ClientToolPermissionPrompt, from session: BrowserToolsDebugSession) -> Bool {
        guard debugAdmissionFailure(toolName: prompt.toolName, requiresRequestAccess: prompt.offersAllowForChat, from: session) == nil else { return false }
        return session.presenter.present(prompt) { [weak self, weak session] decision in
            guard let self, let session else { return }
            let failure = self.debugAdmissionFailure(toolName: prompt.toolName, requiresRequestAccess: prompt.offersAllowForChat, from: session)
            self.clientToolPermissions.respond(to: prompt, decision: failure == nil ? decision : .dismiss, from: session)
        }
    }
}

@MainActor
final class BrowserToolsDebugSession: ClientToolPermissionPrompting {
    let scope: BrowserToolScope
    let presenter: any AIChatNativePermissionPresenting
    let isNormalMode: @MainActor () -> Bool
    private weak var service: AIChatBrowserToolsService?

    init(service: AIChatBrowserToolsService, scope: BrowserToolScope, presenter: any AIChatNativePermissionPresenting,
         isNormalMode: @escaping @MainActor () -> Bool) {
        self.service = service
        self.scope = scope
        self.presenter = presenter
        self.isNormalMode = isNormalMode
        service.registerDebugSession(self)
    }

    func close() {
        service?.closeDebugSession(self)
    }

    func presentClientToolPermissionPrompt(_ prompt: ClientToolPermissionPrompt) -> Bool {
        service?.presentPermissionPrompt(prompt, from: self) ?? false
    }

    func withdrawClientToolPermissionPrompt(requestID: String) {
        presenter.withdraw(requestID: requestID) {}
    }
}
#endif

@MainActor
private final class AIChatBrowserToolsConfiguration: BrowserToolsConfiguration {
    private let feature: ChatToBrowserToolCallingFeatureProviding
    private let featureFlagger: any FeatureFlagger

    init(featureFlagger: any FeatureFlagger) {
        self.featureFlagger = featureFlagger
        self.feature = ChatToBrowserToolCallingFeature(featureFlagger: featureFlagger)
    }

    var isEnabled: Bool { feature.isAvailable }

    var isRequestAccessEnabled: Bool {
        isEnabled && featureFlagger.isFeatureOn(.aiChatBrowserToolRequestAccess)
    }

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
        case .switchToTab:
            .aiChatBrowserToolSwitchToTab
        case .readTabContent:
            .aiChatBrowserToolReadTabContent
        case .searchHistory:
            .aiChatBrowserToolSearchHistory
        case .findInPage:
            .aiChatBrowserToolFindInPage
        case .searchBookmarks:
            .aiChatBrowserToolSearchBookmarks
        case .featureEnabled, .highlightInPage,
             .pinTab, .openTab, .closeTabs, .bookmarkTab, .searchDownloads, .requestAccess:
            nil
        }
    }
}

@MainActor
private final class AIChatBrowserToolsBinding {
    enum Document {
        case ready(BrowserToolScope?)
        case awaitingCommit
    }

    let presenter: (any AIChatNativePermissionPresenting)?
    weak var source: AIChatUserScript?
    let makeScope: @MainActor () -> BrowserToolScope?
    let ownerTabID: String
    let isBurner: Bool
    var document: Document
    var pendingConfigurationRefresh = false

    init(source: AIChatUserScript, owner: Tab, scope: BrowserToolScope?, presenter: (any AIChatNativePermissionPresenting)?, makeScope: @escaping @MainActor () -> BrowserToolScope?) {
        self.source = source
        self.presenter = presenter
        self.makeScope = makeScope
        ownerTabID = owner.uid
        isBurner = owner.mode == .fire
        document = .ready(scope)
    }
}

enum AIChatBrowserToolsClearingTarget {
    case all
    case owner(tabID: String)
    case chats(ids: Set<String>)

    func includes(ownerTabID: String, chatID: String?) -> Bool {
        switch self {
        case .all: return true
        case .owner(let owner): return owner == ownerTabID
        case .chats(let ids): return chatID.map(ids.contains) == true
        }
    }
}

struct AIChatBrowserToolsClearingToken {
    fileprivate let id: UUID
}

private struct AIChatBrowserToolsClearingSnapshot {
    let binding: AIChatBrowserToolsBinding
    let scope: BrowserToolScope?
    let chatID: String?
}

private struct AIChatBrowserToolsClearing {
    let target: AIChatBrowserToolsClearingTarget
    let snapshots: [AIChatBrowserToolsClearingSnapshot]
}

private enum AIChatNativePermissionFailure {
    case unavailable
    case cancelled

    var clientToolError: ClientToolError {
        switch self {
        case .unavailable: .unavailable
        case .cancelled: .cancelled
        }
    }

    var browserToolFailure: BrowserToolFailure {
        switch self {
        case .unavailable: .unavailable
        case .cancelled: .cancelled
        }
    }
}

@MainActor
private final class AIChatNativePermissionCoordinator: ClientToolPermissionCoordinating {
    typealias Admission = @MainActor (String, Bool, (any ClientToolPermissionPrompting)?) -> AIChatNativePermissionFailure?

    private let base: ClientToolPermissionCoordinator
    private let admission: Admission

    init(base: ClientToolPermissionCoordinator, admission: @escaping Admission) {
        self.base = base
        self.admission = admission
    }

    func authorize(callID: String, tool: any BrowserTool, targetsOtherTab: Bool, target: String?, chatID: String?, accessToolNames: [String]?,
                   prompter: (any ClientToolPermissionPrompting)?) async -> ClientToolPermissionAuthorization {
        let requiresRequestAccess = chatID != nil && !tool.asksEveryTime
        if let failure = admission(tool.name, requiresRequestAccess, prompter) {
            return .refused(failure.clientToolError, .beforePermission, answer: nil)
        }
        let authorization = await base.authorize(callID: callID, tool: tool, targetsOtherTab: targetsOtherTab,
                                                 target: target, chatID: chatID, accessToolNames: accessToolNames, prompter: prompter)
        guard case .granted(let permissionPath, let performExecution) = authorization else { return authorization }
        let requiresPrompter = prompter != nil
        let toolName = tool.name
        return .granted(permissionPath, performExecution: { [weak prompter, admission] operation in
            await performExecution { [weak prompter] in
                guard !Task.isCancelled, !requiresPrompter || prompter != nil else { return .failure(.cancelled) }
                if let failure = admission(toolName, requiresRequestAccess, prompter) { return .failure(failure.browserToolFailure) }
                return await operation()
            }
        })
    }

    func state(for tool: any BrowserTool, chatID: String?) -> BrowserToolPermissionState {
        base.state(for: tool, chatID: chatID)
    }

    func accessLevel(for tool: any BrowserTool, chatID: String) -> BrowserToolAccessLevel? {
        base.accessLevel(for: tool, chatID: chatID)
    }
}
