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
import PixelKit
import Subscription
import FeatureFlags

import VPN
import NetworkProtectionUI

protocol ContinueSetUpModelTabOpening {
    @MainActor
    func openTab(_ tab: Tab)
}

struct TabCollectionViewModelTabOpener: ContinueSetUpModelTabOpening {
    let tabCollectionViewModel: TabCollectionViewModel

    @MainActor
    func openTab(_ tab: Tab) {
        tabCollectionViewModel.insertOrAppend(tab: tab, selected: true)
    }
}

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
        let privacyConfigurationManager: PrivacyConfigurationManaging

        var duckPlayerURL: String {
            let duckPlayerSettings = privacyConfigurationManager.privacyConfig.settings(for: .duckPlayer)
            return duckPlayerSettings["tryDuckPlayerLink"] as? String ?? "https://www.youtube.com/watch?v=yKWIA-Pys4c"
        }

        private let defaultBrowserProvider: DefaultBrowserProvider
        private let dockCustomizer: DockCustomization
        private let dataImportProvider: DataImportStatusProviding
        private let tabOpener: ContinueSetUpModelTabOpening
        private let emailManager: EmailManager
        private let duckPlayerPreferences: DuckPlayerPreferencesPersistor
        private let subscriptionManager: any SubscriptionAuthV1toV2Bridge
        private let pixelHandler: (PixelKitEvent, Bool) -> Void

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

        struct Settings {
            @UserDefaultsWrapper(key: .homePageShowMakeDefault, defaultValue: true)
            var shouldShowMakeDefaultSetting: Bool

            @UserDefaultsWrapper(key: .homePageShowAddToDock, defaultValue: true)
            var shouldShowAddToDockSetting: Bool

            @UserDefaultsWrapper(key: .homePageShowImport, defaultValue: true)
            var shouldShowImportSetting: Bool

            @UserDefaultsWrapper(key: .homePageShowDuckPlayer, defaultValue: true)
            var shouldShowDuckPlayerSetting: Bool

            @UserDefaultsWrapper(key: .homePageShowEmailProtection, defaultValue: true)
            var shouldShowEmailProtectionSetting: Bool

            @UserDefaultsWrapper(key: .homePageIsFirstSession, defaultValue: true)
            var isFirstSession: Bool

            @UserDefaultsWrapper(key: .homePageShowSubscription, defaultValue: true)
            var shouldShowSubscriptionSetting: Bool

            @UserDefaultsWrapper(key: .homePageUserHadSubscription, defaultValue: false)
            var userHadSubscription: Bool

            func clear() {
                _shouldShowMakeDefaultSetting.clear()
                _shouldShowAddToDockSetting.clear()
                _shouldShowImportSetting.clear()
                _shouldShowDuckPlayerSetting.clear()
                _shouldShowEmailProtectionSetting.clear()
                _isFirstSession.clear()
                _shouldShowSubscriptionSetting.clear()
                _userHadSubscription.clear()
            }
        }

        private let settings: Settings

        var isMoreOrLessButtonNeeded: Bool {
            return featuresMatrix.count > itemsRowCountWhenCollapsed
        }

        var hasContent: Bool {
            return !featuresMatrix.isEmpty
        }

        lazy var listOfFeatures = settings.isFirstSession ? firstRunFeatures : randomisedFeatures

        @Published var featuresMatrix: [[FeatureType]] = [[]] {
            didSet {
                updateVisibleMatrix()
            }
        }

        @Published var visibleFeaturesMatrix: [[FeatureType]] = [[]]

        private var observer: NSObjectProtocol?

        init(defaultBrowserProvider: DefaultBrowserProvider = SystemDefaultBrowserProvider(),
             dockCustomizer: DockCustomization = DockCustomizer(),
             dataImportProvider: DataImportStatusProviding,
             tabOpener: ContinueSetUpModelTabOpening,
             emailManager: EmailManager = EmailManager(),
             duckPlayerPreferences: DuckPlayerPreferencesPersistor = DuckPlayerPreferencesUserDefaultsPersistor(),
             privacyConfigurationManager: PrivacyConfigurationManaging,
             subscriptionManager: any SubscriptionAuthV1toV2Bridge,
             pixelHandler: @escaping (PixelKitEvent, Bool) -> Void = { PixelKit.fire($0, includeAppVersionParameter: $1) }) {

            self.defaultBrowserProvider = defaultBrowserProvider
            self.dockCustomizer = dockCustomizer
            self.dataImportProvider = dataImportProvider
            self.tabOpener = tabOpener
            self.emailManager = emailManager
            self.duckPlayerPreferences = duckPlayerPreferences
            self.privacyConfigurationManager = privacyConfigurationManager
            self.subscriptionManager = subscriptionManager
            self.pixelHandler = pixelHandler
            self.settings = .init()

            shouldShowAllFeaturesPublisher = shouldShowAllFeaturesSubject.removeDuplicates().eraseToAnyPublisher()

            refreshFeaturesMatrix()

            NotificationCenter.default.addObserver(self, selector: #selector(newTabOpenNotification(_:)), name: HomePage.Models.newHomePageTabOpen, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: nil)

            // HTML NTP doesn't refresh on appear so we have to connect to the appear signal
            // (the notification in this case) to trigger a refresh.
            NotificationCenter.default.addObserver(self, selector: #selector(refreshFeaturesForHTMLNewTabPage(_:)), name: .newTabPageWebViewDidAppear, object: nil)

            observeSubscriptionDidChange()
            checkCachedSubscription()

        }

        private func checkCachedSubscription() {
            Task { @MainActor in
                let currentSubscription = try? await subscriptionManager.getSubscription(cachePolicy: .cacheFirst)
                if currentSubscription != nil {
                    // Prevent card from showing again if the user has any kind of subscription.
                    settings.userHadSubscription = true
                }
                refreshFeaturesMatrix()
            }
        }

        private func observeSubscriptionDidChange() {
            observer = NotificationCenter.default.addObserver(forName: .subscriptionDidChange, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                // Prevent card from showing again if the user has any kind of subscription.
                settings.userHadSubscription = true
                refreshFeaturesMatrix()
            }
        }

        @MainActor func performAction(for featureType: FeatureType) {
            switch featureType {
            case .defaultBrowser:
                performDefaultBrowserAction()
            case .dock:
                performDockAction()
            case .importBookmarksAndPasswords:
                performImportBookmarksAndPasswordsAction()
            case .duckplayer:
                performDuckPlayerAction()
            case .emailProtection:
                performEmailProtectionAction()
            case .subscription:
                performSubscriptionAction()
            }
        }

        private func performDefaultBrowserAction() {
            do {
                pixelHandler(GeneralPixel.defaultRequestedFromHomepageSetupView, true)
                try defaultBrowserProvider.presentDefaultBrowserPrompt()
            } catch {
                defaultBrowserProvider.openSystemPreferences()
            }
        }

        private func performImportBookmarksAndPasswordsAction() {
            dataImportProvider.showImportWindow(customTitle: nil, completion: { self.refreshFeaturesMatrix() })
        }

        @MainActor
        private func performDuckPlayerAction() {
            if let videoUrl = URL(string: duckPlayerURL) {
                let tab = Tab(content: .url(videoUrl, source: .link), shouldLoadInBackground: true)
                tabOpener.openTab(tab)
            }
        }

        @MainActor
        private func performEmailProtectionAction() {
            let tab = Tab(content: .url(EmailUrls().emailProtectionLink, source: .ui), shouldLoadInBackground: true)
            tabOpener.openTab(tab)
        }

        func performDockAction() {
            pixelHandler(GeneralPixel.userAddedToDockFromNewTabPageCard, false)
            dockCustomizer.addToDock()
        }

        @MainActor
        private func performSubscriptionAction() {
            pixelHandler(SubscriptionPixel.subscriptionNewTabPageNextStepsCardClicked, true)
            guard let url = SubscriptionURL.purchaseURLComponentsWithOrigin(SubscriptionFunnelOrigin.onboarding.rawValue)?.url else {
                return
            }

            let tab = Tab(content: .url(url, source: .link), shouldLoadInBackground: true)
            tabOpener.openTab(tab)
        }

        func removeItem(for featureType: FeatureType) {
            switch featureType {
            case .defaultBrowser:
                settings.shouldShowMakeDefaultSetting = false
            case .dock:
                settings.shouldShowAddToDockSetting = false
            case .importBookmarksAndPasswords:
                settings.shouldShowImportSetting = false
            case .duckplayer:
                settings.shouldShowDuckPlayerSetting = false
            case .emailProtection:
                settings.shouldShowEmailProtectionSetting = false
            case .subscription:
                pixelHandler(SubscriptionPixel.subscriptionNewTabPageNextStepsCardDismissed, true)
                settings.shouldShowSubscriptionSetting = false
            }
            refreshFeaturesMatrix()
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
            if !settings.isFirstSession {
                listOfFeatures = randomisedFeatures
            }
#if DEBUG
            settings.isFirstSession = false
#endif
            if OnboardingActionsManager.isOnboardingFinished {
                settings.isFirstSession = false
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
            settings.shouldShowMakeDefaultSetting && !defaultBrowserProvider.isDefault
        }

        private var shouldDockCardBeVisible: Bool {
#if !APPSTORE
            settings.shouldShowAddToDockSetting && !dockCustomizer.isAddedToDock
#else
            return false
#endif
        }

        private var shouldImportCardBeVisible: Bool {
            settings.shouldShowImportSetting && !dataImportProvider.didImport
        }

        private var shouldDuckPlayerCardBeVisible: Bool {
            settings.shouldShowDuckPlayerSetting && duckPlayerPreferences.duckPlayerModeBool == nil && !duckPlayerPreferences.youtubeOverlayAnyButtonPressed
        }

        private var shouldEmailProtectionCardBeVisible: Bool {
            settings.shouldShowEmailProtectionSetting && !emailManager.isSignedIn
        }

        private var shouldSubscriptionCardBeVisible: Bool {
            settings.shouldShowSubscriptionSetting && !settings.userHadSubscription
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
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
