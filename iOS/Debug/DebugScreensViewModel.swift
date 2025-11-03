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
import BrowserServicesKit
import Combine
import Core
import Configuration

/// The view mode for the debug view.  You shouldn't have to add or change anything here.
///  Please add new views/controllers to DebugScreensViewModel+Screens.swift.
public class DebugScreensViewModel: ObservableObject {

    @Published public var isInternalUser = false {
        didSet {
            persisteInternalUserState()
        }
    }

    @Published public var isInspectibleWebViewsEnabled = false {
        didSet {
            persistInspectibleWebViewsState()
        }
    }

    @Published public var filter = "" {
        didSet {
            refreshFilter()
        }
    }

    @Published public var pinnedScreens: [DebugScreen] = []
    @Published public var unpinnedScreens: [DebugScreen] = []
    @Published public var actions: [DebugScreen] = []
    @Published public var filtered: [DebugScreen] = []

    @UserDefaultsWrapper(key: .debugPinnedScreens, defaultValue: [])
    var pinnedTitles: [String]

    var dependencies: AnyDebugDependencies
    var screens: [DebugScreen]

    public var pushController: ((UIViewController) -> Void)?

    var cancellables = Set<AnyCancellable>()

    public init(dependencies: AnyDebugDependencies, screens: [DebugScreen] = []) {
        self.dependencies = dependencies
        self.screens = screens
        refreshFilter()
        refreshToggles()
    }

    public func persisteInternalUserState() {
        (dependencies.internalUserDecider as? DefaultInternalUserDecider)?
            .debugSetInternalUserState(isInternalUser)
    }

    public func persistInspectibleWebViewsState() {
        let oldValue = dependencies.inspectableWebViewEnabled
        dependencies.inspectableWebViewEnabled = isInspectibleWebViewsEnabled

        if oldValue != isInspectibleWebViewsEnabled {
            dependencies.postinspectableWebViewsToggled()
        }
    }

    public func refreshToggles() {
        self.isInternalUser = dependencies.internalUserDecider.isInternalUser
        self.isInspectibleWebViewsEnabled = dependencies.inspectableWebViewEnabled
    }

    public func refreshFilter() {
        func sorter(screen1: DebugScreen, screen2: DebugScreen) -> Bool {
            screen1.title < screen2.title
        }

        self.actions = screens.filter { $0.isAction && !self.isPinned($0) }.sorted(by: sorter)
        self.unpinnedScreens = screens.filter { !$0.isAction && !self.isPinned($0) }.sorted(by: sorter)
        self.pinnedScreens = screens.filter { self.isPinned($0) }.sorted(by: sorter)

        if filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.filtered = []
        } else {
            self.filtered = screens.filter {
                $0.title.lowercased().contains(filter.lowercased())
            }.sorted(by: sorter)
        }
    }

    public func executeAction(_ screen: DebugScreen) {
        switch screen {
        case .action(_, let action):
            action(self.dependencies)
            DebugMessageView.present(message: "\(screen.title) - DONE")

        case .view, .controller:
            assertionFailure("Should not be pushing SwiftUI view as controller")
        }
    }

    public func navigateToController(_ screen: DebugScreen) {
        switch screen {
        case .controller(_, let controllerBuilder):
            pushController?(controllerBuilder(self.dependencies))
        case .view, .action:
            assertionFailure("Should not be pushing SwiftUI view as controller")
        }
    }

    public func buildView(_ screen: DebugScreen) -> AnyView {
        switch screen {
        case .controller, .action:
            return AnyView(FailedAssertionView("Unexpected view creation"))

        case .view(_, let viewBuilder):
            return AnyView(viewBuilder(self.dependencies))
        }
    }

    public func isPinned(_ screen: DebugScreen) -> Bool {
        return Set<String>(pinnedTitles).contains(screen.title)
    }

    public func togglePin(_ screen: DebugScreen) {
        if isPinned(screen) {
            var set = Set<String>(pinnedTitles)
            set.remove(screen.title)
            pinnedTitles = Array(set)
        } else {
            pinnedTitles.append(screen.title)
        }
        refreshFilter()
    }

    func setCustomURL(_ url: URL?, for configuration: Configuration) {
        do {
            try dependencies.customConfigurationURLProvider.setCustomURL(url, for: configuration)
        } catch {
            DebugMessageView.present(message: "Failed to set custom URL: \(error.localizedDescription)")
        }
    }

    func urlString(for configuration: Configuration) -> String {
        dependencies.customConfigurationURLProvider.url(for: configuration).absoluteString
    }

    private func isURLOverridden(for configuration: Configuration) -> Bool {
        dependencies.customConfigurationURLProvider.isURLOverridden(for: configuration)
    }

    // MARK: - Configuration Management

    struct ConfigurationItem {
        let configuration: Configuration
        let title: String
        let fetchAction: () -> Void

        static func privacyConfiguration(fetchAction: @escaping () -> Void) -> ConfigurationItem {
            return ConfigurationItem(
                configuration: .privacyConfiguration,
                title: "Privacy Config",
                fetchAction: fetchAction
            )
        }

        static func remoteMessagingConfiguration(fetchAction: @escaping () -> Void) -> ConfigurationItem {
            return ConfigurationItem(
                configuration: .remoteMessagingConfig,
                title: "Remote Message Framework Config",
                fetchAction: fetchAction
            )
        }
    }

    @UserDefaultsWrapper(key: .lastConfigurationUpdateDate, defaultValue: nil)
    private var lastConfigurationUpdateDate: Date?
    
    func getLastConfigurationUpdateDate() -> Date? {
        return lastConfigurationUpdateDate
    }

    func getConfigurationItems() -> [ConfigurationItem] {
        return [
            .privacyConfiguration { [weak self] in
                self?.fetchPrivacyConfiguration { _ in }
            },
            .remoteMessagingConfiguration { [weak self] in
                self?.fetchRemoteMessagingConfiguration()
            }
        ]
    }

    func getURL(for configuration: Configuration) -> String {
        return urlString(for: configuration)
    }

    func getCustomURL(for configuration: Configuration) -> String? {
        guard isURLOverridden(for: configuration) else { return nil }
        return urlString(for: configuration)
    }

    func fetchPrivacyConfiguration(completion: @escaping (Bool) -> Void) {
        dependencies.fetchPrivacyConfiguration(completion)
    }

    func fetchRemoteMessagingConfiguration() {
        dependencies.fetchRemoteMessagingConfiguration()
    }

    func fetchConfiguration(for configuration: Configuration, completion: @escaping (Bool) -> Void = { _ in }) {
        switch configuration {
        case .privacyConfiguration:
            fetchPrivacyConfiguration(completion: completion)
        case .remoteMessagingConfig:
            fetchRemoteMessagingConfiguration()
            completion(true)
        default:
            // For other configurations, just trigger a general fetch
            fetchPrivacyConfiguration(completion: completion)
        }
    }

    func resetAllCustomURLs() {
        for item in getConfigurationItems() {
            setCustomURL(nil, for: item.configuration)
        }
    }

}
