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
import AIChat
import BrowserServicesKit
import Core

/// No page to attach on this surface — collection/attachability are always empty/inert.
private final class SubscriptionOnboardingNoOpPageContextHandler: AIChatPageContextHandling {
    var contextPublisher: AnyPublisher<AIChatPageContext?, Never> { Empty().eraseToAnyPublisher() }
    func triggerContextCollection(trigger: PageContextExtractionTrigger) -> Bool { false }
    func isCurrentPageAttachable() -> Bool { false }
    func reportAttachabilityMeasurement(trigger: PageContextExtractionTrigger) {}
    func clear() {}
    func resubscribe() {}
    func clearAttachedContext() {}
}

/// No browser tab is behind this surface, so every browser-integration callback is a no-op.
private final class SubscriptionOnboardingNoOpSheetCoordinatorDelegate: AIChatContextualSheetCoordinatorDelegate {
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
/// `AIChatContextualSheetCoordinator` directly — the same coordinator `TabViewController` uses — rather than
/// building a standalone chat surface. There's no tab behind onboarding, so the tab-scoped dependencies
/// (page context, tab URL publishers, browser-integration delegate) are all no-ops; everything else
/// (settings, feature flags, content blocking) is sourced the same way production does.
@MainActor
final class SubscriptionOnboardingDuckAIChatLauncher {

    private let coordinator: AIChatContextualSheetCoordinator
    private let delegate = SubscriptionOnboardingNoOpSheetCoordinatorDelegate()

    init(contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>) {
        coordinator = AIChatContextualSheetCoordinator(
            voiceSearchHelper: VoiceSearchHelper(),
            aiChatSettings: AIChatSettings(),
            privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager,
            contentBlockingAssetsPublisher: contentBlockingAssetsPublisher,
            featureDiscovery: DefaultFeatureDiscovery(),
            featureFlagger: AppDependencyProvider.shared.featureFlagger,
            pageContextHandler: SubscriptionOnboardingNoOpPageContextHandler(),
            tabURLPublishers: AIChatTabURLPublishers(originating: Just<URL?>(nil).eraseToAnyPublisher(),
                                                      didFinish: Just<URL?>(nil).eraseToAnyPublisher()),
            isFireTab: false
        )
        coordinator.delegate = delegate
    }

    /// Presents the sheet from `presentingViewController`, then preselects `modelID` once the sheet's UTI
    /// host exists (iPhone only — see `AIChatContextualSheetCoordinator.preselectModel(_:)`).
    func present(from presentingViewController: UIViewController, modelID: String?) {
        Task { @MainActor in
            await coordinator.presentSheet(from: presentingViewController)
            // Force full-screen for onboarding, overriding the default medium/large detents shared with the
            // production tab sheet — set here rather than in the shared VC/coordinator so tab behavior is untouched.
            if let sheet = coordinator.sheetViewController?.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.selectedDetentIdentifier = .large
                sheet.largestUndimmedDetentIdentifier = .large
                sheet.prefersGrabberVisible = false
            }
            if let modelID {
                coordinator.preselectModel(modelID)
            }
        }
    }
}
