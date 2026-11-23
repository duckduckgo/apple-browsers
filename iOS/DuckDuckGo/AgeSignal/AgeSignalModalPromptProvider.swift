//
//  AgeSignalModalPromptProvider.swift
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

import UIKit
import BrowserServicesKit
import PrivacyConfig
import FeatureFlags_iOS

/// Brings Apple's Declared Age Range sheet into the Promo Queue.
///
/// The sheet is not ours to present, so this is an `.external` provider: the queue holds the slot
/// while the sheet's request runs.
@MainActor
final class AgeSignalModalPromptProvider: ModalPromptProvider {

    private let requester: AgeSignalRequester
    private let featureFlagger: FeatureFlagger
    private var isRequestNeeded = false
    private var isRequesting = false

    init(requester: AgeSignalRequester, featureFlagger: FeatureFlagger) {
        self.requester = requester
        self.featureFlagger = featureFlagger

        // The flag doubles as a kill switch, so Apple's API isn't touched while it's off.
        guard featureFlagger.isFeatureOn(.declaredAgeRange) else {
            return
        }

        // A reinstall wipes the stored date, so it needs no separate signal on iOS.
        Task {
            isRequestNeeded = await requester.isRequestNeeded(isReinstall: false)
        }
    }

    var presentationKind: ModalPromptPresentationKind { .external }

    func isEligibleToPresent(isOnboardingComplete: Bool) -> Bool {
        let output = isOnboardingComplete
            && !isRequesting
            && featureFlagger.isFeatureOn(.declaredAgeRange)
            && isRequestNeeded
            && requester.isRequestDue(isReinstall: false)

        return output
    }

    /// Never called: the manager short-circuits `.external` providers after eligibility.
    func provideModalPrompt() -> ModalPromptConfiguration? {
        nil
    }

    func presentExternalPrompt(from presenter: ModalPromptPresenter, completion: @escaping @MainActor (ExternalPromptResult) -> Void) {
        guard let viewController = presenter as? UIViewController else {
            completion(.notShown)
            return
        }

        isRequesting = true
        Task {
            let didAnswer = await requester.requestAgeRange(isReinstall: false, in: viewController)
            isRequesting = false
            completion(didAnswer ? .shown(.ageSignal) : .notShown)
        }
    }
}
