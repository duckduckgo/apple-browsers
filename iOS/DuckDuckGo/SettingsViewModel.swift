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
import WebExtensions
import BrowserServicesKit
import Persistence
import PrivacyConfig
import SwiftUI
import UIComponents
import Common
import FoundationExtensions
import Combine
import SyncUI_iOS
import DuckPlayer
import Crashes

import Subscription
import VPN
import AIChat
import DataBrokerProtection_iOS
import SystemSettingsPiPTutorial
import SERPSettings
import Networking

enum YouTubeAdBlockingStorageKeys: String, StorageKeyDescribing {
    case youTubeAdBlockingEnabled = "com_duckduckgo_ios_youTubeAdBlockingEnabled"
    case youTubeAnalyticsEnabled = "com_duckduckgo_ios_youTubeAnalyticsEnabled"
    case shouldHideYouTubeAdBlockingDisclosure = "com_duckduckgo_ios_shouldHideYouTubeAdBlockingDisclosure"
    case youTubeAdBlockUnavailableNoticeShown = "com_duckduckgo_ios_youTubeAdBlockUnavailableNoticeShown"

    static let youTubeAdBlockingEnabledDidChangeNotification = Notification.Name("youTubeAdBlockingEnabledDidChange")
}

struct YouTubeAdBlockingKeys: StoringKeys {
    let youTubeAdBlockingEnabled = StorageKey<Bool>(YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabled)
    let youTubeAnalyticsEnabled = StorageKey<Bool>(YouTubeAdBlockingStorageKeys.youTubeAnalyticsEnabled)
    let shouldHideYouTubeAdBlockingDisclosure = StorageKey<Bool>(YouTubeAdBlockingStorageKeys.shouldHideYouTubeAdBlockingDisclosure)
    let youTubeAdBlockUnavailableNoticeShown = StorageKey<Bool>(YouTubeAdBlockingStorageKeys.youTubeAdBlockUnavailableNoticeShown)
}

final class SettingsViewModel: ObservableObject {

    // Dependencies
    private(set) lazy var appSettings = AppDependencyProvider.shared.appSettings
    private(set) var privacyStore = PrivacyUserDefaults()
    lazy var featureFlagger = AppDependencyProvider.shared.featureFlagger
    private lazy var animator: FireButtonAnimator = FireButtonAnimator(appSettings: AppUserDefaults())
    private var legacyViewProvider: SettingsLegacyViewProvider
    private lazy var versionProvider: AppVersion = AppVersion.shared
    private let voiceSearchHelper: VoiceSearchHelperProtocol
    private let syncPausedStateManager: any SyncPausedStateManaging
    var emailManager: EmailManager { EmailManager() }
    private(set) var historyManager: HistoryManaging
    let subscriptionDataReporter: SubscriptionDataReporting?
    let aiChatSettings: AIChatSettingsProvider
    // `var` because the SERP setting accessors have mutating setters (non-class protocol);
    // the conformer is a class, so writes go to the shared instance.
    var serpSettings: SERPSettingsProviding
    let maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging
    private let tabSwitcherSettings: TabSwitcherSettings
    private let autoplaySettings: AutoplaySettings
    let themeManager: ThemeManaging
    var experimentalAIChatManager: ExperimentalAIChatManager
    private let duckPlayerSettings: DuckPlayerSettings
    private let duckPlayerPixelHandler: DuckPlayerPixelFiring.Type
    let featureDiscovery: FeatureDiscovery
    private let urlOpener: URLOpener
    private weak var runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?
    var dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?
    private let freemiumPIREligibilityChecker: FreemiumPIREligibilityChecking
    weak var autoClearActionDelegate: SettingsAutoClearActionDelegate?
    let mobileCustomization: MobileCustomization
    let userScriptsDependencies: DefaultScriptSourceProvider.Dependencies
    private let onboardingSearchExperienceSettingsResolver: OnboardingSearchExperienceSettingsResolver
    private let adBlockingAvailability: AdBlockingAvailabilityProviding

    private lazy var newBadgeVisibilityManager: NewBadgeVisibilityManaging = {
        NewBadgeVisibilityManager(
            keyValueStore: keyValueStore,
            configProvider: DefaultNewBadgeConfigProvider(
                featureFlagger: featureFlagger,
                privacyConfigurationManager: privacyConfigurationManager
            ),
            currentAppVersionProvider: { AppVersion.shared.versionNumber }
        )
    }()

    private var afterInactivityStorage: any ThrowingKeyedStoring<AfterInactivitySettingKeys> {
        keyValueStore.throwingKeyedStoring()
    }

    private var youTubeAdBlockingStorage: any ThrowingKeyedStoring<YouTubeAdBlockingKeys> {
        keyValueStore.throwingKeyedStoring()
    }

    private let idleReturnEligibilityManager: IdleReturnEligibilityManaging
    private let afterInactivityOptionAdapter: AfterInactivityOptionAdapter
    private let lastTabShortcutAdapter: LastTabShortcutAdapter

    // What's New Dependencies
    private let whatsNewCoordinator: ModalPromptProvider & OnDemandModalPromptProvider

    // Subscription Dependencies
    let subscriptionManager: any SubscriptionManager
    let subscriptionFeatureAvailability: SubscriptionFeatureAvailability
    private var subscriptionSignOutObserver: Any?
    var duckPlayerContingencyHandler: DuckPlayerContingencyHandler {
        DefaultDuckPlayerContingencyHandler(privacyConfigurationManager: privacyConfigurationManager)
    }
    var blackFridayCampaignProvider: BlackFridayCampaignProviding {
        DefaultBlackFridayCampaignProvider(
            privacyConfigurationManager: privacyConfigurationManager,
            isFeatureEnabled: { [weak featureFlagger] in
                featureFlagger?.isFeatureOn(.blackFridayCampaign) ?? false
            }
        )
    }

    private enum UserDefaultsCacheKey: String, UserDefaultsCacheKeyStore {
        case subscriptionState = "com.duckduckgo.ios.subscription.state"
    }
    // Used to cache the lasts subscription state for up to a week
    private let subscriptionStateCache = UserDefaultsCache<SettingsState.Subscription>(key: UserDefaultsCacheKey.subscriptionState,
                                                                         settings: UserDefaultsCacheSettings(defaultExpirationInterval: .days(7)))
    // Win-back offer
    let winBackOfferVisibilityManager: WinBackOfferVisibilityManaging
    
    // Properties
    lazy var isPad = UIDevice.current.userInterfaceIdiom == .pad
    private var cancellables = Set<AnyCancellable>()

    // App Data State Notification Observer
    private var textZoomObserver: Any?
    private var appForegroundObserver: Any?
    private var aiChatSettingsObserver: Any?

    private let privacyConfigurationManager: PrivacyConfigurationManaging
    let keyValueStore: ThrowingKeyValueStoring
    let contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>
    private let systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging

    // Closures to interact with legacy view controllers through the container
    var onRequestPushLegacyView: ((UIViewController, _ animated: Bool) -> Void)?
    var onRequestPresentLegacyView: ((UIViewController, _ modal: Bool) -> Void)?
    var onRequestPopLegacyView: (() -> Void)?
    var onRequestDismissSettings: (() -> Void)?
    var onRequestOpenDuckAIChat: (() -> Void)?
    var onRequestPresentFireConfirmation: ((_ sourceRect: CGRect, _ onConfirm: @escaping (FireRequest) -> Void, _ onCancel: @escaping () -> Void) -> Void)?

