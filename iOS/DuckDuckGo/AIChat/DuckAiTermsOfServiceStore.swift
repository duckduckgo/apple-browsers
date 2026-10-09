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
        case hasExistingChats = "aichat.terms-of-service.has-existing-chats"
    }

    enum WebReportOutcome: Equatable {
        case firstAcceptance
        /// The report a native acceptance owed the web: the same acceptance, not a new one.
        case confirmsNativeAcceptance
        case alreadyAccepted
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring = UserDefaults(suiteName: Global.appConfigurationGroupName) ?? UserDefaults()) {
        self.keyValueStore = keyValueStore
    }

    var hasAccepted: Bool {
        keyValueStore.object(forKey: Key.hasAccepted.rawValue) as? Bool == true
    }

    /// For measurement: chats prove an earlier acceptance in both groups, though only native Terms of Service
    /// records one, so users the web app never asks count as accepted with the flag off too.
    var hasAcceptedOrExistingChats: Bool {
        hasAccepted || keyValueStore.object(forKey: Key.hasExistingChats.rawValue) as? Bool == true
    }

    /// Sending from an input that showed the disclaimer. The web reports the same acceptance once the
    /// prompt reaches it, and that report must not read as a repeat. Returns whether this is the first acceptance.
    @discardableResult
    func recordAcceptedInNativeInput() -> Bool {
        recordAcceptedNatively()
    }

    /// Chats on the device prove an earlier acceptance. A page that loaded before they arrived can still
    /// show its own card, and accepting there must not read as a repeat either.
    func recordAcceptedFromExistingChats() {
        recordAcceptedNatively()
    }

    func recordExistingChats() {
        keyValueStore.set(true, forKey: Key.hasExistingChats.rawValue)
    }

    @discardableResult
    func recordWebReport() -> WebReportOutcome {
        let wasAccepted = hasAccepted
        let wasAwaitingWebReport = keyValueStore.object(forKey: Key.isAwaitingWebReport.rawValue) as? Bool == true
        keyValueStore.removeObject(forKey: Key.isAwaitingWebReport.rawValue)
        keyValueStore.set(true, forKey: Key.hasAccepted.rawValue)
        guard wasAccepted else { return .firstAcceptance }
        return wasAwaitingWebReport ? .confirmsNativeAcceptance : .alreadyAccepted
    }

    @discardableResult
    private func recordAcceptedNatively() -> Bool {
        guard !hasAccepted else { return false }
        keyValueStore.set(true, forKey: Key.hasAccepted.rawValue)
        keyValueStore.set(true, forKey: Key.isAwaitingWebReport.rawValue)
        return true
    }

#if DEBUG || ALPHA
    /// Native only: the web app keeps its own copy until Duck.ai data is cleared.
    func resetForDebugging() {
        keyValueStore.removeObject(forKey: Key.hasAccepted.rawValue)
        keyValueStore.removeObject(forKey: Key.isAwaitingWebReport.rawValue)
        keyValueStore.removeObject(forKey: Key.hasExistingChats.rawValue)
    }
#endif
}
