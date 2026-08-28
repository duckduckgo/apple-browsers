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
import FeatureFlags_macOS
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

    /// Kept so usage warnings resolve without repeating the subscription lookup. Empty until first fetch.
    private(set) var lastResolvedUserTier: AIChatUserTier = .free
    private(set) var lastFetchedModels: [AIChatModel] = []
    private let modelsService: AIChatModelsProviding
    private let subscriptionManager: any SubscriptionManager
    private let featureFlagger: FeatureFlagger

    /// NTP reuses one webview per window rather than creating a fresh one per "new tab", so an
    /// already-open tab has no other way to notice its tier changing mid-session. The address bar
    /// gets this for free by rebuilding its menu on every open.
    ///
    /// All four signals matter: a purchase or renewal posts `subscriptionDidChange`, losing or
    /// gaining a plan posts `entitlementsDidChange`, and signing out or in posts the account
    /// notifications without either of the other two.
    private static let modelsDidChangeNotifications: [Notification.Name] = [
        .subscriptionDidChange, .entitlementsDidChange, .accountDidSignIn, .accountDidSignOut
    ]

    var modelsDidChangePublisher: AnyPublisher<Void, Never> {
        Publishers.MergeMany(Self.modelsDidChangeNotifications.map { NotificationCenter.default.publisher(for: $0) })
            .map { _ in () }
            // Sign-out posts two of these back to back; one refetch is enough.
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()
    }

    init(
        modelsService: AIChatModelsProviding? = nil,
        subscriptionManager: any SubscriptionManager = Application.appDelegate.subscriptionManager,
        featureFlagger: FeatureFlagger = Application.appDelegate.featureFlagger
    ) {
        self.modelsService = modelsService ?? AIChatModelsService(accessTokenProvider: subscriptionManager)
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
            lastResolvedUserTier = userTier
            lastFetchedModels = models

            // Recommended = backend-labelled models, shown first with the label as a subtitle.
            let (accessible, gated) = AIChatModelSectionBuilder.groupByAccess(models: models)
            let (recommended, rest) = AIChatModelSectionBuilder.groupByEditorialLabel(models: accessible)
            let ordered = recommended + rest

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
                let header = isSubscriptionUpsellEnabled
                    ? AIChatPickerSectionCopy.gatedModelsHeader(userTier: userTier, isEligibleForFreeTrial: isEligibleForFreeTrial)
                    : nil
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
            // Gated rows never show a subtitle, matching the address bar's `gatedModel` (no subtitle param).
            description: requiredTier == nil ? AIChatPickerSectionCopy.subtitle(for: model.label) : nil,
            isAvailable: model.entityHasAccess,
            supportsImageUpload: model.supportsImageUpload,
            supportedTools: model.supportedTools.map(\.rawValue),
            accessTier: accessTierString(for: model),
            reasoningEfforts: reasoningEfforts(for: model, userTier: userTier),
            supportedFileTypes: model.supportedFileTypes,
            upsell: upsellString(forRequiredTier: requiredTier, userTier: userTier)
        )
    }

    /// `nil` for a free model. `AIChatModelPublicAccessTier` excludes "internal", so that case is
    /// checked separately.
    private func accessTierString(for model: AIChatModel) -> String? {
        guard model.isAdvanced else { return nil }
        return model.lowestPublicAccessTier?.rawValue ?? (model.accessTier.contains("internal") ? "internal" : nil)
    }

    private func reasoningEfforts(for model: AIChatModel, userTier: AIChatUserTier) -> [NewTabPageDataModel.AIModelReasoningEffort] {
        var titledGatedSection = false
        return model.availableReasoningModes.compactMap { mode in
            guard let effort = model.reasoningEffort(for: mode) else { return nil }
            let isAvailable = model.isAccessible(effort)
            let requiredTier = isAvailable ? nil : model.lowestPublicAccessTier(for: effort)
            let upsell = upsellString(forRequiredTier: requiredTier, userTier: userTier)
            // Only the first gated effort heads the section.
            let sectionHeader = isAvailable || titledGatedSection || !isSubscriptionUpsellEnabled
                ? nil
                : AIChatPickerSectionCopy.gatedEffortsHeader(requiredTier: requiredTier,
                                                            userTier: userTier,
                                                            isEligibleForFreeTrial: isEligibleForFreeTrial)
            titledGatedSection = titledGatedSection || sectionHeader != nil
            return NewTabPageDataModel.AIModelReasoningEffort(
                id: effort.rawValue,
                name: effort.title,
                description: effort.subtitle,
                isAvailable: isAvailable,
                upsell: upsell,
                gatedSectionHeader: sectionHeader
            )
        }
    }

    // NTP has no `DuckAIPromptSurface` (only addressBar/promptBar model that), so unlike
    // `AIChatOmnibarController` this can't also check `surface.supportsSubscriptionUpsell` — the flag alone gates it here.
    private var isSubscriptionUpsellEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarSubscriptionUpsell)
    }

    /// `nil` with the kill switch off, so the web leaves gated rows inert instead of opening the
    /// purchase dialog — the address bar's `routesToUpsell: false` in the same state.
    private func upsellString(forRequiredTier requiredTier: AIChatModelPublicAccessTier?, userTier: AIChatUserTier) -> String? {
        guard isSubscriptionUpsellEnabled else { return nil }
        return requiredTier.flatMap { upsellString(for: userTier.upgradeFlow(for: $0)) }
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
