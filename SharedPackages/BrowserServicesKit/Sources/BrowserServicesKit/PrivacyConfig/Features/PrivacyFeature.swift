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
    case shortHistoryMenu
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
    case tabCrashRecovery
    case delayedWebviewPresentation
    case disableFireAnimation
    case feedbackForm
    case htmlNewTabPage
    case daxEasterEggLogos
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

    // Import Chrome's new tab shortcuts when bookmarks are imported
    case importChromeShortcuts

    // Import Safari's bookmarks and favorites to better match Safari's behavior
    case updateSafariBookmarksImport

    // Import Firefox's bookmarks and new tab shortcuts to better match Firefox's behavior
    case updateFirefoxBookmarksImport
}

public enum iOSBrowserConfigSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .iOSBrowserConfig
    }

    // Demonstrative case for default value. Remove once a real-world feature is added
    case intentionallyLocalOnlySubfeatureForTests

    // Shows a PiP video when the user is redirect to the system settings to set DDG as the default browser.
    // https://app.asana.com/1/137249556945/project/1206329551987282/task/1210806442029191?focus=true
    case defaultBrowserTutorial

    case widgetReporting

    /// Add ask AI chat to end of autocomplete suggestions
    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210839825079760?focus=true
    case askAIChatSuggestion

    // Local inactivity provisional notifications delivered to Notification Center.
    // https://app.asana.com/1/137249556945/project/72649045549333/task/1211003501974970?focus=true
    case inactivityNotification
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

    /// Adds context menu action for summarizing text selected on a website.
    case textSummarization

    /// Adds capability to load AI Chat in a sidebar
    case sidebar

    /// Experimental address bar with duck.ai
    case experimentalAddressBar

    /// Global switch to disable all AI Chat related functionality
    case globalToggle
}

public enum HtmlNewTabPageSubfeature: String, Equatable, PrivacySubfeature {
    public var parent: PrivacyFeature {
        .htmlNewTabPage
    }

    /// Global switch to disable New Tab Page search box
    case omnibar

    /// Global switch to control shared or independent New Tab Page
    case newTabPagePerTab
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
    case privacyProFreeTrialJan25
    case privacyProAuthV2
    case privacyProOnboardingPromotion
    case privacyProFreeTrial
    case paidAIChat
    case subscriptionRebranding
    case vpnToolbarUpsell
    case supportsAlternateStripePaymentFlow
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
    case removeWWWInCanonicalization
}

public enum SetAsDefaultAndAddToDockSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .setAsDefaultAndAddToDock }

    // https://app.asana.com/1/137249556945/project/1206329551987282/task/1210225579353384?focus=true
    case scheduledDefaultBrowserAndDockPrompts // macOS

    // https://app.asana.com/1/137249556945/project/1206329551987282/task/1209304767941984?focus=true
    case scheduledDefaultBrowserPrompts // iOS

    // https://app.asana.com/1/137249556945/project/1206329551987282/task/1210716028790591?focus=true
    case scheduledDefaultBrowserPromptsInactiveUser // iOS
}

public enum OnboardingSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .extendedOnboarding }

    case showSettingsCompleteSetupSection
}

public enum ExperimentalThemingSubfeature: String, PrivacySubfeature {
    public var parent: PrivacyFeature { .experimentalTheming }

    case visualUpdates // Rollout
}
