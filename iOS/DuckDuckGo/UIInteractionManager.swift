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

/// This handles foreground-related async tasks that require coordination between services.
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
                    if launchAction.requiresImmediateAction {
                        await self.launchActionHandler.handleLaunchAction(launchAction)
                    }
                    onWebViewReadyForInteractions()
                }

                await group.waitForAll()

                // Handle keyboard launch after data clearing and auth to avoid interfering with the auth screen
                if !launchAction.requiresImmediateAction {
                    self.launchActionHandler.handleLaunchAction(launchAction)
                }

                onAppReadyForInteractions()
            }
        }

    }

}
