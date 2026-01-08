//
//  HomePageContinueSetUpModel.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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

import AppKit
import BrowserServicesKit
import Combine
import Common
import Foundation
import NewTabPage
import PixelKit
import PrivacyConfig
import Subscription

extension HomePage.Models {

    static let newHomePageTabOpen = Notification.Name("newHomePageAppOpen")

    final class ContinueSetUpModel: ObservableObject {

        enum Const {
            static let featuresPerRow = 2
            static let featureRowCountWhenCollapsed = 1
        }

        let itemWidth = FeaturesGridDimensions.itemWidth
        let itemHeight = FeaturesGridDimensions.itemHeight
        let horizontalSpacing = FeaturesGridDimensions.horizontalSpacing
        let verticalSpacing = FeaturesGridDimensions.verticalSpacing
        let itemsPerRow = Const.featuresPerRow
        let itemsRowCountWhenCollapsed = Const.featureRowCountWhenCollapsed
        let gridWidth = FeaturesGridDimensions.width

        private let defaultBrowserProvider: DefaultBrowserProvider
        private let dockCustomizer: DockCustomization
        private let dataImportProvider: DataImportStatusProviding
        private let emailManager: EmailManager
        private let duckPlayerPreferences: DuckPlayerPreferencesPersistor
        private let subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging
        private let pixelHandler: NewTabPageNextStepsCardsPixelHandling
        private let cardActionsHandler: NewTabPageNextStepsCardsActionHandling

        @UserDefaultsWrapper(key: .homePageShowAllFeatures, defaultValue: false)
        var shouldShowAllFeatures: Bool {
            didSet {
                updateVisibleMatrix()
                shouldShowAllFeaturesSubject.send(shouldShowAllFeatures)
            }
        }

        private var cancellables: Set<AnyCancellable> = []
        let shouldShowAllFeaturesPublisher: AnyPublisher<Bool, Never>
        private let shouldShowAllFeaturesSubject = PassthroughSubject<Bool, Never>()
        private var persistor: HomePageContinueSetUpModelPersisting

        var isMoreOrLessButtonNeeded: Bool {
            return featuresMatrix.count > itemsRowCountWhenCollapsed
        }

        var hasContent: Bool {
            return !featuresMatrix.isEmpty
        }

        lazy var listOfFeatures = persistor.isFirstSession ? firstRunFeatures : randomisedFeatures

        @Published var featuresMatrix: [[FeatureType]] = [[]] {
            didSet {
                updateVisibleMatrix()
            }
        }

        @Published var visibleFeaturesMatrix: [[FeatureType]] = [[]]

