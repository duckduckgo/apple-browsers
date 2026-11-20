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

import FeatureFlags_macOS
import Foundation
import PrivacyConfig

protocol DefaultBrowserAndDockActionPerforming {
    var pendingPromptType: DefaultBrowserAndDockPromptType? { get }
    @MainActor
    func performPendingActions(onSetAsDefaultRequested: (() -> Void)?)
}

extension DefaultBrowserAndDockActionPerforming {
    @MainActor
    func performPendingActions() {
        performPendingActions(onSetAsDefaultRequested: nil)
    }
}

final class DefaultBrowserAndDockActionPerformer: DefaultBrowserAndDockActionPerforming {

    private let dockCustomization: DockCustomization
    private let defaultBrowserProvider: DefaultBrowserProvider
    private let featureFlagger: FeatureFlagger
    private let videoPresenter: AddToDockVideoPresenting

    init(dockCustomization: DockCustomization,
         defaultBrowserProvider: DefaultBrowserProvider,
         featureFlagger: FeatureFlagger,
         videoPresenter: AddToDockVideoPresenting) {
        self.dockCustomization = dockCustomization
        self.defaultBrowserProvider = defaultBrowserProvider
        self.featureFlagger = featureFlagger
        self.videoPresenter = videoPresenter
    }

    var pendingPromptType: DefaultBrowserAndDockPromptType? {
        switch (defaultBrowserProvider.isDefault, dockCustomization.isAddedToDock) {
        case (true, true):
            return nil
        case (true, false):
            return canOffer(.addToDockPrompt) ? .addToDockPrompt : nil
        case (false, true):
            return .setAsDefaultPrompt
        case (false, false):
            return canOffer(.bothDefaultBrowserAndDockPrompt) ? .bothDefaultBrowserAndDockPrompt : .setAsDefaultPrompt
        }
    }

    private func canOffer(_ type: DefaultBrowserAndDockPromptType) -> Bool {
        guard !dockCustomization.supportsAddingToDock else { return true }
        switch type {
        case .addToDockPrompt:
            return featureFlagger.isFeatureOn(.appStoreAddToDockOnlyCTA)
        case .bothDefaultBrowserAndDockPrompt:
            return featureFlagger.isFeatureOn(.appStoreBothDefaultBrowserAndDockCTA)
        case .setAsDefaultPrompt:
            return true
        }
    }

    @MainActor
    func performPendingActions(onSetAsDefaultRequested: (() -> Void)?) {
        guard let type = pendingPromptType else { return }

        guard dockCustomization.supportsAddingToDock else {
            performPendingActionsWithVideo(type, onSetAsDefaultRequested: onSetAsDefaultRequested)
            return
        }

        switch type {
        case .bothDefaultBrowserAndDockPrompt:
            // Add to Dock first: the default browser request shows a system confirmation.
            dockCustomization.addToDock()
            setAsDefaultBrowserAction(onRequested: onSetAsDefaultRequested)
        case .addToDockPrompt:
            dockCustomization.addToDock()
        case .setAsDefaultPrompt:
            setAsDefaultBrowserAction(onRequested: onSetAsDefaultRequested)
        }
    }

    @MainActor
    private func performPendingActionsWithVideo(_ type: DefaultBrowserAndDockPromptType, onSetAsDefaultRequested: (() -> Void)?) {
        switch type {
        case .bothDefaultBrowserAndDockPrompt:
            let isPresented = videoPresenter.present(primaryAction: .next) { [weak self] action in
                guard action == .next else { return }
                self?.setAsDefaultBrowserAction(onRequested: onSetAsDefaultRequested)
            }
            if !isPresented {
                setAsDefaultBrowserAction(onRequested: onSetAsDefaultRequested)
            }
        case .addToDockPrompt:
            videoPresenter.present(primaryAction: .done)
        case .setAsDefaultPrompt:
            setAsDefaultBrowserAction(onRequested: onSetAsDefaultRequested)
        }
    }

    /// Asks macOS to make DuckDuckGo the default browser, which shows the system confirmation.
    /// If that request fails, opens System Settings so the user can choose it manually.
    private func setAsDefaultBrowserAction(onRequested: (() -> Void)?) {
        do {
            try defaultBrowserProvider.presentDefaultBrowserPrompt()
        } catch {
            defaultBrowserProvider.openSystemPreferences()
        }
        onRequested?()
    }
}
