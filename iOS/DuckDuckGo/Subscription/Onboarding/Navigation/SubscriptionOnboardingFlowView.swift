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

/// The onboarding flow's root: the first section, inside the shared navigation container.
struct SubscriptionOnboardingFlowView: View {

    let flow: SubscriptionOnboardingFlowViewModel
    let factory: SubscriptionOnboardingViewFactory
    /// The PIR detour reached by tapping the summary's PIR row, presented rather than pushed — the row can
    /// be tapped from a summary that sits several sections before `.pir`, which a linear stack can't express.
    let pirDetour: () -> AnyView

    /// The root observes navigation only, for the same reason the section hosts do.
    @ObservedObject private var navigation: SubscriptionOnboardingNavigationState
    /// Separate from navigation so presenting the detour cannot rebuild a section host's link.
    @ObservedObject private var detour: SubscriptionOnboardingDetourState

    /// Built once and held. `factory.screen(at:)` returns a fresh `AnyView` per call, and this one is the
    /// stack's root — handing SwiftUI a different root on a body pass unwinds the whole path. The body runs
    /// whenever the presenting screen re-renders, which turning on the VPN does.
    private let rootScreen: AnyView

    init(flow: SubscriptionOnboardingFlowViewModel,
         factory: SubscriptionOnboardingViewFactory,
         pirDetour: @escaping () -> AnyView) {
        self.flow = flow
        self.factory = factory
        self.pirDetour = pirDetour
        _navigation = ObservedObject(wrappedValue: flow.navigation)
        _detour = ObservedObject(wrappedValue: flow.detour)
        rootScreen = factory.screen(at: 0)
    }

    var body: some View {
        stack
            .sheet(isPresented: $detour.isPresentingPIR) { pirDetour() }
    }

    /// iOS 16 owns the stack outright: `path` is the truth, and a pop is the system removing an element from
    /// it. iOS 15 has no `NavigationStack`, so it mirrors the same path with a chain of `NavigationLink`s
    /// whose bindings have to distinguish a real pop from a rebuild. This fork goes away with iOS 15 support.
    @ViewBuilder
    private var stack: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $navigation.path) {
                rootScreen
                    .navigationDestination(for: Int.self) { index in
                        factory.screen(at: index)
                    }
                    .subscriptionOnboardingInteractivePopEnabled()
            }
        } else {
            SubscriptionOnboardingSectionHost(index: 0, flow: flow, factory: factory)
                .subscriptionOnboardingNavigationContainer()
        }
    }
}

/// One section of the flow, plus the link that pushes the next one.
///
/// Recursive by design: each host renders its own screen and holds a `NavigationLink` to its successor, so
/// the stack mirrors `flow.cursor` without any imperative push.
struct SubscriptionOnboardingSectionHost: View {

    let index: Int
    let flow: SubscriptionOnboardingFlowViewModel
    let factory: SubscriptionOnboardingViewFactory

    /// Observed instead of the flow view model: a host must re-evaluate when the cursor moves and at no other
    /// time, or rebuilding its `NavigationLink` reads as a pop. See `SubscriptionOnboardingNavigationState`.
    @ObservedObject private var navigation: SubscriptionOnboardingNavigationState

    init(index: Int, flow: SubscriptionOnboardingFlowViewModel, factory: SubscriptionOnboardingViewFactory) {
        self.index = index
        self.flow = flow
        self.factory = factory
        _navigation = ObservedObject(wrappedValue: flow.navigation)
    }

    var body: some View {
        // The link sits beside the screen rather than in its `.background`, so a rebuilt screen — the factory
        // hands back a fresh `AnyView` every time — cannot take the link down with it.
        ZStack {
            nextSectionLink
            factory.screen(at: index)
        }
    }

    @ViewBuilder
    private var nextSectionLink: some View {
        if flow.section(at: index + 1) != nil {
            NavigationLink(isActive: flow.isPastSection(at: index)) {
                // `LazyView` and `AnyView` are both load-bearing. Without the first, rendering the root would
                // eagerly build every screen in the flow — and every view model with it. Without the second,
                // this view's body type would refer to itself and fail to compile.
                LazyView(AnyView(SubscriptionOnboardingSectionHost(index: index + 1, flow: flow, factory: factory)))
            } label: {
                EmptyView()
            }
        }
    }
}
