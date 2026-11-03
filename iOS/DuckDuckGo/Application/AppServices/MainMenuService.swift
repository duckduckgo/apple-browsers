//
//  MainMenuService.swift
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
import FeatureFlags_iOS
import PrivacyConfig
import UIKit

final class MainMenuService {

    private let featureFlagger: FeatureFlagger
    private let contextProvider: () -> MainMenuSpec.Context
    private let deferredContent: [UIMenu.Identifier: MainMenuDeferredContent]
    private let idiom: UIUserInterfaceIdiom
    private let rebuildRequests = PassthroughSubject<Void, Never>()
    private var isBuildHandlerRegistered = false
    private var cancellables = Set<AnyCancellable>()

    var spec: MainMenuSpec {
        MainMenuSpec(isEnabled: featureFlagger.isFeatureOn(.ipadMenuBar), idiom: idiom, context: contextProvider())
    }

    init(featureFlagger: FeatureFlagger,
         idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
         contextProvider: @escaping () -> MainMenuSpec.Context = { .init() },
         deferredContent: [UIMenu.Identifier: MainMenuDeferredContent] = [:],
         rebuildTriggers: [AnyPublisher<Void, Never>] = [],
         notificationCenter: NotificationCenter = .default,
         rebuildDelay: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(100),
         rebuild: @escaping () -> Void = { UIMenuSystem.main.setNeedsRebuild() }) {
        self.featureFlagger = featureFlagger
        self.idiom = idiom
        self.contextProvider = contextProvider
        self.deferredContent = deferredContent

        notificationCenter.publisher(for: .speechRecognizerDidChangeAvailability)
            .sink { [weak self] _ in self?.requestRebuild() }
            .store(in: &cancellables)

        Publishers.MergeMany(rebuildTriggers)
            .sink { [weak self] in self?.requestRebuild() }
            .store(in: &cancellables)

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
            .sink { [weak self] _ in
                self?.registerBuildHandlerIfEnabled()
                self?.requestRebuild()
            }
            .store(in: &cancellables)

        registerBuildHandlerIfEnabled()
    }

    func buildMenu(with builder: UIMenuBuilder) {
        MainMenuBuilder(deferredContent: deferredContent).build(spec, with: builder)
    }

    func requestRebuild() {
        guard idiom == .pad else { return }
        rebuildRequests.send()
    }

    /// Takes over building the main menu the first time the feature is on, so flag-off users keep the `AppDelegate` menu.
    private func registerBuildHandlerIfEnabled() {
        guard !isBuildHandlerRegistered, featureFlagger.isIPadMenuBarEnabled(idiom: idiom),
              #available(iOS 26.0, *) else { return }
        isBuildHandlerRegistered = true
        UIMainMenuSystem.shared.setBuildConfiguration(UIMainMenuSystem.Configuration()) { [weak self] builder in
            self?.buildMenu(with: builder)
        }
    }

}

private extension FeatureFlagger {

    func isIPadMenuBarEnabled(idiom: UIUserInterfaceIdiom) -> Bool {
        idiom == .pad && isFeatureOn(.ipadMenuBar)
    }

}
