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

import Combine
import Foundation
import WebKit

/// Identifies the page and frame that originated a site permission request.
/// The coordinator uses this context to discard stale requests after navigation or process replacement.
public struct SitePermissionRequestContext: Equatable, Sendable {

    public let tabID: String
    /// The committed top-level site whose permission decision applies to the request.
    public let topLevelSite: SitePermissionKey
    /// Identifies the web frame that initiated the permission request.
    public let requestingFrameID: UInt64
    /// A counter that changes whenever WebKit replaces the tab's web content process.
    public let webContentProcessGeneration: UInt
    /// A counter that changes whenever the tab starts a new main-frame navigation.
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

    public init(context: SitePermissionRequestContext,
                permissionTypes: Set<SitePermissionType>) {
        self.context = context
        self.permissionTypes = permissionTypes
    }
}

public struct SitePermissionPrompt: Equatable, Sendable {

    public let site: SitePermissionKey
    public let permissionTypes: Set<SitePermissionType>
}

/// The user's response to an on-site permission prompt.
public enum SitePermissionPromptDecision: Equatable, Sendable {
    /// Allows access until capture ends without storing a persistent site decision.
    case allowOnce
    /// Grants access and stores an Allow decision for the site outside Fire mode.
    case allowWhileUsingSite
    /// Denies access for the current page without storing a persistent site decision.
    case denyOnce
    /// Denies access and stores a Deny decision for the site outside Fire mode.
    case neverAllow
}

/// Describes a system authorization state that prevented a site permission request from being granted.
public struct SitePermissionSystemBlock: Equatable, Sendable {

    /// Indicates when the blocking state was observed relative to a system authorization request.
    public enum Timing: Equatable, Sendable {
        /// The blocking state existed before the coordinator could request authorization.
        case preexisting
        /// The blocking state was observed after the coordinator requested authorization.
        case afterRequest
    }

    public let permissionType: SitePermissionType
    public let state: SystemPermissionAuthorizationState
    public let timing: Timing
}

/// The result of evaluating site-level decisions and system authorization for a permission request.
public enum SitePermissionResolution: Equatable, Sendable {
    case grant
    /// Denies access. An empty array means that a site-level decision blocked the request.
    case deny(systemBlocks: [SitePermissionSystemBlock])
}

public enum SitePermissionRecovery: Equatable, Sendable {
    case toast(permissionTypes: Set<SitePermissionType>)
    case reminder(permissionTypes: Set<SitePermissionType>)
}

/// Describes a page lifecycle change that can invalidate page-scoped permission state.
public enum SitePermissionPageChange: Equatable, Sendable {
    case sameDocumentNavigation
    case reload
    case navigation
    case webContentProcessReplacement
}

/// Coordinates a tab's site permission requests for camera, microphone, and location.
/// It combines stored and page-scoped decisions with system authorization, serializes prompts, and discards stale requests.
@MainActor
public final class SitePermissionsCoordinator {

    /// Returns the current context for a tab and requesting frame so the coordinator can reject stale requests.
    public typealias CurrentContextProvider = (_ tabID: String, _ requestingFrameID: UInt64) -> SitePermissionRequestContext?
    public typealias PromptHandler = (SitePermissionPrompt, @escaping (SitePermissionPromptDecision) -> Void) -> Void
    /// The handler must call its completion after the recovery surface is dismissed so the FIFO can continue.
    public typealias RecoveryHandler = (SitePermissionRecovery, @escaping () -> Void) -> Void
    public typealias EventHandler = (SitePermissionsEvent) -> Void
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
        let promptHandler: PromptHandler
        let completion: Completion

