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
/// ``SubscriptionOnboardingDuckAIActivationViewModel``), presents the "Learn More" info sheet, and — on
/// "Start Duck.ai Chat" — launches the web chat with the selected model (persisted by the view model) in a
/// full-screen modal.
struct SubscriptionOnboardingDuckAIView: View {
    @StateObject private var viewModel: SubscriptionOnboardingDuckAIActivationViewModel
    private let title: String?

    @Environment(\.dismiss) private var dismiss
    @State private var isShowingInfoSheet = false
    @State private var isShowingChat = false

    init(viewModel: @autoclosure @escaping () -> SubscriptionOnboardingDuckAIActivationViewModel = SubscriptionOnboardingDuckAIActivationViewModel(),
         title: String? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.title = title
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: .back({ dismiss() }),
            header: header,
            footer: footer) {
            // TODO: handle loading / empty / error states. If the /models fetch fails or returns nothing
            // (offline, not subscribed), this renders an empty picker — no spinner, message, or retry.
            SubscriptionOnboardingAIModelPicker(
                models: viewModel.availableModels,
                selectedModelID: viewModel.selectedModelID,
                onSelect: { viewModel.select($0) })
        }
        .onAppear { viewModel.onAppear() }
        .sheet(isPresented: $isShowingInfoSheet) {
            SubscriptionOnboardingInfoView(content: .duckAI, onClose: { isShowingInfoSheet = false })
                .subscriptionOnboardingNavigationContainer()
        }
        .sheet(isPresented: $isShowingChat) {
            SubscriptionOnboardingDuckAIChatView(onClose: { isShowingChat = false })
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
                isShowingChat = true
            },
            secondary: .init(UserText.subscriptionOnboardingDuckAIActivationSkipButton) {
                dismiss()
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

#Preview("Light") {
    RebrandedPreview {
        SubscriptionOnboardingDuckAIView(
            viewModel: SubscriptionOnboardingDuckAIActivationViewModel(modelProvider: PreviewAIModelProvider()))
            .subscriptionOnboardingNavigationContainer()
    }
}

#Preview("Dark") {
    RebrandedPreview {
        SubscriptionOnboardingDuckAIView(
            viewModel: SubscriptionOnboardingDuckAIActivationViewModel(modelProvider: PreviewAIModelProvider()))
            .subscriptionOnboardingNavigationContainer()
    }
    .preferredColorScheme(.dark)
}

#endif
