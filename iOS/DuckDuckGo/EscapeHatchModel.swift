//
//  EscapeHatchModel.swift
//  DuckDuckGo
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import Foundation
import CoreGraphics
import Combine
import SwiftUI
import Persistence
import PrivacyConfig
import Core

/// Source for the live tabs array of a given browsing mode.
/// Exists so `EscapeHatchModel` can stay testable / previewable without depending on the whole `TabManaging` surface.
protocol EscapeHatchTabsSource {
    func tabsPublisher(for mode: BrowsingMode) -> AnyPublisher<[Tab], Never>
}

extension TabManager: EscapeHatchTabsSource {
    func tabsPublisher(for mode: BrowsingMode) -> AnyPublisher<[Tab], Never> {
        tabsModel(for: mode).tabsPublisher
    }
}

/// Single sink for the four escape-hatch verbs. Implemented by the object that actually fulfils the
/// actions (today: `MainViewController`). Constructors that want to build an `EscapeHatchModel` without
/// hand-bundling closures hold a weak reference to this and use `EscapeHatchModel(...,router:featureFlagger:)`.
protocol EscapeHatchActionRouter: AnyObject {
    func escapeHatchDidRequestSwitch(to tab: Tab)
    func escapeHatchDidRequestClose(_ tab: Tab)
    func escapeHatchDidRequestBurnWithConfirmation(_ tab: Tab, sourceRect: CGRect)
    func escapeHatchDidRequestBurnImmediately(_ tab: Tab)
    func escapeHatchDidRequestTabSwitcher()
    func escapeHatchDidChangeOpeningScreenOption(to option: AfterInactivityOption)
}

/// Model for the NTP "Return to..." escape hatch card that navigates to the most recently used tab.
/// Subscribes to two tab streams from `EscapeHatchTabsSource`: the target tab's mode drives
/// `isTargetTabPresent`, and the normal-mode stream drives `openTabCount` — the tab-switcher pill
/// always shows the normal-tab count, even when the hatch targets a fire tab.
/// Also bundles the four user-driven actions exposed by the escape-hatch UI so consumers thread a single
/// value through the editing-state / NTP / AI-chat stacks instead of a (model, actions) pair.
final class EscapeHatchModel: ObservableObject {

    enum TabType: Equatable {
        case regular
        case aiChat
        case fire
    }

    @Published private(set) var openTabCount: Int = 0
    @Published private(set) var isTargetTabPresent: Bool = true
    private let afterInactivityOptionAdapter: AfterInactivityOptionAdapter
    private var cancellables = [AnyCancellable]()

    let title: String
    let subtitle: String
    let tabType: TabType
    let domain: String?
    let targetTab: Tab
    let isActionsEnabled: Bool
    let onCardTap: () -> Void
    let onTabSwitcherTap: () -> Void
    let onCloseTab: () -> Void
    let onBurnTabWithConfirmation: (CGRect) -> Void
    let onBurnTabImmediately: () -> Void
    let onOpeningScreenOptionChanged: (AfterInactivityOption) -> Void

    init(title: String,
         subtitle: String,
         tabType: TabType,
         domain: String?,
         targetTab: Tab,
         tabsSource: some EscapeHatchTabsSource,
         isActionsEnabled: Bool,
         afterInactivityOptionAdapter: AfterInactivityOptionAdapter,
         onCardTap: @escaping () -> Void,
         onTabSwitcherTap: @escaping () -> Void,
         onCloseTab: @escaping () -> Void,
         onBurnTabWithConfirmation: @escaping (CGRect) -> Void,
         onBurnTabImmediately: @escaping () -> Void,
         onOpeningScreenOptionChanged: @escaping (AfterInactivityOption) -> Void = { _ in }) {
        self.title = title
        self.subtitle = subtitle
        self.tabType = tabType
        self.domain = domain
        self.targetTab = targetTab
        self.isActionsEnabled = isActionsEnabled
        self.afterInactivityOptionAdapter = afterInactivityOptionAdapter
        self.onCardTap = onCardTap
        self.onTabSwitcherTap = onTabSwitcherTap
        self.onCloseTab = onCloseTab
        self.onBurnTabWithConfirmation = onBurnTabWithConfirmation
        self.onBurnTabImmediately = onBurnTabImmediately
        self.onOpeningScreenOptionChanged = onOpeningScreenOptionChanged

        subscribeToTabsSource(tabsSource)
        startForwardingAdapterWillChangeEvents(afterInactivityOptionAdapter)
    }

