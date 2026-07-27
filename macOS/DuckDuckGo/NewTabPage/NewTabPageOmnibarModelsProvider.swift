//
//  NewTabPageOmnibarModelsProvider.swift
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

import AIChat
import Combine
import FeatureFlags
import Foundation
import NewTabPage
import os.log
import PrivacyConfig
import Subscription

/// Fetches AI models from the duck.ai API and builds the NTP dropdown's model list, mirroring
/// the address bar's model picker (one flat, ordered section, then a gated section if needed).
@MainActor
final class NewTabPageOmnibarModelsProvider: NewTabPageOmnibarModelsProviding {

    private(set) var lastFetchedSections: [NewTabPageDataModel.AIModelSection]?
    private(set) var attachmentLimits: NewTabPageDataModel.AttachmentLimits?
    private(set) var isEligibleForFreeTrial = false
    private let modelsService: AIChatModelsProviding
    private let subscriptionManager: any SubscriptionManager
    private let featureFlagger: FeatureFlagger

    /// NTP reuses one webview per window rather than creating a fresh one per "new tab", so an
    /// already-open tab has no other way to notice a purchase completing mid-session.
    var modelsDidChangePublisher: AnyPublisher<Void, Never> {
        NotificationCenter.default.publisher(for: .subscriptionDidChange)
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    init(
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        subscriptionManager: any SubscriptionManager = Application.appDelegate.subscriptionManager,
        featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger
    ) {
        self.modelsService = modelsService
        self.subscriptionManager = subscriptionManager
        self.featureFlagger = featureFlagger
    }

    func fetchAIModelSections() async -> [NewTabPageDataModel.AIModelSection] {
        do {
            let response = try await modelsService.fetchModels()
            let userTier = await resolveUserTier()
            attachmentLimits = mapAttachmentLimits(response.attachmentLimits?.limits(for: userTier))
            isEligibleForFreeTrial = userTier == .free && subscriptionManager.isUserEligibleForFreeTrial()
            let models = response.models.map { AIChatModel(remoteModel: $0, userTier: userTier) }

            // Flat, ordered accessible list mirrors the address bar's `modelPickerItems` — the old
            // Basic/Advanced split left a stray empty section for tiers with both kinds (e.g. Pro).
            let (accessible, gated) = AIChatModelSectionBuilder.groupByAccess(models: models)
            let ordered = AIChatModelSectionBuilder.orderedAccessibleModels(accessible, userTier: userTier)

            var result: [NewTabPageDataModel.AIModelSection] = []
            if !ordered.isEmpty {
                result.append(
                    NewTabPageDataModel.AIModelSection(
                        header: nil,
                        items: ordered.map { mapToItem($0, requiredTier: nil, userTier: userTier) }
                    )
                )
            }

            if !gated.isEmpty {
                // Mirrors the address bar: a free user's gated section mixes Plus+Pro models
                // ("Subscriber Exclusive"), while a Plus user's is Pro-only ("Pro Exclusive").
                let header = userTier == .free ? UserText.aiChatModelPickerSubscriberExclusive
                                                : UserText.aiChatModelPickerProExclusive
                result.append(
                    NewTabPageDataModel.AIModelSection(
                        header: header,
                        items: gated.map { mapToItem($0.model, requiredTier: $0.requiredTier, userTier: userTier) }
                    )
                )
            }

            lastFetchedSections = result
            return result
        } catch {
            Logger.aiChat.error("Failed to fetch models for NTP: \(error.localizedDescription)")
            // Keep the last known-good snapshot rather than `[]` — otherwise `attachmentLimits`/
            // `isEligibleForFreeTrial` (still at their prior values) wouldn't match what's returned here.
            return lastFetchedSections ?? []
        }
    }

    private func mapToItem(_ model: AIChatModel, requiredTier: AIChatModelPublicAccessTier?, userTier: AIChatUserTier) -> NewTabPageDataModel.AIModelItem {
        NewTabPageDataModel.AIModelItem(
            id: model.id,
            name: model.name,
            shortName: model.shortName,
            isAvailable: model.entityHasAccess,
            supportsImageUpload: model.supportsImageUpload,
            supportedTools: model.supportedTools.map(\.rawValue),
            accessTier: accessTierString(for: model),
            reasoningEfforts: reasoningEfforts(for: model, userTier: userTier),
            supportedFileTypes: model.supportedFileTypes,
            upsell: requiredTier.flatMap { upsellString(for: userTier.upgradeFlow(for: $0)) }
        )
    }

    /// `nil` for a free model. `AIChatModelPublicAccessTier` excludes "internal", so that case is
    /// checked separately.
    private func accessTierString(for model: AIChatModel) -> String? {
        guard model.isAdvanced else { return nil }
        return model.lowestPublicAccessTier?.rawValue ?? (model.accessTier.contains("internal") ? "internal" : nil)
    }

    private func reasoningEfforts(for model: AIChatModel, userTier: AIChatUserTier) -> [NewTabPageDataModel.AIModelReasoningEffort] {
        model.availableReasoningModes.compactMap { mode in
            guard let effort = model.reasoningEffort(for: mode) else { return nil }
            let isAvailable = model.accessibleReasoningModes.contains(mode)
            let upsell = isAvailable ? nil : model.lowestPublicAccessTier(for: effort).flatMap { upsellString(for: userTier.upgradeFlow(for: $0)) }
            return NewTabPageDataModel.AIModelReasoningEffort(
                id: effort.rawValue,
                name: effort.title,
                description: effort.subtitle,
                isAvailable: isAvailable,
                upsell: upsell
            )
        }
    }

    private func upsellString(for flow: DuckAISubscriptionUpsellingFlow) -> String? {
        switch flow {
        case .purchase: return "subscribe"
        case .upgrade: return "upgrade"
        case .none: return nil
        }
    }

    /// `files`/`images` come from the backend when present; `tabs` carries the hardcoded cap, omitted when the limit kill switch is off (web then applies no tab limit).
    private func mapAttachmentLimits(_ limits: AIChatAttachmentTierLimits?) -> NewTabPageDataModel.AttachmentLimits {
        NewTabPageDataModel.AttachmentLimits(
            files: limits.map {
                .init(
                    maxPerConversation: $0.files.maxPerConversation,
                    maxFileSizeMB: $0.files.maxFileSizeMB,
                    maxTotalFileSizeBytes: $0.files.maxTotalFileSizeBytes,
                    maxPagesPerFile: $0.files.maxPagesPerFile
                )
            },
            images: limits.map {
                .init(
                    maxPerTurn: $0.images.maxPerTurn,
                    maxPerConversation: $0.images.maxPerConversation,
                    maxInputCharsWithAttachments: $0.images.maxInputCharsWithAttachments
                )
            },
            tabs: featureFlagger.isFeatureOn(.aiChatTabAttachmentLimit)
                ? .init(maxAttached: AIChatOmnibarController.maxTabAttachments)
                : nil
        )
    }

    private func resolveUserTier() async -> AIChatUserTier {
        do {
            guard let subscription = try await subscriptionManager.getSubscription(),
                  subscription.isActive else { return .free }
            switch subscription.tier {
            case .plus: return .plus
            case .pro: return .pro
            case .none: return .free
            }
        } catch {
            return .free
        }
    }
}
