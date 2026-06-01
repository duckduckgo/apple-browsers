//
//  PrivacyFeature.swift
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

import Foundation

/// Features whose `rawValue` should be the key to access their corresponding `PrivacyConfigurationData.PrivacyFeature` object
public enum PrivacyFeature: String {
    case contentBlocking
    case duckPlayer
    case fingerprintingTemporaryStorage
    case fingerprintingBattery
    case fingerprintingScreenSize
    case fingerprintingCanvas
    case gpc
    case httpsUpgrade = "https"
    case autoconsent
    case clickToLoad
    case autofill
    case autofillBreakageReporter
    case ampLinks
    case trackingParameters
    case customUserAgent
    case referrer
    case adClickAttribution
    case windowsWaitlist
    case windowsDownloadLink
    case incontextSignup
    case newTabContinueSetUp
    case newTabSearchField
    case dbp
    case sync
    case privacyDashboard
    case updates
    case privacyPro
    case sslCertificates
    case toggleReports
    case maliciousSiteProtection
    case brokenSitePrompt
    case remoteMessaging
    case additionalCampaignPixelParams
    case syncPromotion
    case autofillSurveys
    case marketplaceAdPostback
    case networkProtection
    case aiChat
    case contextualOnboarding
    case textZoom
    case adAttributionReporting
    case forceOldAppDelegate
    case htmlHistoryPage
    case tabManager
    case tabSuspension
    case tabSwitcherTrackerCount
    case webViewStateRestoration
    case experimentalTheming
    case setAsDefaultAndAddToDock
    case contentScopeExperiments
    case extendedOnboarding
    case macOSBrowserConfig
    case iOSBrowserConfig
    // Demonstrative case for default value. Remove once a real-world feature is added
    case intentionallyLocalOnlyFeatureForTests
    case delayedWebviewPresentation
    case disableFireAnimation
    case htmlNewTabPage
    case daxEasterEggLogos
    case daxEasterEggPermanentLogo
    case openFireWindowByDefault
    case attributedMetrics
    case dataImport
    case duckAiChatHistory
    case popupBlocking
    case pageContext
    case webExtensions
    case forceDarkModeOnWebsites
    case promoQueue
    case adBlockingExtension
}

/// An abstraction to be implemented by any "subfeature" of a given `PrivacyConfiguration` feature.
/// The `rawValue` should be the key to access their corresponding `PrivacyConfigurationData.PrivacyFeature.Feature` object
/// `parent` corresponds to the top level feature under which these subfeatures can be accessed
public protocol PrivacySubfeature: RawRepresentable where RawValue == String {
    var parent: PrivacyFeature { get }
}

// MARK: Subfeature definitions

