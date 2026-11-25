//
//  DeclaredAgeRequester.swift
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

enum DeclaredAgeStorageKeys: String, StorageKeyDescribing {
    case lastRequestDate = "declaredAgeLastRequestDate"
    case reinstallWasHandled = "declaredAgeReinstallWasHandled"
}

public struct DeclaredAgeSettings: StoringKeys {
    let lastRequestDate = StorageKey<Date>(DeclaredAgeStorageKeys.lastRequestDate)
    let reinstallWasHandled = StorageKey<Bool>(DeclaredAgeStorageKeys.reinstallWasHandled)

    public init() {}
}

@MainActor
public final class DeclaredAgeRequester {

    private let service: DeclaredAgeServicing
    private let storage: any ThrowingKeyedStoring<DeclaredAgeSettings>
    private let now: () -> Date

    public init(service: DeclaredAgeServicing,
                storage: any ThrowingKeyedStoring<DeclaredAgeSettings>,
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

    public func requestDeclaredAge(isReinstall: Bool, in anchor: DeclaredAgeAnchor) async -> Bool {
        guard await request(in: anchor) else {
            // No marker is stored, so the next launch retries.
            return false
        }

        markRequested(isReinstall: isReinstall)
        return true
    }

    /// `isReinstall` stays true on every launch after a reinstall, so it only counts until a request succeeds.
    public func isRequestDue(isReinstall: Bool) -> Bool {
        if isReinstall && (try? storage.reinstallWasHandled) != true {
            return true
        }

        return (try? storage.lastRequestDate) == nil
    }
}

private extension DeclaredAgeRequester {

    func request(in anchor: DeclaredAgeAnchor) async -> Bool {
        (try? await service.requestDeclaredAge(in: anchor)) ?? false
    }

    func markRequested(isReinstall: Bool) {
        try? storage.set(now(), for: \.lastRequestDate)
        try? storage.set(isReinstall, for: \.reinstallWasHandled)
    }
}
