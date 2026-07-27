//
//  OnboardingView+AIModelPersonalizationContent.swift
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

import AIChat
import DuckUI
import Onboarding
import SwiftUI
import UIComponents
import DesignResourcesKitIcons

struct OnboardingPersonalizationSelectionItem: Identifiable {
    let icon: Image
    let title: String
    let isSelected: Binding<Bool>

    var id: String {
        title
    }
}

// MARK: - AI Model Selection

extension OnboardingView {

    /// The AI-model picker step (`.privateAIChat` reason). Single-select.
    ///
    /// The model list is fetched ahead of time by `OnboardingAIModelsPrefetcher` (started when the
    /// reason is chosen), so by the time this step appears the options are already resolved — no
    /// loading state, and the bubble doesn't shrink-then-grow. If the fetch isn't ready (or failed)
    /// the prefetcher returns a fallback list, so this view is always synchronous: options in,
    /// selection tracked locally, persisted through the slice. No view model needed.
    struct AIModelSelection: View {
        @Environment(\.onboardingTheme) private var onboardingTheme
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        @State private var shouldStartTyping = false
        @State private var showContent = false
        @State private var selectedID: String?
        /// Frozen at first appearance so `body` re-runs (typing/visibility animations) never swap the
        /// list out from under the bubble — the content stays fixed, so the bubble never resizes.
        @State private var options: [OnboardingAIModelOption]
        @Binding private var isVisible: Bool

        private let content: OnboardingAIModelContent
        private let modelPersonalization: OnboardingAIChatModelPersonalizing
        private let action: () -> Void

        init(
            content: OnboardingAIModelContent,
            options: [OnboardingAIModelOption],
            defaultID: String?,
            modelPersonalization: OnboardingAIChatModelPersonalizing,
            isVisible: Binding<Bool>,
            action: @escaping () -> Void
        ) {
            self.content = content
            self.modelPersonalization = modelPersonalization
            self._isVisible = isVisible
            self.action = action
            _options = State(initialValue: options)
            _selectedID = State(initialValue: defaultID)
        }

        var body: some View {
            let items = options.map { OnboardingPersonalizationSelectionItem($0, isSelected: isSelectedBinding(for: $0)) }

            LinearDialogContentContainer(
                metrics: .init(
                    outerSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    textSpacing: onboardingTheme.linearOnboardingMetrics.contentInnerSpacing,
                    contentSpacing: onboardingTheme.linearOnboardingMetrics.buttonSpacing,
                    actionsSpacing: onboardingTheme.linearOnboardingMetrics.actionsSpacing
                ),
                message: AnyView(
                    Text(content.message)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .font(onboardingTheme.typography.body)
                        .multilineTextAlignment(.center)
                ),
                content: AnyView(
                    OnboardingPersonalizationSelectionItemsList(items: items)
                ),
                showContent: $showContent,
                title: {
                    TypingText(
                        content.title,
                        startAnimating: $shouldStartTyping,
                        onTypingFinished: { [reduceMotion] in
                            if reduceMotion {
                                showContent = true
                            } else {
                                withAnimation { showContent = true }
                            }
                        })
                    .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                    .font(onboardingTheme.typography.title)
                    .multilineTextAlignment(.center)
                },
                actions: {
                    Button(action: action) {
                        Text(content.primaryCTA)
                    }
                    .buttonStyle(onboardingTheme.primaryButtonStyle.style)
                }
            )
            .onBubbleVisibilityChanged(isVisible: $isVisible, shouldStartTyping: $shouldStartTyping, showContent: $showContent)
            .onAppear(perform: persistDefaultSelection)
        }

        /// A per-row `Bool` binding derived from the single `selectedID`: reads `true` only for the
        /// selected row, and selecting a row (set to `true`) updates the shared selection so every
        /// other row flips off. Setting `false` is ignored — a radio can't be tapped off, only replaced.
        private func isSelectedBinding(for option: OnboardingAIModelOption) -> Binding<Bool> {
            Binding(
                get: { selectedID == option.id },
                set: { isSelected in
                    if isSelected { select(option) }
                }
            )
        }

        private func select(_ option: OnboardingAIModelOption) {
            selectedID = option.id
            persist(option)
        }