public enum MacOSBrowserConfigSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .macOSBrowserConfig
    }

    // Demonstrative case for default value. Remove once a real-world feature is added
    case intentionallyLocalOnlySubfeatureForTests

    /// Address-bar render-performance instrumentation kill switch.
    case addressBarPerformanceInstrumentation

    /// Hang reporting feature flag
    case hangReporting

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211260578559159?focus=true
    case unifiedURLPredictor

    // Gradual rollout for new Fire dialog replacing the legacy popover
    // https://app.asana.com/1/137249556945/project/72649045549333/task/1210417832822045
    case fireDialog

    // Controls visibility of the "Manage individual sites" link in the Fire dialog
    case fireDialogIndividualSitesLink

    /// Use WKDownload for favicon fetching to bypass App Transport Security restrictions on HTTP URLs
    case faviconWKDownload

    /// Hide manual update option and always use automatic updates
    case automaticUpdatesOnly

    /// Warn before quit confirmation overlay
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212444166689969
    case warnBeforeQuit

    /// Feature flag for a macOS Tahoe fix only
    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1211448334620171?focus=true
    case blurryAddressBarTahoeFix

    /// Prevents IME composition-confirm Return from submitting the address bar.
    case addressBarIMEConfirmFix

    /// Feature Flag for the First Time Quit Survey
    /// https://app.asana.com/1/137249556945/inbox/1203972458584425/item/1212200919350194/story/1212483080081687
    case firstTimeQuitSurvey

    /// Suppresses the first-time quit survey when termination wasn't initiated by the user
    /// (Sparkle update relaunch, or system logout/restart/shutdown).
    case firstTimeQuitSurveySkipNonUserQuit

    /// Web Notifications API polyfill - allows websites to show notifications via native macOS Notification Center
    /// https://app.asana.com/1/137249556945/project/414235014887631/task/1211395954816928?focus=true
    case webNotifications

    /// Memory Pressure Reporter
    /// https://app.asana.com/1/137249556945/project/1201048563534612/task/1212762049862427?focus=true
    case memoryPressureReporting

    /// Memory Usage Reporting
    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1212762049862432?focus=true
    case memoryUsageReporting

    /// Failsafe flag for disabling call stack tree depth limiting in crash collector
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213037858764817
    case crashCollectionLimitCallStackTreeDepth

    /// Ctrl+click compatibility fix to preserve right click behavior
    case controlClickFix

    /// Enable Look Up (three-finger click) while keeping link preview disabled
    case webViewLookUpAction

    /// Enables showing browsing history domains in the first-time quit survey
    case websitesHistoryFirstTimeQuitSurvey

    /// Autoplay policy control via WKWebpagePreferences
    case autoplayPolicy

    case tabAnimations

    /// Enables lazy reload for the more options menu
    case lazyMenuRebuild

    case screenTimeCleaning

    /// Enables the custom NSPanel-based bookmarks bar menu (replacing NSPopover) with NSGlassEffectView on macOS 26
    case bookmarksBarMenusCustomWindow

    /// https://app.asana.com/1/137249556945/project/1211264967278501/task/1211806114021633?focus=true
    case onboardingRebranding

    /// Routes reload-after-error through `_evaluateJavaScriptWithoutUserGesture` instead of the
    /// legacy `javascript:` URL trampoline. Kill switch — disable remotely to revert to the
    /// trampoline if the SPI ever misbehaves.
    case newErrorPageReload
}

public enum iOSBrowserConfigSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .iOSBrowserConfig
    }

    // Demonstrative case for default value. Remove once a real-world feature is added
    case intentionallyLocalOnlySubfeatureForTests

    case widgetReporting

    // Local inactivity provisional notifications delivered to Notification Center.
    // https://app.asana.com/1/137249556945/project/72649045549333/task/1211003501974970?focus=true
    case inactivityNotification

    /// https://app.asana.com/1/137249556945/project/715106103902962/task/1210997282929955?focus=true
    case unifiedURLPredictor

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211660503405838?focus=true
    case forgetAllInSettings

    /// https://app.asana.com/1/137249556945/project/481882893211075/task/1212057154681076?focus=true
    case productTelemetrySurfaceUsage

    ///  https://app.asana.com/1/137249556945/project/414709148257752/task/1212395110448661?focus=true
    case appRatingPrompt

    /// https://app.asana.com/1/137249556945/project/1206329551987282/task/1212238464901412?focus=true
    case showWhatsNewPromptOnDemand

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212875994217788?focus=true
    case genericBackgroundTask

    /// Failsafe flag for disabling call stack tree depth limiting in crash collector
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213037858764805
    case crashCollectionLimitCallStackTreeDepth

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212835969125260
    case browsingMenuSheetEnabledByDefault

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213336304802675
    case showNTPAfterIdleReturn

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214749215529034?focus=true
    case escapeHatchActions

    case crashReportOptInStatusResetting

    case screenTimeCleaning

    case minimalChromeInLandscape

    /// https://app.asana.com/1/137249556945/project/1206329551987282/task/1211806114021630?focus=true
    case onboardingRebranding

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214974217398704?focus=true
    case appRebranding

    /// https://app.asana.com/1/137249556945/task/1213314048601761
    case fireMode

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213965646075290
    case fireButtonRefinements

    /// https://app.asana.com/1/137249556945/project/392891325557410/task/1212828713075939?focus=true
    case omniBarLongPressMenu

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214797978179697?focus=true
    case customProductPageDuckAiChat

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215151176422651?focus=true
    case customProductPageDuckAiOnboardingFlow

    /// Gate the default-to-NTP-after-idle behavior for existing iPhone users behind a remote flag.
    /// https://app.asana.com/1/137249556945/project/1204186595873227/task/1214830562427843
    case defaultExistingIPhoneUsersToNewTabAfterIdle

    /// Coalesces tabManager.save into a debounced/max-wait window and moves the disk write off-main.
    /// Kill switch in case the new path regresses persistence reliability or hang counts.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215099690878849
    case tabsSaveOptimization

    /// https://app.asana.com/1/137249556945/project/715106103902962/task/1213690148091855
    case icsCalendarLinks

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215169783702336
    case walletPassDownload
}

