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
import NewTabPage
import os.log
import Subscription

/// Fetches AI models from the duck.ai API and builds sectioned model lists
/// using the shared section builder for the NTP dropdown.
@MainActor
final class NewTabPageOmnibarModelsProvider: NewTabPageOmnibarModelsProviding {

    private(set) var lastFetchedSections: [NewTabPageDataModel.AIModelSection]?
    private let modelsService: AIChatModelsProviding
    private let subscriptionManager: any SubscriptionManager

    init(
        modelsService: AIChatModelsProviding = AIChatModelsService(),
        subscriptionManager: any SubscriptionManager = Application.appDelegate.subscriptionManager
    ) {
        self.modelsService = modelsService
        self.subscriptionManager = subscriptionManager
    }

    func fetchAIModelSections() async -> [NewTabPageDataModel.AIModelSection] {
        do {
            let response = try await modelsService.fetchModels()
            let userTier = await resolveUserTier()
            let models = response.models.map { AIChatModel(remoteModel: $0, userTier: userTier) }
            let hasActiveSubscription = userTier != .free

            let sections = AIChatModelSectionBuilder.buildSections(
                models: models,
                hasActiveSubscription: hasActiveSubscription,
                advancedSectionHeader: UserText.aiChatModelPickerAdvancedSectionHeader,
                basicSectionHeader: UserText.aiChatModelPickerBasicModelsSectionHeader
            )

            let result = sections.map { section in
                NewTabPageDataModel.AIModelSection(
                    header: section.header,
                    items: section.items.map { model in
                        NewTabPageDataModel.AIModelItem(
                            id: model.id,
                            name: model.name,
                            shortName: model.shortName,
                            isEnabled: model.entityHasAccess,
                            supportsImageUpload: model.supportsImageUpload,
                            supportedTools: model.supportedTools.map(\.rawValue),
                            supportedReasoningEffort: model.supportedReasoningEffort.map(\.rawValue)
                        )
                    }
                )
            }
            lastFetchedSections = result
            return result
        } catch {
            Logger.aiChat.error("Failed to fetch models for NTP: \(error.localizedDescription)")
            return []
        }
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
