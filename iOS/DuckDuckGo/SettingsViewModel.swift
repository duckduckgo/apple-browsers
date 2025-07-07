//
//  SettingsViewModel.swift
//  DuckDuckGo
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

import Core
import BrowserServicesKit
import Persistence
import SwiftUI
import Common
import Combine
import SyncUI_iOS
import DuckPlayer
import Crashes

import Subscription
import VPN
import AIChat

final class SettingsViewModel: ObservableObject {

    // Dependencies
    private(set) lazy var appSettings = AppDependencyProvider.shared.appSettings
    private(set) var privacyStore = PrivacyUserDefaults()
    private lazy var featureFlagger = AppDependencyProvider.shared.featureFlagger
    private lazy var animator: FireButtonAnimator = FireButtonAnimator(appSettings: AppUserDefaults())
    private var legacyViewProvider: SettingsLegacyViewProvider
    private lazy var versionProvider: AppVersion = AppVersion.shared
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let syncPausedStateManager: any SyncPausedStateManaging
    var emailManager: EmailManager { EmailManager() }
    private let historyManager: HistoryManaging
    let privacyProDataReporter: PrivacyProDataReporting?
    let textZoomCoordinator: TextZoomCoordinating
    let aiChatSettings: AIChatSettingsProvider
    let maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging
    let themeManager: ThemeManaging
    var experimentalAIChatManager: ExperimentalAIChatManager
    private let duckPlayerSettings: DuckPlayerSettings
    private let duckPlayerPixelHandler: DuckPlayerPixelFiring.Type
    let featureDiscovery: FeatureDiscovery
    private let urlOpener: URLOpener

