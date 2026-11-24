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
import PrivacyConfig

/// Presents Apple's Declared Age Range sheet through the promo queue.
final class DeclaredAgePromoDelegate: InternalPromoDelegate {

    private let requester: DeclaredAgeRequester
    private let isReinstall: Bool
    private let featureFlagger: FeatureFlagger
    private let windowProvider: @MainActor () -> NSWindow?
    private let isRequestNeededSubject = CurrentValueSubject<Bool, Never>(false)
    private var cancellables = Set<AnyCancellable>()

    init(requester: DeclaredAgeRequester,
         reinstallUserDetection: ReinstallingUserDetecting,
         featureFlagger: FeatureFlagger,
         windowProvider: @escaping @MainActor () -> NSWindow?) {
        self.requester = requester
        self.isReinstall = reinstallUserDetection.isReinstallingUser
        self.featureFlagger = featureFlagger
        self.windowProvider = windowProvider

        // The flag doubles as a kill switch, so Apple's API isn't touched until the first time it's on.
        featureFlagger.updatesPublisher
            .prepend(())
            .filter { _ in
                featureFlagger.isFeatureOn(.declaredAgeRange)
            }
            .first()
            .sink { [requester, isReinstall, isRequestNeededSubject] in
                Task { @MainActor in
                    let isNeeded = await requester.isRequestNeeded(isReinstall: isReinstall)
                    isRequestNeededSubject.send(isNeeded)
                }
            }
            .store(in: &cancellables)
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
        guard let window = windowProvider() else {
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
