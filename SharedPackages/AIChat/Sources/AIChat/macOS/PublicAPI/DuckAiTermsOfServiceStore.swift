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

#if os(macOS)
import Combine
import Foundation
import Persistence

/// Whether the user accepted Duck.ai's Terms of Service, whichever side they accepted on.
public final class DuckAiTermsOfServiceStore {

    enum Key: String {
        case isAwaitingWebReport = "aichat.terms-of-service.accepted-natively.awaiting-web-report"
    }

    public enum WebReportOutcome: Equatable {
        case firstAcceptance
        case alreadyAccepted
    }

    private let preferencesStorage: AIChatPreferencesStorage
    private let keyValueStore: ThrowingKeyValueStoring
    private let nativeStorage: DuckAiNativeStorageHandling?

    public init(preferencesStorage: AIChatPreferencesStorage = DefaultAIChatPreferencesStorage(),
                keyValueStore: ThrowingKeyValueStoring,
                nativeStorage: DuckAiNativeStorageHandling? = nil) {
        self.preferencesStorage = preferencesStorage
        self.keyValueStore = keyValueStore
        self.nativeStorage = nativeStorage
    }

    /// Duck.ai's record in native storage is shared by both sides, so it decides whenever Duck.ai can reach it.
    /// The preferences flag stands in only when it can't.
    public var hasAccepted: Bool {
        guard let sharedStorage else { return preferencesStorage.hasAcceptedTermsAndConditions }
        let value = try? sharedStorage.getEntry(key: DuckAiNativeStorageReservedEntryKeys.duckaiHasAgreedToTerms.rawValue)
        return value as? Bool == true || value as? String == "true"
    }

    public var hasAcceptedPublisher: AnyPublisher<Bool, Never> {
        let nativeStorageUpdates = (nativeStorage as? DuckAiNativeEntriesObserving)?.reservedEntryUpdatesPublisher
            .filter { $0 == .duckaiHasAgreedToTerms }
            .map { _ in () }
            .eraseToAnyPublisher()
        return Publishers.Merge(
            preferencesStorage.hasAcceptedTermsAndConditionsPublisher.map { _ in () },
            nativeStorageUpdates ?? Empty().eraseToAnyPublisher()
        )
        .compactMap { [weak self] in self?.hasAccepted }
        .eraseToAnyPublisher()
    }

    /// After a failed setup Duck.ai falls back to its own storage and never writes here.
    private var sharedStorage: DuckAiNativeStorageHandling? {
        nativeStorage?.setupSucceeded == false ? nil : nativeStorage
    }

    /// Sending from an input that showed the disclaimer. The web reports the same acceptance once the
    /// prompt reaches it, and that report must not read as a repeat.
    public func recordAcceptedInNativeInput() {
        guard !hasAccepted else { return }
        try? keyValueStore.set(true, forKey: Key.isAwaitingWebReport.rawValue)
        markAccepted()
    }

    /// Ignores native storage: Duck.ai may write its record there before reporting, which would make every
    /// first acceptance read as a repeat.
    @discardableResult
    public func recordWebReport() -> WebReportOutcome {
        let wasAccepted = preferencesStorage.hasAcceptedTermsAndConditions
        let wasAwaitingWebReport = (try? keyValueStore.object(forKey: Key.isAwaitingWebReport.rawValue) as? Bool) == true
        try? keyValueStore.removeObject(forKey: Key.isAwaitingWebReport.rawValue)
        markAccepted()
        return wasAccepted && !wasAwaitingWebReport ? .alreadyAccepted : .firstAcceptance
    }

    /// Through a copy: the write notifies `hasAcceptedPublisher` subscribers synchronously, and they read
    /// this store back, which would overlap a write to `preferencesStorage` itself.
    private func markAccepted() {
        var preferencesStorage = preferencesStorage
        preferencesStorage.hasAcceptedTermsAndConditions = true
        try? sharedStorage?.putEntry(key: DuckAiNativeStorageReservedEntryKeys.duckaiHasAgreedToTerms.rawValue, value: "true")
    }
}
#endif
