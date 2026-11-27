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
import os.log
import Persistence

enum DeclaredAgeStorageKeys: String, StorageKeyDescribing {
    case lastRequestDate = "declaredAgeLastRequestDate"
    case requestWasNotRequired = "declaredAgeRequestWasNotRequired"
}

public struct DeclaredAgeSettings: StoringKeys {
    let lastRequestDate = StorageKey<Date>(DeclaredAgeStorageKeys.lastRequestDate)
    let requestWasNotRequired = StorageKey<Bool>(DeclaredAgeStorageKeys.requestWasNotRequired)

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

    /// Throws when Apple cannot tell, so callers must not mark it as not required.
    public func isRequestNeeded() async throws -> Bool {
        guard isRequestDue() else {
            Logger.declaredAge.info("Request is not due")
            return false
        }

        do {
            let isRequired = try await service.isRequestRequired()
            Logger.declaredAge.info("Request is required: \(isRequired)")
            return isRequired
        } catch {
            Logger.declaredAge.error("Failed to check whether a request is required: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    /// Apple's "no" is final, so the check is never made again.
    public func markNotRequired() {
        // Already asked or already marked, so there is nothing to record.
        guard isRequestDue() else {
            return
        }

        try? storage.set(true, for: \.requestWasNotRequired)
        Logger.declaredAge.info("Marked as not required")
    }

    public func requestDeclaredAge(in anchor: DeclaredAgeAnchor) async -> Bool {
        guard await request(in: anchor) else {
            // No marker is stored, so the next launch retries.
            return false
        }

        markRequested()
        return true
    }

    public func isRequestDue() -> Bool {
        return (try? storage.lastRequestDate) == nil && (try? storage.requestWasNotRequired) != true
    }
}

private extension DeclaredAgeRequester {

    func request(in anchor: DeclaredAgeAnchor) async -> Bool {
        do {
            let didRequest = try await service.requestDeclaredAge(in: anchor)
            Logger.declaredAge.info("Request finished (supported by the OS: \(didRequest))")
            return didRequest
        } catch {
            Logger.declaredAge.error("Request failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func markRequested() {
        try? storage.set(now(), for: \.lastRequestDate)
    }
}
