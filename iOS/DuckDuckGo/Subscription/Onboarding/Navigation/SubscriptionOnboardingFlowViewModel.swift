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

/// The flow's navigation state, deliberately separate from `SubscriptionOnboardingFlowViewModel`.
///
/// Section hosts observe *only* this. If they observed the flow view model they would re-evaluate on every
/// progress change too — and re-evaluating a host rebuilds the `NavigationLink` in its background, which on
/// iOS 15 writes `false` into the link's binding and reads as a pop. That collapsed the stack whenever a
/// step completed while a deeper screen was showing.
@MainActor
final class SubscriptionOnboardingNavigationState: ObservableObject {

    /// The pushed sections, root excluded. On iOS 16 this *is* `NavigationStack`'s path, so a pop is the
    /// system removing an element — never an ambiguous `false` written into a per-link binding.
    @Published var path: [SubscriptionOnboardingSection] = []
}

/// The PIR launch's presentation, deliberately on its own publisher. It cannot live on
/// ``SubscriptionOnboardingNavigationState`` because the section hosts observe that, and on iOS 15 rebuilding
/// a host rebuilds its `NavigationLink` — which reads as a pop. Only the flow's root view observes this.
@MainActor
final class SubscriptionOnboardingPIRLaunchState: ObservableObject {
    @Published var isPresentingPIR = false
}

/// Drives the onboarding flow with a cursor over a frozen sequence of sections.
@MainActor
final class SubscriptionOnboardingFlowViewModel {

    /// Sections this run walks through, frozen at init. Must not be re-derived during progress changes since
    /// re-shaping an active NavigationLink corrupts the stack; freezing anchors the sequence at launch.
    let sequence: [SubscriptionOnboardingSection]

    /// How far the customer has walked `sequence`. The only mutable navigation state in the flow.
    let navigation = SubscriptionOnboardingNavigationState()

    /// The section on screen. The root is not on the path, so an empty path means the sequence's first.
    var currentSection: SubscriptionOnboardingSection? { navigation.path.last ?? sequence.first }

    /// How far the customer has walked; 0 is the root. The path is a contiguous prefix of `sequence` past the
    /// root, so its count is the position.
    private var depth: Int { navigation.path.count }

    let pirLaunch = SubscriptionOnboardingPIRLaunchState()

    /// Presented rather than pushed: PIR is not in the sequence, and the row that launches it can be tapped
    /// from a summary the customer reaches at any point.
    var isPresentingPIR: Bool {
        get { pirLaunch.isPresentingPIR }
        set { pirLaunch.isPresentingPIR = newValue }
    }

    let entryPoint: SubscriptionOnboardingEntryPoint

    /// Customer's checklist (4 items if PIR unreachable, to keep ceiling at 100%).
    let checklist: [SubscriptionOnboardingChecklistItem]

    /// Screens read cached results from this rather than fetching for themselves.
    let prefetcher: SubscriptionOnboardingPrefetcher

    /// The Data Broker Protection screen, erased once here so callers hand over a plain view. Unreachable
    /// unless `isPIRAvailable`, since only then does the checklist carry a PIR row to tap.
    let pirScreen: () -> AnyView

    /// Assigned by ``SubscriptionOnboardingLauncher/launch(flow:onFinish:)``, which owns how the flow is
    /// presented and therefore how it closes.
    var onFinish: () -> Void = {}

    private var store: SubscriptionOnboardingProgressStoring
    private let isPIRActivated: Bool
    private let onRequestDuckAIChat: (String?) -> Void

    /// `prefetcher` and `onRequestDuckAIChat` are defaulted inside the body rather than in the signature:
    /// default arguments are evaluated in a nonisolated context, and both resolve main-actor isolated types.
    init<PIRScreen: View>(entryPoint: SubscriptionOnboardingEntryPoint,
                          store: SubscriptionOnboardingProgressStoring,
                          isPIRAvailable: Bool,
                          isPIRActivated: Bool = false,
                          prefetcher: SubscriptionOnboardingPrefetcher? = nil,
                          onRequestDuckAIChat: ((String?) -> Void)? = nil,
                          @ViewBuilder pirScreen: @escaping () -> PIRScreen = { EmptyView() }) {
        self.entryPoint = entryPoint
        self.store = store
        self.isPIRActivated = isPIRActivated
        self.prefetcher = prefetcher ?? SubscriptionOnboardingPrefetcher()
        self.pirScreen = { AnyView(pirScreen()) }
        if let onRequestDuckAIChat {
            self.onRequestDuckAIChat = onRequestDuckAIChat
        } else {
            // Built only when it will be used, so a test that supplies its own never constructs one.
            // Deliberately no dismiss — the chat launcher tears down the whole presented chain itself.
            let chatLauncher = SubscriptionOnboardingDuckAIChatLauncher()
            self.onRequestDuckAIChat = { chatLauncher.launch(modelID: $0) }
        }

        self.checklist = SubscriptionOnboardingChecklistItem.checklist(isPIRAvailable: isPIRAvailable)
        self.sequence = Self.makeSequence(entryPoint: entryPoint,
                                          completedItems: store.completedItems)
    }

    /// Kicked off when the flow appears rather than from `init`, so constructing a flow — in a test, or for a
    /// screen that is never shown — starts no network work. `prefetch` ignores targets already in flight.
    func startPrefetching() {
        prefetcher.prefetch(Self.prefetchTargets(for: sequence))
    }