    // Subscription Dependencies
    let isAuthV2Enabled: Bool
    let subscriptionManagerV1: (any SubscriptionManager)?
    let subscriptionManagerV2: (any SubscriptionManagerV2)?
    let subscriptionAuthV1toV2Bridge: any SubscriptionAuthV1toV2Bridge
    let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private var subscriptionSignOutObserver: Any?
    var duckPlayerContingencyHandler: DuckPlayerContingencyHandler {
        DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: ContentBlocking.shared.privacyConfigurationManager)
    }

    private enum UserDefaultsCacheKey: String, UserDefaultsCacheKeyStore {
        case subscriptionState = "com.duckduckgo.ios.subscription.state"
    }
    // Used to cache the lasts subscription state for up to a week
    private let subscriptionStateCache = UserDefaultsCache<SettingsState.Subscription>(key: UserDefaultsCacheKey.subscriptionState,
                                                                         settings: UserDefaultsCacheSettings(defaultExpirationInterval: .days(7)))
    // Properties
    private lazy var isPad = UIDevice.current.userInterfaceIdiom == .pad
    private var cancellables = Set<AnyCancellable>()

    // App Data State Notification Observer
    private var appDataClearingObserver: Any?
    private var textZoomObserver: Any?
    private var appForegroundObserver: Any?

    // Subscription Free Trials
    private let subscriptionFreeTrialsHelper: SubscriptionFreeTrialsHelping

    private let keyValueStore: ThrowingKeyValueStoring

    // Closures to interact with legacy view controllers through the container
    var onRequestPushLegacyView: ((UIViewController) -> Void)?
    var onRequestPresentLegacyView: ((UIViewController, _ modal: Bool) -> Void)?
    var onRequestPopLegacyView: (() -> Void)?
    var onRequestDismissSettings: (() -> Void)?

    // View State
    @Published private(set) var state: SettingsState

    // MARK: Cell Visibility
    enum Features {
        case sync
        case autofillAccessCredentialManagement
        case zoomLevel
        case voiceSearch
        case addressbarPosition
        case speechRecognition
        case networkProtection
    }

    // Indicates if the Paid AI Chat feature flag is enabled for the current user/session.
    var isPaidAIChatEnabled: Bool {
        featureFlagger.isFeatureOn(.paidAIChat)
    }

    var shouldShowNoMicrophonePermissionAlert: Bool = false
    @Published var shouldShowEmailAlert: Bool = false

    @Published var shouldShowRecentlyVisitedSites: Bool = true

    @Published var isInternalUser: Bool = AppDependencyProvider.shared.internalUserDecider.isInternalUser

    @Published var selectedFeedbackFlow: String?

    @Published var shouldShowSetAsDefaultBrowser: Bool = false
    @Published var shouldShowImportPasswords: Bool = false

    // MARK: - Deep linking
    // Used to automatically navigate to a specific section
    // immediately after loading the Settings View
    @Published private(set) var deepLinkTarget: SettingsDeepLinkSection?

    // MARK: Bindings

    var themeStyleBinding: Binding<ThemeStyle> {
        Binding<ThemeStyle>(
            get: { self.state.appThemeStyle },
            set: {
                Pixel.fire(pixel: .settingsThemeSelectorPressed)
                self.state.appThemeStyle = $0
                ThemeManager.shared.setThemeStyle($0)
            }
        )
    }
    var fireButtonAnimationBinding: Binding<FireButtonAnimationType> {
        Binding<FireButtonAnimationType>(
            get: { self.state.fireButtonAnimation },
            set: {
                Pixel.fire(pixel: .settingsFireButtonSelectorPressed)
                self.appSettings.currentFireButtonAnimation = $0
                self.state.fireButtonAnimation = $0
                NotificationCenter.default.post(name: AppUserDefaults.Notifications.currentFireButtonAnimationChange, object: self)
                self.animator.animate {
                    // no op
                } onTransitionCompleted: {
                    // no op
                } completion: {
                    // no op
                }
            }
        )
    }

    var addressBarPositionBinding: Binding<AddressBarPosition> {
        Binding<AddressBarPosition>(
            get: {
                self.state.addressBar.position
            },
            set: {
                Pixel.fire(pixel: $0 == .top ? .settingsAddressBarTopSelected : .settingsAddressBarBottomSelected)
                self.appSettings.currentAddressBarPosition = $0
                self.state.addressBar.position = $0
            }
        )
    }

    var addressBarShowsFullURL: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.showsFullURL },
            set: {
                Pixel.fire(pixel: $0 ? .settingsShowFullURLOn : .settingsShowFullURLOff)
                self.state.showsFullURL = $0
                self.appSettings.showFullSiteAddress = $0
            }
        )
    }

    var experimentalThemingBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.isExperimentalThemingEnabled },
            set: { _ in
                self.themeManager.toggleExperimentalTheming()

                // The theme manager is caching the value, so we use previous state to update the UI.
                // Changes will be applied after restart.
                self.state.isExperimentalThemingEnabled = !self.state.isExperimentalThemingEnabled
            })
    }


    var applicationLockBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.applicationLock },
            set: {
                self.privacyStore.authenticationEnabled = $0
                self.state.applicationLock = $0
            }
        )
    }

    var autocompleteGeneralBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.autocomplete },
            set: {
                self.appSettings.autocomplete = $0
                self.state.autocomplete = $0
                self.clearHistoryIfNeeded()
                self.updateRecentlyVisitedSitesVisibility()
                
                if $0 {
                    Pixel.fire(pixel: .settingsGeneralAutocompleteOn)
                } else {
                    Pixel.fire(pixel: .settingsGeneralAutocompleteOff)
                }
            }
        )
    }

    var autocompletePrivateSearchBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.autocomplete },
            set: {
                self.appSettings.autocomplete = $0
                self.state.autocomplete = $0
                self.clearHistoryIfNeeded()
                self.updateRecentlyVisitedSitesVisibility()

                if $0 {
                    Pixel.fire(pixel: .settingsPrivateSearchAutocompleteOn)
                } else {
                    Pixel.fire(pixel: .settingsPrivateSearchAutocompleteOff)
                }
            }
        )
    }

    var autocompleteRecentlyVisitedSitesBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.recentlyVisitedSites },
            set: {
                self.appSettings.recentlyVisitedSites = $0
                self.state.recentlyVisitedSites = $0
                if $0 {
                    Pixel.fire(pixel: .settingsRecentlyVisitedOn)
                } else {
                    Pixel.fire(pixel: .settingsRecentlyVisitedOff)
                }
                self.clearHistoryIfNeeded()
            }
        )
    }

    var gpcBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.sendDoNotSell },
            set: {
                self.appSettings.sendDoNotSell = $0
                self.state.sendDoNotSell = $0
                NotificationCenter.default.post(name: AppUserDefaults.Notifications.doNotSellStatusChange, object: nil)
                if $0 {
                    Pixel.fire(pixel: .settingsGpcOn)
                } else {
                    Pixel.fire(pixel: .settingsGpcOff)
                }
            }
        )
    }

    var autoconsentBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.autoconsentEnabled },
            set: {
                self.appSettings.autoconsentEnabled = $0
                self.state.autoconsentEnabled = $0
                if $0 {
                    Pixel.fire(pixel: .settingsAutoconsentOn)
                } else {
                    Pixel.fire(pixel: .settingsAutoconsentOff)
                }
            }
        )
    }

    var voiceSearchEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.voiceSearchEnabled },
            set: { newValue in
                self.setVoiceSearchEnabled(to: newValue)
                if newValue {
                    Pixel.fire(pixel: .settingsVoiceSearchOn)
                } else {
                    Pixel.fire(pixel: .settingsVoiceSearchOff)
                }
            }
        )
    }

    var textZoomLevelBinding: Binding<TextZoomLevel> {
        Binding<TextZoomLevel>(
            get: { self.state.textZoom.level },
            set: { newValue in
                Pixel.fire(.settingsAccessiblityTextZoom, withAdditionalParameters: [
                    PixelParameters.textZoomInitial: String(self.appSettings.defaultTextZoomLevel.rawValue),
                    PixelParameters.textZoomUpdated: String(newValue.rawValue),
                ])
                self.appSettings.defaultTextZoomLevel = newValue
                self.state.textZoom.level = newValue
            }
        )
    }

    var duckPlayerModeBinding: Binding<DuckPlayerMode> {
        Binding<DuckPlayerMode>(
            get: {
                return self.state.duckPlayerMode ?? .alwaysAsk
            },
            set: {
                self.appSettings.duckPlayerMode = $0
                self.state.duckPlayerMode = $0
                
                switch self.state.duckPlayerMode {
                case .alwaysAsk:
                    Pixel.fire(pixel: Pixel.Event.duckPlayerSettingBackToDefault)
                case .disabled:
                    Pixel.fire(pixel: Pixel.Event.duckPlayerSettingNeverSettings)
                case .enabled:
                    Pixel.fire(pixel: Pixel.Event.duckPlayerSettingAlwaysSettings)
                default:
                    break
                }
            }
        )
    }
    
    var duckPlayerOpenInNewTabBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.duckPlayerOpenInNewTab },
            set: {
                self.appSettings.duckPlayerOpenInNewTab = $0
                self.state.duckPlayerOpenInNewTab = $0
                if self.state.duckPlayerOpenInNewTab {
                    Pixel.fire(pixel: Pixel.Event.duckPlayerNewTabSettingOn)
                } else {
                    Pixel.fire(pixel: Pixel.Event.duckPlayerNewTabSettingOff)
                }
            }
        )
    }
    
    var duckPlayerNativeUI: Binding<Bool> {
        Binding<Bool>(
            get: {
                (self.featureFlagger.isFeatureOn(.duckPlayerNativeUI) || self.isInternalUser) &&
                UIDevice.current.userInterfaceIdiom == .phone
            },
            set: { _ in }
        )
    }
    
    var duckPlayerAutoplay: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.duckPlayerAutoplay },
            set: {
                self.appSettings.duckPlayerAutoplay = $0
                self.state.duckPlayerAutoplay = $0
            }
        )
    }

    var duckPlayerNativeUISERPEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.duckPlayerNativeUISERPEnabled },
            set: {
                self.appSettings.duckPlayerNativeUISERPEnabled = $0
                self.state.duckPlayerNativeUISERPEnabled = $0
                self.duckPlayerPixelHandler.fire($0 ? .duckPlayerNativeSettingsSerpOn : .duckPlayerNativeSettingsSerpOff)
            }
        )
    }

      var duckPlayerNativeYoutubeModeBinding: Binding<NativeDuckPlayerYoutubeMode> {
        Binding<NativeDuckPlayerYoutubeMode>(
            get: {
                return self.state.duckPlayerNativeYoutubeMode
            },
            set: {
                self.appSettings.duckPlayerNativeYoutubeMode = $0
                self.state.duckPlayerNativeYoutubeMode = $0

                switch $0 {
                case .auto:
                    self.duckPlayerPixelHandler.fire(.duckPlayerNativeSettingsYoutubeAutomatic)
                case .ask:
                    self.duckPlayerPixelHandler.fire(.duckPlayerNativeSettingsYoutubeChoose)
                case .never:
                    self.duckPlayerPixelHandler.fire(.duckPlayerNativeSettingsYoutubeDontShow)
                }
            }
        )
    }

    var duckPlayerVariantBinding: Binding<DuckPlayerVariant> {
        Binding<DuckPlayerVariant>(
            get: {
                return self.duckPlayerSettings.variant
            },
            set: {
                self.duckPlayerSettings.variant = $0
            }
        )
    }

    func setVoiceSearchEnabled(to value: Bool) {
        if value {
            enableVoiceSearch { [weak self] result in
                DispatchQueue.main.async {
                    self?.state.voiceSearchEnabled = result
                    self?.voiceSearchHelper.enableVoiceSearch(true)
                    if !result {
                        // Permission is denied
                        self?.shouldShowNoMicrophonePermissionAlert = true
                    }
                }
            }
        } else {
            voiceSearchHelper.enableVoiceSearch(false)
            state.voiceSearchEnabled = false
        }
    }

    var longPressBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.longPressPreviews },
            set: {
                self.appSettings.longPressPreviews = $0
                self.state.longPressPreviews = $0
            }
        )
    }

    var universalLinksBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.allowUniversalLinks },
            set: {
                self.appSettings.allowUniversalLinks = $0
                self.state.allowUniversalLinks = $0
            }
        )
    }

    var crashCollectionOptInStatusBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.crashCollectionOptInStatus == .optedIn },
            set: {
                if self.appSettings.crashCollectionOptInStatus == .optedIn && $0 == false {
                    let crashCollection = CrashCollection(crashReportSender: CrashReportSender(platform: .iOS, pixelEvents: CrashReportSender.pixelEvents))
                    crashCollection.clearCRCID()
                }
                self.appSettings.crashCollectionOptInStatus = $0 ? .optedIn : .optedOut
                self.state.crashCollectionOptInStatus = $0 ? .optedIn : .optedOut
            }
        )
    }

    var cookiePopUpProtectionStatus: StatusIndicator {
        return appSettings.autoconsentEnabled ? .on : .off
    }
    
    var emailProtectionStatus: StatusIndicator {
        return emailManager.isSignedIn ? .on : .off
    }
    
    var syncStatus: StatusIndicator {
        legacyViewProvider.syncService.authState != .inactive ? .on : .off
    }

    var enablesUnifiedFeedbackForm: Bool {
        subscriptionAuthV1toV2Bridge.isUserAuthenticated
    }

    // Indicates if the Paid AI Chat entitlement flag is available for the current user
    var isPaidAIChatAvailable: Bool {
        state.subscription.subscriptionFeatures.contains(Entitlement.ProductName.paidAIChat)
    }

    // MARK: Default Init
    init(state: SettingsState? = nil,
         legacyViewProvider: SettingsLegacyViewProvider,
         isAuthV2Enabled: Bool,
         subscriptionManagerV1: (any SubscriptionManager)?,
         subscriptionManagerV2: (any SubscriptionManagerV2)?,
         subscriptionAuthV1toV2Bridge: any SubscriptionAuthV1toV2Bridge,
         subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
         voiceSearchHelper: VoiceSearchHelperProtocol,
         variantManager: VariantManager = AppDependencyProvider.shared.variantManager,
         deepLink: SettingsDeepLinkSection? = nil,
         historyManager: HistoryManaging,
         syncPausedStateManager: any SyncPausedStateManaging,
         privacyProDataReporter: PrivacyProDataReporting,
         textZoomCoordinator: TextZoomCoordinating,
         aiChatSettings: AIChatSettingsProvider,
         maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging,
         themeManager: ThemeManaging = ThemeManager.shared,
         experimentalAIChatManager: ExperimentalAIChatManager,
         duckPlayerSettings: DuckPlayerSettings = DuckPlayerSettingsDefault(),
         duckPlayerPixelHandler: DuckPlayerPixelFiring.Type = DuckPlayerPixelHandler.self,
         featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery(),
         subscriptionFreeTrialsHelper: SubscriptionFreeTrialsHelping = SubscriptionFreeTrialsHelper(),
         urlOpener: URLOpener = UIApplication.shared,
         keyValueStore: ThrowingKeyValueStoring
    ) {

        self.state = SettingsState.defaults
        self.legacyViewProvider = legacyViewProvider
        self.isAuthV2Enabled = isAuthV2Enabled
        self.subscriptionManagerV1 = subscriptionManagerV1
        self.subscriptionManagerV2 = subscriptionManagerV2
        self.subscriptionAuthV1toV2Bridge = subscriptionAuthV1toV2Bridge
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.voiceSearchHelper = voiceSearchHelper
        self.deepLinkTarget = deepLink
        self.historyManager = historyManager
        self.syncPausedStateManager = syncPausedStateManager
        self.privacyProDataReporter = privacyProDataReporter
        self.textZoomCoordinator = textZoomCoordinator
        self.aiChatSettings = aiChatSettings
        self.maliciousSiteProtectionPreferencesManager = maliciousSiteProtectionPreferencesManager
        self.themeManager = themeManager
        self.experimentalAIChatManager = experimentalAIChatManager
        self.duckPlayerSettings = duckPlayerSettings
        self.duckPlayerPixelHandler = duckPlayerPixelHandler
        self.featureDiscovery = featureDiscovery
        self.subscriptionFreeTrialsHelper = subscriptionFreeTrialsHelper
        self.urlOpener = urlOpener
        self.keyValueStore = keyValueStore
        setupNotificationObservers()
        updateRecentlyVisitedSitesVisibility()
    }

    deinit {
        subscriptionSignOutObserver = nil
        appDataClearingObserver = nil
        textZoomObserver = nil
        if #available(iOS 18.2, *) {
            appForegroundObserver = nil
        }
    }
}

