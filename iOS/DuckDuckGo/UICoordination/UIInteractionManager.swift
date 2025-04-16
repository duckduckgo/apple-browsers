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

/// This class coordinates foreground tasks that require synchronization between various services.
/// It manages the sequence of operations that occur when the app becomes active, ensuring proper order of execution
/// for authentication, data clearing, and handling of launch actions.
final class UIInteractionManager {

    private let authenticationService: AuthenticationServiceProtocol
    private let autoClearService: AutoClearServiceProtocol
    private let launchActionHandler: LaunchActionHandling

    init(authenticationService: AuthenticationServiceProtocol,
         autoClearService: AutoClearServiceProtocol,
         launchActionHandler: LaunchActionHandling) {
        self.authenticationService = authenticationService
        self.autoClearService = autoClearService
        self.launchActionHandler = launchActionHandler
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
    func start(launchAction: LaunchAction,
               onWebViewReadyForInteractions: @escaping () -> Void,
               onAppReadyForInteractions: @escaping () -> Void) {
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await self.authenticationService.authenticate()
                }
                group.addTask {
                    await self.autoClearService.waitForDataCleared()
                    // Handle URL and shortcutItem after data clearing, so the page is loaded when the auth screen is dismissed.
                    switch launchAction {
                    case .openURL, .handleShortcutItem:
                        await self.launchActionHandler.handleLaunchAction(launchAction)
                    case .showKeyboard:
                        break // Do nothing here for showKeyboard
                    }
                    onWebViewReadyForInteractions()
                }
                await group.waitForAll()
                // Handle keyboard launch after data clearing and auth to avoid interfering with the auth screen
                if case .showKeyboard = launchAction {
                    self.launchActionHandler.handleLaunchAction(launchAction)
                }
                onAppReadyForInteractions()
            }
        }
    }

}