        init(defaultBrowserProvider: DefaultBrowserProvider = SystemDefaultBrowserProvider(),
             dockCustomizer: DockCustomization = DockCustomizer(),
             dataImportProvider: DataImportStatusProviding,
             emailManager: EmailManager = EmailManager(),
             duckPlayerPreferences: DuckPlayerPreferencesPersistor = DuckPlayerPreferencesUserDefaultsPersistor(),
             subscriptionCardVisibilityManager: HomePageSubscriptionCardVisibilityManaging,
             persistor: HomePageContinueSetUpModelPersisting,
             pixelHandler: NewTabPageNextStepsCardsPixelHandling,
             cardActionsHandler: NewTabPageNextStepsCardsActionHandling) {

            self.defaultBrowserProvider = defaultBrowserProvider
            self.dockCustomizer = dockCustomizer
            self.dataImportProvider = dataImportProvider
            self.emailManager = emailManager
            self.duckPlayerPreferences = duckPlayerPreferences
            self.subscriptionCardVisibilityManager = subscriptionCardVisibilityManager
            self.pixelHandler = pixelHandler
            self.cardActionsHandler = cardActionsHandler
            self.persistor = persistor

            shouldShowAllFeaturesPublisher = shouldShowAllFeaturesSubject.removeDuplicates().eraseToAnyPublisher()

            refreshFeaturesMatrix()

            NotificationCenter.default.addObserver(self, selector: #selector(newTabOpenNotification(_:)), name: HomePage.Models.newHomePageTabOpen, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)

            // HTML NTP doesn't refresh on appear so we have to connect to the appear signal
            // (the notification in this case) to trigger a refresh.
            NotificationCenter.default.addObserver(self, selector: #selector(refreshFeaturesForHTMLNewTabPage(_:)), name: .newTabPageWebViewDidAppear, object: nil)

            observeSubscriptionCardVisibilityChanges()
        }

        @MainActor func performAction(for featureType: FeatureType) {
            let card = NewTabPageDataModel.CardID(featureType)
            cardActionsHandler.performAction(for: card) { [weak self] in
                self?.refreshFeaturesMatrix()
            }
        }

        func removeItem(for featureType: FeatureType) {
            fireNextStepsCardDismissedPixel(for: featureType)
            switch featureType {
            case .defaultBrowser:
                persistor.shouldShowMakeDefaultSetting = false
            case .dock:
                persistor.shouldShowAddToDockSetting = false
            case .importBookmarksAndPasswords:
                persistor.shouldShowImportSetting = false
            case .duckplayer:
                persistor.shouldShowDuckPlayerSetting = false
            case .emailProtection:
                persistor.shouldShowEmailProtectionSetting = false
            case .subscription:
                pixelHandler.fireSubscriptionCardDismissedPixel()
                subscriptionCardVisibilityManager.dismissSubscriptionCard()
            }
            refreshFeaturesMatrix()
        }

        // MARK: - Pixel Firing

        private func fireNextStepsCardDismissedPixel(for featureType: FeatureType) {
            let card = NewTabPageDataModel.CardID(featureType)
            pixelHandler.fireNextStepsCardDismissedPixel(card)
        }

        private func observeSubscriptionCardVisibilityChanges() {
            subscriptionCardVisibilityManager.shouldShowSubscriptionCardPublisher
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.refreshFeaturesMatrix()
                }
                .store(in: &cancellables)
        }

        func refreshFeaturesMatrix() {
            var features: [FeatureType] = []
            appendFeatureCards(&features)
            if features.isEmpty {
                NSApp.delegateTyped.appearancePreferences.continueSetUpCardsClosed = true
            }
            featuresMatrix = features.chunked(into: itemsPerRow)
        }

        private func appendFeatureCards(_ features: inout [FeatureType]) {
            for feature in listOfFeatures where shouldAppendFeature(feature: feature) {
                features.append(feature)
            }
        }

        private func shouldAppendFeature(feature: FeatureType) -> Bool {
            switch feature {
            case .defaultBrowser:
                return shouldMakeDefaultCardBeVisible
            case .importBookmarksAndPasswords:
                return shouldImportCardBeVisible
            case .dock:
                return shouldDockCardBeVisible
            case .duckplayer:
                return shouldDuckPlayerCardBeVisible
            case .emailProtection:
                return shouldEmailProtectionCardBeVisible
            case .subscription:
                return shouldSubscriptionCardBeVisible
            }
        }

        // Helper Functions
        @MainActor
        @objc private func newTabOpenNotification(_ notification: Notification) {
            if !persistor.isFirstSession {
                listOfFeatures = randomisedFeatures
            }
#if DEBUG
            persistor.isFirstSession = false
#endif
            if OnboardingActionsManager.isOnboardingFinished {
                persistor.isFirstSession = false
            }
        }

        @objc private func windowDidBecomeKey(_ notification: Notification) {
            // Async dispatch allows default browser setting to propagate
            // after being changed in the system dialog
            DispatchQueue.main.async {
                self.refreshFeaturesMatrix()
            }
        }

        @objc private func refreshFeaturesForHTMLNewTabPage(_ notification: Notification) {
            refreshFeaturesMatrix()
        }

        var randomisedFeatures: [FeatureType] {
            var features: [FeatureType]  = [.defaultBrowser]
            var shuffledFeatures = FeatureType.allCases.filter { $0 != .defaultBrowser }
            shuffledFeatures.shuffle()
            features.append(contentsOf: shuffledFeatures)
            return features
        }

        var firstRunFeatures: [FeatureType] {
            var features = FeatureType.allCases.filter { $0 != .duckplayer }
            features.insert(.duckplayer, at: 0)
            return features
        }

        private func updateVisibleMatrix() {
            guard !featuresMatrix.isEmpty else {
                visibleFeaturesMatrix = [[]]
                return
            }
            visibleFeaturesMatrix = shouldShowAllFeatures ? featuresMatrix : [featuresMatrix[0]]
        }

        private var shouldMakeDefaultCardBeVisible: Bool {
            persistor.shouldShowMakeDefaultSetting && !defaultBrowserProvider.isDefault
        }

        private var shouldDockCardBeVisible: Bool {
#if !APPSTORE
            persistor.shouldShowAddToDockSetting && !dockCustomizer.isAddedToDock
#else
            return false
#endif
        }

        private var shouldImportCardBeVisible: Bool {
            persistor.shouldShowImportSetting && !dataImportProvider.didImport
        }

        private var shouldDuckPlayerCardBeVisible: Bool {
            persistor.shouldShowDuckPlayerSetting && duckPlayerPreferences.duckPlayerModeBool == nil && !duckPlayerPreferences.youtubeOverlayAnyButtonPressed
        }

        private var shouldEmailProtectionCardBeVisible: Bool {
            persistor.shouldShowEmailProtectionSetting && !emailManager.isSignedIn
        }

        private var shouldSubscriptionCardBeVisible: Bool {
            subscriptionCardVisibilityManager.shouldShowSubscriptionCard
        }
    }

    // MARK: Feature Type
    enum FeatureType: CaseIterable, Equatable, Hashable {

        // CaseIterable doesn't work with enums that have associated values, so we have to implement it manually.
        // We ignore the `networkProtectionRemoteMessage` case here to avoid it getting accidentally included - it has special handling and will get
        // included elsewhere.
        static var allCases: [HomePage.Models.FeatureType] {
#if APPSTORE
            [.duckplayer, .emailProtection, .defaultBrowser, .importBookmarksAndPasswords, .subscription]
#else
            [.duckplayer, .emailProtection, .defaultBrowser, .dock, .importBookmarksAndPasswords, .subscription]
#endif
        }

        case duckplayer
        case emailProtection
        case defaultBrowser
        case dock
        case importBookmarksAndPasswords
        case subscription
    }

    enum FeaturesGridDimensions {
        static let itemWidth: CGFloat = 240
        static let itemHeight: CGFloat = 160
        static let verticalSpacing: CGFloat = 16
        static let horizontalSpacing: CGFloat = 24

        static let width: CGFloat = (itemWidth + horizontalSpacing) * CGFloat(ContinueSetUpModel.Const.featuresPerRow) - horizontalSpacing

        static func height(for rowCount: Int) -> CGFloat {
            (itemHeight + verticalSpacing) * CGFloat(rowCount) - verticalSpacing
        }
    }
}
