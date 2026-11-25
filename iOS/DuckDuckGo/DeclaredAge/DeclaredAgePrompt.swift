//
//  DeclaredAgePrompt.swift
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

/// Presents Apple's Declared Age Range sheet once the app is ready for interactions.
@MainActor
final class DeclaredAgePrompt {

    private let requester: DeclaredAgeRequester
    private let featureFlagger: FeatureFlagger
    private var wasAttempted = false

    init(requester: DeclaredAgeRequester, featureFlagger: FeatureFlagger) {
        self.requester = requester
        self.featureFlagger = featureFlagger
    }

    func presentIfNeeded(in viewController: UIViewController) async {
        guard isDue else {
            return
        }

        // Success or failure, the next attempt waits for the next launch.
        wasAttempted = true

        // A reinstall wipes the stored date, so it needs no separate signal on iOS.
        guard await requester.isRequestNeeded() else {
            return
        }

        _ = await requester.requestDeclaredAge(in: viewController)
    }
}

private extension DeclaredAgePrompt {

    /// The flag doubles as a kill switch, so Apple's API isn't touched while it's off.
    var isDue: Bool {
        !wasAttempted
            && featureFlagger.isFeatureOn(.declaredAgeRange)
            && requester.isRequestDue()
    }
}
