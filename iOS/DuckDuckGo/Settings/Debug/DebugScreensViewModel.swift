//
//  DebugScreensViewModel.swift
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
import SwiftUI
import UIKit
import PrivacyConfig
import Combine
import Core
import Configuration
import FeatureFlags_iOS

/// The view mode for the debug view.  You shouldn't have to add or change anything here.
///  Please add new views/controllers to DebugScreensViewModel+Screens.swift.
@MainActor
class DebugScreensViewModel: ObservableObject {

    @Published var isInternalUser = false {
        didSet {
            persisteInternalUserState()
        }
    }

    @Published var isInspectibleWebViewsEnabled = false {
        didSet {
            persistInspectibleWebViewsState()
        }
    }

    @Published var isShakeToOpenDebugMenuEnabled = true {
        didSet {
            AppUserDefaults().shakeToOpenDebugMenuEnabled = isShakeToOpenDebugMenuEnabled
        }
    }

    @Published var isSlowAnimationsEnabled = false {
        didSet {
            guard oldValue != isSlowAnimationsEnabled else { return }
            AppUserDefaults().slowAnimationsEnabled = isSlowAnimationsEnabled
            Self.applySlowAnimations(enabled: isSlowAnimationsEnabled)
        }
    }

    @Published var filter = "" {
        didSet {
            refreshFilter()
        }
    }

    @Published var pinnedScreens: [DebugScreen] = []
    @Published var unpinnedScreens: [DebugScreen] = []
    @Published var actions: [DebugScreen] = []
    @Published var filtered: [DebugScreen] = []
    @Published var filteredFeatureFlags: [FeatureFlag] = []

    var isSearching: Bool {
        !filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @UserDefaultsWrapper(key: .debugPinnedScreens, defaultValue: [])
    var pinnedTitles: [String]

    let dependencies: DebugScreen.Dependencies
    private let options = IOSDebugOptions.shared
    private let featureFlagger: FeatureFlagger = AppDependencyProvider.shared.featureFlagger

    var pushController: ((UIViewController) -> Void)?

    var cancellables = Set<AnyCancellable>()
    private var isVisible = false

    lazy var debugStoryboard = {
        UIStoryboard(name: "Debug", bundle: nil)
    }()

    init(dependencies: DebugScreen.Dependencies) {
        self.dependencies = dependencies
        refreshFilter()
        refreshToggles()
        options.objectWillChange.sink { [weak self] in
            guard let self, isVisible else { return }
            if isInternalUser != options.isInternalUser {
                isInternalUser = options.isInternalUser
                refreshFilter()
            } else if isSearching {
                objectWillChange.send()
            }
        }.store(in: &cancellables)
    }

    func didAppear() {
        isVisible = true
        refreshToggles()
        refreshFilter()
    }

    func didDisappear() {
        isVisible = false
    }

    func persisteInternalUserState() {
        options.setInternalUser(isInternalUser)
    }

    func persistInspectibleWebViewsState() {
        let defaults = AppUserDefaults()
        let oldValue = defaults.inspectableWebViewEnabled
        defaults.inspectableWebViewEnabled = isInspectibleWebViewsEnabled

        if oldValue != isInspectibleWebViewsEnabled {
            NotificationCenter.default.post(Notification(name: AppUserDefaults.Notifications.inspectableWebViewsToggled))
        }
    }

    func refreshToggles() {
        self.isInternalUser = dependencies.internalUserDecider.isInternalUser
        self.isInspectibleWebViewsEnabled = AppUserDefaults().inspectableWebViewEnabled
        self.isShakeToOpenDebugMenuEnabled = AppUserDefaults().shakeToOpenDebugMenuEnabled
        self.isSlowAnimationsEnabled = AppUserDefaults().slowAnimationsEnabled
    }

    /// Matches Simulator Debug → Slow Animations (~10×) by slowing every window's layer clock.
    static func applySlowAnimations(enabled: Bool) {
        let speed = enabled ? AppUserDefaults.slowAnimationsLayerSpeed : 1.0
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for sceneWindow in windowScene.windows {
                sceneWindow.layer.speed = speed
            }
        }
    }

