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
import Common

/// The Duck.ai model-picker onboarding screen, built on ``SubscriptionOnboardingBaseView``.
/// It lists the available AI models (from
/// ``SubscriptionOnboardingDuckAIViewModel``), presents the "Learn More" info sheet, and — on
/// "Start Duck.ai Chat" — persists the selected model and launch Duck.ai chat.
struct SubscriptionOnboardingDuckAIView: View {
    private enum Metrics {
        static let iconTextSpacing: CGFloat = 16
        static let contentInsetHorizontal: CGFloat = 16
        static let contentInsetVertical: CGFloat = 16
    }

    @StateObject private var viewModel: SubscriptionOnboardingDuckAIViewModel
    private let title: String?

    @State private var isShowingInfoSheet = false

    init(viewModel: @autoclosure @escaping () -> SubscriptionOnboardingDuckAIViewModel,
         title: String? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.title = title
    }

    var body: some View {
        SubscriptionOnboardingBaseView(
            title: title,
            navigationButton: .back({ viewModel.goBack() }),
            header: header,
            footer: footer,
            scrollsContent: false) {
            modelPicker
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .subscriptionOnboardingInfoSheet(.duckAI, isPresented: $isShowingInfoSheet)
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

// MARK: - Model picker

/// The Duck.ai model picker: every available model is a row in a single `SubscriptionOnboardingCard`,
/// with a "PLUS"/"PRO" tier marker on paid models and a checkmark on the selected one. The model list comes
/// from a backend call (`AIChatModelsService`) prefetched by ``SubscriptionOnboardingPrefetcher``
/// Rows are non-interactive on iPad: model preselection has no way to reach a fresh iPad chat session.
private extension SubscriptionOnboardingDuckAIView {
    var modelPicker: some View {
        ScrollView(showsIndicators: false) {
            SubscriptionOnboardingCard(cardItems,
                                       style: .borderless,
                                       padding: 0,
                                       contentInset: .init(horizontal: Metrics.contentInsetHorizontal, vertical: Metrics.contentInsetVertical),
                                       onSelect: CardItemList.selectAction(over: viewModel.availableModels, where: { _ in isSelectable }) { viewModel.select($0.id) })
        }
    }

    /// Whether rows show/report a selection at all — false on iPad, where model preselection has no way
    /// to reach a fresh chat session, so neither the checkmark nor its accessibility value should appear.
    var isSelectable: Bool {
        !DevicePlatform.isIpad
    }

    var cardItems: [CardItem] {
        viewModel.availableModels.map { model in
            let (title, remainder) = model.titleComponents

            var details: [CardItemText] = []
            if !remainder.isEmpty {
                details.append(CardItemText(remainder, font: .bodyRegular))
            }
            if let tierMarker = tierMarker(for: model) {
                details.append(CardItemText(tierMarker, font: .footnoteRegular))
            }

            return CardItem(
                icon: CardItemIcon(position: .leadingColumn, visual: icon(for: model), size: .size24, spacing: Metrics.iconTextSpacing),
                title: CardItemText(title, font: .bodyRegular),
                titleDetails: details,
                trailing: isSelectable && model.id == viewModel.selectedModelID ? .checkmark(Color(designSystemColor: .accentPrimary)) : nil,
                accessibilityValue: isSelectable && model.id == viewModel.selectedModelID ? UserText.subscriptionOnboardingDuckAIModelSelectedValue : nil)
        }
    }

    /// The inline PLUS/PRO badge for a model, or `nil` when it needs none. Reads
    /// ``AIChatModel/lowestPublicAccessTier``
    func tierMarker(for model: AIChatModel) -> String? {
        switch model.lowestPublicAccessTier {
        case .plus: return UserText.subscriptionOnboardingDuckAIPlusMarker
        case .pro: return UserText.subscriptionOnboardingDuckAIProMarker
        case .free, nil: return nil
        }
    }

    func icon(for model: AIChatModel) -> Graphic {
        if let menuIcon = model.menuIcon {
            return .image(Image(uiImage: menuIcon))
        }
        return .image(Image(systemName: "sparkles"))
    }
}

#if DEBUG

@MainActor
private final class PreviewAIModelProvider: SubscriptionOnboardingAIModelProviding {
    private let models: [AIChatModel] = [
        AIChatModel(id: "gpt-5.4", name: "GPT-5.4", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
        AIChatModel(id: "claude-sonnet-4.6", name: "Claude Sonnet 4.6", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["plus"]),
        AIChatModel(id: "gpt-5.4-nano", name: "GPT-5.4 nano", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
        AIChatModel(id: "gpt-5.4-mini", name: "GPT-5.4 mini", provider: .openAI, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"]),
        AIChatModel(id: "claude-haiku-4.5", name: "Claude Haiku 4.5", provider: .anthropic, supportsImageUpload: false, entityHasAccess: true, accessTier: ["free"])
    ]
    func fetchModels() async -> [AIChatModel] { models }
    func updateSelectedModel(_ modelID: String) {}
}

/// Resolves to no models, mimicking a failed or empty `/models` fetch so the empty-list state can be previewed.
@MainActor
private final class EmptyPreviewAIModelProvider: SubscriptionOnboardingAIModelProviding {
    func fetchModels() async -> [AIChatModel] { [] }
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
