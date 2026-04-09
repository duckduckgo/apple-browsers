//
//  FeatureFlag.swift
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
import PrivacyConfig

public enum FeatureFlag: String, CaseIterable {
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715841970
    case maliciousSiteProtection

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866473245911
    case scamSiteProtection

    // https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614987519
    case freemiumDBP

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866470686549
    case contextualOnboarding

    /// Onboarding rebranding feature flag
    case onboardingRebranding

    // https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715698981
    case unknownUsernameCategorization

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614369626
    case credentialsImportPromotionForExistingUsers

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866473461472
    case networkProtectionAppStoreSysex

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866473771128
    case networkProtectionAppStoreSysexMessage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615719736
    case autoUpdateInDEBUG

    /// Controls automatic update downloads in REVIEW builds (off by default)
    case autoUpdateInREVIEW

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715515023
    case autofillPartialFormSaves

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866474376005
    case webExtensions

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213380159275576
    case embeddedExtension

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213725495563625
    case adBlockingExtension

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213538183403577
    case forceDarkModeOnWebsites

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866616130440
    case syncSeamlessAccountSwitching

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614764239
    case tabCrashDebugging

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717382544
    case delayedWebviewPresentation

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717886474
    case dbpRemoteBrokerDelivery

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866616923544
    case dbpEmailConfirmationDecoupling

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212397941080401
    case dbpClickActionDelayReductionOptimization

    /// https://app.asana.com/1/137249556945/project/1206873150423133/task/1213344522599586
    case dbpWebViewUserAgent

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717382557
    case syncSetupBarcodeIsUrlBased

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615684438
    case exchangeKeysToSyncWithAnotherDevice

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866613117546
    case canScanUrlBasedSyncSetupBarcodes

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866617269950
    case paidAIChat

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615582950
    case aiChatPageContext

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866617328244
    case aiChatKeepSession

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212016242789291
    case aiChatOmnibarToggle

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212227266479719
    case aiChatOmnibarCluster

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212745919983886?focus=true
    case aiChatSuggestions

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211654922002904
    case aiChatOmnibarTools

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212710873113687
    case aiChatOmnibarOnboarding

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866476152134
    case osSupportForceUnsupportedMessage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866476263589
    case osSupportForceWillSoonDropSupportMessage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719124742
    case willSoonDropBigSurSupport

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866475316806
    case hangReporting

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866476860577
    case newTabPageOmnibar

    /// Managing state of New Tab Page using tab IDs in frontend
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719908836
    case newTabPageTabIDs

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866618846917
    /// Note: 'Failsafe' feature flag. See https://app.asana.com/1/137249556945/project/1202500774821704/task/1210572145398078?focus=true
    case supportsAlternateStripePaymentFlow

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719485546
    case refactorOfSyncPreferences

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619299477
    case newSyncEntryPoints

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720018164
    case syncFeatureLevel3

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619633097
    case appStoreUpdateFlow

    /// Hide manual update option — always use automatic updates
    case automaticUpdatesOnly

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720696560
    case unifiedURLPredictor

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720972159
    case winBackOffer

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211969496845106?focus=true
    case blackFridayCampaign

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866477844148
    case syncCreditCards

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866620280912
    case syncIdentities

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866721266209
    case dataImportNewSafariFilePicker

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866620653515
    case storeSerpSettings

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866620524141
    case blurryAddressBarTahoeFix

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866477623612
    case dataImportNewExperience

    /// https://app.asana.com/1/137249556945/project/1205842942115003/task/1210884473312053
    case attributedMetrics

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866721557461
    case showHideAIGeneratedImagesSection

    /// https://app.asana.com/1/137249556945/project/1201141132935289/task/1210497696306780?focus=true
    case standaloneMigration

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211998614203544?focus=true
    case allowProTierPurchase

    /// New popup blocking heuristics based on user interaction timing (internal only)
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212017698257925?focus=true
    case popupBlocking

    /// Web Notifications API polyfill - allows websites to show notifications via native macOS Notification Center
    /// https://app.asana.com/1/137249556945/project/414235014887631/task/1211395954816928?focus=true
    case webNotifications

