//
//  SitePermissionsCoordinator.swift
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

import Foundation

public struct SitePermissionRequestContext: Equatable, Sendable {

    public let tabID: String
    public let topLevelSite: SitePermissionKey
    public let requestingFrameID: UInt64
    public let webContentProcessGeneration: UInt
    public let navigationGeneration: UInt

    public init(tabID: String,
                topLevelSite: SitePermissionKey,
                requestingFrameID: UInt64,
                webContentProcessGeneration: UInt,
                navigationGeneration: UInt) {
        self.tabID = tabID
        self.topLevelSite = topLevelSite
        self.requestingFrameID = requestingFrameID
        self.webContentProcessGeneration = webContentProcessGeneration
        self.navigationGeneration = navigationGeneration
    }
}

public struct SitePermissionRequest: Sendable {

    public let context: SitePermissionRequestContext
    public let permissionTypes: Set<SitePermissionType>
    public let bypassesModel: Bool

    public init(context: SitePermissionRequestContext,
                permissionTypes: Set<SitePermissionType>,
                bypassesModel: Bool = false) {
        self.context = context
        self.permissionTypes = permissionTypes
        self.bypassesModel = bypassesModel
    }
}

public struct SitePermissionPrompt: Equatable, Sendable {

    public let site: SitePermissionKey
    public let permissionTypes: Set<SitePermissionType>
}

public enum SitePermissionPromptDecision: Equatable, Sendable {
    case allowOnce
    case allowWhileUsingSite
    case denyOnce
    case neverAllow
}

public struct SitePermissionSystemBlock: Equatable, Sendable {

    public enum Timing: Equatable, Sendable {
        case preexisting
        case afterRequest
    }

    public let permissionType: SitePermissionType
    public let state: SystemPermissionAuthorizationState
    public let timing: Timing
}

public enum SitePermissionResolution: Equatable, Sendable {
    case bypass
    case grant
    case deny(systemBlocks: [SitePermissionSystemBlock])
}

public enum SitePermissionPageChange: Equatable, Sendable {
    case sameDocumentNavigation
    case reload
    case navigation
    case webContentProcessReplacement
}

@MainActor
public final class SitePermissionsCoordinator {

    public typealias CurrentContextProvider = (_ tabID: String, _ requestingFrameID: UInt64) -> SitePermissionRequestContext?
    public typealias PromptHandler = (SitePermissionPrompt, @escaping (SitePermissionPromptDecision) -> Void) -> Void
    public typealias Completion = (SitePermissionResolution) -> Void

    typealias AuthorizationStateProvider = (SitePermissionType) -> SystemPermissionAuthorizationState
    typealias AuthorizationRequester = (SitePermissionType) async -> SystemPermissionAuthorizationState

    private enum RequestDisposition {
        case deny
        case allow
        case prompt
    }

    private final class PendingRequest {
        let request: SitePermissionRequest
        let lifecycleGeneration: UInt
        let promptHandler: PromptHandler
        let completion: Completion

        init(request: SitePermissionRequest,
             lifecycleGeneration: UInt,
             promptHandler: @escaping PromptHandler,
             completion: @escaping Completion) {
            self.request = request
            self.lifecycleGeneration = lifecycleGeneration
            self.promptHandler = promptHandler
            self.completion = completion
        }
    }

    private let store: SitePermissionsStore
    private let isFireMode: Bool
    private let currentContext: CurrentContextProvider
    private let authorizationState: AuthorizationStateProvider
    private let requestAuthorization: AuthorizationRequester

    private var allowOnce = Set<SitePermissionType>()
    private var deniedForPage = Set<SitePermissionType>()
    private var queuedRequests = [PendingRequest]()
    private var activeRequest: PendingRequest?
    private var lifecycleGeneration: UInt = 0
    private var isClosed = false

    public convenience init(store: SitePermissionsStore,
                            systemPermissionClient: SystemPermissionClient,
                            isFireMode: Bool,
                            currentContext: @escaping CurrentContextProvider) {
        self.init(store: store,
                  isFireMode: isFireMode,
                  currentContext: currentContext,
                  authorizationState: systemPermissionClient.authorizationState,
                  requestAuthorization: systemPermissionClient.requestAuthorization)
    }

