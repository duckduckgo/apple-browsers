//
//  PermissionAuthorizationViewModel.swift
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

import AppKit
import Combine
import Common
import ConcurrencyExtensions
import Foundation
import PixelKit
import os.log

@MainActor
final class PermissionAuthorizationViewModel: ObservableObject {
    enum Constants {
        /// How long "Waiting for request…" stays before the prompt offers System Settings instead.
        static let systemPermissionRequestTimeout: TimeInterval = 10
    }

    typealias ScheduleAfter = (_ delay: TimeInterval, _ work: @escaping @MainActor () -> Void) -> Void

    @Published
    private(set) var viewState: PermissionAuthorizationViewState

    private weak var query: PermissionAuthorizationQuery?
    private let domain: String
    private let permissions: [PermissionType]
    private let permissionType: PermissionAuthorizationType
    private let systemPermissionManager: SystemPermissionManagerProtocol
    private let appDidBecomeActivePublisher: AnyPublisher<Void, Never>
    private let scheduleAfter: ScheduleAfter
    private let pixelFiring: PixelFiring?
    private let openURL: (URL) -> Void
    private let openSystemSettingsURL: (URL) -> Void
    /// Set by whichever presenter currently shows this view model, so a cached flow closes the popover on screen.
    var finish: () -> Void

    /// The allow choice held back until macOS grants its own permission.
    /// Submitting it earlier would let macOS show its prompt before the user asks for it.
    private var pendingDecision: PermissionPromptDecision?
    private var currentSystemPermission: PermissionType?
    /// What one click on Request Permission asks macOS for: each alert shows right after the previous one is granted.
    private var systemPermissionsToRequest: [PermissionType] = []
    /// A timeout changes the button, but the same click can still authorize the remaining devices.
    private var isRequestingSystemPermissions = false

    private var systemPermissions: [PermissionType] {
        permissions.filter(\.requiresSystemPermission)
    }
    /// The site is already set to Always allow and only the macOS permission is missing,
    /// so granting it isn't a new decision to report.
    private var isResumingStoredDecision = false
    private var systemAuthorizationCancellable: AnyCancellable?
    private var appDidBecomeActiveCancellable: AnyCancellable?
    /// Tells a timeout apart from one scheduled for an earlier request.
    private var systemPermissionRequestCount = 0
    /// Invalidates status snapshots when a newer refresh or a system permission transition supersedes them.
    private var systemPermissionRefreshGeneration = 0

