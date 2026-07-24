//
//  SubscriptionOnboardingDuckAIChatLauncher.swift
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

import UIKit
import Combine

/// No browser tab is behind this surface, so every browser-integration callback is a no-op — except
/// the sheet dismissal, which is forwarded so the onboarding flow can advance when the chat closes.
private final class SubscriptionOnboardingNoOpSheetCoordinatorDelegate: AIChatContextualSheetCoordinatorDelegate {
    var onDismiss: (() -> Void)?

    func aiChatContextualSheetCoordinatorDidDismiss(_ coordinator: AIChatContextualSheetCoordinator) {
        onDismiss?()
    }

    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestToLoad url: URL) {}
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestExpandWithURL url: URL) {}
    func aiChatContextualSheetCoordinatorDidRequestViewAllChats(_ coordinator: AIChatContextualSheetCoordinator) {}
    func aiChatContextualSheetCoordinatorDidRequestOpenSettings(_ coordinator: AIChatContextualSheetCoordinator) {}
    func aiChatContextualSheetCoordinatorDidRequestOpenSyncSettings(_ coordinator: AIChatContextualSheetCoordinator) {}
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didUpdateContextualChatURL url: URL?) {}
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestOpenDownloadWithFileName fileName: String) {}
    func aiChatContextualSheetCoordinator(_ coordinator: AIChatContextualSheetCoordinator, didRequestDeleteChatWithID chatID: String) {}
    func aiChatContextualSheetCoordinatorDidRequestNewVoiceChat(_ coordinator: AIChatContextualSheetCoordinator) {}
}

/// Launches the production Duck.ai contextual chat sheet from post-subscription onboarding by reusing
/// `AIChatContextualSheetCoordinator.makeStandalone(...)`. There's no tab behind onboarding, so the tab-scoped
/// dependencies (page context, tab URL publishers, browser-integration delegate, voice shortcut) are inert;
/// everything else (settings, feature flags, content blocking) is sourced the same way production does.
@MainActor
final class SubscriptionOnboardingDuckAIChatLauncher {

    private let coordinator: AIChatContextualSheetCoordinator
    private let delegate = SubscriptionOnboardingNoOpSheetCoordinatorDelegate()

    init(contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>) {
        coordinator = .makeStandalone(contentBlockingAssetsPublisher: contentBlockingAssetsPublisher)
        coordinator.delegate = delegate
    }

    /// Presents the sheet from `presentingViewController`, then preselects `modelID` once the sheet's UTI
    /// host exists (iPhone only). `onFinished` fires once when the sheet is dismissed.
    func present(from presentingViewController: UIViewController, modelID: String?, onFinished: (() -> Void)? = nil) {
        var didFinish = false
        delegate.onDismiss = {
            guard !didFinish else { return }
            didFinish = true
            onFinished?()
        }
        Task { @MainActor in
            await coordinator.presentSheet(from: presentingViewController)
            // There's no tab behind onboarding to expand into.
            coordinator.sheetViewController?.hideExpandButton()
            if let modelID {
                coordinator.preselectModel(modelID)
            }
        }
    }
}
