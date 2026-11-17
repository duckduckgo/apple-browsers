//
//  DefaultBrowserAndDockActionPerformer.swift
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

protocol DefaultBrowserAndDockActionPerforming {
    var pendingPromptType: DefaultBrowserAndDockPromptType? { get }
    func performPendingActions()
}

final class DefaultBrowserAndDockActionPerformer: DefaultBrowserAndDockActionPerforming {

    private let dockCustomization: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider

    init(dockCustomization: DockCustomization, defaultBrowserProvider: DefaultBrowserProvider) {
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
    }

    var pendingPromptType: DefaultBrowserAndDockPromptType? {
        let isDefaultBrowser = defaultBrowserProvider.isDefault
        guard dockCustomization.supportsAddingToDock else {
            return isDefaultBrowser ? nil : .setAsDefaultPrompt
        }

        switch (isDefaultBrowser, dockCustomization.isAddedToDock) {
        case (true, true): return nil
        case (true, false): return .addToDockPrompt
        case (false, true): return .setAsDefaultPrompt
        case (false, false): return .bothDefaultBrowserAndDockPrompt
        }
    }

    func performPendingActions() {
        guard let type = pendingPromptType else { return }

        switch type {
        case .bothDefaultBrowserAndDockPrompt:
            // Add to Dock first: the default browser request shows a system confirmation.
            dockCustomization.addToDock()
            setAsDefaultBrowserAction()
        case .addToDockPrompt:
            dockCustomization.addToDock()
        case .setAsDefaultPrompt:
            setAsDefaultBrowserAction()
        }
    }

    /// Asks macOS to make DuckDuckGo the default browser, which shows the system confirmation.
    /// If that request fails, opens System Settings so the user can choose it manually.
    private func setAsDefaultBrowserAction() {
        do {
            try defaultBrowserProvider.presentDefaultBrowserPrompt()
        } catch {
            defaultBrowserProvider.openSystemPreferences()
        }
    }
}