    /// Builds the model with action closures wired to a router. The router is captured weakly so holders of `EscapeHatchModel` don't pin its owner's lifecycle.
    ///
    convenience init(title: String, subtitle: String, tabType: TabType, domain: String?, targetTab: Tab, tabsSource: some EscapeHatchTabsSource, router: EscapeHatchActionRouter, featureFlagger: FeatureFlagger, afterInactivityOptionAdapter: AfterInactivityOptionAdapter) {
        self.init(
            title: title,
            subtitle: subtitle,
            tabType: tabType,
            domain: domain,
            targetTab: targetTab,
            tabsSource: tabsSource,
            isActionsEnabled: featureFlagger.isFeatureOn(.escapeHatchActions),
            afterInactivityOptionAdapter: afterInactivityOptionAdapter,
            onCardTap: { [weak router] in
                router?.escapeHatchDidRequestSwitch(to: targetTab)
            },
            onTabSwitcherTap: { [weak router] in
                router?.escapeHatchDidRequestTabSwitcher()
            },
            onCloseTab: { [weak router] in
                router?.escapeHatchDidRequestClose(targetTab)
            },
            onBurnTabWithConfirmation: { [weak router] sourceRect in
                router?.escapeHatchDidRequestBurnWithConfirmation(targetTab, sourceRect: sourceRect)
            },
            onBurnTabImmediately: { [weak router] in
                router?.escapeHatchDidRequestBurnImmediately(targetTab)
            },
            onOpeningScreenOptionChanged: { [weak router] option in
                router?.escapeHatchDidChangeOpeningScreenOption(to: option)
            }
        )
    }
}

extension EscapeHatchModel {

    /// Pairs the user-facing label for the primary swipe gesture with the closure it fires.
    /// Bundled so the view can ask one question ("what does swipe do?") instead of branching
    /// on tab type once per call site.
    struct SwipeAction {
        let label: String
        let perform: () -> Void
    }

    /// Wraps the adapter's binding so writes from the Escape Hatch UI fire `onOpeningScreenOptionChanged`.
    /// Mirrors `SettingsViewModel.afterInactivityOptionBinding` — each surface owns its own pixel via its own binding,
    /// so observing the adapter's `@Published` would conflate sources.
    var afterInactivityOptionBinding: Binding<AfterInactivityOption> {
        let upstream = afterInactivityOptionAdapter.afterInactivityOptionBinding
        return Binding<AfterInactivityOption>(
            get: { upstream.wrappedValue },
            set: { [weak self] newValue in
                upstream.wrappedValue = newValue
                self?.onOpeningScreenOptionChanged(newValue)
            }
        )
    }

    var isFireTab: Bool {
        targetTab.mode == .fire
    }

    /// Fire tabs have no soft-close semantics, so swipe defaults to burn-immediately.
    /// Everything else defaults to close.
    var primarySwipeAction: SwipeAction {
        isFireTab
            ? SwipeAction(label: UserText.escapeHatchMenuBurnTab, perform: onBurnTabImmediately)
            : SwipeAction(label: UserText.escapeHatchMenuCloseTab, perform: onCloseTab)
    }
}

private extension EscapeHatchModel {

    func subscribeToTabsSource(_ tabsSource: some EscapeHatchTabsSource) {
        let targetTab = self.targetTab

        // # Important
        //      `openTabCount` must reflect the Tabs in `.normal`, but `targetTab.mode` might belong to `.fire`.
        //      We'll avoid double subscription, when possible
        //
        let observedTabModes = Set<BrowsingMode>([targetTab.mode, .normal])

        for tabMode in observedTabModes {
            tabsSource.tabsPublisher(for: tabMode)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] tabs in
                    self?.processTabsUpdate(targetTab: targetTab, allTabs: tabs, mode: tabMode)
                }
                .store(in: &cancellables)
        }
    }

    func processTabsUpdate(targetTab: Tab, allTabs: [Tab], mode: BrowsingMode) {
        if mode == targetTab.mode {
            isTargetTabPresent = allTabs.contains { $0 === targetTab }
        }

        if mode == .normal {
            openTabCount = allTabs.count
        }
    }

    /// Forward `AfterInactivityOptionAdapter.objectWillChange` Events:
    /// This causes `model.afterInactivityOptionBinding` to react to `AfterInactivityOptionAdapter` changes
    ///
    func startForwardingAdapterWillChangeEvents(_ adapter: AfterInactivityOptionAdapter) {
        adapter.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}

extension EscapeHatchModel: Equatable {
    static func == (lhs: EscapeHatchModel, rhs: EscapeHatchModel) -> Bool {
        lhs.targetTab === rhs.targetTab &&
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        lhs.tabType == rhs.tabType &&
        lhs.domain == rhs.domain
    }
}
