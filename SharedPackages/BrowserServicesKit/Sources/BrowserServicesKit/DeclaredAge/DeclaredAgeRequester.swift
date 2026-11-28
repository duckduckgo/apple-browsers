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
import PixelKit

enum DeclaredAgeStorageKeys: String, StorageKeyDescribing {
    case lastRequestDate = "declaredAgeLastRequestDate"
    case requestWasNotRequired = "declaredAgeRequestWasNotRequired"
    case reinstallWasHandled = "declaredAgeReinstallWasHandled"
}

public struct DeclaredAgeSettings: StoringKeys {
    let lastRequestDate = StorageKey<Date>(DeclaredAgeStorageKeys.lastRequestDate)
    let requestWasNotRequired = StorageKey<Bool>(DeclaredAgeStorageKeys.requestWasNotRequired)
    let reinstallWasHandled = StorageKey<Bool>(DeclaredAgeStorageKeys.reinstallWasHandled)

    public init() {}
}

@MainActor
public final class DeclaredAgeRequester {

    private let service: DeclaredAgeServicing
    private let storage: any ThrowingKeyedStoring<DeclaredAgeSettings>
    private let pixelFiring: PixelFiring?
    private let now: () -> Date

    public init(service: DeclaredAgeServicing,
                storage: any ThrowingKeyedStoring<DeclaredAgeSettings>,
                pixelFiring: PixelFiring? = PixelKit.shared,
                now: @escaping () -> Date = Date.init) {
        self.service = service
        self.storage = storage
        self.pixelFiring = pixelFiring
        self.now = now
    }

    /// Throws when Apple cannot tell, so callers must not mark it as not required.
    public func isRequestNeeded(isReinstall: Bool = false) async throws -> Bool {
        guard isRequestDue(isReinstall: isReinstall) else {
            Logger.declaredAge.info("Request is not due (isReinstall: \(isReinstall))")
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
    public func markNotRequired(isReinstall: Bool = false) {
        // Already asked or already marked, so there is nothing to record.
        guard isRequestDue(isReinstall: isReinstall) else {
            return
        }

        try? storage.set(true, for: \.requestWasNotRequired)
        try? storage.set(isReinstall, for: \.reinstallWasHandled)
        Logger.declaredAge.info("Marked as not required")
        pixelFiring?.fire(DeclaredAgePixel.checkNotRequired(isReinstall: isReinstall), frequency: .standard)
    }

    public func requestDeclaredAge(isReinstall: Bool = false, in anchor: DeclaredAgeAnchor) async -> Bool {
        guard await request(isReinstall: isReinstall, in: anchor) else {
            // No marker is stored, so the next launch retries.
            return false
        }

        markRequested(isReinstall: isReinstall)
        return true
    }

    /// `isReinstall` stays true on every launch after a reinstall, so it only counts until a request succeeds or isn't required.
    public func isRequestDue(isReinstall: Bool = false) -> Bool {
        if isReinstall && (try? storage.reinstallWasHandled) != true {
            return true
        }

        return (try? storage.lastRequestDate) == nil && (try? storage.requestWasNotRequired) != true
    }
}

private extension DeclaredAgeRequester {

    func request(isReinstall: Bool, in anchor: DeclaredAgeAnchor) async -> Bool {
        pixelFiring?.fire(DeclaredAgePixel.requestShown(isReinstall: isReinstall), frequency: .standard)

        let didRequest: Bool

        do {
            didRequest = try await service.requestDeclaredAge(in: anchor)
            Logger.declaredAge.info("Request finished (supported by the OS: \(didRequest))")

        } catch {
            Logger.declaredAge.error("Request failed: \(String(describing: error), privacy: .public)")
            pixelFiring?.fire(DeclaredAgePixel.requestFailed(isReinstall: isReinstall), frequency: .dailyAndCount)
            return false
        }

        if didRequest {
            pixelFiring?.fire(DeclaredAgePixel.requestCompleted(isReinstall: isReinstall), frequency: .standard)
        }

        return didRequest
    }

    func markRequested(isReinstall: Bool) {
        try? storage.set(now(), for: \.lastRequestDate)
        try? storage.set(isReinstall, for: \.reinstallWasHandled)
    }
}
