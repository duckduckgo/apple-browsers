//
//  AgeSignalPromoDelegate.swift
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

import BrowserServicesKit
import Combine
import FeatureFlags_macOS
import Foundation
import PrivacyConfig

/// Presents Apple's Declared Age Range sheet through the promo queue.
final class AgeSignalPromoDelegate: InternalPromoDelegate {

    private let requester: AgeSignalRequester
    private let isReinstall: Bool
    private let featureFlagger: FeatureFlagger
    private let windowControllersManager: WindowControllersManagerProtocol
    private let isRequestNeededSubject = CurrentValueSubject<Bool, Never>(false)

    init(requester: AgeSignalRequester,
         reinstallUserDetection: ReinstallingUserDetecting,
         featureFlagger: FeatureFlagger,
         windowControllersManager: WindowControllersManagerProtocol) {
        self.requester = requester
        self.isReinstall = reinstallUserDetection.isReinstallingUser
        self.featureFlagger = featureFlagger
        self.windowControllersManager = windowControllersManager

        // The flag doubles as a kill switch, so Apple's API isn't touched while it's off.
        guard featureFlagger.isFeatureOn(.declaredAgeRange) else {
            return
        }

        Task { @MainActor [requester, isReinstall, isRequestNeededSubject] in
            isRequestNeededSubject.send(await requester.isRequestNeeded(isReinstall: isReinstall))
        }
    }

    var isEligible: Bool {
        featureFlagger.isFeatureOn(.declaredAgeRange) && isRequestNeededSubject.value
    }

    var isEligiblePublisher: AnyPublisher<Bool, Never> {
        isRequestNeededSubject
            .combineLatest(featureFlagger.updatesPublisher.prepend(()))
            .map { [weak self] _ in self?.isEligible ?? false }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    @MainActor
    func show(history: PromoHistoryRecord, force: Bool) async -> PromoResult {
        guard let window = windowControllersManager.lastKeyMainWindowController?.window else {
            return .noChange
        }

        guard await requester.requestAgeRange(isReinstall: isReinstall, in: window) else {
            return .noChange
        }

        isRequestNeededSubject.send(false)
        return .ignored(cooldown: 0)
    }

    @MainActor
    func hide() {
        // Apple's age range sheet can't be dismissed programmatically.
    }
}
