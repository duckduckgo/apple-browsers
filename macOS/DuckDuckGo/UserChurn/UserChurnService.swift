//
//  UserChurnService.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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
import Common
import FoundationExtensions

protocol UserChurnStateProviding: AnyObject {
    var hasChurnedFromDefault: Bool { get }
    func checkForDefaultBrowserChange()
}

final class UserChurnService: UserChurnStateProviding {

    enum Key: String {
        case wasDefaultBrowser = "was-default-browser"
        case churnedFromDefault = "churned-from-default"

        var storageKey: String { "user-churn.\(rawValue)" }
    }

    private let defaultBrowserProvider: DefaultBrowserProvider
    private let keyValueStore: ThrowingKeyValueStoring
    private let pixelFiring: PixelFiring?
    private let atbProvider: () -> String?
    private let bundleIdentifierProvider: (URL) -> String?
    private let lock = NSLock()

    var hasChurnedFromDefault: Bool {
        readValue(for: .churnedFromDefault) ?? false
    }

    init(
        defaultBrowserProvider: DefaultBrowserProvider,
        keyValueStore: ThrowingKeyValueStoring,
        pixelFiring: PixelFiring?,
        atbProvider: @escaping () -> String?,
        bundleIdentifierProvider: @escaping (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }
    ) {
        self.defaultBrowserProvider = defaultBrowserProvider
        self.keyValueStore = keyValueStore
        self.pixelFiring = pixelFiring
        self.atbProvider = atbProvider
        self.bundleIdentifierProvider = bundleIdentifierProvider
    }

    /// Records whether the user switched their default browser away from DuckDuckGo, and fires the churn pixel when they do.
    func checkForDefaultBrowserChange() {
        lock.lock()
        defer { lock.unlock() }

        let defaultBrowserURL = defaultBrowserProvider.defaultBrowserURL
        let isDuckDuckGoDefault = isDuckDuckGoBuild(url: defaultBrowserURL)

        guard let wasDuckDuckGoDefault = readValue(for: .wasDefaultBrowser) else {
            write(isDuckDuckGoDefault, for: .wasDefaultBrowser)
            return
        }

        if isDuckDuckGoDefault {
            recordDuckDuckGoIsDefault(wasDefault: wasDuckDuckGoDefault)
        } else if wasDuckDuckGoDefault {
            recordChurn(newDefaultBrowserURL: defaultBrowserURL)
        }
    }

    private func recordDuckDuckGoIsDefault(wasDefault: Bool) {
        if !wasDefault {
            write(true, for: .wasDefaultBrowser)
        }
        if hasChurnedFromDefault {
            write(false, for: .churnedFromDefault)
        }
    }

    private func recordChurn(newDefaultBrowserURL: URL?) {
        write(true, for: .churnedFromDefault)
        write(false, for: .wasDefaultBrowser)

        let bundleId = newDefaultBrowserURL.flatMap { bundleIdentifierProvider($0) }
        pixelFiring?.fire(UserChurnPixel.unsetAsDefault(newDefaultBrowserBundleId: bundleId, atb: atbProvider()))
    }

    private func readValue(for key: Key) -> Bool? {
        do {
            return try keyValueStore.object(forKey: key.storageKey) as? Bool
        } catch {
            Logger.general.error("Failed to read \(key.storageKey) from keyValueStore: \(error)")
            pixelFiring?.fire(UserChurnDebugPixel.readFailed(key: key, error: error), frequency: .dailyAndCount)
            return nil
        }
    }

    private func write(_ value: Bool, for key: Key) {
        do {
            try keyValueStore.set(value, forKey: key.storageKey)
        } catch {
            Logger.general.error("Failed to write \(key.storageKey) to keyValueStore: \(error)")
            pixelFiring?.fire(UserChurnDebugPixel.writeFailed(key: key, error: error), frequency: .dailyAndCount)
        }
    }

    /// Returns true if the app at the given URL is a DuckDuckGo build.
    ///
    /// All DuckDuckGo builds share the `com.duckduckgo` bundle identifier prefix.
    private func isDuckDuckGoBuild(url: URL?) -> Bool {
        guard let url,
              let bundleIdentifier = bundleIdentifierProvider(url) else {
            return false
        }
        return bundleIdentifier.hasPrefix("com.duckduckgo")
    }
}
