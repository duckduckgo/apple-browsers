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

// (TODO|Post-iOS15-Drop): fold back into the flow view model
/// The PIR launch's presentation
@MainActor
final class SubscriptionOnboardingPIRLaunchState: ObservableObject {
    @Published var isPresentingPIR = false
}

/// Drives the onboarding flow, pushing along a frozen sequence of sections.
@MainActor
final class SubscriptionOnboardingFlowViewModel: ObservableObject {

    // MARK: - Navigation

    /// Sections this run walks through, frozen at init.
    let sequence: [SubscriptionOnboardingSection]

    /// The pushed sections, root excluded. Must stay the *sole* `@Published` member: anything else
    /// republishing rebuilds a section host's `NavigationLink`, which reads as a pop.
    // (TODO|Post-iOS15-Drop): constraint lifts — other state may share this publisher.
    @Published var path: [SubscriptionOnboardingSection] = []

    /// The section on screen.
    var currentSection: SubscriptionOnboardingSection? { path.last ?? sequence.first }

    // (TODO|Post-iOS15-Drop): delete — only `isPastSection(_:)` reads it.
    private var depth: Int { path.count }

    // MARK: - PIR

    let pirLaunch = SubscriptionOnboardingPIRLaunchState()

    /// Presented rather than pushed: PIR is not in the sequence, and the row that launches it can be tapped
    /// from a summary the customer reaches at any point.
    var isPresentingPIR: Bool {
        get { pirLaunch.isPresentingPIR }
        set { pirLaunch.isPresentingPIR = newValue }
    }

    /// The Data Broker Protection screen, erased once here so callers hand over a plain view. Unreachable
    /// unless `isPIRAvailable`
    let pirScreen: () -> AnyView

    /// Both edges of the PIR sheet, reported from the summary's own observation of `pirLaunch`
    func reportPIRPresentation(_ isPresenting: Bool) {
        if isPresenting {
            instrumentation.stepShown(.pir)
        } else if progress.completedItems.contains(.pir) {
            instrumentation.stepCompleted(.pir)
        }
    }

    // MARK: - Progress

    /// The flow writes completion into this and reads it twice — for the step indicator and, once at launch,
    /// to skip finished sections.
    var progress: SubscriptionOnboardingProgress

    // MARK: - Dependencies

    /// Screens read cached results from this rather than fetching for themselves.
    let prefetcher: SubscriptionOnboardingPrefetcher

    let instrumentation: SubscriptionOnboardingInstrumenting

    private let onFinish: () -> Void
    private let onRequestDuckAIChat: (String?) -> Bool

    // MARK: - Init

    /// `prefetcher` and `onRequestDuckAIChat` are defaulted inside the body rather than in the signature:
    /// default arguments are evaluated in a nonisolated context, and both resolve main-actor isolated types.
    init<PIRScreen: View>(entryPoint: SubscriptionOnboardingEntryPoint,
                          progress: SubscriptionOnboardingProgress,
                          onFinish: @escaping () -> Void = {},
                          prefetcher: SubscriptionOnboardingPrefetcher? = nil,
                          onRequestDuckAIChat: ((String?) -> Bool)? = nil,
                          instrumentation: SubscriptionOnboardingInstrumenting? = nil,
                          @ViewBuilder pirScreen: @escaping () -> PIRScreen) {
        self.progress = progress
        self.onFinish = onFinish
        self.prefetcher = prefetcher ?? SubscriptionOnboardingPrefetcher()
        self.instrumentation = instrumentation ?? SubscriptionOnboardingInstrumentation(entryPoint: entryPoint)
        self.pirScreen = { AnyView(pirScreen()) }
        if let onRequestDuckAIChat {
            self.onRequestDuckAIChat = onRequestDuckAIChat
        } else {
            let chatLauncher = SubscriptionOnboardingDuckAIChatLauncher()
            self.onRequestDuckAIChat = { chatLauncher.launch(modelID: $0) }
        }

        switch entryPoint {
        case .postCheckout:
            self.sequence = Self.makePostCheckoutSequence(checklist: self.progress.checklist,
                                                          completedItems: self.progress.completedItems)
        case .subscriptionSettings:
            self.sequence = Self.makeSubscriptionSettingsSequence(checklist: self.progress.checklist,
                                                                  completedItems: self.progress.completedItems)
        }
    }

