//
//  AgeSignalRequester.swift
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

enum AgeSignalStorageKeys: String, StorageKeyDescribing {
    case lastRequestDate = "ageSignalLastRequestDate"
    case handledReinstall = "ageSignalHandledReinstall"
}

public struct AgeSignalSettings: StoringKeys {
    let lastRequestDate = StorageKey<Date>(AgeSignalStorageKeys.lastRequestDate)
    let handledReinstall = StorageKey<Bool>(AgeSignalStorageKeys.handledReinstall)

    public init() {}
}

@MainActor
public final class AgeSignalRequester {

    private let service: AgeRangeServicing
    private let storage: any ThrowingKeyedStoring<AgeSignalSettings>
    private let now: () -> Date

    public init(service: AgeRangeServicing,
                storage: any ThrowingKeyedStoring<AgeSignalSettings>,
                now: @escaping () -> Date = Date.init) {
        self.service = service
        self.storage = storage
        self.now = now
    }

    public func isRequestNeeded(isReinstall: Bool) async -> Bool {
        guard isRequestDue(isReinstall: isReinstall) else {
            return false
        }

        return (try? await service.isRequestRequired()) ?? false
    }

    public func requestAgeRange(isReinstall: Bool, in anchor: AgeRangeAnchor) async -> Bool {
        do {
            try await service.requestAgeRange(in: anchor)
        } catch {
            // No marker is stored, so the next launch retries.
            return false
        }

        try? storage.set(now(), for: \.lastRequestDate)
        try? storage.set(isReinstall, for: \.handledReinstall)
        return true
    }

    /// `isReinstall` stays true on every launch after a reinstall, so it only counts until a request succeeds.
    public func isRequestDue(isReinstall: Bool) -> Bool {
        if isReinstall && (try? storage.handledReinstall) != true {
            return true
        }

        guard let lastRequestDate = try? storage.lastRequestDate,
              let nextRequestDate = Calendar.current.date(byAdding: .year, value: 1, to: lastRequestDate) else {
            return true
        }

        return now() >= nextRequestDate
    }
}
