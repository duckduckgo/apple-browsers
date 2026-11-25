//
//  DeclaredAgePromoDelegate.swift
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

import AppKit
import BrowserServicesKit
import Combine
import FeatureFlags_macOS
import os.log
import PrivacyConfig

/// Presents Apple's Declared Age Range sheet through the promo queue.
final class DeclaredAgePromoDelegate: InternalPromoDelegate {

    private let requester: DeclaredAgeRequester
    private let isReinstall: Bool
    private let featureFlagger: FeatureFlagger
    private let notificationCenter: NotificationCenter
    private let windowProvider: @MainActor () -> NSWindow?
    private let isRequestNeededSubject = CurrentValueSubject<Bool, Never>(false)
    private var cancellables = Set<AnyCancellable>()

    init(requester: DeclaredAgeRequester,
         reinstallUserDetection: ReinstallingUserDetecting,
         featureFlagger: FeatureFlagger,
         notificationCenter: NotificationCenter = .default,
         windowProvider: @escaping @MainActor () -> NSWindow?) {
        self.requester = requester
        self.isReinstall = reinstallUserDetection.isReinstallingUser
        self.featureFlagger = featureFlagger
        self.notificationCenter = notificationCenter
        self.windowProvider = windowProvider

        startListeningToFeatureFlagger()
    }

    var isEligible: Bool {
        featureFlagger.isFeatureOn(.declaredAgeRange) && isRequestNeededSubject.value
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isRequestNeededSubject
            .combineLatest(featureFlagger.updatesPublisher.prepend(()))
            .map { [weak self] _ in
                self?.isEligible ?? false
            }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        Logger.declaredAge.info("Showing the promo (force: \(force))")

        guard let window = windowProvider() else {
            Logger.declaredAge.error("No main window to present the request in")
            return .noChange
        }

        // Success or failure, the next attempt waits for the next launch.
        _ = await requester.requestDeclaredAge(isReinstall: isReinstall, in: window)
        isRequestNeededSubject.send(false)

        return .noChange
    }

    @MainActor
    func hide() {
        // Apple's age range sheet can't be dismissed programmatically.
    }
}

private extension DeclaredAgePromoDelegate {

    func startListeningToFeatureFlagger() {
        let featureFlagsDidChange = featureFlagger.updatesPublisher
        let internalUserDidChange = featureFlagger.internalUserDecider.isInternalUserPublisher.asVoid()

        Publishers.Merge(featureFlagsDidChange, internalUserDidChange)
            .prepend(())
            .first { [featureFlagger] in
                featureFlagger.isFeatureOn(.declaredAgeRange)
            }
            .sink { [weak self] in
                Task { @MainActor [weak self] in
                    await self?.refreshIsRequestNeeded()
                }
            }
            .store(in: &cancellables)
    }

    @MainActor
    func refreshIsRequestNeeded() async {
        let isNeeded = await requester.isRequestNeeded(isReinstall: isReinstall)
        isRequestNeededSubject.send(isNeeded)

        if isNeeded {
            notificationCenter.post(name: .declaredAgeBecameEligible, object: nil)
        }
    }
}
