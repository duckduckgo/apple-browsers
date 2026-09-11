//
//  DuckPlayerOverlayObserver.swift
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
import DuckPlayer
import FeatureFlags_macOS
import Foundation
import PrivacyConfig

/// Reports whether the "Watch in Duck Player?" overlay is on screen in the selected tab.
final class DuckPlayerOverlayObserver: ExternalPromoDelegate {

    private let duckPlayer: DuckPlayer
    private let windowControllersManager: WindowControllersManagerProtocol
    private let featureFlagger: FeatureFlagger

    private let visibilitySubject: CurrentValueSubject<Bool, Never>
    private var cancellables = Set<AnyCancellable>()

    var isVisible: Bool { visibilitySubject.value }
    var isVisiblePublisher: AnyPublisher<Bool, Never> { visibilitySubject.eraseToAnyPublisher() }

    /// The overlay is offered again on the next eligible video, so a dismissal is never permanent.
    var resultWhenHidden: PromoResult { .ignored(cooldown: 0) }

    @MainActor
    init(duckPlayer: DuckPlayer,
         windowControllersManager: WindowControllersManagerProtocol,
         featureFlagger: FeatureFlagger) {
        self.duckPlayer = duckPlayer
        self.windowControllersManager = windowControllersManager
        self.featureFlagger = featureFlagger
        self.visibilitySubject = CurrentValueSubject(false)

        // Re-subscribe to the newly selected tab's content whenever the selection changes, so a
        // navigation within the selected tab is observed but background tabs are ignored.
        let selectedTabContentChanged = windowControllersManager.stateChanged
            .prepend(())
            .map { [weak windowControllersManager] _ -> AnyPublisher<Void, Never> in
                guard let tab = windowControllersManager?.selectedTab else {
                    return Empty().eraseToAnyPublisher()
                }
                return tab.$content.dropFirst().map { _ in () }.eraseToAnyPublisher()
            }
            .switchToLatest()
            .eraseToAnyPublisher()

        // Seeded synchronously so `isVisible` is already correct when `PromoService` reads it
        // during registration, rather than one main-queue hop later.
        visibilitySubject.send(computeVisibility())

        Publishers.MergeMany(
            duckPlayer.$mode.map { _ in () }.eraseToAnyPublisher(),
            duckPlayer.preferences.$youtubeOverlayInteracted.map { _ in () }.eraseToAnyPublisher(),
            windowControllersManager.stateChanged,
            selectedTabContentChanged
        )
        .receive(on: DispatchQueue.main)
        .map { [weak self] _ in self?.computeVisibility() ?? false }
        .sink { [weak self] visible in
            guard let self, self.visibilitySubject.value != visible else { return }
            self.visibilitySubject.send(visible)
        }
        .store(in: &cancellables)
    }

    @MainActor
    private func computeVisibility() -> Bool {
        guard featureFlagger.isFeatureOn(.promoQueueDuckPlayerOverlayPromo) else { return false }

        return duckPlayer.isAvailable
            && duckPlayer.mode == .alwaysAsk
            && !duckPlayer.overlayInteracted
            && windowControllersManager.selectedTab?.content.urlForWebView?.isYoutubeWatch == true
    }
}