    /// New permission management view
    /// https://app.asana.com/1/137249556945/project/1148564399326804/task/1211985993948718?focus=true
    case newPermissionView

    /// Shows a survey when quitting the app for the first time in a determined period
    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1212242893241885?focus=true
    case firstTimeQuitSurvey

    /// Prioritize results where the domain matches the search query when searching passwords & autofill
    case autofillPasswordSearchPrioritizeDomain

    /// Controls visibility of the Passwords menu bar feature
    case autofillPasswordsStatusBar

    /// Warn before quit confirmation overlay
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212444166689969
    case warnBeforeQuit

    /// https://app.asana.com/1/137249556945/project/1201899738287924/task/1212437820560561?focus=true
    case memoryUsageMonitor

    /// Memory Usage Reporting
    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1212762049862432?focus=true
    case memoryUsageReporting

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212901927858518?focus=true
    case aiChatSync

    /// Autoconsent heuristic action experiment
    /// https://app.asana.com/1/137249556945/project/1201621853593513/task/1212068164128054?focus=true
    case heuristicAction

    /// Enables Next Steps List widget with a single card displayed at a time on New Tab page
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212634388261605?focus=true
    case nextStepsListWidget

    /// Enables advanced card ordering for the Next Steps List widget
    /// This flag is disabled by default to allow testing the new widget design with current ordering logic
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213076052926663?focus=true
    case nextStepsListAdvancedCardOrdering

    /// Whether the wide event POST endpoint is enabled
    /// https://app.asana.com/1/137249556945/project/1199333091098016/task/1212738953909168?focus=true
    case wideEventPostEndpoint

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213037858764817
    case crashCollectionLimitCallStackTreeDepth

    /// Failsafe flag for whether the free trial conversion wide event is enabled
    case freeTrialConversionWideEvent

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212901927858518?focus=true
    case supportsSyncChatsDeletion

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213433942918287?focus=true
    case aiChatMultiplePageContexts

    /// Enables the image generation mode toggle in the Duck.ai omnibar
    case aiChatOmnibarImageGeneration

    /// Enables the web search tool in the Duck.ai omnibar
    case aiChatOmnibarWebSearch

    /// Enables attaching content from multiple open tabs to Duck.ai chat
    case aiChatAttachMoreTabs

    /// https://app.asana.com/1/137249556945/task/1213316822018797
    case aiChatSidebarResizable

    /// https://app.asana.com/1/137249556945/project/1148564399326804/task/1213356927349370?focus=true
    case aiChatNtpRecentChats

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213622362394873
    case aiChatNtpChatTools

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213279513677422
    case aiChatSidebarFloating

    /// Private Process Name Flag
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213442286513425
    case privateProcessName

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213610208091978?focus=true
    case aiChatChromeSidebar

    /// Enable Look Up (three-finger click) while keeping link preview disabled
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213489080183740
    case webViewLookUpAction

    /// Autoplay policy control via WKWebpagePreferences
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213734484627619
    case autoplayPolicy

    /// Window Semaphore Fullscreen Behavior Flag
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213585076410725?focus=true
    case semaphoreAlwaysVisible

    /// Enables the promo service to coordinate promos/calls to action
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213431687119179?focus=true
    case promoQueue

    /// Enables showing browsing history domains in the first-time quit survey
    case websitesHistoryFirstTimeQuitSurvey

    /// Enables the new Tab Animations (Milestone 1)
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213643457004332
    case tabAnimations

    /// Defers menu population to NSMenuDelegate.menuNeedsUpdate(_:) to avoid expensive eager rebuilds
    case lazyMenuRebuild

    /// Enables the "Add to dock" onboarding step and setting for App Store builds
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213725466401987?focus=true
    case addToDockAppStore

    /// Enables removing individual AI chat suggestions from the omnibar
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213761882751264?focus=true
    case aiChatRemoveSuggestion

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213813585476250?focus=true
    case screenTimeCleaning

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213876665476278?focus=true
    case tabSuspension

    /// Gates the Suspend Tab / Resume Tab context menu actions for debugging purposes
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213883766662888?focus=true
    case tabSuspensionDebugging

