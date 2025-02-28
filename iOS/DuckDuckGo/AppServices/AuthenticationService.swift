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

    func authenticate() async

}

final class AuthenticationService {

    private let authenticator: Authenticating
    private let overlayWindowManager: OverlayWindowManaging
    private let privacyStore: PrivacyStore

    init(authenticator: Authenticating = Authenticator(),
         overlayWindowManager: OverlayWindowManaging,
         privacyStore: PrivacyStore = PrivacyUserDefaults()) {
        self.authenticator = authenticator
        self.overlayWindowManager = overlayWindowManager
        self.privacyStore = privacyStore
    }

    // MARK: - Suspend

    func suspend() {
        if privacyStore.authenticationEnabled {
            overlayWindowManager.displayBlankSnapshotWindow()
        }
    }

}

extension AuthenticationService: AuthenticationServiceProtocol {

    @MainActor
    func authenticate() async {
        guard shouldAuthenticate else {
            return
        }
        overlayWindowManager.removeOverlay()
        let authenticationViewController = showAuthenticationScreen()
        await authenticate(with: authenticationViewController)
    }

    private var shouldAuthenticate: Bool {
         privacyStore.authenticationEnabled && authenticator.canAuthenticate()
    }

    @MainActor
    private func authenticate(with authenticationViewController: AuthenticationViewController) async {
        let didAuthenticate = await authenticator.authenticate(reason: UserText.appUnlock)
        if didAuthenticate {
            overlayWindowManager.removeOverlay()
            authenticationViewController.dismiss(animated: true)
        } else {
            authenticationViewController.showUnlockInstructions()
        }
    }

    private func showAuthenticationScreen() -> AuthenticationViewController {
        let authenticationViewController = AuthenticationViewController.loadFromStoryboard()
        authenticationViewController.delegate = self
        overlayWindowManager.displayOverlay(with: authenticationViewController)
        return authenticationViewController
    }

}

extension AuthenticationService: AuthenticationViewControllerDelegate {

    func authenticationViewController(authenticationViewController: AuthenticationViewController, didTapWithSender sender: Any) {
        Task { @MainActor in
            authenticationViewController.hideUnlockInstructions()
            await authenticate(with: authenticationViewController)
        }
    }

}