    /// Only the sections this run will actually reach are worth fetching for.
    private static func prefetchTargets(for sequence: [SubscriptionOnboardingSection]) -> SubscriptionOnboardingPrefetcher.Targets {
        var targets: SubscriptionOnboardingPrefetcher.Targets = []
        if sequence.contains(.vpnActivation) {
            targets.insert(.connectionInfo)
        }
        if sequence.contains(.duckAI) {
            targets.insert(.aiModels)
        }
        return targets
    }

    // MARK: - Routing

    /// The section following `section`, or `nil` at the end of the sequence.
    func section(after section: SubscriptionOnboardingSection) -> SubscriptionOnboardingSection? {
        guard let index = sequence.firstIndex(of: section),
              sequence.indices.contains(index + 1) else { return nil }
        return sequence[index + 1]
    }

    /// Advances to the next section, or finishes if there is none.
    func proceed() {
        guard let current = currentSection, let next = section(after: current) else {
            finish()
            return
        }
        navigation.path.append(next)
    }

    func finish() {
        onFinish()
    }

    /// Drives the `NavigationLink` that pushes the section after `section`.
    ///
    /// The setter exists for one case only: a swipe-back on the top screen, which UIKit performs itself and
    /// reports here. The back chevron goes through ``goBack(from:)`` directly, and a `false` from any
    /// shallower link is SwiftUI rebuilding the chain rather than the customer popping anything — accepting
    /// one of those would unwind every screen above it.
    func isPastSection(_ section: SubscriptionOnboardingSection) -> Binding<Bool> {
        Binding(get: { [weak self] in
            guard let self, let index = self.sequence.firstIndex(of: section) else { return false }
            return self.depth > index
        }, set: { [weak self] isShowingNext in
            guard let self, !isShowingNext,
                  let index = self.sequence.firstIndex(of: section),
                  self.depth == index + 1 else { return }
            self.navigation.path.removeLast()
        })
    }

    /// Close button for the root screen; back button for pushed screens.
    func navigationButton(for section: SubscriptionOnboardingSection) -> SubscriptionOnboardingNavigationButton {
        section == sequence.first
            ? .close { [weak self] in self?.finish() }
            : .back { [weak self] in self?.goBack(from: section) }
    }

    /// The "Step X of N" indicator counted over this customer's checklist, so a PIR-ineligible customer sees the correct ceiling.
    func title(for section: SubscriptionOnboardingSection) -> String? {
        guard case .activation(let item) = section.kind,
              let step = checklist.firstIndex(of: item) else { return nil }
        return String(format: UserText.subscriptionOnboardingStepIndicatorFormat, step + 1, checklist.count)
    }

    /// The path is written in exactly two places — here and ``proceed()`` — and both are reached only from
    /// a customer action: a forward CTA, the back chevron, or a swipe-back. Nothing else may move it.
    /// Recording progress in particular must not, which is why completion notifies no one.
    private func goBack(from section: SubscriptionOnboardingSection) {
        guard let position = navigation.path.firstIndex(of: section) else { return }
        navigation.path.removeSubrange(position...)
    }

    // MARK: - Sequence construction

    private static func makeSequence(entryPoint: SubscriptionOnboardingEntryPoint,
                                     completedItems: Set<SubscriptionOnboardingChecklistItem>) -> [SubscriptionOnboardingSection] {
        switch entryPoint {
        case .postCheckout:
            return [.orderConfirmation, .welcome] + SubscriptionOnboardingSection.activationSections + [.progress]

        case .subscriptionSettings:
            let unfinished = SubscriptionOnboardingSection.activationSections.filter { section in
                guard case .activation(let item) = section.kind else { return false }
                return !completedItems.contains(item)
            }
            return unfinished + [.progress]
        }
    }
}

// MARK: - Progress

/// Progress is the store's business, not the flow's. Nothing here moves the cursor or touches navigation:
/// ``markComplete(_:)`` forwards to the store and stops, and the rest are reads derived from it. Kept apart
/// from the navigation members above so that stays true — a completion that published would re-evaluate a
/// section host, and on iOS 15 rebuilding a host's `NavigationLink` reads as a pop.
extension SubscriptionOnboardingFlowViewModel: SubscriptionOnboardingProgressProviding {

    /// Read straight from the store so screens take their progress when built; PIR is composed in at read time since it completes outside this flow.
    var completedItems: Set<SubscriptionOnboardingChecklistItem> {
        isPIRActivated ? store.completedItems.union([.pir]) : store.completedItems
    }

    /// Over the checklist this customer actually sees, so a PIR-ineligible customer can reach 100%.
    var completionPercentage: Int {
        SubscriptionOnboardingChecklistItem.completionPercentage(completed: completedItems, checklist: checklist)
    }

    /// Writes to the store. That is the whole of it.
    func markComplete(_ item: SubscriptionOnboardingChecklistItem) {
        store.markComplete(item)
    }
}

// MARK: - SubscriptionOnboardingSectionDelegate

extension SubscriptionOnboardingFlowViewModel: SubscriptionOnboardingSectionDelegate {

    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        guard case .activation(let item) = section.kind else { return }
        markComplete(item)
    }

    func sectionDidRequestAdvance() {
        proceed()
    }

    func sectionDidRequestDuckAIChat(modelID: String?) {
        onRequestDuckAIChat(modelID)
    }
}
