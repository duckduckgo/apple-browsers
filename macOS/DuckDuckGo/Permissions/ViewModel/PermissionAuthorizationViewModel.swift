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
import ConcurrencyExtensions
import Foundation
import PixelKit

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
    private let finish: () -> Void

    /// The allow choice held back until macOS grants its own permission.
    /// Submitting it earlier would let macOS show its prompt before the user asks for it.
    private var pendingDecision: PermissionPromptDecision?
    /// The site is already set to Always allow and only the macOS permission is missing,
    /// so granting it isn't a new decision to report.
    private var isResumingStoredDecision = false
    private var systemAuthorizationCancellable: AnyCancellable?
    private var appDidBecomeActiveCancellable: AnyCancellable?
    /// Tells a timeout apart from one scheduled for an earlier request.
    private var systemPermissionRequestCount = 0

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
        self.domain = query.domain
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
            viewState.title = makeTitle()
            viewState.learnMore = permissionType.learnMoreURL.map {
                PermissionAuthorizationViewState.LearnMore(title: UserText.permissionPopupLearnMoreLink, url: $0)
            }
            if query?.isSystemPermissionDisabled == true, pendingDecision == nil {
                isResumingStoredDecision = true
                allow(.alwaysAllow)
            }

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
            stopObservingSystemPermission()
            query?.wasDismissed = true
            query?.cancel()
            finish()

        case .learnMore:
            guard let url = viewState.learnMore?.url else { return }
            openURL(url)
        }
    }

    // MARK: - Decisions

    private func allow(_ decision: PermissionPromptDecision) {
        guard permissionType.requiresSystemPermission else {
            submit(decision)
            return
        }

        switch systemPermissionManager.cachedAuthorizationState(for: permissionType.asPermissionType) {
        case .authorized:
            submit(decision)
        case .notDetermined:
            showSystemPermissionStep(.request, holding: decision)
        case .denied, .restricted, .systemDisabled:
            showSystemPermissionStep(.openSettings, holding: decision)
        }
    }

    private func submit(_ decision: PermissionPromptDecision) {
        stopObservingSystemPermission()
        defer { finish() }
        guard let query else { return }

        let output = decision.output
        if !isResumingStoredDecision {
            for permission in permissions {
                pixelFiring?.fire(PermissionPixel.authorizationDecision(permissionType: permission, decision: output.granted ? .allow : .deny))
            }
        }
        query.handleDecision(grant: output.granted, remember: output.remember)
    }

    private func submitPendingDecision() {
        guard let pendingDecision else { return }
        submit(pendingDecision)
    }

    // MARK: - System permission step

    private func showSystemPermissionStep(_ phase: PermissionAuthorizationViewState.SystemPermissionStep.Phase, holding decision: PermissionPromptDecision) {
        pendingDecision = decision
        showSystemPermissionPhase(phase)
        observeAppDidBecomeActive()
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
        viewState.systemPermissionStep = .init(phase: phase, message: message, buttonTitle: buttonTitle)
    }

    private func requestSystemPermission() {
        guard viewState.systemPermissionStep?.phase == .request else { return }
        showSystemPermissionPhase(.waiting)
        systemPermissionRequestCount += 1
        let requestCount = systemPermissionRequestCount

        systemAuthorizationCancellable = systemPermissionManager.requestAuthorization(for: permissionType.asPermissionType) { [weak self] state in
            Task { @MainActor in
                self?.systemPermissionRequestDidComplete(with: state)
            }
        }
        scheduleAfter(Constants.systemPermissionRequestTimeout) { [weak self] in
            guard self?.systemPermissionRequestCount == requestCount else { return }
            self?.systemPermissionRequestDidTimeOut()
        }
    }

    private func systemPermissionRequestDidComplete(with state: SystemPermissionAuthorizationState) {
        guard pendingDecision != nil else { return }

        switch state {
        case .authorized:
            submitPendingDecision()
        case .notDetermined:
            guard viewState.systemPermissionStep?.phase == .waiting else { return }
            showSystemPermissionPhase(.request)
        case .denied, .restricted, .systemDisabled:
            showSystemPermissionPhase(.openSettings)
        }
    }

    private func systemPermissionRequestDidTimeOut() {
        guard pendingDecision != nil, viewState.systemPermissionStep?.phase == .waiting else { return }
        showSystemPermissionPhase(.openSettings)
    }

    private func openSystemSettings() {
        guard let url = permissionType.systemSettingsURL else { return }
        pixelFiring?.fire(PermissionPixel.systemPreferencesOpened(permissionType: permissionType.asPermissionType))
        openSystemSettingsURL(url)
    }

    /// Checks the macOS permission again when the user comes back, e.g. from System Settings.
    private func observeAppDidBecomeActive() {
        guard appDidBecomeActiveCancellable == nil else { return }

        appDidBecomeActiveCancellable = appDidBecomeActivePublisher.sink { [weak self] in
            guard let self else { return }
            Task { @MainActor [systemPermissionManager, permissionType] in
                let state = await systemPermissionManager.authorizationState(for: permissionType.asPermissionType)
                self.systemPermissionStateDidRefresh(state)
            }
        }
    }

    private func systemPermissionStateDidRefresh(_ state: SystemPermissionAuthorizationState) {
        guard pendingDecision != nil else { return }

        switch state {
        case .authorized:
            submitPendingDecision()
        case .notDetermined:
            // Location Services turned back on: macOS can ask again.
            guard viewState.systemPermissionStep?.phase == .openSettings else { return }
            showSystemPermissionPhase(.request)
        case .denied, .restricted, .systemDisabled:
            break
        }
    }

    private func stopObservingSystemPermission() {
        pendingDecision = nil
        systemAuthorizationCancellable = nil
        appDidBecomeActiveCancellable = nil
    }

    // MARK: - Copy

    private var systemPermissionRequiredMessage: String {
        switch permissionType {
        case .geolocation:
            return UserText.websitePermissionsPromptSystemLocationRequired
        case .notification:
            return UserText.websitePermissionsPromptSystemNotificationsRequired
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
            return ""
        }
    }

    private var systemPermissionOffMessage: String {
        switch permissionType {
        case .geolocation:
            return UserText.websitePermissionsPromptSystemLocationOff
        case .notification:
            return UserText.websitePermissionsPromptSystemNotificationsOff
        case .camera, .microphone, .cameraAndMicrophone, .popups, .externalScheme:
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