// MARK: Private methods
extension SettingsViewModel {
    
    // This manual (re)initialization will go away once appSettings and
    // other dependencies are observable (Such as AppIcon and netP)
    // and we can use subscribers (Currently called from the view onAppear)
    @MainActor
    private func initState() {
        self.state = SettingsState(
            appThemeStyle: appSettings.currentThemeStyle,
            appIcon: AppIconManager.shared.appIcon,
            fireButtonAnimation: appSettings.currentFireButtonAnimation,
            textZoom: SettingsState.TextZoom(enabled: textZoomCoordinator.isEnabled, level: appSettings.defaultTextZoomLevel),
            addressBar: SettingsState.AddressBar(enabled: !isPad, position: appSettings.currentAddressBarPosition),
            showsFullURL: appSettings.showFullSiteAddress,
            isExperimentalThemingEnabled: themeManager.properties.isExperimentalThemingEnabled,
            isExperimentalAIChatEnabled: experimentalAIChatManager.isExperimentalAIChatSettingsEnabled,
            isExperimentalAIChatTransitionEnabled: experimentalAIChatManager.isExperimentalTransitionEnabled,
            sendDoNotSell: appSettings.sendDoNotSell,
            autoconsentEnabled: appSettings.autoconsentEnabled,
            autoclearDataEnabled: AutoClearSettingsModel(settings: appSettings) != nil,
            applicationLock: privacyStore.authenticationEnabled,
            autocomplete: appSettings.autocomplete,
            recentlyVisitedSites: appSettings.recentlyVisitedSites,
            longPressPreviews: appSettings.longPressPreviews,
            allowUniversalLinks: appSettings.allowUniversalLinks,
            activeWebsiteAccount: nil,
            activeWebsiteCreditCard: nil,
            showCreditCardManagement: false,
            version: versionProvider.versionAndBuildNumber,
            crashCollectionOptInStatus: appSettings.crashCollectionOptInStatus,
            debugModeEnabled: featureFlagger.isFeatureOn(.debugMenu) || isDebugBuild,
            voiceSearchEnabled: voiceSearchHelper.isVoiceSearchEnabled,
            speechRecognitionAvailable: voiceSearchHelper.isSpeechRecognizerAvailable,
            loginsEnabled: featureFlagger.isFeatureOn(.autofillAccessCredentialManagement),
            networkProtectionConnected: false,
            subscription: SettingsState.defaults.subscription,
            sync: getSyncState(),
            syncSource: nil,
            duckPlayerEnabled: featureFlagger.isFeatureOn(.duckPlayer) || shouldDisplayDuckPlayerContingencyMessage,
            duckPlayerMode: duckPlayerSettings.mode,
            duckPlayerOpenInNewTab: duckPlayerSettings.openInNewTab,
            duckPlayerOpenInNewTabEnabled: featureFlagger.isFeatureOn(.duckPlayerOpenInNewTab),
            duckPlayerAutoplay: duckPlayerSettings.autoplay,
            duckPlayerNativeUISERPEnabled: duckPlayerSettings.nativeUISERPEnabled,
            duckPlayerNativeYoutubeMode: duckPlayerSettings.nativeUIYoutubeMode
        )

        // Subscribe to DuckPlayerSettings updates
        duckPlayerSettings.duckPlayerSettingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDuckPlayerState()
            }
            .store(in: &cancellables)

