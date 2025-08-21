//
//  SyncDeviceButtonModel.swift
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

import Combine
import Persistence
import AppKit

@MainActor
public final class SyncDeviceButtonModel: ObservableObject {
    enum SyncDevicePromoSource: CaseIterable {
        case bookmarksBar
        case bookmarkAdded

        fileprivate var wasDismissedKey: String {
            switch self {
            case .bookmarksBar:
                return "com.duckduckgo.bookmarksBarSyncPromoDismissed"
            case .bookmarkAdded:
                return "com.duckduckgo.bookmarkAddedSyncPromoDismissed"
            }
        }

        fileprivate var promoWasPresentedCountKey: String? {
            switch self {
            case .bookmarksBar:
                return nil
            case .bookmarkAdded:
                return "com.duckduckgo.bookmarkAddedSyncPromoPresentedCount"
            }
        }

        fileprivate var promoFirstPresentedDateKey: String? {
            switch self {
            case .bookmarksBar:
                return "com.duckduckgo.bookmarkFirstPresentedCount"
            case .bookmarkAdded:
                return nil
            }
        }

        fileprivate var promoMaxPresentationCount: Int {
            switch self {
            case .bookmarksBar:
                return .max
            case .bookmarkAdded:
                return 5
            }
        }

        fileprivate var promoMaxPresentationDays: Int {
            switch self {
            case .bookmarksBar:
                return 7
            case .bookmarkAdded:
                return .max
            }
        }
    }

    lazy var syncLauncher: SyncDeviceFlowLaunching? = DeviceSyncCoordinator()

    @Published var shouldShowSyncButton: Bool = false

    private let source: SyncDevicePromoSource
    private let keyValueStore: KeyValueStoring

    init(source: SyncDevicePromoSource, keyValueStore: KeyValueStoring) {
        self.source = source
        self.keyValueStore = keyValueStore
    }

    func viewDidLoad() {
        guard
            !wasDimissed(),
            !incrementPresentationCountLimitReturningLimitReached(),
            !setFirstSeenDateReturningHasExpired()
        else {
            shouldShowSyncButton = false
            return
        }
        shouldShowSyncButton = true
    }

    func syncButtonAction() {
        syncLauncher?.startDeviceSyncFlow(completion: nil)
    }

    func dismissSyncButtonAction() {
        shouldShowSyncButton = false
        keyValueStore.set(true, forKey: source.wasDismissedKey)
    }

    static func resetAllState(from keyValueStore: KeyValueStoring) {
        for source in SyncDevicePromoSource.allCases {
            keyValueStore.removeObject(forKey: source.wasDismissedKey)
            if let dateKey = source.promoFirstPresentedDateKey {
                keyValueStore.removeObject(forKey: dateKey)
            }
            if let countKey = source.promoWasPresentedCountKey {
                keyValueStore.removeObject(forKey: countKey)
            }
        }
    }

    private func wasDimissed() -> Bool {
        guard let wasDismissed = keyValueStore.object(forKey: source.wasDismissedKey) as? Bool else {
            return false
        }
        return wasDismissed
    }

    private func incrementPresentationCountLimitReturningLimitReached() -> Bool {
        guard let key = source.promoWasPresentedCountKey else {
            return false
        }
        let count = keyValueStore.object(forKey: key) as? Int ?? 0
        guard count < source.promoMaxPresentationCount else {
            return true
        }
        keyValueStore.set(count + 1, forKey: key)
        return false
    }

    private func setFirstSeenDateReturningHasExpired() -> Bool {
        guard let key = source.promoFirstPresentedDateKey else {
            return false
        }
        guard let firstSeenDate = keyValueStore.object(forKey: key) as? Date else {
            keyValueStore.set(Date(), forKey: key)
            return false
        }

        return !firstSeenDate.isLessThan(daysAgo: source.promoMaxPresentationDays)
    }
}