        /// Persists the pre-selected default so a user who taps Next without changing anything still
        /// gets a value stored.
        private func persistDefaultSelection() {
            guard let selectedID, let option = options.first(where: { $0.id == selectedID }) else { return }
            persist(option)
        }

        private func persist(_ option: OnboardingAIModelOption) {
            modelPersonalization.setAIChatModel(OnboardingAIModel(option))
        }
    }

}

extension OnboardingPersonalizationSelectionItem {

    init(_ aiModel: OnboardingAIModelOption, isSelected: Binding<Bool>) {
        self.init(icon: aiModel.icon, title: aiModel.displayName, isSelected: isSelected)
    }

}

extension OnboardingAIModelOption {

    init?(_ value: AIChatRemoteModel) {
        guard let provider = OnboardingAIProvider(rawValue: value.provider) else { return nil }
        self.init(id: value.id, provider: provider, modelShortName: value.modelShortName)
    }

}

extension OnboardingAIModel {

    init(_ option: OnboardingAIModelOption) {
        self.init(id: option.id, name: option.modelShortName ?? "")
    }

}

// MARK: - Prefetcher

enum OnboardingAIProvider: String, CaseIterable {
    case anthropic
    case openai
    case mistral
}

struct OnboardingAIModelOption: Identifiable {
    let id: String
    let provider: OnboardingAIProvider
    let modelShortName: String?
}

@MainActor
protocol OnboardingAIModelsPrefetching {
    var resolvedModel: (models: [OnboardingAIModelOption], defaultModelId: String?) { get }

    func prefetch()
}

/// Fetches the AI models ahead of the picker step so its options are ready when the view appears
/// (avoids a loading state and the bubble resize that comes with late-arriving content).
///
/// `prefetch()` is kicked off when the user picks the `.privateAIChat` reason — a couple of screens
/// before the model step — and the result is read synchronously via `resolvedModels`. If the fetch
/// isn't finished (or failed), `resolvedModels` returns the fallback list, so callers never wait.
@MainActor
final class OnboardingAIModelsPrefetcher: OnboardingAIModelsPrefetching {

    private let service: AIChatModelsProviding
    private var didStartPrefetch = false

    // The mapped result, computed once when the fetch completes.
    private var resolved: (models: [OnboardingAIModelOption], defaultId: String?)?

    // The fallback, mapped once at init.
    private let fallbackModels: [AIChatRemoteModel]

    var resolvedModel: (models: [OnboardingAIModelOption], defaultModelId: String?) {
        resolved ?? ([], nil)
    }

    init(
        service: AIChatModelsProviding = AIChatModelsService(),
        fallbackModels: [AIChatRemoteModel] = []
    ) {
        self.service = service
        self.fallbackModels = fallbackModels
    }

    /// Starts the fetch once. On success the models are mapped immediately and cached; failures are
    /// swallowed — `resolvedModels` returns the fallback instead.
    func prefetch() {
        guard !didStartPrefetch else { return }
        didStartPrefetch = true
        let fallbackModels = self.fallbackModels
        Task { [weak self, service] in
            do {
                let apiModels = try await service.fetchModels().models
                self?.resolved = OnboardingAIModelsResolver.resolve(from: apiModels)
            } catch {
                self?.resolved = OnboardingAIModelsResolver.resolve(from: fallbackModels)
            }
        }
    }
}

// MARK: - Private

enum OnboardingAIModelsResolver {

    /// Maps raw models to options (accessible only, one per provider in first-appearance order) and
    /// picks the default (OpenAI, falling back to the first available).
    static func resolve(from models: [AIChatRemoteModel]) -> (models: [OnboardingAIModelOption], defaultId: String?) {
        let aiModels = models
            .filter(\.entityHasAccess)
            .compactMap(OnboardingAIModelOption.init)

        let modelsByProvider = Dictionary(grouping: aiModels, by: \.provider)

        let modelsToReturn = OnboardingAIProvider.allCases
            .compactMap { modelsByProvider[$0]?.first }
        
        let defaultProviderId = modelsByProvider[OnboardingAIProvider.openai]?.first?.id

        return (modelsToReturn, defaultProviderId)
    }

}