    init(
        initialState: PermissionAuthorizationViewState? = .init(),
        query: PermissionAuthorizationQuery,
        systemPermissionManager: SystemPermissionManagerProtocol,
        appDidBecomeActivePublisher: AnyPublisher<Void, Never> = NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)
            .map { _ in }
            .eraseToAnyPublisher(),
        scheduleAfter: @escaping ScheduleAfter = { delay, work in
            Task { @MainActor in
                try? await Task.sleep(interval: delay)
                work()
            }
        },
        pixelFiring: PixelFiring? = PixelKit.shared,
        openURL: @escaping (URL) -> Void,
        openSystemSettingsURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
        finish: @escaping () -> Void
    ) {
        viewState = initialState ?? .init()
        self.query = query
        self.domain = query.domain.permissionDisplayName
        self.permissions = query.permissions
        self.permissionType = PermissionAuthorizationType(from: query.permissions)
        self.systemPermissionManager = systemPermissionManager
        self.appDidBecomeActivePublisher = appDidBecomeActivePublisher
        self.scheduleAfter = scheduleAfter
        self.pixelFiring = pixelFiring
        self.openURL = openURL
        self.openSystemSettingsURL = openSystemSettingsURL
        self.finish = finish
    }

    // MARK: - Public

    func send(action: Action) {
        switch action {
        case .onAppear:
            onAppear()

        case .allowThisVisit:
            allow(.allowThisVisit)

        case .alwaysAllow:
            allow(.alwaysAllow)

        case .neverAllow:
            submit(.neverAllow)

        case .requestSystemPermission:
            requestSystemPermission()

        case .openSystemSettings:
            openSystemSettings()

        case .dismiss:
            onDismiss()

        case .learnMore:
            guard let url = viewState.decision?.learnMore?.url else { return }
            openURL(url)
        }
    }

    // MARK: - Private

    private func onAppear() {
        viewState.title = makeTitle()
        if case .decision(var decision) = viewState.content {
            decision.learnMore = permissionType.learnMoreURL.map {
                PermissionAuthorizationViewState.LearnMore(title: UserText.permissionPopupLearnMoreLink, url: $0)
            }
            if case .externalScheme = permissionType, domain.isEmpty {
                // A link typed in the address bar has no website to save the choice for, as on Windows
                decision.buttons = decision.buttons.filter { $0.action == .allowThisVisit }
            }
            viewState.content = .decision(decision)
        }
        if query?.opensOnSystemPermissionStep == true, pendingDecision == nil {
            isResumingStoredDecision = true
            allow(.alwaysAllow)
        }
    }

    private func allow(_ decision: PermissionPromptDecision) {
        pendingDecision = decision
        observeAppDidBecomeActive()
        updateSystemPermissionStep(using: cachedSystemPermissionStates)
    }

    private var cachedSystemPermissionStates: [PermissionType: SystemPermissionAuthorizationState] {
        Dictionary(uniqueKeysWithValues: systemPermissions.map { ($0, systemPermissionManager.cachedAuthorizationState(for: $0)) })
    }

    private func submit(_ decision: PermissionPromptDecision) {
        stopObservingSystemPermission()
        guard let query else {
            Logger.general.debug("PermissionAuthorizationViewModel: Cannot submit decision because the query was released")
            finish()
            return
        }
        // Completion removes the query from the model. Keep it alive for the presenter's identity check when dismissing.
        defer { withExtendedLifetime(query) { finish() } }

        let output = decision.output
        if !isResumingStoredDecision {
            fireAuthorizationPixels { PermissionPixel.AuthorizationAction(decision: decision, permissionType: $0) }
        }
        query.handleDecision(grant: output.granted, remember: output.remember)
    }

    private func onDismiss() {
        withExtendedLifetime(query) {
            // A site already set to Always allow made no new choice, so closing doesn't cancel one.
            if query != nil, !isResumingStoredDecision {
                fireAuthorizationPixels { _ in .cancel }
            }
            stopObservingSystemPermission()
            query?.wasDismissed = true
            query?.cancel()
            finish()
        }
    }

    private func fireAuthorizationPixels(_ action: (PermissionType) -> PermissionPixel.AuthorizationAction) {
        for permission in permissions {
            pixelFiring?.fire(PermissionPixel.authorizationAction(permissionType: permission, action: action(permission)))
        }
    }

    private func submitPendingDecision() {
        guard let pendingDecision else {
            Logger.general.debug("PermissionAuthorizationViewModel: Ignoring submission because there is no pending decision")
            return
        }
        submit(pendingDecision)
    }

    // MARK: - System permission step

    private func updateSystemPermissionStep(using states: [PermissionType: SystemPermissionAuthorizationState], requestCompleted: Bool = false) {
        guard pendingDecision != nil else {
            Logger.general.debug("PermissionAuthorizationViewModel: Ignoring system permission update because there is no pending decision")
            return
        }
        // Resolve blocked permissions before asking for another device, and never grant a combined request partially.
        let blockedPermission = systemPermissions.first {
            states[$0] == .denied || states[$0] == .restricted || states[$0] == .systemDisabled
        }
        let permissionsToRequest = systemPermissions.filter { states[$0] != .authorized }
        guard let permission = blockedPermission ?? permissionsToRequest.first else {
            submitPendingDecision()
            return
        }
        let isWaiting = viewState.systemPermissionStep?.phase == .waiting
        if isRequestingSystemPermissions, blockedPermission == nil, let currentSystemPermission, states[currentSystemPermission] == .authorized {
            // The same click asks for the next device: the microphone alert follows the camera one.
            if !isWaiting {
                showSystemPermissionPhase(.waiting)
            }
            requestSystemAuthorization(for: permission)
            return
        }
        let wasWaiting = currentSystemPermission == permission && isWaiting
        currentSystemPermission = permission
        if blockedPermission != nil {
            isRequestingSystemPermissions = false
            saveAlwaysAllowWhileSystemPermissionIsBlocked()
            showSystemPermissionPhase(.openSettings)
        } else if !wasWaiting || requestCompleted {
            if requestCompleted {
                isRequestingSystemPermissions = false
            }
            systemPermissionsToRequest = permissionsToRequest
            showSystemPermissionPhase(.request)
        }
    }

    /// Saves Always allow right away, as Never allow is, although macOS blocks access for now.
    /// The request stays pending and is granted once macOS allows.
    private func saveAlwaysAllowWhileSystemPermissionIsBlocked() {
        guard pendingDecision == .alwaysAllow, !isResumingStoredDecision, let query else { return }
        fireAuthorizationPixels { PermissionPixel.AuthorizationAction(decision: .alwaysAllow, permissionType: $0) }
        // The site is now set to Always allow: granting later reports no new decision.
        isResumingStoredDecision = true
        query.saveAlwaysAllow()
    }

    private func showSystemPermissionPhase(_ phase: PermissionAuthorizationViewState.SystemPermissionStep.Phase) {
        let message: String
        let buttonTitle: String
        switch phase {
        case .request:
            message = systemPermissionRequiredMessage
            buttonTitle = UserText.websitePermissionsPromptRequestSystemPermission
        case .waiting:
            message = systemPermissionRequiredMessage
            buttonTitle = UserText.websitePermissionsPromptWaitingForSystemPermission
        case .openSettings:
            message = systemPermissionOffMessage
            buttonTitle = UserText.websitePermissionsPromptOpenSystemSettings
        }
        systemPermissionRefreshGeneration += 1
        viewState.content = .systemPermission(.init(phase: phase, message: message, buttonTitle: buttonTitle))
    }

    private func requestSystemPermission() {
        guard viewState.systemPermissionStep?.phase == .request, let currentSystemPermission else {
            Logger.general.debug("PermissionAuthorizationViewModel: Ignoring system permission request outside the request phase")
            return
        }
        isRequestingSystemPermissions = true
        showSystemPermissionPhase(.waiting)
        requestSystemAuthorization(for: currentSystemPermission)
    }

    /// Shows the macOS alert for `permission` while the prompt says "Waiting for request…".
    private func requestSystemAuthorization(for permission: PermissionType) {
        // Status snapshots read before this request no longer describe the step.
        systemPermissionRefreshGeneration += 1
        currentSystemPermission = permission
        systemPermissionRequestCount += 1
        let requestCount = systemPermissionRequestCount

        systemAuthorizationCancellable = systemPermissionManager.requestAuthorization(for: permission) { [weak self] state in
            Task { @MainActor in
                guard let self, self.systemPermissionRequestCount == requestCount,
                      self.currentSystemPermission == permission else {
                    Logger.general.debug("PermissionAuthorizationViewModel: Ignoring completion from an earlier system permission request")
                    return
                }
                self.systemPermissionRequestDidComplete(with: state)
            }
        }
        scheduleAfter(Constants.systemPermissionRequestTimeout) { [weak self] in
            guard self?.systemPermissionRequestCount == requestCount else {
                Logger.general.debug("PermissionAuthorizationViewModel: Ignoring timeout for request \(requestCount): newer request or released view model")
                return
            }
            self?.systemPermissionRequestDidTimeOut()
        }
    }

    private func systemPermissionRequestDidComplete(with state: SystemPermissionAuthorizationState) {
        guard pendingDecision != nil, let currentSystemPermission else {
            Logger.general.debug("PermissionAuthorizationViewModel: Ignoring system permission completion because there is no pending decision")
            return
        }
        guard state != .notDetermined || viewState.systemPermissionStep?.phase == .waiting else {
            Logger.general.debug("PermissionAuthorizationViewModel: Ignoring undetermined completion outside the waiting phase")
            return
        }
        var states = cachedSystemPermissionStates
        states[currentSystemPermission] = state
        updateSystemPermissionStep(using: states, requestCompleted: true)
    }

    private func systemPermissionRequestDidTimeOut() {
        guard pendingDecision != nil, viewState.systemPermissionStep?.phase == .waiting else {
            Logger.general.debug("PermissionAuthorizationViewModel: Ignoring timeout because there is no pending decision or the prompt is not waiting")
            return
        }
        showSystemPermissionPhase(.openSettings)
    }

    private func openSystemSettings() {
        guard let currentSystemPermission,
              let url = PermissionAuthorizationType(from: [currentSystemPermission]).systemSettingsURL else {
            Logger.general.debug("PermissionAuthorizationViewModel: Cannot open System Settings because the permission has no settings URL")
            return
        }
        pixelFiring?.fire(PermissionPixel.systemPreferencesOpened(permissionType: currentSystemPermission))
        openSystemSettingsURL(url)
    }

    /// Checks the macOS permission again when the user comes back, e.g. from System Settings.
    private func observeAppDidBecomeActive() {
        guard appDidBecomeActiveCancellable == nil else { return }

        appDidBecomeActiveCancellable = appDidBecomeActivePublisher.sink { [weak self] in
            guard let self else { return }
            Task { @MainActor [systemPermissionManager, systemPermissions] in
                self.systemPermissionRefreshGeneration += 1
                let refreshGeneration = self.systemPermissionRefreshGeneration
                var states: [PermissionType: SystemPermissionAuthorizationState] = [:]
                for permission in systemPermissions {
                    states[permission] = await systemPermissionManager.authorizationState(for: permission)
                }
                guard self.systemPermissionRefreshGeneration == refreshGeneration else { return }
                self.updateSystemPermissionStep(using: states)
            }
        }
    }

    private func stopObservingSystemPermission() {
        systemPermissionRefreshGeneration += 1
        pendingDecision = nil
        currentSystemPermission = nil
        isRequestingSystemPermissions = false
        systemAuthorizationCancellable = nil
        appDidBecomeActiveCancellable = nil
    }

    // MARK: - Copy

    private var systemPermissionRequiredMessage: String {
        if Set(systemPermissionsToRequest) == [.camera, .microphone] {
            return UserText.websitePermissionsPromptSystemCameraAndMicrophoneRequired
        }
        switch systemPermissionsToRequest.first {
        case .camera:
            return UserText.websitePermissionsPromptSystemCameraRequired
        case .microphone:
            return UserText.websitePermissionsPromptSystemMicrophoneRequired
        case .geolocation:
            return UserText.websitePermissionsPromptSystemLocationRequired
        case .notification:
            return UserText.websitePermissionsPromptSystemNotificationsRequired
        case .none, .popups, .externalScheme, .autoplayPolicy:
            return ""
        }
    }

    private var systemPermissionOffMessage: String {
        switch currentSystemPermission {
        case .camera:
            return UserText.websitePermissionsPromptSystemCameraOff
        case .microphone:
            return UserText.websitePermissionsPromptSystemMicrophoneOff
        case .geolocation:
            return UserText.websitePermissionsPromptSystemLocationOff
        case .notification:
            return UserText.websitePermissionsPromptSystemNotificationsOff
        case .none, .popups, .externalScheme, .autoplayPolicy:
            return ""
        }
    }

    private func makeTitle() -> String {
        switch permissionType {
        case .geolocation:
            return String(format: UserText.websitePermissionsPromptLocationFormat, domain)
        case .camera, .microphone, .cameraAndMicrophone:
            return String(format: UserText.websitePermissionsPromptDeviceFormat, domain, permissionType.localizedDescription.lowercased())
        case .notification:
            return String(format: UserText.websitePermissionsPromptNotificationsFormat, domain)
        case .popups:
            return String(format: UserText.popupWindowsPermissionAuthorizationFormat, domain, permissionType.localizedDescription.lowercased())
        case .externalScheme:
            if domain.isEmpty {
                return String(format: UserText.externalSchemePermissionAuthorizationNoDomainFormat, permissionType.localizedDescription)
            }
            return String(format: UserText.externalSchemePermissionAuthorizationFormat, domain, permissionType.localizedDescription)
        }
    }
}

extension PermissionAuthorizationViewModel {
    enum Action {
        case onAppear
        case allowThisVisit
        case alwaysAllow
        case neverAllow
        case requestSystemPermission
        case openSystemSettings
        case dismiss
        case learnMore
    }
}