        updateRecentlyVisitedSitesVisibility()

        if #available(iOS 18.2, *) {
            updateCompleteSetupSectionVisiblity()
        }

        setupSubscribers()
        Task { await setupSubscriptionEnvironment() }
    }

    private func updateRecentlyVisitedSitesVisibility() {
        withAnimation {
            shouldShowRecentlyVisitedSites = historyManager.isHistoryFeatureEnabled() && state.autocomplete
        }
    }

    private func clearHistoryIfNeeded() {
        if !historyManager.isEnabledByUser {
            Task {
                await self.historyManager.removeAllHistory()
            }
        }
    }

    private func getSyncState() -> SettingsState.SyncSettings {
        SettingsState.SyncSettings(enabled: legacyViewProvider.syncService.featureFlags.contains(.userInterface),
                                   title: {
            let syncService = legacyViewProvider.syncService
            let isDataSyncingDisabled = !syncService.featureFlags.contains(.dataSyncing)
            && syncService.authState == .active
            if isDataSyncingDisabled
                || syncPausedStateManager.isSyncPaused
                || syncPausedStateManager.isSyncBookmarksPaused
                || syncPausedStateManager.isSyncCredentialsPaused {
                return "⚠️ \(UserText.settingsSync)"
            }
            return SyncUI_iOS.UserText.syncTitle
        }())
    }

    private func firePixel(_ event: Pixel.Event,
                           withAdditionalParameters params: [String: String] = [:]) {
        Pixel.fire(pixel: event, withAdditionalParameters: params)
    }
    
    private func enableVoiceSearch(completion: @escaping (Bool) -> Void) {
        SpeechRecognizer.requestMicAccess { permission in
            if !permission {
                completion(false)
                return
            }
            completion(true)
        }
    }

    private func updateNetPStatus(connectionStatus: ConnectionStatus) {
        switch connectionStatus {
        case .connected:
            self.state.networkProtectionConnected = true
        default:
            self.state.networkProtectionConnected = false
        }
    }
    
    // Function to update local state from DuckPlayerSettings
    private func updateDuckPlayerState() {
        state.duckPlayerMode = duckPlayerSettings.mode
        state.duckPlayerOpenInNewTab = duckPlayerSettings.openInNewTab
        state.duckPlayerAutoplay = duckPlayerSettings.autoplay
        state.duckPlayerNativeUISERPEnabled = duckPlayerSettings.nativeUISERPEnabled
        state.duckPlayerNativeYoutubeMode = duckPlayerSettings.nativeUIYoutubeMode
    }

    @available(iOS 18.2, *)
    private func updateCompleteSetupSectionVisiblity() {
        guard featureFlagger.isFeatureOn(.showSettingsCompleteSetupSection) else {
            return
        }

        if let didDismissBrowserPrompt = try? keyValueStore.object(forKey: Constants.didDismissSetAsDefaultBrowserKey) as? Bool {
            shouldShowSetAsDefaultBrowser = !didDismissBrowserPrompt
        } else {
            // No dismissal record found, show by default
            shouldShowSetAsDefaultBrowser = true
        }

        if let didDismissImportPrompt = try? keyValueStore.object(forKey: Constants.didDismissImportPasswordsKey) as? Bool {
            shouldShowImportPasswords = !didDismissImportPrompt
        } else {
            // No dismissal record found, show by default
            shouldShowImportPasswords = true
        }

        // Only proceed with checks if one of the rows from this section has not already been dismissed
        guard shouldShowSetAsDefaultBrowser || shouldShowImportPasswords else {
            return
        }

        if let secureVault = try? AutofillSecureVaultFactory.makeVault(reporter: SecureVaultReporter()),
           let passwordsCount = try? secureVault.accountsCount(),
           passwordsCount >= 25 {
            permanentlyDismissCompleteSetupSection()
            return
        }

        if let checkIfDefaultBrowser = try? keyValueStore.object(forKey: Constants.shouldCheckIfDefaultBrowserKey) as? Bool {
            do {
                if checkIfDefaultBrowser, try UIApplication.shared.isDefault(.webBrowser) {
                    try? keyValueStore.set(true, forKey: Constants.didDismissSetAsDefaultBrowserKey)
                    shouldShowSetAsDefaultBrowser = false
                }
            } catch {
                try? keyValueStore.set(true, forKey: Constants.didDismissSetAsDefaultBrowserKey)
                shouldShowSetAsDefaultBrowser = false
            }

            // only want to check default browser state once after the first time a user interacts with this row due to API restrictions. After that users can swipe to dismiss
            try? keyValueStore.set(false, forKey: Constants.shouldCheckIfDefaultBrowserKey)
        }
    }

    private func permanentlyDismissCompleteSetupSection() {
        try? keyValueStore.set(true, forKey: Constants.didDismissSetAsDefaultBrowserKey)
        try? keyValueStore.set(true, forKey: Constants.didDismissImportPasswordsKey)
        shouldShowSetAsDefaultBrowser = false
        shouldShowImportPasswords = false
    }
}