    /// Kicked off when the flow appears.
    func startPrefetching() {
        instrumentation.flowStarted()
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
        path.append(next)
    }

    func finish() {
        onFinish()
    }

    // (TODO|Post-iOS15-Drop): delete this and its four tests — `NavigationStack` drives itself from `path`.
    /// Drives the `NavigationLink` that pushes the section after `section`.
    func isPastSection(_ section: SubscriptionOnboardingSection) -> Binding<Bool> {
        Binding(get: { [weak self] in
            guard let self, let index = self.sequence.firstIndex(of: section) else { return false }
            return self.depth > index
        }, set: { [weak self] isShowingNext in
            guard let self, !isShowingNext,
                  let index = self.sequence.firstIndex(of: section),
                  self.depth == index + 1 else { return }
            self.path.removeLast()
        })
    }

    /// Close button for the root screen; back button for pushed screens.
    func navigationButton(for section: SubscriptionOnboardingSection) -> SubscriptionOnboardingNavigationButton {
        section == sequence.first
            ? .close { [weak self] in self?.finish() }
            : .back { [weak self] in self?.goBack(from: section) }
    }

    /// The "Step X of N" indicator counted over this customer's checklist
    func title(for section: SubscriptionOnboardingSection) -> String? {
        guard case .activation(let item) = section.kind,
              let step = progress.checklist.firstIndex(of: item) else { return nil }
        return String(format: UserText.subscriptionOnboardingStepIndicatorFormat,
                      step + 1,
                      progress.checklist.count)
    }

    /// Reached from the back chevron only.
    private func goBack(from section: SubscriptionOnboardingSection) {
        guard let position = path.firstIndex(of: section) else { return }
        path.removeSubrange(position...)
    }
}

// MARK: - Sequence construction

private extension SubscriptionOnboardingFlowViewModel {

    /// Entitled sections not yet completed. Shared by both entry points: an item can already be complete
    /// before this run starts via an out-of-flow signal
    static func unfinishedEntitledSections(checklist: [SubscriptionOnboardingChecklistItem],
                                           completedItems: Set<SubscriptionOnboardingChecklistItem>)
    -> [SubscriptionOnboardingSection] {
        SubscriptionOnboardingSection.activationSections.compactMap { section in
            guard case .activation(let item) = section.kind,
                  checklist.contains(item),
                  !completedItems.contains(item) else { return nil }
            return section
        }
    }

    static func makePostCheckoutSequence(checklist: [SubscriptionOnboardingChecklistItem],
                                         completedItems: Set<SubscriptionOnboardingChecklistItem>)
    -> [SubscriptionOnboardingSection] {
        let unfinished = unfinishedEntitledSections(checklist: checklist, completedItems: completedItems)
        return [.orderConfirmation, .welcome] + unfinished + [.progress]
    }

    /// Resumes at the first unfinished entitled section.
    static func makeSubscriptionSettingsSequence(checklist: [SubscriptionOnboardingChecklistItem],
                                                 completedItems: Set<SubscriptionOnboardingChecklistItem>)
    -> [SubscriptionOnboardingSection] {
        unfinishedEntitledSections(checklist: checklist, completedItems: completedItems) + [.progress]
    }
}

// MARK: - SubscriptionOnboardingSectionDelegate

/// Recording a completion
extension SubscriptionOnboardingFlowViewModel: SubscriptionOnboardingSectionDelegate {

    func sectionDidComplete(_ section: SubscriptionOnboardingSection) {
        if case .activation(let item) = section.kind {
            guard !progress.completedItems.contains(item) else { return }
            progress.markComplete(item)
        }
        instrumentation.stepCompleted(section)
    }

    func sectionDidRequestAdvance() {
        reportSkipIfNeeded()
        proceed()
    }

    /// The two sections with a skip CTA.
    private func reportSkipIfNeeded() {
        switch currentSection {
        case .vpnActivation:
            // An incomplete VPN means the customer skipped.
            if !progress.completedItems.contains(.vpn) {
                instrumentation.stepSkipped(.vpnActivation)
            }
        case .duckAI:
            // Advancing means user skipped the step
            instrumentation.stepSkipped(.duckAI)
        default:
            break
        }
    }

    func sectionDidRequestDuckAIChat(modelID: String?) -> Bool {
        onRequestDuckAIChat(modelID)
    }
}
