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

    let flow: SubscriptionOnboardingFlowViewModel
    let factory: SubscriptionOnboardingViewFactory

    /// The root observes navigation only, for the same reason the section hosts do.
    @ObservedObject private var navigation: SubscriptionOnboardingNavigationState
    /// Separate from navigation so launching PIR cannot rebuild a section host's link.
    @ObservedObject private var pirLaunch: SubscriptionOnboardingPIRLaunchState

    private let rootSection: SubscriptionOnboardingSection?

    /// Built once and held. `factory.screen(for:)` returns a fresh `AnyView` per call, and this one is the
    /// stack's root — handing SwiftUI a different root on a body pass unwinds the whole path. The body runs
    /// whenever the presenting screen re-renders, which turning on the VPN does.
    private let rootScreen: AnyView

    init(flow: SubscriptionOnboardingFlowViewModel,
         factory: SubscriptionOnboardingViewFactory) {
        self.flow = flow
        self.factory = factory
        _navigation = ObservedObject(wrappedValue: flow.navigation)
        _pirLaunch = ObservedObject(wrappedValue: flow.pirLaunch)
        rootSection = flow.sequence.first
        rootScreen = flow.sequence.first.map { factory.screen(for: $0) } ?? AnyView(EmptyView())
    }

    var body: some View {
        stack
            .sheet(isPresented: $pirLaunch.isPresentingPIR) { factory.pirLaunchScreen() }
            .onAppear { flow.startPrefetching() }
    }

    /// iOS 16 owns the stack outright: `path` is the truth, and a pop is the system removing an element from
    /// it. iOS 15 has no `NavigationStack`, so it mirrors the same path with a chain of `NavigationLink`s
    /// whose bindings have to distinguish a real pop from a rebuild. This fork goes away with iOS 15 support.
    @ViewBuilder
    private var stack: some View {
        if #available(iOS 16.0, *) {
            NavigationStack(path: $navigation.path) {
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

/// Recursive section host: renders its screen and the link to its successor.
struct SubscriptionOnboardingSectionHost: View {

    let section: SubscriptionOnboardingSection
    let flow: SubscriptionOnboardingFlowViewModel
    let factory: SubscriptionOnboardingViewFactory

    /// Observed instead of the flow view model: a host must re-evaluate when the cursor moves and at no other
    /// time, or rebuilding its `NavigationLink` reads as a pop. See `SubscriptionOnboardingNavigationState`.
    @ObservedObject private var navigation: SubscriptionOnboardingNavigationState

    init(section: SubscriptionOnboardingSection,
         flow: SubscriptionOnboardingFlowViewModel,
         factory: SubscriptionOnboardingViewFactory) {
        self.section = section
        self.flow = flow
        self.factory = factory
        _navigation = ObservedObject(wrappedValue: flow.navigation)
    }

    var body: some View {
        // The link sits beside the screen rather than in its `.background`, so a rebuilt screen — the factory
        // hands back a fresh `AnyView` every time — cannot take the link down with it.
        ZStack {
            nextSectionLink
            factory.screen(for: section)
        }
    }

    @ViewBuilder
    private var nextSectionLink: some View {
        if let next = flow.section(after: section) {
            NavigationLink(isActive: flow.isPastSection(section)) {
                // `LazyView` and `AnyView` are both load-bearing. Without the first, rendering the root would
                // eagerly build every screen in the flow — and every view model with it. Without the second,
                // this view's body type would refer to itself and fail to compile.
                LazyView(AnyView(SubscriptionOnboardingSectionHost(section: next, flow: flow, factory: factory)))
            } label: {
                EmptyView()
            }
        }
    }
}