// MARK: Subscribers
extension SettingsViewModel {
    
    private func setupSubscribers() {

        AppDependencyProvider.shared.connectionObserver.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.updateNetPStatus(connectionStatus: status)
            }
            .store(in: &cancellables)

    }
}

// MARK: Public Methods
extension SettingsViewModel {

    enum Constants {
        static let didDismissSetAsDefaultBrowserKey = "com.duckduckgo.settings.setup.browser-default-dismissed"
        static let didDismissImportPasswordsKey = "com.duckduckgo.settings.setup.import-passwords-dismissed"
        static let shouldCheckIfDefaultBrowserKey = "com.duckduckgo.settings.setup.check-browser-default"
    }

    func onAppear() {
        Task {
            await initState()
            triggerDeepLinkNavigation(to: self.deepLinkTarget)
        }
    }
    
    func onDisappear() {
        self.deepLinkTarget = nil
    }

    func setAsDefaultBrowser(_ source: String? = nil) {
        var parameters: [String: String] = [:]
        if let source = source {
            parameters[PixelParameters.source] = source
        }
        Pixel.fire(pixel: .settingsSetAsDefault, withAdditionalParameters: parameters)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        if shouldShowSetAsDefaultBrowser {
            try? keyValueStore.set(true, forKey: Constants.shouldCheckIfDefaultBrowserKey)
        }
    }

    @available(iOS 18.2, *)
    func dismissSetAsDefaultBrowser() {
        try? keyValueStore.set(true, forKey: Constants.didDismissSetAsDefaultBrowserKey)
        updateCompleteSetupSectionVisiblity()
    }

    @available(iOS 18.2, *)
    func dismissImportPasswords() {
        try? keyValueStore.set(true, forKey: Constants.didDismissImportPasswordsKey)
        updateCompleteSetupSectionVisiblity()
    }

