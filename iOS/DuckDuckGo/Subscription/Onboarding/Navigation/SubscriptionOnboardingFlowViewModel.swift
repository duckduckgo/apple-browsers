//
//  SubscriptionOnboardingFlowViewModel.swift
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

/// The host that owns a running onboarding flow — the debug menu entry at the moment. The
/// flow view model forwards the app-level actions it can't perform itself: launching Duck.ai chat, and
/// finishing (closing) the flow.
protocol SubscriptionOnboardingFlowHosting: AnyObject {
    func launchDuckAIChat(modelID: String?)
    func onboardingFlowDidFinish()
}

/// Walks an ordered list of ``SubscriptionOnboardingSection``s one at a time, publishing the current section
/// for ``SubscriptionOnboardingFlowView`` to render. It is each section's ``SubscriptionOnboardingSectionDelegate``
/// (translating a section's completion and chat-launch requests) and exposes `advance` / `goBack` for
/// the section screens' terminal buttons. It owns the ``SubscriptionOnboardingPrefetcher`` and kicks off its
/// fetches at flow start, so leaving and returning to a section re-reads warmed data rather than refetching.
final class SubscriptionOnboardingFlowViewModel: ObservableObject {

    @Published private(set) var currentSection: SubscriptionOnboardingSection?

    let prefetcher: SubscriptionOnboardingPrefetcher

    private let sections: [SubscriptionOnboardingSection]
    private var currentIndex = 0
    private weak var host: SubscriptionOnboardingFlowHosting?

    @MainActor
    init(sections: [SubscriptionOnboardingSection] = SubscriptionOnboardingSection.allCases,
         prefetcher: SubscriptionOnboardingPrefetcher,
         host: SubscriptionOnboardingFlowHosting? = nil) {
        self.sections = sections
        self.prefetcher = prefetcher
        self.host = host
        self.currentSection = sections.first
        prefetcher.prefetch()
    }

    // MARK: - Navigation

    /// Moves to the next section, or finishes the flow once past the last one.
    @MainActor
    func advance() {
        guard currentIndex + 1 < sections.count else {
            host?.onboardingFlowDidFinish()
            return
        }
        currentIndex += 1
        currentSection = sections[currentIndex]
    }

    /// Returns to the previous section, or finishes (closes) the flow when already on the first one.
    @MainActor
    func goBack() {
        guard currentIndex > 0 else {
            host?.onboardingFlowDidFinish()
            return
        }
        currentIndex -= 1
        currentSection = sections[currentIndex]
    }
}

// MARK: - SubscriptionOnboardingSectionDelegate

extension SubscriptionOnboardingFlowViewModel: SubscriptionOnboardingSectionDelegate {

    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        // TODO: Completion drives the checklist percentage, which arrives with the progress store
    }

    func sectionDidRequestDuckAIChat(modelID: String?) {
        host?.launchDuckAIChat(modelID: modelID)
    }

    @MainActor
    func sectionDidRequestAdvance() {
        advance()
    }

    @MainActor
    func sectionDidRequestGoBack() {
        goBack()
    }
}

/// Hosts the onboarding flow in a single sheet: renders the current section from the injected
/// ``SubscriptionOnboardingViewFactory`` and swaps to the next when the view model's `currentSection` changes.
/// Each section carries its own navigation container, so a swap replaces one section's screen stack with the next.
struct SubscriptionOnboardingFlowView: View {

    @StateObject private var viewModel: SubscriptionOnboardingFlowViewModel
    private let factory: SubscriptionOnboardingViewFactory

    init(viewModel: @autoclosure @escaping () -> SubscriptionOnboardingFlowViewModel,
         factory: SubscriptionOnboardingViewFactory) {
        _viewModel = StateObject(wrappedValue: viewModel())
        self.factory = factory
    }

    var body: some View {
        ZStack {
            if let section = viewModel.currentSection {
                factory.makeView(for: section, delegate: viewModel, prefetcher: viewModel.prefetcher)
                    .id(section)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentSection)
    }
}
