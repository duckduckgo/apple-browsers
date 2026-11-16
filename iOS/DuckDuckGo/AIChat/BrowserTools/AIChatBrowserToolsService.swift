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
import FeatureFlags_iOS
import Foundation
import Persistence
import PrivacyConfig

@MainActor
final class AIChatBrowserToolsService {
    private var lastClientToolsConfiguration: ClientToolsConfiguration?
    private var featureFlagChanges: AnyCancellable?
    private var bindings: [ObjectIdentifier: AIChatBrowserToolsBinding] = [:]
    private var clearing: [UUID: AIChatBrowserToolsClearing] = [:]
    private let injectedScopeProvider: BrowserToolScopeProvider?
    private(set) lazy var catalog = BrowserToolCatalog(
        tools: makeTools(),
        configuration: configuration, capabilities: supportedCapabilities)
    private(set) lazy var invoker = BrowserToolInvoker(
        catalog: catalog,
        clientToolPermissions: AIChatNativePermissionCoordinator(base: clientToolPermissions) { [weak self] toolName, prompter in
            guard let source = prompter as? AIChatUserScript else { return nil }
            guard let self else { return .unavailable }
            return self.permissionAdmissionFailure(toolName: toolName, from: source)
        })
    let permissions: BrowserToolPermissionStoring
    let clientToolPermissions: ClientToolPermissionCoordinator
    private let configuration: AIChatBrowserToolsConfiguration

    private var supportedCapabilities: [ClientToolCapability] = [
        .listOpenTabs,
        .switchToTab
    ]

    init(featureFlagger: any FeatureFlagger,
         scopeProvider: BrowserToolScopeProvider? = nil,
         permissionStorage: any KeyedStoring<BrowserToolPermissionStorageKeys> = UserDefaults.standard.keyedStoring(),
         capabilities: [ClientToolCapability]? = nil) {
        configuration = AIChatBrowserToolsConfiguration(featureFlagger: featureFlagger)
        injectedScopeProvider = scopeProvider
        if let capabilities {
            self.supportedCapabilities = capabilities
        }
        let permissions = BrowserToolPermissionStore(storage: permissionStorage)
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
        return [
            ListOpenTabsBrowserTool(scopeProvider: scopeProvider),
            SwitchToTabBrowserTool(scopeProvider: scopeProvider)
        ]
    }
}

// MARK: - Configuration

extension AIChatBrowserToolsService {
    var isEnabled: Bool { configuration.isEnabled }

    var clientToolsConfiguration: ClientToolsConfiguration? {
        let capabilities = catalog.enabledClientToolCapabilities
        guard !capabilities.isEmpty,
              let configuration = try? ClientToolsConfiguration(capabilities: capabilities),
              ClientToolPayloadLimits.fits(configuration, within: ClientToolPayloadLimits.configBytes) else { return nil }
        return configuration
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
        let context = BrowserToolCallContext(ownerTabID: scope.ownerTabID, ownerWindowToken: scope.token,
                                             isBurner: scope.isBurner)
        return await invoker.invokeClientTool(request, context: context, permissionPrompter: source)
    }

    private func permissionAdmissionFailure(toolName: String, requestID: String? = nil, from source: AIChatUserScript) -> AIChatNativePermissionFailure? {
        guard admittedScope(for: source) != nil, catalog.tool(named: toolName) != nil else { return .unavailable }
        return binding(for: source)?.presenter?.isAvailable(for: requestID) == true ? nil : .cancelled
    }

    func presentPermissionPrompt(_ prompt: ClientToolPermissionPrompt, from source: AIChatUserScript) -> Bool {
        guard permissionAdmissionFailure(toolName: prompt.toolName, requestID: prompt.requestID, from: source) == nil,
              let binding = binding(for: source), let tool = catalog.tool(named: prompt.toolName) else { return false }
        return binding.presenter?.present(prompt, message: tool.permissionReason) { [weak self, weak source, weak binding] decision in
            guard let self, let source, let binding, self.binding(for: source) === binding else { return }
            let response = self.permissionAdmissionFailure(toolName: prompt.toolName, requestID: prompt.requestID, from: source) == nil ? decision : .dismiss
            self.clientToolPermissions.respond(to: prompt, decision: response, from: source)
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
        return injectedScopeProvider?(context)
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
        case .switchToTab:
            .aiChatBrowserToolSwitchToTab
        case .featureEnabled, .searchHistory, .readTabContent, .findInPage, .highlightInPage:
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
    typealias Admission = @MainActor (String, (any ClientToolPermissionPrompting)?) -> AIChatNativePermissionFailure?

    private let base: ClientToolPermissionCoordinator
    private let admission: Admission

    init(base: ClientToolPermissionCoordinator, admission: @escaping Admission) {
        self.base = base
        self.admission = admission
    }

    func authorize(callID: String, tool: any BrowserTool, prompter: (any ClientToolPermissionPrompting)?) async -> ClientToolPermissionAuthorization {
        if let failure = admission(tool.name, prompter) { return .refused(failure.clientToolError) }
        let authorization = await base.authorize(callID: callID, tool: tool, prompter: prompter)
        guard case .granted(let performExecution) = authorization else { return authorization }
        let requiresPrompter = prompter != nil
        let toolName = tool.name
        return .granted(performExecution: { [weak prompter, admission] operation in
            await performExecution { [weak prompter] in
                guard !Task.isCancelled, !requiresPrompter || prompter != nil else { return .failure(.cancelled) }
                if let failure = admission(toolName, prompter) { return .failure(failure.browserToolFailure) }
                return await operation()
            }
        })
    }
}