    @MainActor func shouldPresentAutofillViewWith(accountDetails: SecureVaultModels.WebsiteAccount?, card: SecureVaultModels.CreditCard?, showCreditCardManagement: Bool, source: AutofillSettingsSource? = nil) {
        state.activeWebsiteAccount = accountDetails
        state.activeWebsiteCreditCard = card
        state.showCreditCardManagement = showCreditCardManagement
        state.autofillSource = source
        
        presentLegacyView(.autofill)
    }

    @MainActor func shouldPresentSyncViewWithSource(_ source: String? = nil) {
        state.syncSource = source
        presentLegacyView(.sync(nil))
    }

    func openEmailProtection() {
        urlOpener.open(URL.emailProtectionQuickLink)
    }

    func openEmailAccountManagement() {
        urlOpener.open(URL.emailProtectionAccountLink)
    }

    func openEmailSupport() {
        urlOpener.open(URL.emailProtectionSupportLink)
    }

    func openOtherPlatforms() {
        urlOpener.open(URL.otherDevices)
    }

    func openMoreSearchSettings() {
        Pixel.fire(pixel: .settingsMoreSearchSettings)
        urlOpener.open(URL.searchSettings)
    }

    func openAssistSettings() {
        Pixel.fire(pixel: .settingsOpenAssistSettings)
        urlOpener.open(URL.assistSettings)
    }

    func openAIChat() {
        urlOpener.open(AppDeepLinkSchemes.openAIChat.url)
    }

    var shouldDisplayDuckPlayerContingencyMessage: Bool {
        duckPlayerContingencyHandler.shouldDisplayContingencyMessage
    }

    func openDuckPlayerContingencyMessageSite() {
        guard let url = duckPlayerContingencyHandler.learnMoreURL else { return }
        Pixel.fire(pixel: .duckPlayerContingencyLearnMoreClicked)
        urlOpener.open(url)
    }

    @MainActor func openCookiePopupManagement() {
        pushViewController(legacyViewProvider.autoConsent)
    }
    
    @MainActor func dismissSettings() {
        onRequestDismissSettings?()
    }

}

// MARK: Legacy View Presentation
// Some UIKit views have visual issues when presented via UIHostingController so
// for all existing subviews, default to UIKit based presentation until we
// can review and migrate
extension SettingsViewModel {
    
    @MainActor func presentLegacyView(_ view: SettingsLegacyViewProvider.LegacyView) {
        
        switch view {
        
        case .addToDock:
            presentViewController(legacyViewProvider.addToDock, modal: true)
        case .sync(let pairingInfo):
            pushViewController(legacyViewProvider.syncSettings(source: state.syncSource, pairingInfo: pairingInfo))
        case .appIcon: pushViewController(legacyViewProvider.appIconSettings(onChange: { [weak self] appIcon in
            self?.state.appIcon = appIcon
        }))
        case .unprotectedSites: pushViewController(legacyViewProvider.unprotectedSites)
        case .fireproofSites: pushViewController(legacyViewProvider.fireproofSites)
        case .autoclearData:
            pushViewController(legacyViewProvider.autoclearData)
        case .keyboard: pushViewController(legacyViewProvider.keyboard)
        case .debug: pushViewController(legacyViewProvider.debug)
            
        case .feedback:
            presentViewController(legacyViewProvider.feedback, modal: false)
        case .autofill:
            pushViewController(legacyViewProvider.loginSettings(delegate: self,
                                                                selectedAccount: state.activeWebsiteAccount,
                                                                selectedCard: state.activeWebsiteCreditCard,
                                                                showPasswordManagement: false,
                                                                showCreditCardManagement: state.showCreditCardManagement,
                                                                source: state.autofillSource))

        case .gpc:
            firePixel(.settingsDoNotSellShown)
            pushViewController(legacyViewProvider.gpc)
        
        case .autoconsent:
            pushViewController(legacyViewProvider.autoConsent)
        case .passwordsImport:
            pushViewController(legacyViewProvider.importPasswords(delegate: self))
        }
    }
 
    @MainActor
    private func pushViewController(_ view: UIViewController) {
        onRequestPushLegacyView?(view)
    }
    
    @MainActor
    private func presentViewController(_ view: UIViewController, modal: Bool) {
        onRequestPresentLegacyView?(view, modal)
    }
    
}

// MARK: AutofillLoginSettingsListViewControllerDelegate
extension SettingsViewModel: AutofillSettingsViewControllerDelegate {
    
    @MainActor
    func autofillSettingsViewControllerDidFinish(_ controller: AutofillSettingsViewController) {
        onRequestPopLegacyView?()
    }
}

// MARK: DataImportViewControllerDelegate
extension SettingsViewModel: DataImportViewControllerDelegate {
    @MainActor
    func dataImportViewControllerDidFinish(_ controller: DataImportViewController) {
        AppDependencyProvider.shared.autofillLoginSession.startSession()
        pushViewController(legacyViewProvider.loginSettings(delegate: self,
                                                            selectedAccount: nil,
                                                            selectedCard: nil,
                                                            showPasswordManagement: true,
                                                            showCreditCardManagement: false,
                                                            source: state.autofillSource))
    }
}


// MARK: DeepLinks
extension SettingsViewModel {

    enum SettingsDeepLinkSection: Identifiable, Equatable {
        case netP
        case dbp
        case itr
        case subscriptionFlow(redirectURLComponents: URLComponents? = nil)
        case restoreFlow
        case duckPlayer
        case aiChat
        case subscriptionSettings
        // Add other cases as needed

        var id: String {
            switch self {
            case .netP: return "netP"
            case .dbp: return "dbp"
            case .itr: return "itr"
            case .subscriptionFlow: return "subscriptionFlow"
            case .restoreFlow: return "restoreFlow"
            case .duckPlayer: return "duckPlayer"
            case .aiChat: return "aiChat"
            case .subscriptionSettings: return "subscriptionSettings"
            // Ensure all cases are covered
            }
        }

