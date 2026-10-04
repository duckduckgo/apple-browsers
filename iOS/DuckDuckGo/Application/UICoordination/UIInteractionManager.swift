//
//  UIInteractionManager.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import UIKit
import Combine

/// This class coordinates foreground tasks that require synchronization between various services.
/// It manages the sequence of operations that occur when the app becomes active, ensuring proper order of execution
/// for authentication, data clearing, and handling of launch actions.
final class UIInteractionManager {

    private let authenticationService: AuthenticationServiceProtocol
    private let autoClearService: AutoClearServiceProtocol
    private let launchActionHandler: LaunchActionHandling
    private let onboardingPresenter: OnboardingPresenting
    private let waitsForSuccessfulAuthentication: Bool
    private let notificationCenter: NotificationCenter
    private let isApplicationActive: @MainActor () -> Bool
    private var pendingInteractions: Task<Void, Never>?

    init(authenticationService: AuthenticationServiceProtocol,
         autoClearService: AutoClearServiceProtocol,
         launchActionHandler: LaunchActionHandling,
         onboardingPresenter: OnboardingPresenting,
         waitsForSuccessfulAuthentication: Bool = false,
         notificationCenter: NotificationCenter = .default,
         isApplicationActive: @escaping @MainActor () -> Bool = { UIApplication.shared.applicationState == .active }
    ) {
        self.authenticationService = authenticationService
        self.autoClearService = autoClearService
        self.launchActionHandler = launchActionHandler
        self.onboardingPresenter = onboardingPresenter
        self.waitsForSuccessfulAuthentication = waitsForSuccessfulAuthentication
        self.notificationCenter = notificationCenter
        self.isApplicationActive = isApplicationActive
    }

    @MainActor
    func cancelPendingInteractions() {
        guard waitsForSuccessfulAuthentication else { return }
        pendingInteractions?.cancel()
        pendingInteractions = nil
    }

    /// This method orchestrates the following operations:
    ///
    /// 1. Triggers authentication (if needed)
    /// 2. Waits for data clearing to complete
    /// 3. Handles immediate launch actions (if any)
    /// 4. Signals when the WebView is ready for interactions
    /// 5. Handles non-immediate launch actions (if any)
    /// 6. Signals when the entire app is ready for user interactions
    ///
    @MainActor
    @discardableResult
    func start(launchAction: LaunchAction,
               onWebViewReadyForInteractions: @escaping () -> Void,
               onAppReadyForInteractions: @escaping () -> Void) -> Task<Void, Never> {
        cancelPendingInteractions()
        let task = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.authenticationService.authenticate(waitForSuccessfulAuthentication: self.waitsForSuccessfulAuthentication)
                }
                group.addTask {
                    await self.autoClearService.waitForDataCleared()
                    guard !Task.isCancelled else { return }

                    // Present Onboarding Flow if needed
                    await self.onboardingPresenter.startOnboardingFlowIfNotSeenBefore(url: launchAction.url)
                    guard !Task.isCancelled else { return }

                    // Handle URL, shortcut item, and user activities after data clearing, so UI is ready when auth is dismissed.
                    switch launchAction {
                    case .openURL, .handleShortcutItem, .handleUserActivity:
                        await self.launchActionHandler.handleLaunchAction(launchAction)
                    case .standardLaunch:
                        break // Do nothing here for standardLaunch
                    }
                    onWebViewReadyForInteractions()
                }
                await group.waitForAll()
                guard !Task.isCancelled else { return }
                if waitsForSuccessfulAuthentication {
                    await waitForApplicationActive()
                    guard !Task.isCancelled else { return }
                }
                // Handle keyboard launch after data clearing and auth to avoid interfering with the auth screen
                if case .standardLaunch = launchAction {
                    self.launchActionHandler.handleLaunchAction(launchAction)
                }
                onAppReadyForInteractions()
            }
        }
        pendingInteractions = task
        return task
    }

    @MainActor
    private func waitForApplicationActive() async {
        guard !isApplicationActive() else { return }
        var activationContinuation: AsyncStream<Void>.Continuation?
        let activations = AsyncStream<Void> { continuation in
            activationContinuation = continuation
            let cancellable = notificationCenter.publisher(for: UIApplication.didBecomeActiveNotification)
                .sink { _ in continuation.yield(()) }
            continuation.onTermination = { _ in cancellable.cancel() }
        }
        defer { activationContinuation?.finish() }
        // Authentication can succeed before the system prompt returns the app to active.
        guard !isApplicationActive() else { return }
        for await _ in activations {
            guard !Task.isCancelled else { return }
            if isApplicationActive() { return }
        }
    }

}
