//
//  SubscriptionOnboardingDuckAIView.swift
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

import SwiftUI
import DesignResourcesKit
import UIComponents
import AIChat

/// The Duck.ai model-picker onboarding screen, built by ``SubscriptionOnboardingViewFactory`` on
/// ``SubscriptionOnboardingBaseView``. It lists the available AI models (from
/// ``SubscriptionOnboardingDuckAIViewModel``), presents the "Learn More" info sheet, and — on
/// "Start Duck.ai Chat" — persists the selected model and asks the flow to launch Duck.ai chat.
struct SubscriptionOnboardingDuckAIView: View {
    @StateObject private var viewModel: SubscriptionOnboardingDuckAIViewModel
    private let title: String?

    @State private var isShowingInfoSheet = false

    @MainActor
    init(viewModel: @autoclosure @escaping () -> SubscriptionOnboardingDuckAIViewModel,
         title: String? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.title = title
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: .back({ viewModel.delegate?.sectionDidRequestGoBack() }),
            header: header,
            footer: footer) {
            SubscriptionOnboardingAIModelPicker(
                models: viewModel.availableModels,
                selectedModelID: viewModel.selectedModelID,
                onSelect: { viewModel.select($0) })
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .sheet(isPresented: $isShowingInfoSheet) {
            SubscriptionOnboardingInfoView(content: .duckAI, onClose: { isShowingInfoSheet = false })
                .subscriptionOnboardingNavigationContainer()
        }
    }
}

// MARK: - Header + Footer

private extension SubscriptionOnboardingDuckAIView {
    var header: SubscriptionOnboardingHeaderView {
        SubscriptionOnboardingHeaderView(
            visual: .image(Image(.onboardingDuckAI128)),
            title: UserText.subscriptionOnboardingDuckAIActivationTitle,
            explanation: UserText.subscriptionOnboardingDuckAIActivationExplanation,
            onInfoLinkTap: { isShowingInfoSheet = true })
    }

    var footer: SubscriptionOnboardingFooter {
        .double(
            primary: .init(UserText.subscriptionOnboardingDuckAIActivationStartButton) {
                viewModel.startChat()
            },
            secondary: .init(UserText.subscriptionOnboardingDuckAIActivationSkipButton) {
                viewModel.skip()
            })
    }
}

#if DEBUG

@MainActor
private final class PreviewAIModelProvider: SubscriptionOnboardingAIModelProviding {
    let models: [AIChatModel] = [
        AIChatModel(id: "gpt-5.4", name: "GPT-5.4", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
        AIChatModel(id: "claude-sonnet-4.6", name: "Claude Sonnet 4.6", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
        AIChatModel(id: "gpt-5.4-nano", name: "GPT-5.4 nano", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
        AIChatModel(id: "gpt-5.4-mini", name: "GPT-5.4 mini", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
        AIChatModel(id: "claude-haiku-4.5", name: "Claude Haiku 4.5", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"])
    ]
    var persistedModelID: String? = "gpt-5.4-nano"
    var onModelsUpdated: (() -> Void)?
    func fetchModels() { onModelsUpdated?() }
    func updateSelectedModel(_ modelID: String) {}
}

/// Resolves to no models, mimicking a failed or empty `/models` fetch so the empty-list state can be previewed.
@MainActor
private final class EmptyPreviewAIModelProvider: SubscriptionOnboardingAIModelProviding {
    let models: [AIChatModel] = []
    var persistedModelID: String?
    var onModelsUpdated: (() -> Void)?
    func fetchModels() { onModelsUpdated?() }
    func updateSelectedModel(_ modelID: String) {}
}

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingDuckAIView(
            viewModel: SubscriptionOnboardingDuckAIViewModel(prefetcher: SubscriptionOnboardingPrefetcher(modelProvider: PreviewAIModelProvider())))
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingDuckAIView(
            viewModel: SubscriptionOnboardingDuckAIViewModel(prefetcher: SubscriptionOnboardingPrefetcher(modelProvider: PreviewAIModelProvider())))
            .subscriptionOnboardingNavigationContainer()
    }
    .preferredColorScheme(.dark)
}

#Preview("Empty") {
    RebrandedPreview {
        SubscriptionOnboardingDuckAIView(
            viewModel: SubscriptionOnboardingDuckAIViewModel(prefetcher: SubscriptionOnboardingPrefetcher(modelProvider: EmptyPreviewAIModelProvider())))
            .subscriptionOnboardingNavigationContainer()
    }
}

#endif
