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

/// The host that owns a running onboarding flow — the debug entry today, the shipping coordinator later. The
/// flow view model forwards the app-level actions it can't perform itself: launching Duck.ai chat, and
/// finishing (closing) the flow.
protocol SubscriptionOnboardingFlowHosting: AnyObject {
    func launchDuckAIChat(modelID: String?)
    func onboardingFlowDidFinish()
}

/// Walks an ordered list of ``SubscriptionOnboardingSection``s one at a time, publishing the current section
/// for ``SubscriptionOnboardingFlowView`` to render. It is each section's ``SubscriptionOnboardingSectionDelegate``
/// (translating a section's completion and chat-launch requests) and exposes `advance` / `skip` / `goBack` for
/// the section screens' terminal buttons. It owns the ``SubscriptionOnboardingPrefetcher`` so leaving and
/// returning to a section re-reads warmed data rather than refetching.
///
/// Persistence is deferred to a later checkpoint: with no progress store yet, `skip()` behaves like `advance()`
/// and `sectionDidComplete(_:)` is not recorded.
final class SubscriptionOnboardingFlowViewModel: ObservableObject, SubscriptionOnboardingSectionDelegate {

    @Published private(set) var currentSection: SubscriptionOnboardingSection?

    private let sections: [SubscriptionOnboardingSection]
    private var currentIndex = 0
    private weak var host: SubscriptionOnboardingFlowHosting?

    @MainActor
    init(sections: [SubscriptionOnboardingSection] = SubscriptionOnboardingSection.allCases,
         host: SubscriptionOnboardingFlowHosting? = nil) {
        self.sections = sections
        self.host = host
        self.currentSection = sections.first
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

    /// Skips the current section. Identical to ``advance()`` until the progress store lands, at which point a
    /// skip will be recorded as skipped rather than completed.
    @MainActor
    func skip() {
        advance()
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

    // MARK: - SubscriptionOnboardingSectionDelegate

    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        // Completion drives the checklist percentage, which arrives with the progress store (deferred).
    }

    func launchDuckAIChat(modelID: String?) {
        host?.launchDuckAIChat(modelID: modelID)
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
                factory.makeView(for: section)
                    .id(section)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.currentSection)
    }
}
