//
//  DismissableSyncDeviceButtonModel.swift
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
import CombineExtensions
import Persistence
import AppKit
import DDGSync
import FeatureFlags_macOS
import PixelKit
import PrivacyConfig

@MainActor
public final class DismissableSyncDeviceButtonModel: ObservableObject {
    enum DismissableSyncDevicePromoSource: CaseIterable {
        case bookmarksBar
        case bookmarkAdded

        var wasDismissedKey: String {
            switch self {
            case .bookmarksBar:
                return UserDefaultsKeys.bookmarksBarSyncPromoDismissed.rawValue
            case .bookmarkAdded:
                return "com.duckduckgo.bookmarkAddedSyncPromoDismissed"
            }
        }

        var promoWasPresentedCountKey: String? {
            switch self {
            case .bookmarksBar:
                return nil
            case .bookmarkAdded:
                return "com.duckduckgo.bookmarkAddedSyncPromoPresentedCount"
            }
        }

        var promoFirstPresentedDateKey: String? {
            switch self {
            case .bookmarksBar:
                return UserDefaultsKeys.bookmarksBarSyncPromoFirstPresentedDate.rawValue
            case .bookmarkAdded:
                return nil
            }
        }

        var promoMaxPresentationCount: Int {
            switch self {
            case .bookmarksBar:
                return .max
            case .bookmarkAdded:
                return 5
            }
        }

        var pixelSource: SyncDeviceButtonTouchpoint {
            switch self {
            case .bookmarksBar:
                return SyncDeviceButtonTouchpoint.bookmarksBar
            case .bookmarkAdded:
                return SyncDeviceButtonTouchpoint.bookmarkAdded
            }
        }

        @MainActor
        var promo: BookmarksBarSyncPromoPresenting? {
            switch self {
            case .bookmarksBar:
                return NSApp.delegateTyped.bookmarksBarSyncPromoDelegate
            case .bookmarkAdded:
                return nil
            }
        }
    }

    @Published var shouldShowSyncButton: Bool = false

    private var authState: SyncAuthState = .initializing {
        didSet {
            guard
                featureFlagger.isNewSyncEntryPointsFeatureOn,
                case .inactive = authState,
                !wasDimissed,
                !wasPresentationCountLimitReached else {
                shouldShowSyncButton = false
                return
            }
            shouldShowSyncButton = true
        }
    }

    private let source: DismissableSyncDevicePromoSource
    private let keyValueStore: KeyValueStoring
    private let syncLauncher: SyncDeviceFlowLaunching?
    private let featureFlagger: FeatureFlagger
    private let pixelFiring: PixelFiring?
    private let promo: BookmarksBarSyncPromoPresenting?

    private var cancellables: Set<AnyCancellable> = []
    private var hasFiredImpressionPixel = false

    private var wasDimissed: Bool {
        guard let wasDismissed = keyValueStore.object(forKey: source.wasDismissedKey) as? Bool else {
            return false
        }
        return wasDismissed
    }

    private var wasPresentationCountLimitReached: Bool {
        guard let key = source.promoWasPresentedCountKey else {
            return false
        }
        let count = keyValueStore.object(forKey: key) as? Int ?? 0
        guard count < source.promoMaxPresentationCount else {
            return true
        }
        return false
    }

    init(
        source: DismissableSyncDevicePromoSource,
        keyValueStore: KeyValueStoring,
        authStatePublisher: AnyPublisher<SyncAuthState, Never>,
        initialAuthState: SyncAuthState,
        syncLauncher: SyncDeviceFlowLaunching?,
        featureFlagger: FeatureFlagger = NSApp.delegateTyped.featureFlagger,
        pixelFiring: PixelFiring? = PixelKit.shared,
        promo: BookmarksBarSyncPromoPresenting? = nil
    ) {
        self.source = source
        self.keyValueStore = keyValueStore
        self.syncLauncher = syncLauncher
        self.featureFlagger = featureFlagger
        self.pixelFiring = pixelFiring
        self.promo = promo ?? source.promo

        if let promo = self.promo {
            promo.isPromoActivePublisher
                .assign(to: &$shouldShowSyncButton)
            return
        }

        self.authState = initialAuthState
        authStatePublisher
            .receive(on: DispatchQueue.main)
            .assign(to: \.authState, onWeaklyHeld: self)
            .store(in: &cancellables)
    }

