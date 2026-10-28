//
//  MainMenuController.swift
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
import CoreData
import Core
import Persistence
import FeatureFlags_iOS
import PrivacyConfig
import UIKit

final class MainMenuController {
    private let featureFlagger: FeatureFlagger
    private let contextProvider: () -> MainMenuSpec.Context
    private let idiom: UIUserInterfaceIdiom
    private let rebuildRequests = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()

    var spec: MainMenuSpec {
        let enabled = featureFlagger.isIPadMenuBarEnabled(idiom: idiom)
        return MainMenuSpec(isEnabled: enabled, context: enabled ? contextProvider() : .init())
    }

    init(featureFlagger: FeatureFlagger,
         idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
         contextProvider: @escaping () -> MainMenuSpec.Context = { .init() },
         notificationCenter: NotificationCenter = .default,
         bookmarksDatabase: CoreDataDatabase? = nil,
         rebuildDelay: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(100),
         rebuild: @escaping () -> Void = { UIMenuSystem.main.setNeedsRebuild() }) {
        self.featureFlagger = featureFlagger
        self.idiom = idiom
        self.contextProvider = contextProvider

        notificationCenter.publisher(for: .speechRecognizerDidChangeAvailability)
            .sink { [weak self] _ in self?.requestRebuild() }
            .store(in: &cancellables)

        notificationCenter.publisher(for: AppUserDefaults.Notifications.favoritesDisplayModeChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.requestRebuild() }
            .store(in: &cancellables)

        if let bookmarksDatabase {
            notificationCenter.publisher(for: NSManagedObjectContext.didSaveObjectsNotification)
                .filter { notification in
                    (notification.object as? NSManagedObjectContext)?.persistentStoreCoordinator === bookmarksDatabase.coordinator
                }
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.requestRebuild() }
                .store(in: &cancellables)
        }

        rebuildRequests
            .debounce(for: rebuildDelay, scheduler: DispatchQueue.main)
            .sink { rebuild() }
            .store(in: &cancellables)

        featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .map { featureFlagger.isIPadMenuBarEnabled(idiom: idiom) }
            .prepend(featureFlagger.isIPadMenuBarEnabled(idiom: idiom))
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.requestRebuild() }
            .store(in: &cancellables)
    }

    func requestRebuild() {
        guard idiom == .pad else { return }
        rebuildRequests.send()
    }
}

extension FeatureFlagger {
    func isIPadMenuBarEnabled(idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom) -> Bool {
        idiom == .pad && isFeatureOn(.ipadMenuBar)
    }
}
