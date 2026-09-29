//
//  DuckAiTermsOfServiceStore.swift
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

import Core
import Foundation
import Persistence

/// The one record of whether the user accepted Duck.ai's Terms of Service, whichever side they
/// accepted on. The key predates native acceptance, so the web's reports already live under it.
struct DuckAiTermsOfServiceStore {

    enum Key: String {
        case hasAccepted = "aichat.hasAcceptedTermsAndConditions"
        case isAwaitingWebReport = "aichat.terms-of-service.accepted-natively.awaiting-web-report"
    }

    enum WebReportOutcome: Equatable {
        case firstAcceptance
        case alreadyAccepted
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults()) {
        self.keyValueStore = keyValueStore
    }

    var hasAccepted: Bool {
        keyValueStore.object(forKey: Key.hasAccepted.rawValue) as? Bool == true
    }

    /// Sending from an input that showed the disclaimer. The web reports the same acceptance once the
    /// prompt reaches it, and that report must not read as a repeat.
    func recordAcceptedInNativeInput() {
        guard !hasAccepted else { return }
        keyValueStore.set(true, forKey: Key.hasAccepted.rawValue)
        keyValueStore.set(true, forKey: Key.isAwaitingWebReport.rawValue)
    }

    @discardableResult
    func recordWebReport() -> WebReportOutcome {
        let wasAccepted = hasAccepted
        let wasAwaitingWebReport = keyValueStore.object(forKey: Key.isAwaitingWebReport.rawValue) as? Bool == true
        keyValueStore.removeObject(forKey: Key.isAwaitingWebReport.rawValue)
        keyValueStore.set(true, forKey: Key.hasAccepted.rawValue)
        return wasAccepted && !wasAwaitingWebReport ? .alreadyAccepted : .firstAcceptance
    }

#if DEBUG || ALPHA
    /// Native only: the web app keeps its own copy until Duck.ai data is cleared.
    func resetForDebugging() {
        keyValueStore.removeObject(forKey: Key.hasAccepted.rawValue)
        keyValueStore.removeObject(forKey: Key.isAwaitingWebReport.rawValue)
    }
#endif
}