public enum TabManagerSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .tabManager
    }

    case multiSelection
}

public enum AutofillSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .autofill
    }

    case credentialsAutofill
    case credentialsSaving
    case inlineIconCredentials
    case accessCredentialManagement
    case autofillPasswordGeneration
    case onByDefault
    case onForExistingUsers
    case unknownUsernameCategorization
    case credentialsImportPromotionForExistingUsers
    case partialFormSaves
    case autofillCreditCards
    case autofillCreditCardsOnByDefault
    case passwordVariantCategorization
    case autocompleteAttributeSupport
    case inputFocusApi
    case canPromoteImportPasswordsInPasswordManagement
    case canPromoteImportPasswordsInBrowser
    case createFireproofFaviconUpdaterSecureVaultInBackground
    case autofillExtensionSettings
    case canPromoteAutofillExtensionInBrowser
    case canPromoteAutofillExtensionInPasswordManagement
    case migrateKeychainAccessibility
    case autofillPasswordSearchPrioritizeDomain
    case onboardingDismissExperiment
    case autofillPasswordsStatusBar
}

public enum DBPSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .dbp
    }

    case waitlist
    case waitlistBetaActive
    case freemium
    case remoteBrokerDelivery
    case emailConfirmationDecoupling
    case foregroundRunningOnAppActive
    case continuedProcessing
    case pirRollout
    case goToMarket
    case webViewUserAgent
    case freemiumPIR
    case contentBlocking
}

