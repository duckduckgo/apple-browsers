//
//  AuthenticationService.swift
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

protocol AuthenticationServiceProtocol {

    func authenticate(waitForSuccessfulAuthentication: Bool) async

}

final class AuthenticationService {

    private let authenticator: Authenticating
    private let overlayWindowManager: OverlayWindowManaging
    private let privacyStore: PrivacyStore
    private weak var authenticationViewController: AuthenticationViewController?
    private var unlockContinuation: AsyncStream<Void>.Continuation?
    private var waitsForSuccessfulAuthentication = false
    private(set) var hasCompletedAuthentication = false

    init(authenticator: Authenticating = Authenticator(),
         overlayWindowManager: OverlayWindowManaging,
         privacyStore: PrivacyStore = PrivacyUserDefaults()) {
        self.authenticator = authenticator
        self.overlayWindowManager = overlayWindowManager
        self.privacyStore = privacyStore
    }

    // MARK: - Suspend

    func suspend() {
        if waitsForSuccessfulAuthentication {
            // A retry has its own task; invalidate it as well as the cancelled foreground launch.
            authenticationViewController = nil
            unlockContinuation?.finish()
            unlockContinuation = nil
        }
        if privacyStore.authenticationEnabled {
            overlayWindowManager.displayBlankSnapshotWindow(for: .authentication)
        }
    }

}

extension AuthenticationService: AuthenticationServiceProtocol {

    @MainActor
    func authenticate(waitForSuccessfulAuthentication: Bool = false) async {
        guard !waitForSuccessfulAuthentication || !Task.isCancelled else { return }
        guard shouldAuthenticate else {
            hasCompletedAuthentication = true
            return
        }
        waitsForSuccessfulAuthentication = waitForSuccessfulAuthentication
        overlayWindowManager.removeAnyOverlay()
        let authenticationViewController = showAuthenticationScreen()
        await authenticate(with: authenticationViewController, waitForSuccessfulAuthentication: waitForSuccessfulAuthentication)
        if waitForSuccessfulAuthentication, !Task.isCancelled, self.authenticationViewController === authenticationViewController {
            let unlocked = AsyncStream<Void> { unlockContinuation = $0 }
            // Cancelling the waiting launch task terminates the stream, including after a failed attempt.
            for await _ in unlocked { }
        }
    }

    private var shouldAuthenticate: Bool {
         privacyStore.authenticationEnabled && authenticator.canAuthenticate()
    }

    @MainActor
    private func authenticate(with authenticationViewController: AuthenticationViewController, waitForSuccessfulAuthentication: Bool) async {
        let didAuthenticate = await authenticator.authenticate(reason: UserText.appUnlock)
        // A newer foreground may have replaced the lock screen while this attempt was pending.
        guard !waitForSuccessfulAuthentication || (!Task.isCancelled && self.authenticationViewController === authenticationViewController) else { return }
        if didAuthenticate {
            if !Task.isCancelled, self.authenticationViewController === authenticationViewController {
                hasCompletedAuthentication = true
            }
            overlayWindowManager.removeAnyOverlay()
            authenticationViewController.dismiss(animated: true)
            self.authenticationViewController = nil
            unlockContinuation?.finish()
            unlockContinuation = nil
        } else {
            authenticationViewController.showUnlockInstructions()
        }
    }

    private func showAuthenticationScreen() -> AuthenticationViewController {
        let authenticationViewController = AuthenticationViewController()
        self.authenticationViewController = authenticationViewController
        authenticationViewController.delegate = self
        overlayWindowManager.displayOverlay(with: authenticationViewController)
        return authenticationViewController
    }

}

extension AuthenticationService: AuthenticationViewControllerDelegate {

    func authenticationViewController(authenticationViewController: AuthenticationViewController, didTapWithSender sender: Any) {
        Task { @MainActor in
            authenticationViewController.hideUnlockInstructions()
            await authenticate(with: authenticationViewController, waitForSuccessfulAuthentication: waitsForSuccessfulAuthentication)
        }
    }

}