        init(request: SitePermissionRequest,
             promptHandler: @escaping PromptHandler,
             completion: @escaping Completion) {
            self.request = request
            self.promptHandler = promptHandler
            self.completion = completion
        }
    }

    private let store: SitePermissionsStore
    private let isFireMode: Bool
    private let currentContext: CurrentContextProvider
    private let authorizationState: AuthorizationStateProvider
    private let requestAuthorization: AuthorizationRequester
    private let recoveryHandler: RecoveryHandler
    private let eventHandler: EventHandler

    private var allowOnce = Set<SitePermissionType>()
    private var deniedForPage = Set<SitePermissionType>()
    private var queuedRequests = [PendingRequest]()
    private var activeRequest: PendingRequest?
    private var isClosed = false
    private var cameraCaptureObservation: NSKeyValueObservation?
    private var microphoneCaptureObservation: NSKeyValueObservation?
    private var mediaCaptureObservationGeneration: UInt = 0

    @Published public private(set) var captureStates = [SitePermissionType: SitePermissionCaptureState]()

    public convenience init(store: SitePermissionsStore,
                            systemPermissionClient: SystemPermissionClient,
                            isFireMode: Bool,
                            currentContext: @escaping CurrentContextProvider,
                            recoveryHandler: @escaping RecoveryHandler,
                            eventHandler: @escaping EventHandler = { _ in }) {
        self.init(store: store,
                  isFireMode: isFireMode,
                  currentContext: currentContext,
                  authorizationState: systemPermissionClient.authorizationState,
                  requestAuthorization: systemPermissionClient.requestAuthorization,
                  recoveryHandler: recoveryHandler,
                  eventHandler: eventHandler)
    }

    init(store: SitePermissionsStore,
         isFireMode: Bool,
         currentContext: @escaping CurrentContextProvider,
         authorizationState: @escaping AuthorizationStateProvider,
         requestAuthorization: @escaping AuthorizationRequester,
         recoveryHandler: @escaping RecoveryHandler,
         eventHandler: @escaping EventHandler = { _ in }) {
        self.store = store
        self.isFireMode = isFireMode
        self.currentContext = currentContext
        self.authorizationState = authorizationState
        self.requestAuthorization = requestAuthorization
        self.recoveryHandler = recoveryHandler
        self.eventHandler = eventHandler
    }

    public func request(_ request: SitePermissionRequest,
                        promptHandler: @escaping PromptHandler,
                        completion: @escaping Completion) {
        guard !isClosed, !request.permissionTypes.isEmpty else { return }
        guard isValid(request.context) else { return }

        switch disposition(for: request) {
        case .deny:
            completion(.deny(systemBlocks: []))
        case .allow, .prompt:
            enqueue(request, promptHandler: promptHandler, completion: completion)
        }
    }

    private func disposition(for request: SitePermissionRequest) -> RequestDisposition {
        var disposition = RequestDisposition.allow
        for permissionType in ordered(request.permissionTypes) {
            switch store.decision(for: permissionType, at: request.context.topLevelSite) {
            case .deny:
                return .deny
            case .allow:
                continue
            case .ask, .none:
                if deniedForPage.contains(permissionType) {
                    return .deny
                }
                if allowOnce.contains(permissionType) {
                    continue
                }
                if store.globalDefault(for: permissionType) == .deny {
                    return .deny
                }
                disposition = .prompt
            }
        }
        return disposition
    }

    public func captureDidEnd(_ permissionTypes: Set<SitePermissionType>) {
        allowOnce.subtract(permissionTypes)
    }

    public func captureState(for permissionType: SitePermissionType) -> SitePermissionCaptureState {
        captureStates[permissionType] ?? .inactive
    }

    public func observeMediaCapture(in webView: WKWebView) {
        invalidateMediaCaptureObservations()
        guard !isClosed else { return }
        let observationGeneration = mediaCaptureObservationGeneration

        cameraCaptureObservation = webView.observe(\.cameraCaptureState, options: [.initial, .new]) { [weak self] webView, _ in
            let state = webView.sitePermissionCameraCaptureState
            MainActor.assumeIsolated {
                guard self?.mediaCaptureObservationGeneration == observationGeneration else { return }
                self?.updateCaptureState(state, for: .camera)
            }
        }
        microphoneCaptureObservation = webView.observe(\.microphoneCaptureState, options: [.initial, .new]) { [weak self] webView, _ in
            let state = webView.sitePermissionMicrophoneCaptureState
            MainActor.assumeIsolated {
                guard self?.mediaCaptureObservationGeneration == observationGeneration else { return }
                self?.updateCaptureState(state, for: .microphone)
            }
        }
    }

    public func pageDidChange(_ change: SitePermissionPageChange) {
        guard change != .sameDocumentNavigation else { return }
        resetPageState()
    }

    public func close() {
        isClosed = true
        invalidateMediaCaptureObservations()
        captureStates.removeAll()
        resetPageState()
    }

    private func updateCaptureState(_ state: SitePermissionCaptureState, for permissionType: SitePermissionType) {
        guard !isClosed else { return }
        let previousState = captureState(for: permissionType)
        guard previousState != state else { return }

        if state == .inactive {
            captureStates[permissionType] = nil
            captureDidEnd([permissionType])
        } else {
            captureStates[permissionType] = state
        }
    }

    private func invalidateMediaCaptureObservations() {
        mediaCaptureObservationGeneration &+= 1
        cameraCaptureObservation?.invalidate()
        cameraCaptureObservation = nil
        microphoneCaptureObservation?.invalidate()
        microphoneCaptureObservation = nil
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
            guard isActiveAndValid(pendingRequest) else {
                drop(pendingRequest)
                return
            }

            let permissionStates = ordered(pendingRequest.request.permissionTypes).map { permissionType in
                (permissionType, self.authorizationState(permissionType))
            }
            let preexistingBlocks = permissionStates.compactMap { permissionType, state in
                self.preexistingSystemBlock(for: permissionType, state: state)
            }
            if !preexistingBlocks.isEmpty {
                finish(pendingRequest, with: .deny(systemBlocks: preexistingBlocks))
                return
            }

            var blocks = [SitePermissionSystemBlock]()
            for (permissionType, state) in permissionStates where state == .notDetermined {
                guard isActiveAndValid(pendingRequest) else {
                    drop(pendingRequest)
                    return
                }

                let requestedState = await requestAuthorization(permissionType)
                eventHandler(.permissionSystemPromptResult(
                    type: permissionType,
                    result: requestedState == .authorized ? .granted : .denied
                ))
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

    private func preexistingSystemBlock(for permissionType: SitePermissionType,
                                        state: SystemPermissionAuthorizationState) -> SitePermissionSystemBlock? {
        switch state {
        case .denied, .restricted, .unavailable:
            return SitePermissionSystemBlock(permissionType: permissionType, state: state, timing: .preexisting)
        case .notDetermined, .authorized:
            return nil
        }
    }

    private func persist(_ decision: SitePermissionDecision, for request: SitePermissionRequest) {
        for permissionType in ordered(request.permissionTypes) {
            store.setPersistentDecision(decision, for: permissionType, at: request.context.topLevelSite)
        }
    }

    private func finish(_ pendingRequest: PendingRequest, with resolution: SitePermissionResolution) {
        guard activeRequest === pendingRequest else { return }

        if case .deny(let systemBlocks) = resolution,
           let recovery = recovery(for: systemBlocks) {
            pendingRequest.completion(resolution)
            // Completion releases the bridge context; page resets invalidate the active request.
            guard activeRequest === pendingRequest else { return }

            recoveryHandler(recovery) { [weak self, weak pendingRequest] in
                guard let self, let pendingRequest else { return }
                finishRecovery(for: pendingRequest)
            }
            return
        }

        activeRequest = nil
        pendingRequest.completion(resolution)
        processNextRequestIfNeeded()
    }

    private func finishRecovery(for pendingRequest: PendingRequest) {
        guard activeRequest === pendingRequest else { return }
        activeRequest = nil
        processNextRequestIfNeeded()
    }

    private func recovery(for systemBlocks: [SitePermissionSystemBlock]) -> SitePermissionRecovery? {
        let preexistingPermissionTypes = Set(systemBlocks.compactMap { block -> SitePermissionType? in
            guard block.timing == .preexisting else { return nil }
            switch block.state {
            case .denied, .restricted, .unavailable:
                return block.permissionType
            case .notDetermined, .authorized:
                return nil
            }
        })
        if !preexistingPermissionTypes.isEmpty {
            return .reminder(permissionTypes: preexistingPermissionTypes)
        }

        let freshlyDeniedPermissionTypes = Set(systemBlocks.compactMap { block in
            block.timing == .afterRequest ? block.permissionType : nil
        })
        return freshlyDeniedPermissionTypes.isEmpty ? nil : .toast(permissionTypes: freshlyDeniedPermissionTypes)
    }

    private func drop(_ pendingRequest: PendingRequest) {
        guard activeRequest === pendingRequest else { return }
        activeRequest = nil
        processNextRequestIfNeeded()
    }

    private func resetPageState() {
        allowOnce.removeAll()
        deniedForPage.removeAll()
        queuedRequests.removeAll()
        activeRequest = nil
    }

    private func isActiveAndValid(_ pendingRequest: PendingRequest) -> Bool {
        activeRequest === pendingRequest && isValid(pendingRequest)
    }

    private func isValid(_ pendingRequest: PendingRequest) -> Bool {
        isValid(pendingRequest.request.context)
    }

    private func isValid(_ context: SitePermissionRequestContext) -> Bool {
        !isClosed && currentContext(context.tabID, context.requestingFrameID) == context
    }

    private func ordered(_ permissionTypes: Set<SitePermissionType>) -> [SitePermissionType] {
        SitePermissionType.allCases.filter(permissionTypes.contains)
    }
}