    func viewDidLoad() {
        guard promo == nil else { return }
        guard
            featureFlagger.isNewSyncEntryPointsFeatureOn,
            syncLauncher != nil,
            case .inactive = authState,
            !wasDimissed,
            !incrementPresentationCountLimitReturningLimitReached()
        else {
            shouldShowSyncButton = false
            return
        }
        syncButtonDidAppear()
        shouldShowSyncButton = true
    }

    func syncButtonDidAppear() {
        guard !hasFiredImpressionPixel else { return }
        hasFiredImpressionPixel = true
        pixelFiring?.fire(SyncPromoPixelKitEvent.syncPromoDisplayed, options: .parameters(["source": source.pixelSource.rawValue]))
    }

    func syncButtonAction() {
        promo?.syncSetupStarted()
        syncLauncher?.startDeviceSyncFlow(source: source.pixelSource, completion: nil)
        pixelFiring?.fire(SyncPromoPixelKitEvent.syncPromoConfirmed, options: .parameters(["source": source.pixelSource.rawValue]))
    }

    func dismissSyncButtonAction() {
        shouldShowSyncButton = false
        keyValueStore.set(true, forKey: source.wasDismissedKey)
        pixelFiring?.fire(SyncPromoPixelKitEvent.syncPromoDismissed, options: .parameters(["source": source.pixelSource.rawValue]))
    }

    static func resetAllState(from keyValueStore: KeyValueStoring) {
        for source in DismissableSyncDevicePromoSource.allCases {
            keyValueStore.removeObject(forKey: source.wasDismissedKey)
            if let dateKey = source.promoFirstPresentedDateKey {
                keyValueStore.removeObject(forKey: dateKey)
            }
            if let countKey = source.promoWasPresentedCountKey {
                keyValueStore.removeObject(forKey: countKey)
            }
        }
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
}

extension DismissableSyncDeviceButtonModel {
    /// Decides visibility for buttons that aren't shown through the promo queue.
    struct Legacy {
        let source: DismissableSyncDevicePromoSource
        let keyValueStore: KeyValueStoring
        let syncLauncher: SyncDeviceFlowLaunching?
        let featureFlagger: FeatureFlagger

        func canShowSyncButton(authState: SyncAuthState) -> Bool {
            featureFlagger.isNewSyncEntryPointsFeatureOn
                && authState == .inactive
                && !wasDismissed
                && !wasPresentationCountLimitReached
        }

        private var wasDismissed: Bool {
            keyValueStore.object(forKey: source.wasDismissedKey) as? Bool ?? false
        }

        private var wasPresentationCountLimitReached: Bool {
            guard let key = source.promoWasPresentedCountKey else {
                return false
            }
            let count = keyValueStore.object(forKey: key) as? Int ?? 0
            return count >= source.promoMaxPresentationCount
        }

        func incrementPresentationCountLimitReturningLimitReached() -> Bool {
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
    }
}

extension DismissableSyncDeviceButtonModel {
    convenience init(source: DismissableSyncDevicePromoSource, keyValueStore: KeyValueStoring) {
        let authStatePublisher: AnyPublisher<SyncAuthState, Never>
        let syncLauncher: SyncDeviceFlowLaunching?
        let initialAuthState: SyncAuthState
        if let syncService = NSApp.delegateTyped.syncService, let syncPausedStateManager = NSApp.delegateTyped.syncDataProviders?.syncErrorHandler {
            authStatePublisher = syncService.authStatePublisher
            syncLauncher = DeviceSyncCoordinator(syncService: syncService, syncPausedStateManager: syncPausedStateManager)
            initialAuthState = syncService.authState
        } else {
            authStatePublisher = Just<SyncAuthState>(.initializing).eraseToAnyPublisher()
            syncLauncher = nil
            initialAuthState = .initializing
        }
        self.init(source: source, keyValueStore: keyValueStore, authStatePublisher: authStatePublisher, initialAuthState: initialAuthState, syncLauncher: syncLauncher)
    }
}
