//
//  ApplicationShortcutItemsService.swift
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

import Combine
import Subscription
import UIKit

@MainActor
final class ApplicationShortcutItemsService {

    typealias ShortcutItemProvider = @MainActor () async -> UIApplicationShortcutItem?
    typealias ApplicationStateProvider = @MainActor () -> UIApplication.State
    typealias CurrentShortcutItemsProvider = @MainActor () -> [UIApplicationShortcutItem]
    typealias ShortcutItemsFilter = @MainActor ([UIApplicationShortcutItem]) -> [UIApplicationShortcutItem]
    typealias ShortcutItemsUpdater = @MainActor ([UIApplicationShortcutItem]) -> Void

    private let shortcutItemProviders: [ShortcutItemProvider]
    private let applicationStateProvider: ApplicationStateProvider
    private let currentShortcutItemsProvider: CurrentShortcutItemsProvider
    private let shortcutItemsFilter: ShortcutItemsFilter
    private let shortcutItemsUpdater: ShortcutItemsUpdater
    private var refreshTask: Task<Void, Never>?
    private var isActive = false
    private var cancellables: Set<AnyCancellable> = []

    init(shortcutItemProviders: [ShortcutItemProvider],
         notificationCenter: NotificationCenter = .default,
         applicationStateProvider: @escaping ApplicationStateProvider = { UIApplication.shared.applicationState },
         currentShortcutItemsProvider: @escaping CurrentShortcutItemsProvider = { UIApplication.shared.shortcutItems ?? [] },
         shortcutItemsFilter: @escaping ShortcutItemsFilter = { $0 },
         shortcutItemsUpdater: @escaping ShortcutItemsUpdater = { UIApplication.shared.shortcutItems = $0 }) {
        self.shortcutItemProviders = shortcutItemProviders
        self.applicationStateProvider = applicationStateProvider
        self.currentShortcutItemsProvider = currentShortcutItemsProvider
        self.shortcutItemsFilter = shortcutItemsFilter
        self.shortcutItemsUpdater = shortcutItemsUpdater

        Publishers.MergeMany([
            notificationCenter.publisher(for: .aiChatSettingsChanged),
            notificationCenter.publisher(for: .accountDidSignIn),
            notificationCenter.publisher(for: .accountDidSignOut),
            notificationCenter.publisher(for: .entitlementsDidChange),
            notificationCenter.publisher(for: .subscriptionDidChange)
        ])
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        .store(in: &cancellables)
    }

    func resume() {
        isActive = true
        refresh()
    }

    func suspend() {
        isActive = false
        refreshTask?.cancel()
        refreshTask = nil

        guard applicationStateProvider() != .background else { return }

        let currentShortcutItems = currentShortcutItemsProvider()
        let filteredShortcutItems = shortcutItemsFilter(currentShortcutItems)
        guard currentShortcutItems.map(\.type) != filteredShortcutItems.map(\.type) else { return }

        shortcutItemsUpdater(filteredShortcutItems)
    }

    private func refresh() {
        guard isActive else { return }

        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            var shortcutItems: [UIApplicationShortcutItem] = []
            for shortcutItemProvider in self.shortcutItemProviders {
                if let shortcutItem = await shortcutItemProvider() {
                    shortcutItems.append(shortcutItem)
                }
            }

            guard !Task.isCancelled,
                  self.isActive,
                  self.applicationStateProvider() == .active else { return }

            self.shortcutItemsUpdater(shortcutItems)
        }
    }

}
