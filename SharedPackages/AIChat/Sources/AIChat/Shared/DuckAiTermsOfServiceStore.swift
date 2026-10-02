//
//  DuckAiTermsOfServiceStore.swift
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

import Foundation
import Persistence

/// The one record of whether the user accepted Duck.ai's Terms of Service, whichever side they
/// accepted on. The key predates native acceptance, so the web's reports already live under it.
public struct DuckAiTermsOfServiceStore {

    enum Key: String {
        case hasAccepted = "aichat.hasAcceptedTermsAndConditions"
        case isAwaitingWebReport = "aichat.terms-of-service.accepted-natively.awaiting-web-report"
    }

    public enum WebReportOutcome: Equatable {
        case firstAcceptance
        case alreadyAccepted
    }

    private let keyValueStore: KeyValueStoring
    private let nativeStorageHandler: DuckAiNativeStorageHandling?
    private let notificationCenter: NotificationCenter

    /// Pass `nativeStorageHandler` to also count acceptances made before native kept a record.
    public init(keyValueStore: KeyValueStoring,
                nativeStorageHandler: DuckAiNativeStorageHandling? = nil,
                notificationCenter: NotificationCenter = .default) {
        self.keyValueStore = keyValueStore
        self.nativeStorageHandler = nativeStorageHandler
        self.notificationCenter = notificationCenter
    }

    /// Writes the record on the first earlier acceptance it finds, so later reads skip the chats lookup.
    public var hasAccepted: Bool {
        if isAcceptanceOnRecord { return true }
        guard hasAcceptedBeforeNativeRecord else { return false }
        keyValueStore.set(true, forKey: Key.hasAccepted.rawValue)
        return true
    }

    /// Sending from an input that showed the disclaimer. The web reports the same acceptance once the
    /// prompt reaches it, and that report must not read as a repeat.
    public func recordAcceptedInNativeInput() {
        guard !hasAccepted else { return }
        keyValueStore.set(true, forKey: Key.hasAccepted.rawValue)
        keyValueStore.set(true, forKey: Key.isAwaitingWebReport.rawValue)
        notificationCenter.post(name: .aiChatTermsOfServiceDidChange, object: nil)
    }

    @discardableResult
    public func recordWebReport() -> WebReportOutcome {
        let wasAccepted = isAcceptanceOnRecord
        let wasAwaitingWebReport = keyValueStore.object(forKey: Key.isAwaitingWebReport.rawValue) as? Bool == true
        keyValueStore.removeObject(forKey: Key.isAwaitingWebReport.rawValue)
        keyValueStore.set(true, forKey: Key.hasAccepted.rawValue)
        if !wasAccepted {
            notificationCenter.post(name: .aiChatTermsOfServiceDidChange, object: nil)
        }
        return wasAccepted && !wasAwaitingWebReport ? .alreadyAccepted : .firstAcceptance
    }

    /// Native only: the web app keeps its own copy until Duck.ai data is cleared.
    public func reset() {
        keyValueStore.removeObject(forKey: Key.hasAccepted.rawValue)
        keyValueStore.removeObject(forKey: Key.isAwaitingWebReport.rawValue)
        notificationCenter.post(name: .aiChatTermsOfServiceDidChange, object: nil)
    }

    private var isAcceptanceOnRecord: Bool {
        keyValueStore.object(forKey: Key.hasAccepted.rawValue) as? Bool == true
    }

    /// Native started recording the web's reports in March 2026. Earlier acceptances show up only in
    /// the web's own record, or as chats, which can't exist without accepting.
    private var hasAcceptedBeforeNativeRecord: Bool {
        guard let nativeStorageHandler else { return false }
        let webRecord = try? nativeStorageHandler.getEntry(key: DuckAiNativeStorageConsent.termsOfServiceEntryKey)
        if webRecord as? String == "true" || webRecord as? Bool == true {
            return true
        }
        // Reading chats waits for the chats database to open, so skip it until it has rather than block the caller.
        guard nativeStorageHandler.setupSucceeded == true else { return false }
        return (try? nativeStorageHandler.getAllChats().isEmpty == false) ?? false
    }
}