public enum AIChatSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .aiChat
    }

    /// Displays the AI Chat icon in the iOS browsing menu toolbar.
    case browsingToolbarShortcut

    /// Displays the AI Chat icon in the iOS address bar while on a SERP.
    case addressBarShortcut

    /// Web and native integration for opening AI Chat in a custom webview.
    case deepLink

    /// Keep AI Chat session after the user closes it
    case keepSession

    /// Adds capability to load AI Chat in a sidebar
    case sidebar

    /// Experimental address bar with duck.ai
    case experimentalAddressBar

    /// Global switch to disable all AI Chat related functionality
    case globalToggle

    /// Adds support for passing currently visible website context to the sidebar
    case pageContext

    /// Enables updated AI features settings screen
    case aiFeaturesSettingsUpdate

    /// Show AI Chat address bar choice screen
    case showAIChatAddressBarChoiceScreen

    /// Adds toggle for controlling  'Ask Follow-Up Questions' setting.
    case serpSettingsFollowUpQuestions

    /// Rollout feature flag for entry point improvements
    case improvements

    /// Allows user to clear AI Chat history with the fire button or auto-clear
    case clearAIChatHistory

    /// Signals that the iOS app should display duck.ai chats in "full mode" i.e in a tab, not a sheet
    case fullDuckAIMode

    /// Enables native-side support for standalone migration flows in AI Chat
    case standaloneMigration

    /// Enables Duck.ai query experiment during onboarding
    case onboardingDuckAIQueryExperiment

    /// Enables Duck.ai query experiment with tracker-blocking demo during onboarding
    case onboardingDuckAIQueryTrackersDemoExperiment

    /// Enables the omnibar toggle for AI Chat
    case omnibarToggle

    /// Enables the omnibar onboarding for AI Chat
    case omnibarOnboarding

    /// Enables the omnibar cluster for AI Chat
    case omnibarCluster

    /// Enables the omnibar tools (customize, search toggle, image upload) for AI Chat
    case omnibarTools

    /// Enables the default omnibar toggle position setting for AI Chat
    case omnibarDefaultPosition

    case unifiedToggleInput

    /// Hides the Search↔Duck.ai toggle in the unified input when the user is on a Duck.ai tab,
    /// regardless of the user's `Settings → Address Bar → Show Duck.ai Toggle` preference. Lets us
    /// roll out the new Duck.ai-tab nav UI (no toggle on chat) independently of the master flag.
    case aiChatTabHideToggle

    /// Signals that the iOS app should display duck.ai chats in "contextual mode" when opened from specific entry points
    case contextualDuckAIMode

    /// Controls whether automatic page context attachment defaults to enabled
    case autoAttachContextByDefault

    /// Signals that the iPad app should display duck.ai chats in a tab instead of a sheet
    case iPadDuckaiOnTab

    /// Signals that the iPad app should display the duck.ai toggle
    case iPadAIChatToggle

    /// Controls deletion of Synced chats
    case supportsSyncChatsDeletion

    /// Shows a link in Settings → AI Features that opens the Duck.ai Settings modal.
    case settingsLinkInAiFeatures

    case sidebarResizable

    case sidebarFloating

    /// Enables recent AI chats on the New Tab Page omnibar
    case ntpRecentChats

    /// Enables the "View all chats" button on the New Tab Page omnibar
    case ntpViewAllChats

    /// Enables AI chat tools (model selector, image upload) on the New Tab Page omnibar
    case ntpChatTools

    /// Enables image generation mode on the New Tab Page omnibar
    case ntpImageGeneration

    /// Enables web search mode on the New Tab Page omnibar
    case ntpWebSearch

    /// Enables support for adding multiple page contexts to a single chat session
    case multiplePageContexts

    /// Enables attaching content from multiple open tabs to the Duck.ai sidebar chat.
    case sidebarAttachMoreTabs

    /// Enables attaching content from multiple open tabs to the Duck.ai omnibar (address bar) chat.
    case omnibarAttachMoreTabs

    /// Enables page context feature on iPad
    case iPadPageContext

    /// Enables voice chat shortcut in the focused address bar
    case voiceShortcut

    /// Enables improved contextual sheet UX (welcome message, ask about page, etc.)
    case contextualSheetImprovements

    /// Enables removing individual AI chat suggestions
    case removeSuggestion

    /// Enables the fire button in the contextual AI chat sheet
    case contextualFireButton

    /// Enables the Duck.ai top-level main menu shortcut (macOS only)
    case mainMenuShortcut

    /// Enables the Duck.ai submenu in the more options (hamburger) menu (macOS only)
    case moreOptionsMenuShortcut

    /// Enables native-side storage for AI Chat (settings, chats, files)
    case nativeStorage

    /// Prevents about: scheme navigations (e.g. about:srcdoc) from opening new tabs in the sidebar
    case sidebarAboutSchemeNavigationFix

    /// Enabled 'View all chats' for Duck.ai in the omnibar
    case viewAllChatsNativeOmnibar

    /// Enables image generation mode toggle in the Duck.ai omnibar
    case omnibarImageGeneration

    /// Enables web search tool in the Duck.ai omnibar
    case omnibarWebSearch

    /// Enables the reasoning effort picker in the Duck.ai omnibar
    case omnibarReasoningEffort

    /// Enables 1-click voice-chat access from the Duck.ai omnibar (mic icon shown when input is empty)
    case omnibarVoiceChatAccess

    /// Enables querying AI Chat data directly from local storage instead of via webview
    case nativeDataAccess

    /// macOS only. Routes duck.ai voice-chat microphone permission entirely through native:
    /// auto-grants per-site mic permission at launch, locks the Permission Center row,
    /// surfaces a "System microphone disabled" warning when the OS has denied access, and
    /// presents the Permission Center popover when the FE reports `getUserMedia` failure.
    case nativeVoicePermissionFlow

    /// Displays the Duck.ai shortcut in the iPad browser chrome (tabs bar).
    case iPadChromeShortcut

    /// Enables moving the AI Chat native-storage container from the shared App
    /// Group into the app's Application Support directory on iOS. Off keeps the
    /// legacy App Group path.
    case nativeStoragePathMigration
}

