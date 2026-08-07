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

    /// Indices of the pushed sections, root excluded. On iOS 16 this *is* `NavigationStack`'s path, so a pop
    /// is the system removing an element — never an ambiguous `false` written into a per-link binding.
    @Published var path: [Int] = []

    /// The section on screen.
    var cursor: Int { path.last ?? 0 }
}

/// The PIR detour's presentation, deliberately on its own publisher. It cannot live on
/// ``SubscriptionOnboardingNavigationState`` because the section hosts observe that, and on iOS 15 rebuilding
/// a host rebuilds its `NavigationLink` — which reads as a pop. Only the flow's root view observes this.
@MainActor
final class SubscriptionOnboardingDetourState: ObservableObject {
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

    var cursor: Int { navigation.cursor }

    /// Read straight from the store, never mirrored here. Completion has no in-memory state to update and
    /// nothing to notify, so recording a step cannot re-evaluate a section host — which on iOS 15 would
    /// rebuild its `NavigationLink` and read as a pop. Screens take their progress when they are built.
    var completedItems: Set<SubscriptionOnboardingChecklistItem> {
        // PIR is the one step nothing in this flow records: it completes inside Data Broker Protection, so it
        // is composed in at read time rather than written into the store as though the customer earned it here.
        isPIRActivated ? store.completedItems.union([.pir]) : store.completedItems
    }

    let detour = SubscriptionOnboardingDetourState()

    /// Presented rather than pushed, since the PIR row can be tapped from a summary many sections earlier.
    var isPresentingPIR: Bool {
        get { detour.isPresentingPIR }
        set { detour.isPresentingPIR = newValue }
    }

    let entryPoint: SubscriptionOnboardingEntryPoint

    /// Customer's checklist (4 items if PIR unreachable, to keep ceiling at 100%).
    let checklist: [SubscriptionOnboardingChecklistItem]

    private var store: SubscriptionOnboardingProgressStoring
    private let isPIRActivated: Bool
    private let onFinish: () -> Void
    private let onRequestDuckAIChat: (String?) -> Void

    init(entryPoint: SubscriptionOnboardingEntryPoint,
         store: SubscriptionOnboardingProgressStoring,
         isPIRAvailable: Bool,
         isPIRActivated: Bool = false,
         onFinish: @escaping () -> Void,
         onRequestDuckAIChat: @escaping (String?) -> Void) {
        self.entryPoint = entryPoint
        self.store = store
        self.isPIRActivated = isPIRActivated
        self.onFinish = onFinish
        self.onRequestDuckAIChat = onRequestDuckAIChat

        self.checklist = SubscriptionOnboardingChecklistItem.checklist(isPIRAvailable: isPIRAvailable)
        self.sequence = Self.makeSequence(entryPoint: entryPoint,
                                          completedItems: store.completedItems,
                                          isPIRAvailable: isPIRAvailable)
    }

    // MARK: - Routing

    /// The section at `index`, or `nil` past the end. Indices rather than section cases are the routing key:
    /// `.progress` appears twice in a settings-entry sequence — as the opening summary and as the closing one
    /// — with a different successor each time.
    func section(at index: Int) -> SubscriptionOnboardingSection? {
        sequence.indices.contains(index) ? sequence[index] : nil
    }

    /// Moves to the next section, or leaves the flow when there is none.
    func proceed() {
        // The sequence is frozen at flow start, but PIR completes outside it — via the summary's detour. A
        // customer who finished PIR that way has reached 100%, so the queued PIR step is stale: finish
        // instead of pushing a screen for something already done.
        let next = section(at: cursor + 1)
        guard let next, !(next == .pir && completedItems.contains(.pir)) else {
            finish()
            return
        }
        navigation.path.append(cursor + 1)
    }

    func finish() {
        onFinish()
    }

    /// Drives the `NavigationLink` that pushes the section after `index`.
    ///
    /// The setter exists for one case only: a swipe-back on the top screen, which UIKit performs itself and
    /// reports here. The back chevron goes through ``goBack(from:)`` directly, and a `false` from any
    /// shallower link is SwiftUI rebuilding the chain rather than the customer popping anything — accepting
    /// one of those would unwind every screen above it.
    func isPastSection(at index: Int) -> Binding<Bool> {
        Binding(get: { [weak self] in
            (self?.cursor ?? 0) > index
        }, set: { [weak self] isShowingNext in
            guard let self, !isShowingNext, self.cursor == index + 1 else { return }
            self.navigation.path.removeLast()
        })
    }

    /// The flow's root renders the nav bar's close button; every pushed screen renders back.
    func navigationButton(at index: Int) -> SubscriptionOnboardingNavigationButton {
        index == 0 ? .close { [weak self] in self?.finish() } : .back { [weak self] in self?.goBack(from: index) }
    }

    /// The "Step X of N" indicator, or `nil` on the screens that don't show one.
    /// Counted over *this* customer's checklist, not a static table: someone who cannot reach PIR has four
    /// steps, and telling them "Step 4 of 5" describes a fifth they will never be offered.
    func title(at index: Int) -> String? {
        guard let section = section(at: index),
              case .activation(let item) = section.kind,
              let step = checklist.firstIndex(of: item) else { return nil }
        return String(format: UserText.subscriptionOnboardingStepIndicatorFormat, step + 1, checklist.count)
    }

    /// The cursor is written in exactly two places — here and ``proceed()`` — and both are reached only from
    /// a customer action: a forward CTA, the back chevron, or a swipe-back. Nothing else may move it.
    /// Recording progress in particular must not, which is why completion notifies no one.
    private func goBack(from index: Int) {
        guard navigation.path.count >= index, index > 0 else { return }
        navigation.path.removeLast(navigation.path.count - index + 1)
    }

    // MARK: - Progress

    /// Writes to the store. That is the whole of it.
    func markComplete(_ item: SubscriptionOnboardingChecklistItem) {
        store.markComplete(item)
    }

    /// Completion over the checklist this customer actually sees, so a PIR-ineligible customer can reach 100%.
    var completionPercentage: Int {
        SubscriptionOnboardingChecklistItem.completionPercentage(completed: completedItems, checklist: checklist)
    }

    /// The summary is the celebration variant only when everything on this customer's checklist is done.
    var progressVariant: SubscriptionOnboardingProgressView.Variant {
        completionPercentage >= 100 ? .completion : .summary
    }

    // MARK: - Sequence construction

    private static func makeSequence(entryPoint: SubscriptionOnboardingEntryPoint,
                                     completedItems: Set<SubscriptionOnboardingChecklistItem>,
                                     isPIRAvailable: Bool) -> [SubscriptionOnboardingSection] {
        // Appended to both entry points, on the same rule: PIR is outstanding and this customer can reach it.
        let pirTail: [SubscriptionOnboardingSection] = isPIRAvailable && !completedItems.contains(.pir) ? [.pir] : []

        switch entryPoint {
        case .postCheckout:
            // Fixed sequence post-purchase; filtering is for re-entry only.
            return [.orderConfirmation, .welcome] + SubscriptionOnboardingSection.activationSections + [.progress] + pirTail

        case .subscriptionSettings:
            let unfinished = SubscriptionOnboardingSection.activationSections.filter { section in
                guard case .activation(let item) = section.kind else { return false }
                return !completedItems.contains(item)
            }
            // Opens and closes on summary so finishers reach 100% state.
            let body: [SubscriptionOnboardingSection] = unfinished.isEmpty ? [.progress] : [.progress] + unfinished + [.progress]
            return body + pirTail
        }
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