    init(store: SitePermissionsStore,
         isFireMode: Bool,
         currentContext: @escaping CurrentContextProvider,
         authorizationState: @escaping AuthorizationStateProvider,
         requestAuthorization: @escaping AuthorizationRequester) {
        self.store = store
        self.isFireMode = isFireMode
        self.currentContext = currentContext
        self.authorizationState = authorizationState
        self.requestAuthorization = requestAuthorization
    }

    public func request(_ request: SitePermissionRequest,
                        promptHandler: @escaping PromptHandler,
                        completion: @escaping Completion) {
        guard !isClosed, !request.permissionTypes.isEmpty else { return }

        if request.bypassesModel {
            completion(.bypass)
            return
        }

        guard isValid(request.context, lifecycleGeneration: lifecycleGeneration) else { return }

        switch disposition(for: request) {
        case .deny:
            completion(.deny(systemBlocks: []))
        case .allow:
            completion(systemResolution(for: request.permissionTypes))
        case .prompt:
            enqueue(request, promptHandler: promptHandler, completion: completion)
        }
    }

    private func disposition(for request: SitePermissionRequest) -> RequestDisposition {
        var hasDeniedPermission = false
        var hasUnresolvedPermission = false
        for permissionType in ordered(request.permissionTypes) {
            switch store.decision(for: permissionType, at: request.context.topLevelSite) {
            case .deny:
                hasDeniedPermission = true
            case .allow:
                continue
            case .ask, .none:
                if deniedForPage.contains(permissionType) {
                    hasDeniedPermission = true
                } else if allowOnce.contains(permissionType) {
                    continue
                } else if store.globalDefault(for: permissionType) == .deny {
                    hasDeniedPermission = true
                } else {
                    hasUnresolvedPermission = true
                }
            }
        }

        if hasDeniedPermission {
            return .deny
        } else if hasUnresolvedPermission {
            return .prompt
        } else {
            return .allow
        }
    }

    public func captureDidEnd(_ permissionTypes: Set<SitePermissionType>) {
        allowOnce.subtract(permissionTypes)
    }

    public func pageDidChange(_ change: SitePermissionPageChange) {
        guard change != .sameDocumentNavigation else { return }
        resetPageState()
    }

    public func close() {
        isClosed = true
        resetPageState()
    }

    private func systemResolution(for permissionTypes: Set<SitePermissionType>) -> SitePermissionResolution {
        let blocks = ordered(permissionTypes).compactMap { permissionType -> SitePermissionSystemBlock? in
            let state = authorizationState(permissionType)
            guard state != .authorized else { return nil }
            return SitePermissionSystemBlock(permissionType: permissionType, state: state, timing: .preexisting)
        }
        return blocks.isEmpty ? .grant : .deny(systemBlocks: blocks)
    }

    private func enqueue(_ request: SitePermissionRequest,
                         promptHandler: @escaping PromptHandler,
                         completion: @escaping Completion) {
        queuedRequests.append(PendingRequest(request: request,
                                             lifecycleGeneration: lifecycleGeneration,
                                             promptHandler: promptHandler,
                                             completion: completion))
        processNextRequestIfNeeded()
    }

    private func processNextRequestIfNeeded() {
        guard activeRequest == nil else { return }

        while !queuedRequests.isEmpty {
            let pendingRequest = queuedRequests.removeFirst()
            guard isValid(pendingRequest) else { continue }

            activeRequest = pendingRequest
            switch disposition(for: pendingRequest.request) {
            case .deny:
                finish(pendingRequest, with: .deny(systemBlocks: []))
            case .allow:
                finish(pendingRequest, with: systemResolution(for: pendingRequest.request.permissionTypes))
            case .prompt:
                let prompt = SitePermissionPrompt(site: pendingRequest.request.context.topLevelSite,
                                                  permissionTypes: pendingRequest.request.permissionTypes)
                pendingRequest.promptHandler(prompt) { [weak self, weak pendingRequest] decision in
                    guard let self, let pendingRequest else { return }
                    self.handle(decision, for: pendingRequest)
                }
            }
            return
        }
    }