public enum HtmlNewTabPageSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .htmlNewTabPage
    }

    /// Global switch to disable New Tab Page search box
    case omnibar

    /// Global switch to control managing state of NTP in frontend using tab IDs
    case newTabPageTabIDs

    /// Controls whether the Next Steps List widget is enabled on New Tab Page
    case nextStepsListWidget
}

public enum NetworkProtectionSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .networkProtection
    }

    /// App Exclusions for the VPN
    /// https://app.asana.com/0/1206580121312550/1209150117333883/f
    case appExclusions

    /// App Store System Extension support
    ///  https://app.asana.com/0/0/1209402073283584
    case appStoreSystemExtension

    /// App Store System Extension Update Message support
    /// https://app.asana.com/0/1203108348835387/1209710972679271/f
    case appStoreSystemExtensionMessage

    /// Display user tips for Network Protection
    /// https://app.asana.com/0/72649045549333/1208231259093710/f
    case userTips

    /// Enforce routes for the VPN to fix TunnelVision
    /// https://app.asana.com/0/72649045549333/1208617860225199/f
    case enforceRoutes

    /// Risky Domain Protection for VPN
    /// https://app.asana.com/0/1204186595873227/1206489252288889
    case riskyDomainsProtection
}

public enum SyncSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .sync
    }

    case level0ShowSync
    case level1AllowDataSyncing
    case level2AllowSetupFlows
    case level3AllowCreateAccount
    case seamlessAccountSwitching
    case exchangeKeysToSyncWithAnotherDevice
    case canScanUrlBasedSyncSetupBarcodes
    case canInterceptSyncSetupUrls
    case syncSetupBarcodeIsUrlBased
    case refactorOfSyncPreferences
    case newSyncEntryPoints
    case newDeviceSyncPrompt
    case syncAutoRestore
    case syncCreditCards
    case syncIdentities
    case aiChatSync
    case aiChatSyncPromo
    case simplifiedSyncSetupExperiment
    case allowSingleDeviceOnConnectScreen
}

public enum AutoconsentSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .autoconsent
    }

    case onByDefault
    case filterlist
    case heuristicAction
}

public enum PrivacyProSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .privacyPro }

    case allowPurchase
    case allowPurchaseStripe
    case useUnifiedFeedback
    case privacyProOnboardingPromotion
    case paidAIChat
    case supportsAlternateStripePaymentFlow
    case winBackOffer
    case vpnMenuItem
    case blackFridayCampaign
    case allowProTierPurchase
    case freeTrialConversionWideEvent
    case subscriptionPromoForReinstallers
}

public enum DuckPlayerSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .duckPlayer }
    case pip
    case autoplay
    case openInNewTab
    case customError
    case enableDuckPlayer // iOS DuckPlayer rollout feature
    case nativeUI // Use Duckplayer's native UI
}

public enum SyncPromotionSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .syncPromotion }
    case bookmarks
    case passwords
}

public enum HTMLHistoryPageSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .htmlHistoryPage }
    case isLaunched
}

public enum TabSuspensionSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .tabSuspension }
    case memoryPressureTrigger
}

