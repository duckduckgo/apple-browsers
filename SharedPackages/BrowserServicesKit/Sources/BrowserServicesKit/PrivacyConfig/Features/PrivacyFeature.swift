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
    case breakageReporting
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
    case updatesWontAutomaticallyRestartApp
    case performanceMetrics
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
    case autocompleteTabs
    case networkProtection
    case aiChat
    case contextualOnboarding
    case textZoom
    case adAttributionReporting
    case forceOldAppDelegate
    case htmlHistoryPage
    case tabManager
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
    case openFireWindowByDefault
    case attributedMetrics
    case dataImport
    case duckAiDataClearing
    case serp
    case popupBlocking
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

    /// https://app.asana.com/1/137249556945/project/1206580121312550/task/1209808389662317?focus=true
    case willSoonDropBigSurSupport

    /// Hang reporting feature flag
    case hangReporting

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211260578559159?focus=true
    case unifiedURLPredictor

    /// Enable WebKit page load timing performance reporting
    /// https://app.asana.com/1/137249556945/project/72649045549333/task/XXXXXXXXX?focus=true
    case webKitPerformanceReporting

    // Gradual rollout for new Fire dialog replacing the legacy popover
    // https://app.asana.com/1/137249556945/project/72649045549333/task/1210417832822045
    case fireDialog

    // Controls visibility of the "Manage individual sites" link in the Fire dialog
    case fireDialogIndividualSitesLink

    /// New App Store Update flow feature flag
    /// https://app.asana.com/1/137249556945/project/1199230911884351/task/1211563301906360?focus=true
    case appStoreUpdateFlow

    /// Feature flag for a macOS Tahoe fix only
    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1211448334620171?focus=true
    case blurryAddressBarTahoeFix

    /// New permission center
    /// https://app.asana.com/1/137249556945/project/1148564399326804/task/1211985993948718?focus=true
    case newPermissionView

    /// Tab closing event recreation feature flag (failsafe for removing private API)
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212206087745586?focus=true
    case tabClosingEventRecreation

    /// Feature Flag for the Tab Spinner
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866479296718
    case tabProgressIndicator

    /// Feature Flag for the First Time Quit Survey
    /// https://app.asana.com/1/137249556945/inbox/1203972458584425/item/1212200919350194/story/1212483080081687
    case firstTimeQuitSurvey

    /// Web Notifications API polyfill - allows websites to show notifications via native macOS Notification Center
    /// https://app.asana.com/1/137249556945/project/414235014887631/task/1211395954816928?focus=true
    case webNotifications
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

    /// https://app.asana.com/1/137249556945/project/392891325557410/task/1210869716452614?focus=true
    case customization

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211660503405838?focus=true
    case forgetAllInSettings

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212397873940926?focus=true
    case ampBackgroundTaskSupport

    /// https://app.asana.com/1/137249556945/project/481882893211075/task/1212057154681076?focus=true
    case productTelemetrySurfaceUsage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212229431540900
    case granularFireButtonOptions

    /// https://app.asana.com/1/137249556945/project/1206226850447395/task/1211661206210892?focus=true
    case experimentalBrowsingMenu

    ///  https://app.asana.com/1/137249556945/project/414709148257752/task/1212395110448661?focus=true
    case appRatingPrompt
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
    case foregroundRunningWhenDashboardOpen
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

    /// Append the kbg disable parameter only when Duck AI features are not shown
    case duckAISearchParameter

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

    /// Allows to present Search Experience choice screen during onboarding
    case onboardingSearchExperience

    /// Enables the omnibar toggle for AI Chat
    case omnibarToggle

    /// Enables the omnibar cluster for AI Chat
    case omnibarCluster

    /// Controls showing the Hide AI section in Settings -> AI Features
    case showHideAiGeneratedImages

    /// Controls showing the AI Chat as Tabs Experiment Setting in Settings -> AI Features
    case fullDuckAIModeExperimentalSetting

    /// Controls different input sizes and fade out animation for toggle.
    case fadeOutOnToggle

    /// Signals that the iOS app should display duck.ai chats in "contextual mode" when opened from specific entry points
    case contextualDuckAIMode
}

public enum HtmlNewTabPageSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .htmlNewTabPage
    }

    /// Global switch to disable New Tab Page search box
    case omnibar

    /// Global switch to control shared or independent New Tab Page
    case newTabPagePerTab

    /// Global switch to control managing state of NTP in frontend using tab IDs
    case newTabPageTabIDs

    /// Global switch to display autoconsent stats on New Tab Page
    case autoconsentStats
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
    case syncCreditCards
    case syncIdentities
    case aiChatSync
}

public enum AutoconsentSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .autoconsent
    }

    case onByDefault
    case filterlist
}

public enum PrivacyProSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature { .privacyPro }

    case allowPurchase
    case allowPurchaseStripe
    case useUnifiedFeedback
    case privacyProOnboardingPromotion
    case paidAIChat
    case supportsAlternateStripePaymentFlow
    case vpnConnectionWidePixelMeasurement
    case winBackOffer
    case vpnMenuItem
    case blackFridayCampaign
    case tierMessagingEnabled
    case allowProTierPurchase
}

public enum SslCertificatesSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .sslCertificates }
    case allowBypass
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
    case sitesSection
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

public enum SetAsDefaultAndAddToDockSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .setAsDefaultAndAddToDock }

    // https://app.asana.com/1/137249556945/project/492600419927320/task/1210863200265479?focus=true
    case scheduledDefaultBrowserAndDockPromptsInactiveUser // macOS
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
    case dataImportWideEventMeasurement
    case newDataImportExperience
}

public enum SERPSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .serp
    }

    /// Global switch to disable New Tab Page search box
    case storeSerpSettings
}

public enum PopupBlockingSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .popupBlocking
    }

    /// Use extended user-initiated popup timeout (extends from 1s to 6s)
    case extendedUserInitiatedPopupTimeout

    /// Suppress empty or about: URL popups after permission approval
    case suppressEmptyPopUpsOnApproval

    /// Allow popups for current page after permission approval (until next navigation)
    case allowPopupsForCurrentPage

    /// Show popup permission button in inactive state when temporary allowance is active
    case popupPermissionButtonPersistence
}