        // Define the presentation type: .sheet or .push
        // Default to .sheet, specify .push where needed
        var type: DeepLinkType {
            switch self {
            case .netP, .dbp, .itr, .subscriptionFlow, .restoreFlow, .duckPlayer, .aiChat, .subscriptionSettings:
                return .navigationLink
            }
        }
    }

    // Define DeepLinkType outside the enum if not already defined
    enum DeepLinkType {
        case sheet
        case navigationLink
    }
            
    // Navigate to a section in settings
    func triggerDeepLinkNavigation(to target: SettingsDeepLinkSection?) {
        guard let target else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.deepLinkTarget = target
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.deepLinkTarget = nil
            }
        }
    }
}

// MARK: Subscriptions
extension SettingsViewModel {

    @MainActor
    private func setupSubscriptionEnvironment() async {
        // If there's cached data use it by default
        if let cachedSubscription = subscriptionStateCache.get() {
            state.subscription = cachedSubscription
        // Otherwise use defaults and setup purchase availability
        } else {
            state.subscription = SettingsState.defaults.subscription
        }

        // Update if can purchase based on App Store product availability
        state.subscription.canPurchase = subscriptionAuthV1toV2Bridge.canPurchase

        // Update if user is signed in based on the presence of token
        state.subscription.isSignedIn = subscriptionAuthV1toV2Bridge.isUserAuthenticated

        // Active subscription check
        guard let token = try? await subscriptionAuthV1toV2Bridge.getAccessToken() else {
            // Reset state in case cache was outdated
            state.subscription.hasSubscription = false
            state.subscription.hasActiveSubscription = false
            state.subscription.entitlements = []
            state.subscription.platform = .unknown
            state.subscription.isActiveTrialOffer = false

            state.subscription.isEligibleForTrialOffer = await isUserEligibleForTrialOffer()

            subscriptionStateCache.set(state.subscription) // Sync cache
            return
        }
        
        do {
            let subscription = try await subscriptionAuthV1toV2Bridge.getSubscription(cachePolicy: .cacheFirst)
            state.subscription.platform = subscription.platform
            state.subscription.hasSubscription = true
            state.subscription.hasActiveSubscription = subscription.isActive
            state.subscription.isActiveTrialOffer = subscription.hasActiveTrialOffer

            // Check entitlements and update state
            var currentEntitlements: [Entitlement.ProductName] = []
            let entitlementsToCheck: [Entitlement.ProductName] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .identityTheftRestorationGlobal, .paidAIChat]

            for entitlement in entitlementsToCheck {
                if let hasEntitlement = try? await subscriptionAuthV1toV2Bridge.isEnabled(feature: entitlement),
                    hasEntitlement {
                    currentEntitlements.append(entitlement)
                }
            }

            self.state.subscription.entitlements = currentEntitlements
            self.state.subscription.subscriptionFeatures = await subscriptionAuthV1toV2Bridge.currentSubscriptionFeatures()
        } catch SubscriptionEndpointServiceError.noData {
            Logger.subscription.debug("No subscription data available")
            state.subscription.hasSubscription = false
            state.subscription.hasActiveSubscription = false
            state.subscription.entitlements = []
            state.subscription.platform = .unknown
            state.subscription.isActiveTrialOffer = false

            DailyPixel.fireDailyAndCount(pixel: .settingsPrivacyProAccountWithNoSubscriptionFound)
        } catch {
            Logger.subscription.error("Failed to fetch Subscription: \(error, privacy: .public)")
        }

