//
//  ScreenTimeDataCleaner.swift
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

import ScreenTime
import WebKit

@available(iOS 26, macOS 26, *)
public struct ScreenTimeDataCleaner: Sendable {

    private static let removalTimeoutNanoseconds: UInt64 = 2_000_000_000

    public init() { }

    public func hasScreenTimeData() async -> Bool {
        if let history = makeWebHistory(), let hasHistory = await history.hasData(), hasHistory {
            return true
        }

        // Cross-check WebKit when Screen Time reports no history.
        return await hasScreenTimeDataInWebsiteDataStores()
    }

    public func removeScreenTimeData() async {
        if let history = makeWebHistory(), await history.removeData() {
            return
        }

        await removeScreenTimeDataFromWebsiteDataStores()
    }

    private func makeWebHistory() -> ScreenTimeWebHistory? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }

        return ScreenTimeWebHistory(bundleIdentifier: bundleIdentifier)
    }

    @MainActor
    private func hasScreenTimeDataInWebsiteDataStores() async -> Bool {
        guard !Task.isCancelled else { return false }

        let uids = await WKWebsiteDataStore.allDataStoreIdentifiers

        guard !Task.isCancelled else { return false }
        let defaultRecords = await WKWebsiteDataStore.default().dataRecords(ofTypes: [WKWebsiteDataTypeScreenTime])
        guard defaultRecords.isEmpty else { return true }

        for uid in uids {
            guard !Task.isCancelled else { return false }
            let records = await WKWebsiteDataStore(forIdentifier: uid).dataRecords(ofTypes: [WKWebsiteDataTypeScreenTime])
            if !records.isEmpty {
                return true
            }
        }

        return false
    }

    @MainActor
    private func removeScreenTimeDataFromWebsiteDataStores() async {
        let uids = await WKWebsiteDataStore.allDataStoreIdentifiers

        guard !Task.isCancelled else { return }
        guard await removeScreenTimeData(from: .default) else { return }

        for uid in uids {
            guard !Task.isCancelled else { return }
            guard await removeScreenTimeData(from: .identified(uid)) else { return }
        }
    }

    @MainActor
    private func removeScreenTimeData(from dataStore: DataStore) async -> Bool {
        let result = FirstRemovalResult()
        let removalTask = Task { @MainActor in
            let store: WKWebsiteDataStore
            switch dataStore {
            case .identified(let uid):
                store = WKWebsiteDataStore(forIdentifier: uid)
            case .default:
                store = .default()
            }

            await store.removeData(ofTypes: [WKWebsiteDataTypeScreenTime], modifiedSince: .distantPast)
            await result.resolve(with: .completed)
        }
        let timeoutTask = Task.detached {
            do {
                try await Task.sleep(nanoseconds: Self.removalTimeoutNanoseconds)
                await result.resolve(with: .timedOut)
            } catch {
                return
            }
        }

        switch await result.value() {
        case .completed:
            timeoutTask.cancel()
            return true
        case .timedOut:
            removalTask.cancel()
            return false
        }
    }

}

@available(iOS 26, macOS 26, *)
private actor ScreenTimeWebHistory {

    private let bundleIdentifier: String
    private var history: STWebHistory?

    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }

    func hasData() async -> Bool? {
        guard let history = makeHistory() else { return nil }

        return await withCheckedContinuation { continuation in
            history.fetchAllHistory { urls, error in
                guard error == nil else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: urls?.isEmpty == false)
            }
        }
    }

    func removeData() -> Bool {
        guard let history = makeHistory() else { return false }

        history.deleteAllHistory()
        return true
    }

    private func makeHistory() -> STWebHistory? {
        if let history {
            return history
        }

        history = try? STWebHistory(bundleIdentifier: bundleIdentifier)
        return history
    }

}

@available(iOS 26, macOS 26, *)
private extension ScreenTimeDataCleaner {

    enum DataStore: Sendable {
        case identified(UUID)
        case `default`
    }

}

private enum RemovalResult: Sendable {
    case completed
    case timedOut
}

private actor FirstRemovalResult {

    private var result: RemovalResult?
    private var continuation: CheckedContinuation<RemovalResult, Never>?

    func value() async -> RemovalResult {
        if let result {
            return result
        }

        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(with result: RemovalResult) {
        guard self.result == nil else { return }

        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }

}