    // View State
    @Published private(set) var state: SettingsState
    private var lastEnabledDuckPlayerMode: DuckPlayerMode?
    private var lastEnabledNativeYoutubeMode: NativeDuckPlayerYoutubeMode?

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

    // When true, indicates the AI Features settings was opened from the SERP settings button
    // This affects UI: shows Done button and hides Search Assist link
    var openedFromSERPSettingsButton: Bool = false

    // Indicates if the Paid AI Chat feature flag is enabled for the current user/session.
    var isPaidAIChatEnabled: Bool {
        featureFlagger.isFeatureOn(.paidAIChat)
    }

    var isPIREnabled: Bool {
        featureFlagger.isFeatureOn(.personalInformationRemoval)
    }

    var meetsLocaleRequirement: Bool {
        runPrerequisitesDelegate?.meetsLocaleRequirement ?? false
    }

    var canShowFreemiumPIRSettingsEntryPoint: Bool {
        freemiumPIREligibilityChecker.canShowEntryPoint()
            && dataBrokerProtectionViewControllerProvider != nil
    }

    var dbpMeetsProfileRunPrequisite: Bool {
        get {
            (try? runPrerequisitesDelegate?.meetsProfileRunPrequisite) ?? false
        }
    }

    var isDefaultOmnibarModeEnabled: Bool {
        featureFlagger.isFeatureOn(.aiChatOmnibarDefaultPosition)
    }

    var isAIFeaturesNativeControlsEnabled: Bool {
        featureFlagger.isFeatureOn(.aiFeaturesNativeControls)
    }

    var isTabSwitcherTrackerCountEnabled: Bool {
        featureFlagger.isFeatureOn(.tabSwitcherTrackerCount)
    }

    let darkReaderFeatureSettings: DarkReaderFeatureSettings

    var isForceWebsiteDarkModeAvailable: Bool {
        darkReaderFeatureSettings.isFeatureEnabled
    }

    var isBlackFridayCampaignEnabled: Bool {
        blackFridayCampaignProvider.isCampaignEnabled
    }

    var blackFridayDiscountPercent: Int {
        blackFridayCampaignProvider.discountPercent
    }

    var purchaseButtonText: String {
        if isBlackFridayCampaignEnabled {
            return UserText.blackFridayCampaignViewPlansCTA(discountPercent: blackFridayDiscountPercent)
        } else if state.subscription.isEligibleForTrialOffer {
            return UserText.trySubscriptionButton
        } else {
            return UserText.getSubscriptionButton
        }
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

    var afterInactivityOption: AfterInactivityOption {
        afterInactivityOptionAdapter.afterInactivityOption
    }
    @Published var afterInactivityIdleInterval: AfterInactivityIdleInterval = .default

    // MARK: Bindings

    var selectedToolbarButton: Binding<MobileCustomization.Button> {
        Binding<MobileCustomization.Button>(
            get: {
                self.state.mobileCustomization.currentToolbarButton
            },
            set: {
                guard $0 != self.state.mobileCustomization.currentToolbarButton else { return }
                self.state.mobileCustomization.currentToolbarButton = $0
                self.mobileCustomization.persist(self.state.mobileCustomization)
            }
        )
    }

    var selectedAddressBarButton: Binding<MobileCustomization.Button> {
        Binding<MobileCustomization.Button>(
            get: {
                self.state.mobileCustomization.currentAddressBarButton
            },
            set: {
                guard $0 != self.state.mobileCustomization.currentAddressBarButton else { return }
                self.state.mobileCustomization.currentAddressBarButton = $0
                self.mobileCustomization.persist(self.state.mobileCustomization)
            }
        )
    }

    var themeStyleBinding: Binding<ThemeStyle> {
        Binding<ThemeStyle>(
            get: { self.state.appThemeStyle },
            set: {
                Pixel.fire(pixel: .settingsThemeSelectorPressed)
                self.state.appThemeStyle = $0
                ThemeManager.shared.setThemeStyle($0)
                self.state.forceWebsiteDarkMode = self.darkReaderFeatureSettings.isForceDarkModeEnabled
                // Delay to allow web views to re-render with the new interface style
                // before the dark reader extension is enabled or disabled.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.darkReaderFeatureSettings.themeDidChange()
                }
            }
        )
    }
    
    // MARK: - Child View Models
    
    @MainActor
    private(set) lazy var dataClearingViewModel: DataClearingSettingsViewModel = {
        DataClearingSettingsViewModel(
            appSettings: appSettings,
            aiChatSettings: aiChatSettings,
            fireproofing: legacyViewProvider.fireproofing,
            delegate: self
        )
    }()

    // MARK: - Actions

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

    var hideTabBarWhileScrollingOnIPadBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                !self.appSettings.keepAddressBarVisibleOnIPad
            },
            set: { hideWhileScrolling in
                Pixel.fire(pixel: hideWhileScrolling ? .settingsHideTabBarWhileScrollingOn : .settingsHideTabBarWhileScrollingOff)
                let keepVisible = !hideWhileScrolling
                self.appSettings.keepAddressBarVisibleOnIPad = keepVisible
            }
        )
    }

    var refreshButtonPositionBinding: Binding<RefreshButtonPosition> {
        Binding<RefreshButtonPosition>(
            get: {
                self.state.refreshButtonPosition
            },
            set: {
                Pixel.fire(pixel: $0 == .addressBar ? .settingsRefreshButtonPositionAddressBar : .settingsRefreshButtonPositionMenu)
                self.appSettings.currentRefreshButtonPosition = $0
                self.state.refreshButtonPosition = $0
            }
        )
    }

    var autoplayBlockingModeBinding: Binding<AutoplayBlockingMode> {
        Binding<AutoplayBlockingMode>(
            get: {
                self.state.autoplayBlockingMode
            },
            set: {
                self.autoplaySettings.currentAutoplayBlockingMode = $0
                self.state.autoplayBlockingMode = $0
                Pixel.fire(pixel: .settingsAutoplayChanged,
                          withAdditionalParameters: [PixelParameters.autoplayBlockingMode: $0.rawValue])
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

    var showTrackersBlockedAnimationBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.showTrackersBlockedAnimation },
            set: {
                self.state.showTrackersBlockedAnimation = $0
                self.appSettings.showTrackersBlockedAnimation = $0
                Pixel.fire(pixel: .settingsTrackerCountInAddressBarToggled,
                          withAdditionalParameters: [PixelParameters.enabled: String($0)])
            }
        )
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

    var shouldShowNTPAfterIdleSetting: Bool {
        featureFlagger.isFeatureOn(.showNTPAfterIdleReturn)
    }

    var shouldShowLastTabShortcutSetting: Bool {
        featureFlagger.isFeatureOn(.escapeHatchHideShortcut)
    }

    var lastTabShortcutEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.lastTabShortcutAdapter.isEnabled },
            set: { newValue in
                self.lastTabShortcutAdapter.setEnabled(newValue)
                DailyPixel.fireDailyAndCount(
                    pixel: newValue ? .ntpAfterIdleLastTabShortcutSettingEnabled : .ntpAfterIdleLastTabShortcutSettingDisabled
                )
            }
        )
    }

    var idleTimeInterval: String {
        formattedIdleThreshold(from: idleReturnEligibilityManager.idleThresholdSeconds())
    }

    var afterInactivityFooterText: String {
        if afterInactivityOption == .lastUsedTab || afterInactivityIdleInterval == .none {
            return UserText.settingsAfterInactivityFooterNone
        }
        return String(format: UserText.settingsAfterInactivityFooterFormat, idleTimeInterval)
    }

    var afterInactivityOptionBinding: Binding<AfterInactivityOption> {
        let upstream = afterInactivityOptionAdapter.afterInactivityOptionBinding
        return Binding<AfterInactivityOption>(
            get: { upstream.wrappedValue },
            set: { newValue in
                upstream.wrappedValue = newValue
                let pixel: Pixel.Event = newValue == .newTab
                    ? .ntpAfterIdleSettingChangedToNewTab
                    : .ntpAfterIdleSettingChangedToLastUsedTab
                DailyPixel.fireDailyAndCount(pixel: pixel)
            }
        )
    }

    var afterInactivityIdleIntervalBinding: Binding<AfterInactivityIdleInterval> {
        Binding<AfterInactivityIdleInterval>(
            get: { self.afterInactivityIdleInterval },
            set: { newValue in
                self.afterInactivityIdleInterval = newValue
                try? self.afterInactivityStorage.set(newValue.seconds, for: \AfterInactivitySettingKeys.idleReturnIntervalSeconds)
                DailyPixel.fireDailyAndCount(
                    pixel: .ntpAfterIdleSettingIdleIntervalChanged,
                    withAdditionalParameters: ["idle_interval_seconds": String(newValue.seconds)]
                )
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

    var cookiePopupPreferenceBinding: Binding<CookiePopupPreference> {
        Binding<CookiePopupPreference>(
            get: { self.state.cookiePopupPreference },
            set: {
                self.appSettings.cookiePopupPreference = $0
                self.state.cookiePopupPreference = $0
                if $0.isBlockingEnabled {
                    Pixel.fire(pixel: .settingsAutoconsentOn)
                } else {
                    Pixel.fire(pixel: .settingsAutoconsentOff)
                }
            }
        )
    }

    var autoconsentBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.cookiePopupPreference.isBlockingEnabled },
            set: {
                self.appSettings.autoconsentEnabled = $0
                self.state.cookiePopupPreference = self.appSettings.cookiePopupPreference
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

    private var resolvedDuckPlayerMode: DuckPlayerMode {
        if let lastEnabledDuckPlayerMode {
            return lastEnabledDuckPlayerMode
        }
        if let current = state.duckPlayerMode, current != .disabled {
            return current
        }
        return .alwaysAsk
    }

    private var resolvedNativeYoutubeMode: NativeDuckPlayerYoutubeMode {
        if let lastEnabledNativeYoutubeMode {
            return lastEnabledNativeYoutubeMode
        }
        let current = state.duckPlayerNativeYoutubeMode
        return current != .never ? current : .ask
    }

    var isDuckPlayerEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                return self.state.duckPlayerMode != .disabled
            },
            set: { newValue in
                let oldMode = self.state.duckPlayerMode ?? .alwaysAsk

                if !newValue {
                    if oldMode != .disabled {
                        self.lastEnabledDuckPlayerMode = oldMode
                    }
                    self.appSettings.duckPlayerMode = .disabled
                    self.state.duckPlayerMode = .disabled
                } else {
                    let restoredMode = self.resolvedDuckPlayerMode
                    self.appSettings.duckPlayerMode = restoredMode
                    self.state.duckPlayerMode = restoredMode
                }

                if oldMode != self.state.duckPlayerMode {
                    switch self.state.duckPlayerMode {
                    case .enabled:
                        Pixel.fire(pixel: .duckPlayerSettingAlwaysSettings)
                    case .alwaysAsk:
                        Pixel.fire(pixel: .duckPlayerSettingBackToDefault)
                    case .disabled:
                        Pixel.fire(pixel: .duckPlayerSettingNeverSettings)
                    case .none:
                        break
                    }
                }
            }
        )
    }

    var isAlwaysOpenBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                return self.state.duckPlayerMode == .enabled
            },
            set: { newValue in
                let oldMode = self.state.duckPlayerMode ?? .alwaysAsk
                let newMode: DuckPlayerMode = newValue ? .enabled : .alwaysAsk

                self.appSettings.duckPlayerMode = newMode
                self.state.duckPlayerMode = newMode

                if oldMode != newMode {
                    switch newMode {
                    case .enabled:
                        Pixel.fire(pixel: .duckPlayerSettingAlwaysSettings)
                    case .alwaysAsk:
                        Pixel.fire(pixel: .duckPlayerSettingBackToDefault)
                    case .disabled:
                        Pixel.fire(pixel: .duckPlayerSettingNeverSettings)
                    }
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

    var youTubeAdBlockingEnabled: Binding<Bool> {
        Binding<Bool>(
            get: {
                self.state.youTubeAdBlockingEnabled && !self.adBlockingAvailability.isDisabledUntilRelaunch
            },
            set: {
                self.adBlockingAvailability.clearDisableUntilRelaunch()
                guard $0 != self.state.youTubeAdBlockingEnabled else { return }
                let disclosureVisibleAtToggle = !self.state.youTubeAdBlockingDisclosureHidden
                try? self.youTubeAdBlockingStorage.set($0, for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled)
                self.state.youTubeAdBlockingEnabled = $0
                if !$0 {
                    self.setYouTubeAnalyticsEnabled(false)
                } else if disclosureVisibleAtToggle {
                    self.setYouTubeAnalyticsEnabled(true)
                }
                DailyPixel.fireDailyAndCount(
                    pixel: $0 ? .webExtensionAdBlockingEnabled : .webExtensionAdBlockingDisabled,
                    pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes
                )
                NotificationCenter.default.post(name: YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabledDidChangeNotification, object: nil)
            }
        )
    }

    var isYouTubeAdBlockingDisabledUntilRelaunch: Bool {
        state.youTubeAdBlockingEnabled && adBlockingAvailability.isDisabledUntilRelaunch
    }

    func setYouTubeAnalyticsEnabled(_ enabled: Bool) {
        try? youTubeAdBlockingStorage.set(enabled, for: \YouTubeAdBlockingKeys.youTubeAnalyticsEnabled)
    }

    var isYouTubeAdBlockingDisclosureHidden: Bool {
        state.youTubeAdBlockingDisclosureHidden
    }

    var isYouTubeAdBlockingRemotelyDisabled: Bool {
        adBlockingAvailability.isRemotelyDisabled
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

    var isShowDuckPlayerOnYoutubeBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                return self.state.duckPlayerNativeYoutubeMode != .never
            },
            set: { newValue in
                let oldMode = self.state.duckPlayerNativeYoutubeMode

                if !newValue {
                    if oldMode != .never {
                        self.lastEnabledNativeYoutubeMode = oldMode
                    }
                    self.appSettings.duckPlayerNativeYoutubeMode = .never
                    self.state.duckPlayerNativeYoutubeMode = .never
                } else {
                    let restoredMode = self.resolvedNativeYoutubeMode
                    self.appSettings.duckPlayerNativeYoutubeMode = restoredMode
                    self.state.duckPlayerNativeYoutubeMode = restoredMode
                }

                if oldMode != self.state.duckPlayerNativeYoutubeMode {
                    switch self.state.duckPlayerNativeYoutubeMode {
                    case .auto:
                        self.duckPlayerPixelHandler.fire(.duckPlayerNativeSettingsYoutubeAutomatic)
                    case .ask:
                        self.duckPlayerPixelHandler.fire(.duckPlayerNativeSettingsYoutubeChoose)
                    case .never:
                        self.duckPlayerPixelHandler.fire(.duckPlayerNativeSettingsYoutubeDontShow)
                    }
                }
            }
        )
    }

    var isOpenAutomaticallyBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                return self.state.duckPlayerNativeYoutubeMode == .auto
            },
            set: { newValue in
                let oldMode = self.state.duckPlayerNativeYoutubeMode
                let newMode: NativeDuckPlayerYoutubeMode = newValue ? .auto : .ask

                self.appSettings.duckPlayerNativeYoutubeMode = newMode
                self.state.duckPlayerNativeYoutubeMode = newMode

                if oldMode != newMode {
                    switch newMode {
                    case .auto:
                        self.duckPlayerPixelHandler.fire(.duckPlayerNativeSettingsYoutubeAutomatic)
                    case .ask:
                        self.duckPlayerPixelHandler.fire(.duckPlayerNativeSettingsYoutubeChoose)
                    case .never:
                        self.duckPlayerPixelHandler.fire(.duckPlayerNativeSettingsYoutubeDontShow)
                    }
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

    var forceWebsiteDarkModeBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.state.forceWebsiteDarkMode },
            set: {
                self.darkReaderFeatureSettings.setForceDarkModeEnabled($0)
                self.state.forceWebsiteDarkMode = $0
                DailyPixel.fireDailyAndCount(
                    pixel: $0 ? .webExtensionDarkReaderEnabled : .webExtensionDarkReaderDisabled,
                    pixelNameSuffixes: DailyPixel.Constant.dailyAndStandardSuffixes
                )
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

    var autoClearAIChatHistoryBinding: Binding<Bool> {
        Binding<Bool>(
            get: {
                self.state.autoClearAIChatHistory
            },
            set: {
                self.appSettings.autoClearAIChatHistory = $0
                self.state.autoClearAIChatHistory = $0
            }
        )
    }

    var cookiePopUpProtectionStatus: StatusIndicator {
        return appSettings.cookiePopupPreference.isBlockingEnabled ? .on : .off
    }
    
    var emailProtectionStatus: StatusIndicator {
        return emailManager.isSignedIn ? .on : .off
    }
    
    var syncStatus: StatusIndicator {
        legacyViewProvider.syncService.authState != .inactive ? .on : .off
    }

    var enablesUnifiedFeedbackForm: Bool {
        subscriptionManager.isUserAuthenticated
    }

    // Indicates if the Paid AI Chat entitlement flag is available for the current user
    var isPaidAIChatAvailable: Bool {
        state.subscription.subscriptionFeatures.contains(.paidAIChat)
    }

    // Indicates if AI features are generally enabled
    var isAIChatEnabled: Bool {
        aiChatSettings.isAIChatEnabled
    }

    // MARK: Default Init
    init(state: SettingsState? = nil,
         legacyViewProvider: SettingsLegacyViewProvider,
         subscriptionManager: any SubscriptionManager,
         subscriptionFeatureAvailability: SubscriptionFeatureAvailability,
         voiceSearchHelper: VoiceSearchHelperProtocol,
         deepLink: SettingsDeepLinkSection? = nil,
         historyManager: HistoryManaging,
         syncPausedStateManager: any SyncPausedStateManaging,
         subscriptionDataReporter: SubscriptionDataReporting,
         aiChatSettings: AIChatSettingsProvider,
         serpSettings: SERPSettingsProviding,
         maliciousSiteProtectionPreferencesManager: MaliciousSiteProtectionPreferencesManaging,
         themeManager: ThemeManaging = ThemeManager.shared,
         experimentalAIChatManager: ExperimentalAIChatManager,
         duckPlayerSettings: DuckPlayerSettings = DuckPlayerSettingsDefault(),
         duckPlayerPixelHandler: DuckPlayerPixelFiring.Type = DuckPlayerPixelHandler.self,
         featureDiscovery: FeatureDiscovery = DefaultFeatureDiscovery(),
         urlOpener: URLOpener = UIApplication.shared,
         privacyConfigurationManager: PrivacyConfigurationManaging,
         keyValueStore: ThrowingKeyValueStoring,
         contentBlockingAssetsPublisher: AnyPublisher<ContentBlockingUpdating.NewContent, Never>,
         idleReturnEligibilityManager: IdleReturnEligibilityManaging,
         afterInactivityOptionAdapter: AfterInactivityOptionAdapter,
         lastTabShortcutAdapter: LastTabShortcutAdapter,
         systemSettingsPiPTutorialManager: SystemSettingsPiPTutorialManaging,
         runPrerequisitesDelegate: DBPIOSInterface.RunPrerequisitesDelegate?,
         dataBrokerProtectionViewControllerProvider: DBPIOSInterface.DataBrokerProtectionViewControllerProvider?,
         freemiumPIREligibilityChecker: FreemiumPIREligibilityChecking,
         winBackOfferVisibilityManager: WinBackOfferVisibilityManaging,
         mobileCustomization: MobileCustomization,
         userScriptsDependencies: DefaultScriptSourceProvider.Dependencies,
         onboardingSearchExperienceSettingsResolver: OnboardingSearchExperienceSettingsResolver? = nil,
         whatsNewCoordinator: ModalPromptProvider & OnDemandModalPromptProvider,
         tabSwitcherSettings: TabSwitcherSettings = DefaultTabSwitcherSettings(),
         autoplaySettings: AutoplaySettings = DefaultAutoplaySettings(),
         darkReaderFeatureSettings: DarkReaderFeatureSettings,
         adBlockingAvailability: AdBlockingAvailabilityProviding
    ) {

        self.darkReaderFeatureSettings = darkReaderFeatureSettings
        self.state = SettingsState.defaults
        self.tabSwitcherSettings = tabSwitcherSettings
        self.autoplaySettings = autoplaySettings
        self.legacyViewProvider = legacyViewProvider
        self.subscriptionManager = subscriptionManager
        self.subscriptionFeatureAvailability = subscriptionFeatureAvailability
        self.voiceSearchHelper = voiceSearchHelper
        self.deepLinkTarget = deepLink
        self.historyManager = historyManager
        self.syncPausedStateManager = syncPausedStateManager
        self.subscriptionDataReporter = subscriptionDataReporter
        self.aiChatSettings = aiChatSettings
        self.serpSettings = serpSettings
        self.maliciousSiteProtectionPreferencesManager = maliciousSiteProtectionPreferencesManager
        self.themeManager = themeManager
        self.experimentalAIChatManager = experimentalAIChatManager
        self.duckPlayerSettings = duckPlayerSettings
        self.duckPlayerPixelHandler = duckPlayerPixelHandler
        self.featureDiscovery = featureDiscovery
        self.urlOpener = urlOpener
        self.privacyConfigurationManager = privacyConfigurationManager
        self.keyValueStore = keyValueStore
        self.contentBlockingAssetsPublisher = contentBlockingAssetsPublisher
        self.idleReturnEligibilityManager = idleReturnEligibilityManager
        self.afterInactivityOptionAdapter = afterInactivityOptionAdapter
        self.lastTabShortcutAdapter = lastTabShortcutAdapter
        self.afterInactivityIdleInterval = AfterInactivityIdleInterval(rawValue: idleReturnEligibilityManager.idleThresholdSeconds()) ?? .default
        self.systemSettingsPiPTutorialManager = systemSettingsPiPTutorialManager
        self.runPrerequisitesDelegate = runPrerequisitesDelegate
        self.dataBrokerProtectionViewControllerProvider = dataBrokerProtectionViewControllerProvider
        self.freemiumPIREligibilityChecker = freemiumPIREligibilityChecker
        self.winBackOfferVisibilityManager = winBackOfferVisibilityManager
        self.mobileCustomization = mobileCustomization
        self.userScriptsDependencies = userScriptsDependencies
        self.onboardingSearchExperienceSettingsResolver = onboardingSearchExperienceSettingsResolver ?? OnboardingSearchExperienceSettingsResolver(
            onboardingProvider: OnboardingSearchExperience(),
            daxDialogsStatusProvider: legacyViewProvider.daxDialogsManager
        )
        self.whatsNewCoordinator = whatsNewCoordinator
        self.adBlockingAvailability = adBlockingAvailability
        setupNotificationObservers()
        updateRecentlyVisitedSitesVisibility()
        startForwardingAdapterWillChangeEvents(afterInactivityOptionAdapter)
        startForwardingAdapterWillChangeEvents(lastTabShortcutAdapter)
    }

    deinit {
        subscriptionSignOutObserver = nil
        textZoomObserver = nil
        aiChatSettingsObserver = nil
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
        // Pin the disclosure preference based on the YouTube Ad Blocking
        // storage state. For users who made an explicit choice (storage
        // non-nil), pin once and preserve it — the rollout doesn't change
        // their effective state, so the disclosure shown at their decision
        // moment is the right one. For users with no explicit choice
        // (storage nil), re-pin to the current rollout default on every
        // Settings open so the rollout flip doesn't strand them with a stale
        // "show disclosure" pin from a pre-rollout visit. Done here — not in
        // the destination view's `onAppear` — so the resulting `@Published`
        // change can't race with a push transition and pop the screen on iPad.
        let storageEnabled = try? youTubeAdBlockingStorage.value(for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled)
        if let storageEnabled {
            if (try? youTubeAdBlockingStorage.value(for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)) == nil {
                try? youTubeAdBlockingStorage.set(storageEnabled, for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)
            }
        } else {
            try? youTubeAdBlockingStorage.set(adBlockingAvailability.defaultYouTubeAdBlockingEnabled,
                                              for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)
        }

        self.state = SettingsState(
            appThemeStyle: appSettings.currentThemeStyle,
            appIcon: AppIconManager.shared.appIcon,
            textZoom: SettingsState.TextZoom(level: appSettings.defaultTextZoomLevel),
            addressBar: SettingsState.AddressBar(enabled: !isPad, position: appSettings.currentAddressBarPosition),
            showsFullURL: appSettings.showFullSiteAddress,
            showTrackersBlockedAnimation: appSettings.showTrackersBlockedAnimation,
            isExperimentalAIChatEnabled: experimentalAIChatManager.isExperimentalAIChatSettingsEnabled,
            refreshButtonPosition: appSettings.currentRefreshButtonPosition,
            mobileCustomization: mobileCustomization.state,
            forceWebsiteDarkMode: darkReaderFeatureSettings.isForceDarkModeEnabled,
            sendDoNotSell: appSettings.sendDoNotSell,
            cookiePopupPreference: appSettings.cookiePopupPreference,
            autoClearAIChatHistory: appSettings.autoClearAIChatHistory,
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
            debugModeEnabled: isInternalUser || isDebugBuild,
            voiceSearchEnabled: voiceSearchHelper.isVoiceSearchEnabled,
            speechRecognitionAvailable: voiceSearchHelper.isSpeechRecognizerAvailable,
            loginsEnabled: featureFlagger.isFeatureOn(.autofillAccessCredentialManagement),
            networkProtectionConnected: false,
            subscription: SettingsState.defaults.subscription,
            sync: getSyncState(),
            syncSource: nil,
            duckPlayerEnabled: !adBlockingAvailability.isFeatureSupported && (featureFlagger.isFeatureOn(.duckPlayer) || shouldDisplayDuckPlayerContingencyMessage),
            duckPlayerMode: duckPlayerSettings.mode,
            duckPlayerOpenInNewTab: duckPlayerSettings.openInNewTab,
            duckPlayerOpenInNewTabEnabled: featureFlagger.isFeatureOn(.duckPlayerOpenInNewTab),
            duckPlayerAutoplay: duckPlayerSettings.autoplay,
            duckPlayerNativeUISERPEnabled: duckPlayerSettings.nativeUISERPEnabled,
            duckPlayerNativeYoutubeMode: duckPlayerSettings.nativeUIYoutubeMode,
            autoplayBlockingMode: autoplaySettings.currentAutoplayBlockingMode,
            youTubeAdBlockingAvailable: adBlockingAvailability.isFeatureSupported,
            youTubeAdBlockingEnabled: (try? youTubeAdBlockingStorage.value(for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled))
                ?? adBlockingAvailability.defaultYouTubeAdBlockingEnabled,
            youTubeAdBlockingDisclosureHidden: (try? youTubeAdBlockingStorage.value(for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)) == true
        )

        // Subscribe to DuckPlayerSettings updates
        duckPlayerSettings.duckPlayerSettingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateDuckPlayerState()
            }
            .store(in: &cancellables)

        // Republish when YouTube Ad Block state changes (including the in-memory
        // disable-until-relaunch override on `adBlockingAvailability`). Refresh
        // `state.youTubeAdBlockingEnabled` from storage so the toggle binding
        // reflects writes made by other surfaces (e.g. the browsing menu).
        NotificationCenter.default.publisher(for: YouTubeAdBlockingStorageKeys.youTubeAdBlockingEnabledDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.state.youTubeAdBlockingEnabled =
                    (try? self.youTubeAdBlockingStorage.value(for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled))
                    ?? self.adBlockingAvailability.defaultYouTubeAdBlockingEnabled
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Re-pin the disclosure and refresh the resolved YouTube Ad Blocking
        // state when the feature flagger emits — covers mid-session rollout
        // flips while Settings is open. Skips users with explicit storage so
        // their conscious decision is preserved.
        featureFlagger.updatesPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                // Refresh the UI for every flag flip so the contingency notice
                // (which reads `adBlockingAvailability.isRemotelyDisabled` live)
                // re-renders even for users with explicit storage who skip the
                // disclosure re-pin below.
                defer { self.objectWillChange.send() }
                guard (try? self.youTubeAdBlockingStorage.value(for: \YouTubeAdBlockingKeys.youTubeAdBlockingEnabled)) == nil else { return }
                let resolvedDefault = self.adBlockingAvailability.defaultYouTubeAdBlockingEnabled
                try? self.youTubeAdBlockingStorage.set(resolvedDefault, for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)
                self.state.youTubeAdBlockingEnabled = resolvedDefault
                self.state.youTubeAdBlockingDisclosureHidden =
                    (try? self.youTubeAdBlockingStorage.value(for: \YouTubeAdBlockingKeys.shouldHideYouTubeAdBlockingDisclosure)) == true
            }
            .store(in: &cancellables)

        updateRecentlyVisitedSitesVisibility()

        if #available(iOS 18.2, *) {
            updateCompleteSetupSectionVisiblity()
        }

        setupSubscribers()
        Task { await setupSubscriptionEnvironment() }
    }

    /// Forward an adapter's `objectWillChange` events so derived values (e.g. `afterInactivityOption`,
    /// `lastTabShortcutEnabledBinding`) react to changes the adapter makes to the shared settings storage.
    private func startForwardingAdapterWillChangeEvents(_ adapter: some ObservableObject) {
        adapter.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    private func updateRecentlyVisitedSitesVisibility() {
        withAnimation {
            shouldShowRecentlyVisitedSites = state.autocomplete
        }
    }

    private func clearHistoryIfNeeded() {
        if !historyManager.isEnabledByUser {
            Task {
                _ = await self.historyManager.removeAllHistory()
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

    private func formattedIdleThreshold(from seconds: Int) -> String {
        let oneHour = 3600
        if seconds >= oneHour {
            let hours = seconds / oneHour
            if hours == 1 {
                return UserText.settingsAfterInactivityIdleIntervalHourSingular
            }
            return String(format: UserText.settingsAfterInactivityIdleIntervalHoursFormat, hours)
        }
        let minutes = seconds / 60
        if minutes >= 1 {
            if minutes == 1 {
                return UserText.settingsAfterInactivityIdleIntervalMinuteSingular
            }
            return String(format: UserText.settingsAfterInactivityIdleIntervalMinutesFormat, minutes)
        }
        if seconds == 1 {
            return UserText.settingsAfterInactivityIdleIntervalSecondSingular
        }
        return String(format: UserText.settingsAfterInactivityIdleIntervalSecondsFormat, seconds)
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

    func onFirstAppear() {
        Task {
            await initState()
            triggerDeepLinkNavigation(to: self.deepLinkTarget)
        }
    }

    func onSubsequentAppear() {
        Task {
            await setupSubscriptionEnvironment()
        }
    }

    @MainActor
    func setAsDefaultBrowser(_ source: String? = nil) {
        var parameters: [String: String] = [:]
        if let source = source {
            parameters[PixelParameters.source] = source
        }
        Pixel.fire(pixel: .settingsSetAsDefault, withAdditionalParameters: parameters)
        systemSettingsPiPTutorialManager.playPiPTutorialAndNavigateTo(destination: .defaultBrowser)
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

    @MainActor func shouldPresentAutofillViewWith(accountDetails: SecureVaultModels.WebsiteAccount?, card: SecureVaultModels.CreditCard?, showCreditCardManagement: Bool, showSettingsScreen: AutofillSettingsDestination? = nil, source: AutofillSettingsSource? = nil) {
        state.activeWebsiteAccount = accountDetails
        state.activeWebsiteCreditCard = card
        state.showCreditCardManagement = showCreditCardManagement
        state.showSettingsScreen = showSettingsScreen
        state.autofillSource = source
        
        presentLegacyView(.autofill)
    }

    @MainActor func shouldPresentSyncViewWithSource(_ source: String? = nil, animated: Bool = true) {
        state.syncSource = source
        presentLegacyView(.sync(nil), animated: animated)
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

    func shouldShowNewBadge(for feature: NewBadgeFeature) -> Bool {
        guard isFeatureAvailableForNewBadge(feature) else { return false }
        return newBadgeVisibilityManager.shouldShowBadge(for: feature)
    }

    func storeNewBadgeFirstImpressionDateIfNeeded(for feature: NewBadgeFeature) {
        guard isFeatureAvailableForNewBadge(feature) else { return }
        newBadgeVisibilityManager.storeFirstImpressionDateIfNeeded(for: feature)
    }

    private func isFeatureAvailableForNewBadge(_ feature: NewBadgeFeature) -> Bool {
        switch feature {
        case .personalInformationRemoval:
            return isPIREnabled && meetsLocaleRequirement && dataBrokerProtectionViewControllerProvider != nil
        }
    }

    func openOtherPlatforms() {
        urlOpener.open(URL.otherDevices)
    }

    func openMoreSearchSettings() {
        Pixel.fire(pixel: .settingsMoreSearchSettings)
        let url = URL.searchSettings.appendingParameter(name: SERPSettingsConstants.returnParameterKey,
                                                        value: SERPSettingsConstants.privateSearch)
        urlOpener.open(url)
    }

    func openAssistSettings() {
        Pixel.fire(pixel: .settingsOpenAssistSettings)
        let url = URL.assistSettings.appendingParameter(name: SERPSettingsConstants.returnParameterKey,
                                                        value: SERPSettingsConstants.aiFeatures)
        urlOpener.open(url)
    }

    func openAIChat() {
        urlOpener.open(AppDeepLinkSchemes.openAIChat.url)
    }

    func openAIFeaturesSettings() {
        triggerDeepLinkNavigation(to: .aiChat)
    }

    func openWebTrackingProtectionLearnMore() {
        urlOpener.open(URL.webTrackingProtection)
    }
    
    func openGPCLearnMore() {
        urlOpener.open(URL.gpcLearnMore)
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

    @MainActor func openDuckAIChat() {
        onRequestOpenDuckAIChat?()
    }
}

// MARK: Legacy View Presentation
// Some UIKit views have visual issues when presented via UIHostingController so
// for all existing subviews, default to UIKit based presentation until we
// can review and migrate
extension SettingsViewModel {
    
    @MainActor func presentLegacyView(_ view: SettingsLegacyViewProvider.LegacyView, animated: Bool = true) {
        
        switch view {
        
        case .addToDock:
            presentViewController(legacyViewProvider.addToDock, modal: true)
        case .sync(let pairingInfo):
            pushViewController(legacyViewProvider.syncSettings(source: state.syncSource, pairingInfo: pairingInfo), animated: animated)
        case .appIcon: pushViewController(legacyViewProvider.appIconSettings(onChange: { [weak self] appIcon in
            self?.state.appIcon = appIcon
        }))
        case .unprotectedSites: pushViewController(legacyViewProvider.unprotectedSites)
        case .fireproofSites: pushViewController(legacyViewProvider.fireproofSites)
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
                                                                showSettingsScreen: state.showSettingsScreen,
                                                                source: state.autofillSource))

        case .gpc:
            firePixel(.settingsDoNotSellShown)
            pushViewController(legacyViewProvider.gpc)
        
        case .autoconsent:
            pushViewController(legacyViewProvider.autoConsent)
        case .passwordsImport:
            pushViewController(legacyViewProvider.importPasswords(importScreen: .completeSetup,
                                                                  delegate: self,
                                                                  onFinished: { [weak self] in
                                                                      Task { @MainActor [weak self] in
                                                                          self?.handleDataImportCompletion()
                                                                      }
                                                                  }))
        }
    }
 
    @MainActor
    private func pushViewController(_ view: UIViewController, animated: Bool = true) {
        onRequestPushLegacyView?(view, animated)
    }
    
    @MainActor
    private func presentViewController(_ view: UIViewController, modal: Bool) {
        onRequestPresentLegacyView?(view, modal)
    }

    @MainActor
    private func handleDataImportCompletion() {
        AppDependencyProvider.shared.autofillLoginSession.startSession()
        pushViewController(legacyViewProvider.loginSettings(delegate: self,
                                                            selectedAccount: nil,
                                                            selectedCard: nil,
                                                            showPasswordManagement: true,
                                                            showCreditCardManagement: false,
                                                            showSettingsScreen: nil,
                                                            source: state.autofillSource))
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
        handleDataImportCompletion()
    }
}


// MARK: DeepLinks
extension SettingsViewModel {

    enum SettingsDeepLinkSection: Identifiable, Equatable {
        case netP
        case dbp
        case itr
        case subscriptionFlow(redirectURLComponents: URLComponents? = nil)
        case subscriptionPlanChangeFlow(redirectURLComponents: URLComponents? = nil)
        case restoreFlow
        case duckPlayer
        case aiChat
        case privateSearch
        case subscriptionSettings
        case customizeToolbarButton
        case customizeAddressBarButton
        case appearance
        case general
        // Add other cases as needed

        var id: String {
            switch self {
            case .netP: return "netP"
            case .dbp: return "dbp"
            case .itr: return "itr"
            case .subscriptionFlow: return "subscriptionFlow"
            case .subscriptionPlanChangeFlow: return "subscriptionPlanChangeFlow"
            case .restoreFlow: return "restoreFlow"
            case .duckPlayer: return "duckPlayer"
            case .aiChat: return "aiChat"
            case .privateSearch: return "privateSearch"
            case .subscriptionSettings: return "subscriptionSettings"
            case .customizeToolbarButton: return "customizeToolbarButton"
            case .customizeAddressBarButton: return "customizeAddressButton"
            case .appearance: return "appearance"
            case .general: return "general"
            // Ensure all cases are covered
            }
        }

        // Define the presentation type: .sheet or .push
        // Default to .sheet, specify .push where needed
        var type: DeepLinkType {
            switch self {
            case .netP, .dbp, .itr, .subscriptionFlow, .subscriptionPlanChangeFlow, .restoreFlow, .duckPlayer, .aiChat, .privateSearch, .subscriptionSettings, .customizeToolbarButton, .customizeAddressBarButton, .appearance, .general:
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

    /// Fetches the current subscription from the backend and updates `state.subscription` and the cache.
    /// Handles three outcomes: active subscription (populates entitlements), nil/no subscription, and no token (unauthenticated).
    @MainActor
    private func setupSubscriptionEnvironment() async {
        // 1. Start from cached state or defaults
        var updatedSubscriptionState = subscriptionStateCache.get() ?? SettingsState.defaults.subscription

        // 2. Set store availability, auth status, and offer eligibility (independent of backend subscription)
        updatedSubscriptionState.hasAppStoreProductsAvailable = subscriptionManager.hasAppStoreProductsAvailable
        updatedSubscriptionState.isSignedIn = subscriptionManager.isUserAuthenticated
        updatedSubscriptionState.isEligibleForTrialOffer = await isUserEligibleForTrialOffer()
        updatedSubscriptionState.isWinBackEligible = winBackOfferVisibilityManager.isOfferAvailable

        do {
            // 3. Fetch subscription from backend (returns nil if no subscription exists)
            guard let subscription = try await subscriptionManager.getSubscription() else {
                // 3a. No subscription on backend — reset subscription fields and exit early
                Logger.subscription.debug("No subscription data available")
                applyNoSubscriptionState(&updatedSubscriptionState)
                DailyPixel.fireDailyAndCount(pixel: .settingsSubscriptionAccountWithNoSubscriptionFound)
                state.subscription = updatedSubscriptionState
                subscriptionStateCache.set(state.subscription)
                return
            }

            // 4. Populate subscription details from backend response
            updatedSubscriptionState.platform = subscription.platform
            updatedSubscriptionState.hasSubscription = true
            updatedSubscriptionState.hasActiveSubscription = subscription.isActive
            updatedSubscriptionState.isActiveTrialOffer = subscription.hasActiveTrialOffer

            // 5. Check which features are enabled for the user (entitlements present in the access token)
            let featuresToCheck: [SubscriptionEntitlement] = [.networkProtection, .dataBrokerProtection, .identityTheftRestoration, .identityTheftRestorationGlobal, .paidAIChat]
            var enabledFeatures: [SubscriptionEntitlement] = []
            for feature in featuresToCheck {
                if let isEnabled = try? await subscriptionManager.isFeatureEnabled(feature),
                    isEnabled {
                    enabledFeatures.append(feature)
                }
            }

            // 6. Set enabled features and plan-included features
            updatedSubscriptionState.entitlements = enabledFeatures
            updatedSubscriptionState.subscriptionFeatures = subscription.features ?? []
        } catch SubscriptionManagerError.noTokenAvailable {
            // 3b. User is not authenticated — reset subscription fields (no pixel: user has no account)
            Logger.subscription.debug("No subscription data available - user not authenticated")
            updatedSubscriptionState.isSignedIn = false
            applyNoSubscriptionState(&updatedSubscriptionState)
        } catch {
            // 3c. Transient error — keep cached state as-is
            Logger.subscription.error("Failed to fetch Subscription: \(error, privacy: .public)")
        }

        // 7. Persist updated state
        state.subscription = updatedSubscriptionState
        subscriptionStateCache.set(state.subscription)
    }

    /// Resets subscription-dependent fields to their "no subscription" defaults.
    private func applyNoSubscriptionState(_ subscription: inout SettingsState.Subscription) {
        subscription.hasSubscription = false
        subscription.hasActiveSubscription = false
        subscription.entitlements = []
        subscription.platform = .unknown
        subscription.isActiveTrialOffer = false
        subscription.subscriptionFeatures = []
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
        
        textZoomObserver = NotificationCenter.default.addObserver(forName: AppUserDefaults.Notifications.textZoomChange,
                                                                  object: nil,
                                                                  queue: .main, using: { [weak self] _ in
            guard let self = self else { return }
            self.state.textZoom = SettingsState.TextZoom(level: self.appSettings.defaultTextZoomLevel)
        })
        
        aiChatSettingsObserver = NotificationCenter.default.addObserver(forName: .aiChatSettingsChanged,
                                                                  object: nil,
                                                                  queue: .main, using: { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.refreshAutoClearOptionsIfNeeded()
            }
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

    func forgetAll(fireRequest: FireRequest) {
        autoClearActionDelegate?.performDataClearing(for: fireRequest)
    }

    func restoreAccountPurchase() async {
        await restoreAccountPurchaseV2()
    }

    func restoreAccountPurchaseV2() async {
        DispatchQueue.main.async { self.state.subscription.isRestoring = true }

        let appStoreRestoreFlow = DefaultAppStoreRestoreFlow(subscriptionManager: subscriptionManager,
                                                             storePurchaseManager: subscriptionManager.storePurchaseManager())
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
                DailyPixel.fireDailyAndCount(pixel: .subscriptionActivatingRestoreErrorMissingAccountOrTransactions)
            case .pastTransactionAuthenticationError:
                DailyPixel.fireDailyAndCount(pixel: .subscriptionActivatingRestoreErrorPastTransactionAuthenticationError)
            case .failedToObtainAccessToken:
                DailyPixel.fireDailyAndCount(pixel: .subscriptionActivatingRestoreErrorFailedToObtainAccessToken)
            case .failedToFetchAccountDetails:
                DailyPixel.fireDailyAndCount(pixel: .subscriptionActivatingRestoreErrorFailedToFetchAccountDetails)
            case .failedToFetchSubscriptionDetails:
                DailyPixel.fireDailyAndCount(pixel: .subscriptionActivatingRestoreErrorFailedToFetchSubscriptionDetails)
            case .subscriptionExpired:
                DailyPixel.fireDailyAndCount(pixel: .subscriptionActivatingRestoreErrorSubscriptionExpired)
            }
        }
    }

    /// Checks if the user is eligible for a free trial subscription offer.
    /// - Returns: `true` if free trials are available and the user is eligible for a free trial, `false` otherwise.
    private func isUserEligibleForTrialOffer() async -> Bool {
        return subscriptionManager.storePurchaseManager().isUserEligibleForFreeTrial()
    }

}

// Deeplink notification handling
extension NSNotification.Name {
    static let settingsDeepLinkNotification: NSNotification.Name = Notification.Name(rawValue: "com.duckduckgo.notification.settingsDeepLink")
}

enum SettingsDeepLinkUserInfoKey {
    static let onPresented = "onPresented"
}

/// Typed wrapper for the post-presentation callback passed via `settingsDeepLinkNotification`
/// userInfo. Using a concrete type instead of a bare closure makes signature mismatches a
/// build error rather than a silent runtime nil.
struct SettingsDeepLinkCallback {
    let onPresented: () -> Void
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
            get: {
                self.onboardingSearchExperienceSettingsResolver.deferredValue ?? self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled
            },
            set: { newValue in
                if self.onboardingSearchExperienceSettingsResolver.shouldUseDeferredOnboardingChoice {
                    if self.onboardingSearchExperienceSettingsResolver.storeIfDeferred(newValue) {
                        self.objectWillChange.send()
                    }
                } else {
                    guard newValue != self.aiChatSettings.isAIChatSearchInputUserSettingsEnabled else { return }
                    withAnimation {
                        self.objectWillChange.send()
                        self.aiChatSettings.enableAIChatSearchInputUserSettings(enable: newValue)
                    }
                }
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

    var aiChatTabBarEnabledBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.aiChatSettings.isAIChatTabBarUserSettingsEnabled },
            set: { newValue in
                self.aiChatSettings.enableAIChatTabBarUserSettings(enable: newValue)
                DailyPixel.fireDailyAndCount(pixel: newValue ? .aiChatSettingsNavigationBarTurnedOn : .aiChatSettingsNavigationBarTurnedOff)
            }
        )
    }

    var isAutomaticContextAttachmentEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { self.aiChatSettings.isAutomaticContextAttachmentEnabled },
            set: { newValue in
                withAnimation {
                    self.objectWillChange.send()
                    self.aiChatSettings.enableAutomaticContextAttachment(enable: newValue)
                }
            }
        )
    }

    var defaultOmnibarModeBinding: Binding<DefaultOmnibarMode> {
        Binding<DefaultOmnibarMode>(
            get: { self.aiChatSettings.defaultOmnibarMode },
            set: { newValue in
                guard newValue != self.aiChatSettings.defaultOmnibarMode else { return }
                self.objectWillChange.send()
                self.aiChatSettings.setDefaultOmnibarMode(newValue)
            }
        )
    }

    var searchAssistFrequencyBinding: Binding<SearchAssistFrequency> {
        Binding<SearchAssistFrequency>(
            get: { self.serpSettings.searchAssistFrequency },
            set: { newValue in
                guard newValue != self.serpSettings.searchAssistFrequency else { return }
                self.objectWillChange.send()
                self.serpSettings.searchAssistFrequency = newValue
                DailyPixel.fireDailyAndCount(pixel: Self.searchAssistPixel(for: newValue))
            }
        )
    }

    var hideAIImagesBinding: Binding<HideAIImagesOption> {
        Binding<HideAIImagesOption>(
            get: { HideAIImagesOption(hidden: self.serpSettings.hideAIGeneratedImages) },
            set: { newValue in
                guard newValue.hidden != self.serpSettings.hideAIGeneratedImages else { return }
                self.objectWillChange.send()
                self.serpSettings.hideAIGeneratedImages = newValue.hidden
                DailyPixel.fireDailyAndCount(pixel: newValue.hidden ? .aiFeaturesHideImagesOn : .aiFeaturesHideImagesOff)
            }
        )
    }

    /// Maps a Search Assist frequency to its value-in-name AI Features pixel.
    private static func searchAssistPixel(for frequency: SearchAssistFrequency) -> Pixel.Event {
        switch frequency {
        case .never: return .aiFeaturesSearchAssistNever
        case .onDemand: return .aiFeaturesSearchAssistOnDemand
        case .sometimes: return .aiFeaturesSearchAssistSometimes
        case .often: return .aiFeaturesSearchAssistOften
        }
    }

    /// True when Duck.ai is off and both SERP AI settings are at their most-restrictive values.
    /// Hides the "Disable AI Features" button once everything is already disabled.
    var isAllAIDisabled: Bool {
        !aiChatSettings.isAIChatEnabled
            && serpSettings.searchAssistFrequency == .never
            && serpSettings.hideAIGeneratedImages
    }

    func disableAllAI() {
        objectWillChange.send()
        aiChatSettings.enableAIChat(enable: false)
        serpSettings.searchAssistFrequency = .never
        serpSettings.hideAIGeneratedImages = true
        DailyPixel.fireDailyAndCount(pixel: .aiFeaturesDisabled)
    }

    var isChatSuggestionsEnabled: Binding<Bool> {
        Binding<Bool>(
            get: { self.aiChatSettings.isChatSuggestionsEnabled },
            set: { newValue in
                withAnimation {
                    self.objectWillChange.send()
                    self.aiChatSettings.enableChatSuggestions(enable: newValue)
                }
            }
        )
    }

    var showTrackerCountInTabSwitcherBinding: Binding<Bool> {
        Binding<Bool>(
            get: { self.tabSwitcherSettings.showTrackerCountInTabSwitcher },
            set: { newValue in
                self.tabSwitcherSettings.showTrackerCountInTabSwitcher = newValue
                Pixel.fire(pixel: .settingsTrackerCountInTabSwitcherToggled,
                          withAdditionalParameters: [PixelParameters.enabled: String(newValue)])
            }
        )
    }

    func launchAIFeaturesLearnMore() {
        urlOpener.open(URL.aiFeaturesLearnMore)
    }

}

@MainActor
extension SettingsViewModel: DataClearingSettingsViewModelDelegate {

    func navigateToFireproofSites() {
        presentLegacyView(.fireproofSites)
    }

    func navigateToAutoClearData() {
        let viewModel = AutoClearSettingsViewModel(
            appSettings: appSettings,
            aiChatSettings: aiChatSettings
        )
        let view = AutoClearSettingsView(viewModel: viewModel)
            .environmentObject(self)
        let hostingController = UIHostingController(rootView: view)
        pushViewController(hostingController)
    }

    func presentFireConfirmation(from sourceRect: CGRect) {
        onRequestPresentFireConfirmation?(sourceRect, { [weak self] fireRequest in
            self?.forgetAll(fireRequest: fireRequest)
        }, {
            // Cancelled - no action needed
        })
    }
    
    private func refreshAutoClearOptionsIfNeeded() {
        if !aiChatSettings.isAIChatEnabled {
            appSettings.autoClearAction = appSettings.autoClearAction.subtracting(.aiChats)
        }
    }
}

// MARK: - Settings + What's New

extension SettingsViewModel {

    @MainActor
    var shouldShowWhatsNew: Bool {
        featureFlagger.isFeatureOn(.showWhatsNewPromptOnDemand) && whatsNewCoordinator.canShowPromptOnDemand
    }

    @MainActor
    func openWhatsNew() {
        guard let viewController = whatsNewCoordinator.provideModalPrompt()?.viewController else {
            assertionFailure("Prompt should not be nil")
            return
        }

        Pixel.fire(pixel: .settingsWhatsNewOpen)
        // Set Modal false to prevent caller to set fullScreen modal presentation style.
        // Coordinator already sets the appropriate presentation style for iPhone and iPad.
        presentViewController(viewController, modal: false)
    }
    
}