        // Sync Cache
        subscriptionStateCache.set(state.subscription)
    }
    
    private func setupNotificationObservers() {
        subscriptionSignOutObserver = NotificationCenter.default.addObserver(forName: .accountDidSignOut,
                                                                             object: nil,
                                                                             queue: .main) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task {
                strongSelf.subscriptionStateCache.reset()
                await strongSelf.setupSubscriptionEnvironment()
            }
        }
        
        // Observe App Data clearing state
        appDataClearingObserver = NotificationCenter.default.addObserver(forName: AppUserDefaults.Notifications.appDataClearingUpdated,
                                                                         object: nil,
                                                                         queue: .main) { [weak self] _ in
            guard let settings = self?.appSettings else { return }
            self?.state.autoclearDataEnabled = (AutoClearSettingsModel(settings: settings) != nil)
        }
        
        textZoomObserver = NotificationCenter.default.addObserver(forName: AppUserDefaults.Notifications.textZoomChange,
                                                                  object: nil,
                                                                  queue: .main, using: { [weak self] _ in
            guard let self = self else { return }
            self.state.textZoom = SettingsState.TextZoom(enabled: true, level: self.appSettings.defaultTextZoomLevel)
        })

        if #available(iOS 18.2, *) {
            appForegroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self = self else { return }
                if self.shouldShowSetAsDefaultBrowser, let shouldCheckIfDefaultBrowser = try? keyValueStore.object(forKey: Constants.shouldCheckIfDefaultBrowserKey) as? Bool, shouldCheckIfDefaultBrowser {
                    self.updateCompleteSetupSectionVisiblity()
                }
            }
        }
    }

    func restoreAccountPurchase() async {
        if !isAuthV2Enabled {
            await restoreAccountPurchaseV1()
        } else {
            await restoreAccountPurchaseV2()
        }
    }

    func restoreAccountPurchaseV1() async {
        guard let subscriptionManagerV1 else {
            assertionFailure("Missing dependency: subscriptionManagerV1")
            return
        }

        DispatchQueue.main.async { self.state.subscription.isRestoring = true }
        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(accountManager: subscriptionManagerV1.accountManager,
                                                             storePurchaseManager: subscriptionManagerV1.storePurchaseManager(),
                                                             subscriptionEndpointService: subscriptionManagerV1.subscriptionEndpointService,
                                                             authEndpointService: subscriptionManagerV1.authEndpointService)
        let result = await appStoreRestoreFlow.restoreAccountFromPastPurchase()
        switch result {
        case .success:
            DispatchQueue.main.async {
                self.state.subscription.isRestoring = false
            }
            await self.setupSubscriptionEnvironment()
            
        case .failure(let restoreFlowError):
            DispatchQueue.main.async {
                self.state.subscription.isRestoring = false
                self.state.subscription.shouldDisplayRestoreSubscriptionError = true
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.state.subscription.shouldDisplayRestoreSubscriptionError = false
                }
            }

            switch restoreFlowError {
            case .missingAccountOrTransactions:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorMissingAccountOrTransactions)
            case .pastTransactionAuthenticationError:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorPastTransactionAuthenticationError)
            case .failedToObtainAccessToken:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorFailedToObtainAccessToken)
            case .failedToFetchAccountDetails:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorFailedToFetchAccountDetails)
            case .failedToFetchSubscriptionDetails:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorFailedToFetchSubscriptionDetails)
            case .subscriptionExpired:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorSubscriptionExpired)
            }
        }
    }

    func restoreAccountPurchaseV2() async {

        guard let subscriptionManagerV2 else {
            assertionFailure("Missing dependency: subscriptionManagerV2")
            return
        }

        DispatchQueue.main.async { self.state.subscription.isRestoring = true }

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlowV2(subscriptionManager: subscriptionManagerV2,
                                                             storePurchaseManager: subscriptionManagerV2.storePurchaseManager())
        let result = await appStoreRestoreFlow.restoreAccountFromPastPurchase()
        switch result {
        case .success:
            DispatchQueue.main.async {
                self.state.subscription.isRestoring = false
            }
            await self.setupSubscriptionEnvironment()

        case .failure(let restoreFlowError):
            DispatchQueue.main.async {
                self.state.subscription.isRestoring = false
                self.state.subscription.shouldDisplayRestoreSubscriptionError = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.state.subscription.shouldDisplayRestoreSubscriptionError = false
                }
            }

            switch restoreFlowError {
            case .missingAccountOrTransactions:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorMissingAccountOrTransactions)
            case .pastTransactionAuthenticationError:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorPastTransactionAuthenticationError)
            case .failedToObtainAccessToken:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorFailedToObtainAccessToken)
            case .failedToFetchAccountDetails:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorFailedToFetchAccountDetails)
            case .failedToFetchSubscriptionDetails:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorFailedToFetchSubscriptionDetails)
            case .subscriptionExpired:
                DailyPixel.fireDailyAndCount(pixel: .privacyProActivatingRestoreErrorSubscriptionExpired)
            }
        }
    }

    /// Checks if the user is eligible for a free trial subscription offer.
    /// - Returns: `true` if free trials are available and the user is eligible for a free trial, `false` otherwise.
    private func isUserEligibleForTrialOffer() async -> Bool {
        guard subscriptionFreeTrialsHelper.areFreeTrialsEnabled else { return false }
        if isAuthV2Enabled {
            return await subscriptionManagerV2?.storePurchaseManager().isUserEligibleForFreeTrial() ?? false
        } else {
            return await subscriptionManagerV1?.storePurchaseManager().isUserEligibleForFreeTrial() ?? false
        }
    }

}

// Deeplink notification handling
extension NSNotification.Name {
    static let settingsDeepLinkNotification: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.settingsDeepLink")
}

// MARK: - AI Chat
extension SettingsViewModel {

    var isAiChatEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.aiChatSettings.isAIChatEnabled },
            set: { newValue in
                withAnimation {
                    self.objectWillChange.send()
                    self.aiChatSettings.enableAIChat(enable: newValue)
                }
            }
        )
    }

    var aiChatBrowsingMenuEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.aiChatSettings.isAIChatBrowsingMenuUserSettingsEnabled },
            set: { newValue in
                self.aiChatSettings.enableAIChatBrowsingMenuUserSettings(enable: newValue)
            }
        )
    }

    var aiChatAddressBarEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.aiChatSettings.isAIChatAddressBarUserSettingsEnabled },
            set: { newValue in
                self.aiChatSettings.enableAIChatAddressBarUserSettings(enable: newValue)
            }
        )
    }

    var aiChatSearchInputEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled },
            set: { newValue in
                self.aiChatSettings.enableAIChatSearchInputUserSettings(enable: newValue)
            }
        )
    }

    var aiChatVoiceSearchEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.aiChatSettings.isAIChatVoiceSearchUserSettingsEnabled },
            set: { newValue in
                self.aiChatSettings.enableAIChatVoiceSearchUserSettings(enable: newValue)
            }
        )
    }

    var aiChatTabSwitcherEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.aiChatSettings.isAIChatTabSwitcherUserSettingsEnabled },
            set: { newValue in
                self.aiChatSettings.enableAIChatTabSwitcherUserSettings(enable: newValue)
            }
        )
    }

    var aiChatExperimentalBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.isExperimentalAIChatEnabled },
            set: { _ in
                self.experimentalAIChatManager.toggleExperimentalTheming()
                self.state.isExperimentalAIChatEnabled = self.experimentalAIChatManager.isExperimentalAIChatSettingsEnabled
            })
    }

    var aiChatExperimentalTransitionBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.isExperimentalAIChatTransitionEnabled },
            set: { _ in
                self.experimentalAIChatManager.toggleExperimentalTransition()
                self.state.isExperimentalAIChatTransitionEnabled = self.experimentalAIChatManager.isExperimentalTransitionEnabled
            })
    }

    func launchAIFeaturesLearnMore() {
        urlOpener.open(URL.aiFeaturesLearnMore)
    }

}