    /// Enables the Duck.ai top-level main menu shortcut (macOS only, disabled by default)
    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1213833143996470
    case aiChatMainMenuShortcut

    /// Enables the Duck.ai submenu in the more options (hamburger) menu (macOS only, disabled by default)
    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1213833143996470
    case aiChatMoreOptionsMenuShortcut

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213973058005627?focus=true
    case aiChatSidebarAboutSchemeNavigationFix

    case aiChatNativeStorage
}

extension FeatureFlag: FeatureFlagDescribing {

    /// Cohorts for the autoconsent heuristic action experiment
    public enum HeuristicActionCohort: String, FeatureFlagCohortDescribing {
        case control
        case treatment
    }

    private struct Config {
        let defaultValue: FeatureFlagDefaultValue
        let source: FeatureFlagSource
        let supportsLocalOverriding: Bool
        let cohortType: (any FeatureFlagCohortDescribing.Type)?
        let category: FeatureFlagCategory

        init(
            defaultValue: FeatureFlagDefaultValue = .disabled,
            source: FeatureFlagSource,
            supportsLocalOverriding: Bool = true,
            cohortType: (any FeatureFlagCohortDescribing.Type)? = nil,
            category: FeatureFlagCategory = .other
        ) {
            self.defaultValue = defaultValue
            self.source = source
            self.supportsLocalOverriding = supportsLocalOverriding
            self.cohortType = cohortType
            self.category = category
        }
    }