public enum ContentBlockingSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .contentBlocking }
    case tdsNextExperimentBaseline
    case tdsNextExperimentFeb25
    case tdsNextExperimentMar25
    case tdsNextExperimentApr25
    case tdsNextExperimentMay25
    case tdsNextExperimentJun25
    case tdsNextExperimentJul25
    case tdsNextExperimentAug25
    case tdsNextExperimentSep25
    case tdsNextExperimentOct25
    case tdsNextExperimentNov25
    case tdsNextExperimentDec25
    case tdsNextExperiment001
    case tdsNextExperiment002
    case tdsNextExperiment003
    case tdsNextExperiment004
    case tdsNextExperiment005
    case tdsNextExperiment006
    case tdsNextExperiment007
    case tdsNextExperiment008
    case tdsNextExperiment009
    case tdsNextExperiment010
    case tdsNextExperiment011
    case tdsNextExperiment012
    case tdsNextExperiment013
    case tdsNextExperiment014
    case tdsNextExperiment015
    case tdsNextExperiment016
    case tdsNextExperiment017
    case tdsNextExperiment018
    case tdsNextExperiment019
    case tdsNextExperiment020
    case tdsNextExperiment021
    case tdsNextExperiment022
    case tdsNextExperiment023
    case tdsNextExperiment024
    case tdsNextExperiment025
    case tdsNextExperiment026
    case tdsNextExperiment027
    case tdsNextExperiment028
    case tdsNextExperiment029
    case tdsNextExperiment030
}

public enum MaliciousSiteProtectionSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .maliciousSiteProtection }
    case onByDefault // Rollout feature
    case scamProtection
}

public enum OnboardingSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .extendedOnboarding }

    case showSettingsCompleteSetupSection
}

public enum ExperimentalThemingSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .experimentalTheming }

    case visualUpdates // Rollout
}

public enum AttributedMetricsSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .attributedMetrics }

    case featureEnabled
    case emitAllMetrics
    case retention
    case canEmitRetention
    case searchDaysAvg
    case canEmitSearchDaysAvg
    case searchCountAvg
    case canEmitSearchCountAvg
    case adClickCountAvg
    case canEmitAdClickCountAvg
    case aiUsageAvg
    case canEmitAIUsageAvg
    case subscriptionRetention
    case canEmitSubscriptionRetention
    case syncDevices
    case canEmitSyncDevices
    case sendOriginParam
}

public enum DataImportSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .dataImport }

    case newSafariFilePicker
    case newDataImportExperience
    case dataImportSummarySyncPromotion
}

public enum PopupBlockingSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .popupBlocking
    }

    case featureEnabled
    case createWebViewGatingFailsafe
}

public enum WebExtensionsSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .webExtensions }

    case featureEnabled
    case embeddedExtension = "embedded"
    case embeddedRollout
}

public enum AdBlockingExtensionSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .adBlockingExtension }

    case featureEnabled
    case featureEnabledByDefault
}

public enum ForceDarkModeOnWebsitesSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .forceDarkModeOnWebsites }

    case featureRollout
}

public enum ContextualOnboardingSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .contextualOnboarding }

    case featureEnabled
}

public enum DelayedWebviewPresentationSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .delayedWebviewPresentation }

    case featureEnabled
}

public enum DuckAiChatHistorySubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .duckAiChatHistory }

    case featureEnabled
    case nativeChatHistory
}

public enum PromoQueueSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .promoQueue }

    case featureEnabled
}

public enum AutofillBreakageReporterSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .autofillBreakageReporter }

    case featureEnabled
}

public enum IncontextSignupSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .incontextSignup }

    case featureEnabled
}

public enum AutofillSurveysSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .autofillSurveys }

    case featureEnabled
}

public enum AdAttributionReportingSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .adAttributionReporting }

    case featureEnabled
}

public enum DaxEasterEggLogosSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .daxEasterEggLogos }

    case featureEnabled
}

public enum DaxEasterEggPermanentLogoSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .daxEasterEggPermanentLogo }

    case featureEnabled
}

public enum PageContextSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .pageContext }

    case featureEnabled
}

public enum TabSwitcherTrackerCountSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .tabSwitcherTrackerCount }

    case featureEnabled
}
