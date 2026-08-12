//
//  SubscriptionOnboardingFlowView.swift
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

struct SubscriptionOnboardingFlowView: View {

    /// Observed for `path` and nothing else — see its documentation on the view model.
    @ObservedObject var flow: SubscriptionOnboardingFlowViewModel
    let factory: SubscriptionOnboardingViewFactory

    /// Separate from the flow view model so a PIR toggle cannot rebuild a section host's link.
    // (TODO|Post-iOS15-Drop): observe the flow view model instead.
    @ObservedObject private var pirLaunch: SubscriptionOnboardingPIRLaunchState

    // (TODO|Post-iOS15-Drop): delete — the `NavigationStack` branch renders `rootScreen`.
    private let rootSection: SubscriptionOnboardingSection?

    /// Built once and held. `factory.screen(for:)` returns a fresh `AnyView` per call, and this one is the
    /// stack's root
    private let rootScreen: AnyView

    init(flow: SubscriptionOnboardingFlowViewModel,
         factory: SubscriptionOnboardingViewFactory) {
        _flow = ObservedObject(wrappedValue: flow)
        self.factory = factory
        _pirLaunch = ObservedObject(wrappedValue: flow.pirLaunch)
        rootSection = flow.sequence.first
        rootScreen = flow.sequence.first.map { factory.screen(for: $0) } ?? AnyView(EmptyView())
    }

    var body: some View {
        stack
            .sheet(isPresented: $pirLaunch.isPresentingPIR) { factory.pirLaunchScreen() }
            .onFirstAppear { flow.startPrefetching() }
    }

    // (TODO|Post-iOS15-Drop): drop the fork and keep the `NavigationStack` branch.
    @ViewBuilder
    private var stack: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $flow.path) {
                rootScreen
                    .navigationDestination(for: SubscriptionOnboardingSection.self) { section in
                        factory.screen(for: section)
                    }
                    .subscriptionOnboardingInteractivePopEnabled()
            }
        } else if let rootSection {
            SubscriptionOnboardingSectionHost(section: rootSection, flow: flow, factory: factory)
                .subscriptionOnboardingNavigationContainer()
        }
    }
}

// (TODO|Post-iOS15-Drop): delete this whole type — `NavigationStack` + `navigationDestination` replace it.
/// Recursive section host: renders its screen and the link to its successor.
struct SubscriptionOnboardingSectionHost: View {

    let section: SubscriptionOnboardingSection

    @ObservedObject var flow: SubscriptionOnboardingFlowViewModel

    let factory: SubscriptionOnboardingViewFactory

    var body: some View {
        // The link sits beside the screen
        ZStack {
            nextSectionLink
            factory.screen(for: section)
        }
    }

    @ViewBuilder
    private var nextSectionLink: some View {
        if let next = flow.section(after: section) {
            NavigationLink(isActive: flow.isPastSection(section)) {
                LazyView(AnyView(SubscriptionOnboardingSectionHost(section: next, flow: flow, factory: factory)))
            } label: {
                EmptyView()
            }
        }
    }
}