    func refreshFilter() {
        func sorter(screen1: DebugScreen, screen2: DebugScreen) -> Bool {
            screen1.title < screen2.title
        }

        self.actions = screens.filter { $0.isAction && !self.isPinned($0) }.sorted(by: sorter)
        self.unpinnedScreens = screens.filter { !$0.isAction && !self.isPinned($0) }.sorted(by: sorter)
        self.pinnedScreens = screens.filter { self.isPinned($0) }.sorted(by: sorter)

        let trimmedFilter = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedFilter.isEmpty {
            self.filtered = []
            self.filteredFeatureFlags = []
        } else {
            self.filtered = screens.filter {
                $0.title.lowercased().contains(filter.lowercased())
            }.sorted(by: sorter)
            self.filteredFeatureFlags = isInternalUser ? FeatureFlag.allCases.filter {
                $0.supportsLocalOverriding && $0.cohortType == nil && $0.rawValue.localizedCaseInsensitiveContains(trimmedFilter)
            }.sorted(by: { $0.rawValue < $1.rawValue }) : []
        }
    }

    @MainActor
    func executeAction(_ screen: DebugScreen) {
        switch screen {
        case .action(_, let action):
            action(self.dependencies)
            ActionMessageView.present(message: "\(screen.title) - DONE")

        case .view, .controller:
            assertionFailure("Should not be pushing SwiftUI view as controller")
        }
    }

    func navigateToController(_ screen: DebugScreen) {
        switch screen {
        case .controller(_, let controllerBuilder):
            pushController?(controllerBuilder(self.dependencies))
        case .view, .action:
            assertionFailure("Should not be pushing SwiftUI view as controller")
        }
    }

    func buildView(_ screen: DebugScreen) -> AnyView {
        switch screen {
        case .controller, .action:
            return AnyView(FailedAssertionView("Unexpected view creation"))

        case .view(_, let viewBuilder):
            return AnyView(viewBuilder(self.dependencies))
        }
    }

    func isPinned(_ screen: DebugScreen) -> Bool {
        return Set<String>(pinnedTitles).contains(screen.title)
    }

    func togglePin(_ screen: DebugScreen) {
        if isPinned(screen) {
            var set = Set<String>(pinnedTitles)
            set.remove(screen.title)
            pinnedTitles = Array(set)
        } else {
            pinnedTitles.append(screen.title)
        }
        refreshFilter()
    }

    func isFeatureFlagEnabled(_ flag: FeatureFlag) -> Bool {
        featureFlagger.isFeatureOn(for: flag)
    }

    func setFeatureFlag(_ flag: FeatureFlag, enabled: Bool) {
        do { try options.featureFlags.setEnabled(enabled, for: flag) } catch { options.report(error) }
    }

    func requiresRelaunch(_ flag: FeatureFlag) -> Bool {
        options.featureFlags.activation(for: flag) == "nextLaunch"
    }

    func resetFeatureFlagOverride(_ flag: FeatureFlag) {
        do { try options.featureFlags.reset(flag) } catch { options.report(error) }
    }

    func featureFlagDefaultValue(_ flag: FeatureFlag) -> Bool {
        featureFlagger.isFeatureOn(for: flag, allowOverride: false)
    }

    func setCustomURL(_ url: String?, for configuration: Configuration) {
        Task {
            do {
                if let url {
                    _ = try await options.configurations.setURL(url, for: configuration)
                } else {
                    _ = try await options.configurations.reset(configuration)
                }
            } catch { options.report(error) }
        }
    }

    // MARK: - Configuration Management

    struct ConfigurationItem {
        let configuration: Configuration
        let title: String
    }

    func getLastConfigurationUpdateDate(for configuration: Configuration) -> Date? {
        options.configurations.lastRefreshDate(for: configuration)
    }

    func getConfigurationItems() -> [ConfigurationItem] {
        [
            .init(configuration: .privacyConfiguration, title: "Privacy Config"),
            .init(configuration: .remoteMessagingConfig, title: "Remote Message Framework Config")
        ]
    }

    func getURL(for configuration: Configuration) -> String {
        dependencies.customConfigurationURLProvider.url(for: configuration).absoluteString
    }

    func getCustomURL(for configuration: Configuration) -> String? {
        dependencies.customConfigurationURLProvider.state(for: configuration).savedOverrideURL?.absoluteString
    }

    func fetchConfiguration(for configuration: Configuration) {
        Task {
            do {
                _ = try await options.configurations.refresh(configuration)
            } catch { options.report(error) }
        }
    }

    func resetAllCustomURLs() {
        for item in getConfigurationItems() {
            setCustomURL(nil, for: item.configuration)
        }
    }

}