    private var config: Config {
        switch self {
        case .maliciousSiteProtection:
            Config(source: .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.onByDefault)))
        case .scamSiteProtection:
            Config(source: .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.scamProtection)))
        case .freemiumDBP:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.freemium)), supportsLocalOverriding: false)
        case .contextualOnboarding:
            Config(source: .remoteReleasable(.feature(.contextualOnboarding)), supportsLocalOverriding: false)
        case .onboardingRebranding:
            Config(source: .disabled)
        case .unknownUsernameCategorization:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.unknownUsernameCategorization)), supportsLocalOverriding: false)
        case .credentialsImportPromotionForExistingUsers:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.credentialsImportPromotionForExistingUsers)), supportsLocalOverriding: false)
        case .networkProtectionAppStoreSysex:
            Config(source: .remoteReleasable(.subfeature(NetworkProtectionSubfeature.appStoreSystemExtension)), category: .vpn)
        case .networkProtectionAppStoreSysexMessage:
            Config(source: .remoteReleasable(.subfeature(NetworkProtectionSubfeature.appStoreSystemExtensionMessage)), category: .vpn)
        case .autoUpdateInDEBUG:
            Config(source: .disabled, category: .updates)
        case .autoUpdateInREVIEW:
            Config(source: .disabled, category: .updates)
        case .autofillPartialFormSaves:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.partialFormSaves)))
        case .webExtensions:
            Config(source: .remoteReleasable(.feature(.webExtensions)), category: .webExtensions)
        case .embeddedExtension:
            Config(source: .remoteReleasable(.subfeature(WebExtensionsSubfeature.embeddedExtension)), category: .webExtensions)
        case .adBlockingExtension:
            Config(source: .remoteReleasable(.feature(.adBlockingExtension)), category: .webExtensions)
        case .forceDarkModeOnWebsites:
            Config(source: .remoteReleasable(.subfeature(ForceDarkModeOnWebsitesSubfeature.featureRollout)), category: .webExtensions)
        case .syncSeamlessAccountSwitching:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.seamlessAccountSwitching)), category: .sync)
        case .tabCrashDebugging:
            Config(source: .disabled)
        case .delayedWebviewPresentation:
            Config(source: .remoteReleasable(.feature(.delayedWebviewPresentation)))
        case .dbpRemoteBrokerDelivery:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.remoteBrokerDelivery)), category: .dbp)
        case .dbpEmailConfirmationDecoupling:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.emailConfirmationDecoupling)), category: .dbp)
        case .dbpClickActionDelayReductionOptimization:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.clickActionDelayReductionOptimization)), category: .dbp)
        case .dbpWebViewUserAgent:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.webViewUserAgent)), category: .dbp)
        case .syncSetupBarcodeIsUrlBased:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.syncSetupBarcodeIsUrlBased)), category: .sync)
        case .exchangeKeysToSyncWithAnotherDevice:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.exchangeKeysToSyncWithAnotherDevice)), category: .sync)
        case .canScanUrlBasedSyncSetupBarcodes:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.canScanUrlBasedSyncSetupBarcodes)), category: .sync)
        case .paidAIChat:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.paidAIChat)), category: .subscription)
        case .aiChatPageContext:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.pageContext)), category: .duckAI)
        case .aiChatKeepSession:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.keepSession)), category: .duckAI)
        case .aiChatOmnibarToggle:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarToggle)), category: .duckAI)
        case .aiChatOmnibarCluster:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarCluster)), category: .duckAI)
        case .aiChatSuggestions:
            Config(source: .remoteReleasable(.feature(.duckAiChatHistory)), category: .duckAI)
        case .aiChatOmnibarTools:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarTools)), category: .duckAI)
        case .aiChatOmnibarOnboarding:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarOnboarding)), category: .duckAI)
        case .osSupportForceUnsupportedMessage:
            Config(source: .disabled, category: .osSupportWarnings)
        case .osSupportForceWillSoonDropSupportMessage:
            Config(source: .disabled, category: .osSupportWarnings)
        case .willSoonDropBigSurSupport:
            Config(source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.willSoonDropBigSurSupport)), category: .osSupportWarnings)
        case .hangReporting:
            Config(source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.hangReporting)))
        case .newTabPageOmnibar:
            Config(source: .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.omnibar)))
        case .newTabPageTabIDs:
            Config(source: .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.newTabPageTabIDs)))
        case .supportsAlternateStripePaymentFlow:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(PrivacyProSubfeature.supportsAlternateStripePaymentFlow)), category: .subscription)
        case .refactorOfSyncPreferences:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(SyncSubfeature.refactorOfSyncPreferences)))
        case .newSyncEntryPoints:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.newSyncEntryPoints)))
        case .syncFeatureLevel3:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.level3AllowCreateAccount)))
        case .appStoreUpdateFlow:
            Config(source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.appStoreUpdateFlow)), category: .updates)
        case .automaticUpdatesOnly:
            Config(source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.automaticUpdatesOnly)), category: .updates)
        case .unifiedURLPredictor:
            Config(source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.unifiedURLPredictor)))
        case .winBackOffer:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.winBackOffer)), category: .vpn)
        case .blackFridayCampaign:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.blackFridayCampaign)), category: .subscription)
        case .syncCreditCards:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(SyncSubfeature.syncCreditCards)))
        case .syncIdentities:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(SyncSubfeature.syncIdentities)))
        case .dataImportNewSafariFilePicker:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(DataImportSubfeature.newSafariFilePicker)))
        case .storeSerpSettings:
            Config(source: .remoteReleasable(.subfeature(SERPSubfeature.storeSerpSettings)))
        case .blurryAddressBarTahoeFix:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.blurryAddressBarTahoeFix)))
        case .dataImportNewExperience:
            Config(source: .remoteReleasable(.subfeature(DataImportSubfeature.newDataImportExperience)))
        case .attributedMetrics:
            Config(source: .remoteReleasable(.feature(.attributedMetrics)))
        case .showHideAIGeneratedImagesSection:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.showHideAiGeneratedImages)))
        case .standaloneMigration:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.standaloneMigration)), category: .duckAI)
        case .allowProTierPurchase:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.allowProTierPurchase)), category: .subscription)
        case .popupBlocking:
            Config(source: .remoteReleasable(.feature(.popupBlocking)), category: .popupBlocking)
        case .webNotifications:
            Config(source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.webNotifications)), category: .webNotifications)
        case .newPermissionView:
            Config(source: .remoteReleasable(.feature(.combinedPermissionView)))
        case .firstTimeQuitSurvey:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.firstTimeQuitSurvey)))
        case .autofillPasswordSearchPrioritizeDomain:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AutofillSubfeature.autofillPasswordSearchPrioritizeDomain)))
        case .autofillPasswordsStatusBar:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(.subfeature(AutofillSubfeature.autofillPasswordsStatusBar)))
        case .warnBeforeQuit:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.warnBeforeQuit)))
        case .memoryUsageMonitor:
            Config(source: .disabled)
        case .memoryUsageReporting:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.memoryUsageReporting)))
        case .aiChatSync:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.aiChatSync)))
        case .heuristicAction:
            Config(source: .remoteReleasable(.subfeature(AutoconsentSubfeature.heuristicAction)), cohortType: HeuristicActionCohort.self)
        case .nextStepsListWidget:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.nextStepsListWidget)))
        case .nextStepsListAdvancedCardOrdering:
            Config(source: .disabled)
        case .wideEventPostEndpoint:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.wideEventPostEndpoint)))
        case .crashCollectionLimitCallStackTreeDepth:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.crashCollectionLimitCallStackTreeDepth)), supportsLocalOverriding: false)
        case .freeTrialConversionWideEvent:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.freeTrialConversionWideEvent)))
        case .supportsSyncChatsDeletion:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.supportsSyncChatsDeletion)))
        case .aiChatMultiplePageContexts:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.multiplePageContexts)), category: .duckAI)
        case .aiChatOmnibarImageGeneration:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarImageGeneration)), category: .duckAI)
        case .aiChatOmnibarWebSearch:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarWebSearch)), category: .duckAI)
        case .aiChatAttachMoreTabs:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.attachMoreTabs)), category: .duckAI)
        case .aiChatSidebarResizable:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.sidebarResizable)), category: .duckAI)
        case .aiChatNtpRecentChats:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.ntpRecentChats)), category: .duckAI)
        case .aiChatNtpChatTools:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.ntpChatTools)), category: .duckAI)
        case .aiChatSidebarFloating:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(.subfeature(AIChatSubfeature.sidebarFloating)), category: .duckAI)
        case .privateProcessName:
            Config(source: .disabled)
        case .aiChatChromeSidebar:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.sidebar)), category: .duckAI)
        case .webViewLookUpAction:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.webViewLookUpAction)))
        case .semaphoreAlwaysVisible:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.semaphoreAlwaysVisible)))
        case .promoQueue:
            Config(defaultValue: .enabled, source: .remoteReleasable(.feature(.promoQueue)))
        case .websitesHistoryFirstTimeQuitSurvey:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.websitesHistoryFirstTimeQuitSurvey)))
        case .tabAnimations:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.tabAnimations)))
        case .lazyMenuRebuild:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.lazyMenuRebuild)))
        case .addToDockAppStore:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.addToDockAppStore)))
        case .aiChatRemoveSuggestion:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(.subfeature(AIChatSubfeature.removeSuggestion)), category: .duckAI)
        case .screenTimeCleaning:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.screenTimeCleaning)))
        case .tabSuspension:
            Config(source: .disabled)
        case .tabSuspensionDebugging:
            Config(source: .disabled)
        case .aiChatMoreOptionsMenuShortcut:
            Config(defaultValue: .disabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.moreOptionsMenuShortcut)), category: .duckAI)
        case .aiChatMainMenuShortcut:
            Config(defaultValue: .disabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.mainMenuShortcut)), category: .duckAI)
        case .aiChatSidebarAboutSchemeNavigationFix:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.sidebarAboutSchemeNavigationFix)), category: .duckAI)
        case .aiChatNativeStorage:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.nativeStorage)), category: .duckAI)
        case .autoplayPolicy:
            Config(defaultValue: .disabled, source: .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.autoplayPolicy)), supportsLocalOverriding: true)
        }
    }

    public var defaultValue: FeatureFlagDefaultValue { config.defaultValue }
    public var source: FeatureFlagSource { config.source }
    public var supportsLocalOverriding: Bool { config.supportsLocalOverriding }
    public var cohortType: (any FeatureFlagCohortDescribing.Type)? { config.cohortType }
}

extension FeatureFlag: FeatureFlagCategorization {
    public var category: FeatureFlagCategory { config.category }
}

public extension FeatureFlagger {

    func isFeatureOn(_ featureFlag: FeatureFlag) -> Bool {
        isFeatureOn(for: featureFlag)
    }
}