    private func handle(_ decision: SitePermissionPromptDecision, for pendingRequest: PendingRequest) {
        guard isActiveAndValid(pendingRequest) else {
            drop(pendingRequest)
            return
        }

        let permissionTypes = pendingRequest.request.permissionTypes
        switch decision {
        case .denyOnce:
            allowOnce.subtract(permissionTypes)
            deniedForPage.formUnion(permissionTypes)
            finish(pendingRequest, with: .deny(systemBlocks: []))
        case .neverAllow:
            allowOnce.subtract(permissionTypes)
            if isFireMode {
                deniedForPage.formUnion(permissionTypes)
            } else {
                persist(.deny, for: pendingRequest.request)
            }
            finish(pendingRequest, with: .deny(systemBlocks: []))
        case .allowOnce, .allowWhileUsingSite:
            deniedForPage.subtract(permissionTypes)
            if decision == .allowWhileUsingSite, !isFireMode {
                persist(.allow, for: pendingRequest.request)
            }
            requestSystemAuthorization(for: pendingRequest,
                                       activatesAllowOnce: decision == .allowOnce || isFireMode)
        }
    }

    private func requestSystemAuthorization(for pendingRequest: PendingRequest, activatesAllowOnce: Bool) {
        Task { @MainActor [weak self, weak pendingRequest] in
            guard let self, let pendingRequest else { return }

            var blocks = [SitePermissionSystemBlock]()
            for permissionType in ordered(pendingRequest.request.permissionTypes) {
                guard isActiveAndValid(pendingRequest) else {
                    drop(pendingRequest)
                    return
                }

                let state = authorizationState(permissionType)
                if state == .authorized {
                    continue
                }
                if state != .notDetermined {
                    blocks.append(SitePermissionSystemBlock(permissionType: permissionType,
                                                            state: state,
                                                            timing: .preexisting))
                    continue
                }

                let requestedState = await requestAuthorization(permissionType)
                guard isActiveAndValid(pendingRequest) else {
                    drop(pendingRequest)
                    return
                }
                if requestedState != .authorized {
                    blocks.append(SitePermissionSystemBlock(permissionType: permissionType,
                                                            state: requestedState,
                                                            timing: .afterRequest))
                }
            }

            if blocks.isEmpty {
                if activatesAllowOnce {
                    allowOnce.formUnion(pendingRequest.request.permissionTypes)
                }
                finish(pendingRequest, with: .grant)
            } else {
                finish(pendingRequest, with: .deny(systemBlocks: blocks))
            }
        }
    }

    private func persist(_ decision: SitePermissionDecision, for request: SitePermissionRequest) {
        for permissionType in ordered(request.permissionTypes) {
            store.setPersistentDecision(decision, for: permissionType, at: request.context.topLevelSite)
        }
    }

    private func finish(_ pendingRequest: PendingRequest, with resolution: SitePermissionResolution) {
        guard activeRequest === pendingRequest else { return }
        activeRequest = nil
        pendingRequest.completion(resolution)
        processNextRequestIfNeeded()
    }

    private func drop(_ pendingRequest: PendingRequest) {
        guard activeRequest === pendingRequest else { return }
        activeRequest = nil
        processNextRequestIfNeeded()
    }

    private func resetPageState() {
        lifecycleGeneration &+= 1
        allowOnce.removeAll()
        deniedForPage.removeAll()
        queuedRequests.removeAll()
        activeRequest = nil
    }

    private func isActiveAndValid(_ pendingRequest: PendingRequest) -> Bool {
        activeRequest === pendingRequest && isValid(pendingRequest)
    }

    private func isValid(_ pendingRequest: PendingRequest) -> Bool {
        isValid(pendingRequest.request.context, lifecycleGeneration: pendingRequest.lifecycleGeneration)
    }

    private func isValid(_ context: SitePermissionRequestContext, lifecycleGeneration: UInt) -> Bool {
        !isClosed && self.lifecycleGeneration == lifecycleGeneration && currentContext(context.tabID, context.requestingFrameID) == context
    }

    private func ordered(_ permissionTypes: Set<SitePermissionType>) -> [SitePermissionType] {
        SitePermissionType.allCases.filter(permissionTypes.contains)
    }
}
