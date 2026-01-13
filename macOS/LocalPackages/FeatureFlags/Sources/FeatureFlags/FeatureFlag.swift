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

    /// Add experimental atb parameter to SERP queries for internal users to display Privacy Reminder
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866472784764
    case appendAtbToSerpQueries

    // https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614987519
    case freemiumDBP

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866470686549
    case contextualOnboarding

    // https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715698981
    case unknownUsernameCategorization

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614369626
    case credentialsImportPromotionForExistingUsers

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866473461472
    case networkProtectionAppStoreSysex

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866473771128
    case networkProtectionAppStoreSysexMessage

    /// Subfeature: display the Sites section inside History View
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866716610324
    case historyViewSitesSection

    /// Enable WebKit page load timing performance reporting
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615625098
    case webKitPerformanceReporting

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615719736
    case autoUpdateInDEBUG

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615802881
    case updatesWontAutomaticallyRestartApp

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715515023
    case autofillPartialFormSaves

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866714296474
    case autocompleteTabs

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866474376005
    case webExtensions

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

    /// Loading New Tab Page in regular browsing webview
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719013868
    case newTabPagePerTab

    /// Managing state of New Tab Page using tab IDs in frontend
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719908836
    case newTabPageTabIDs

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866618846917
    /// Note: 'Failsafe' feature flag. See https://app.asana.com/1/137249556945/project/1202500774821704/task/1210572145398078?focus=true
    case supportsAlternateStripePaymentFlow

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866473926615
    case duckAISearchParameter

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719485546
    case refactorOfSyncPreferences

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619299477
    case newSyncEntryPoints

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720018164
    case syncFeatureLevel3

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720557742
    case themes

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619633097
    case appStoreUpdateFlow

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720696560
    case unifiedURLPredictor

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720972159
    case winBackOffer

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211969496845106?focus=true
    case blackFridayCampaign

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866477541910
    case fireDialog

    /// Toggle for showing the "Manage individual sites" link in Fire dialog
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715393773
    case fireDialogIndividualSitesLink

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866477844148
    case syncCreditCards

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866620280912
    case syncIdentities

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866478543578
    case aiChatDataClearing

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866721266209
    case dataImportNewSafariFilePicker

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866620653515
    case storeSerpSettings

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866620524141
    case blurryAddressBarTahoeFix

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866477623612
    case dataImportNewExperience

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866721275379
    case scheduledDefaultBrowserAndDockPromptsInactiveUser

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866479296718
    case tabProgressIndicator

    /// https://app.asana.com/1/137249556945/project/1205842942115003/task/1210884473312053
    case attributedMetrics

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866721557461
    case showHideAIGeneratedImagesSection

    /// https://app.asana.com/1/137249556945/project/1201141132935289/task/1210497696306780?focus=true
    case standaloneMigration

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212014826835069?focus=true
    case newTabPageAutoconsentStats

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211998610726861?focus=true
    case tierMessagingEnabled

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211998614203544?focus=true
    case allowProTierPurchase

    /// New popup blocking heuristics based on user interaction timing (internal only)
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212017698257925?focus=true
    case popupBlocking

    /// Use extended user-initiated popup timeout (extends from 1s to 6s)
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212001891093823?focus=true
    case extendedUserInitiatedPopupTimeout

    /// Suppress empty or about: URL popups after permission approval
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212017701300907?focus=true
    case suppressEmptyPopUpsOnApproval

    /// Allow all popups for current page after permission approval (until next navigation)
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212017701300913?focus=true
    case allowPopupsForCurrentPage

    /// Show popup permission button in inactive state when temporary allowance is active
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212017701300919?focus=true
    case popupPermissionButtonPersistence

    /// Web Notifications API polyfill - allows websites to show notifications via native macOS Notification Center
    /// https://app.asana.com/1/137249556945/project/414235014887631/task/1211395954816928?focus=true
    case webNotifications

    /// New permission management view
    /// https://app.asana.com/1/137249556945/project/1148564399326804/task/1211985993948718?focus=true
    case newPermissionView

    /// Tab closing event recreation (failsafe for removing private API)
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212206087745586?focus=true
    case tabClosingEventRecreation

    /// Shows a survey when quitting the app for the first time in a determined period
    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1212242893241885?focus=true
    case firstTimeQuitSurvey

    /// Modular termination decider pattern for app quit flow
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212684817782056?focus=true
    case terminationDeciderSequence

    /// Prioritize results where the domain matches the search query when searching passwords & autofill
    case autofillPasswordSearchPrioritizeDomain

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212357739558636?focus=true
    case dataImportWideEventMeasurement

    /// https://app.asana.com/1/137249556945/project/1201899738287924/task/1212437820560561?focus=true
    case memoryUsageMonitor

    /// https://app.asana.com/1/137249556945/project/1201462886803403/task/1211837879355661?focus=true
    case aiChatSync

    /// Autoconsent heuristic action experiment
    /// https://app.asana.com/1/137249556945/project/1201621853593513/task/1212068164128054?focus=true
    case heuristicAction

    /// Next Steps cards iteration with single card displayed on New Tab page
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212634388261605?focus=true
    case nextStepsSingleCardIteration
}

extension FeatureFlag: FeatureFlagDescribing {

    /// Cohorts for the autoconsent heuristic action experiment
    public enum HeuristicActionCohort: String, FeatureFlagCohortDescribing {
        case control
        case treatment
    }

    public var defaultValue: Bool {
        switch self {
        case .supportsAlternateStripePaymentFlow,
                .refactorOfSyncPreferences,
                .duckAISearchParameter,
                .syncCreditCards,
                .syncIdentities,
                .dataImportNewSafariFilePicker,
                .fireDialog,
                .fireDialogIndividualSitesLink,
                .historyViewSitesSection,
                .blurryAddressBarTahoeFix,
                .allowPopupsForCurrentPage,
                .extendedUserInitiatedPopupTimeout,
                .suppressEmptyPopUpsOnApproval,
                .popupPermissionButtonPersistence,
                .tabClosingEventRecreation,
                .dataImportWideEventMeasurement,
                .tabProgressIndicator,
                .firstTimeQuitSurvey,
                .terminationDeciderSequence,
                .autofillPasswordSearchPrioritizeDomain,
                .themes:
            true
        default:
            false
        }
    }

    public var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
        case .heuristicAction:
            return HeuristicActionCohort.self
        default:
            return nil
        }
    }

    public var supportsLocalOverriding: Bool {
        switch self {
        case .autofillPartialFormSaves,
                .autocompleteTabs,
                .networkProtectionAppStoreSysex,
                .networkProtectionAppStoreSysexMessage,
                .syncSeamlessAccountSwitching,
                .historyViewSitesSection,
                .webExtensions,
                .autoUpdateInDEBUG,
                .updatesWontAutomaticallyRestartApp,
                .scamSiteProtection,
                .tabCrashDebugging,
                .maliciousSiteProtection,
                .delayedWebviewPresentation,
                .syncSetupBarcodeIsUrlBased,
                .paidAIChat,
                .exchangeKeysToSyncWithAnotherDevice,
                .canScanUrlBasedSyncSetupBarcodes,
                .osSupportForceUnsupportedMessage,
                .osSupportForceWillSoonDropSupportMessage,
                .willSoonDropBigSurSupport,
                .hangReporting,
                .aiChatPageContext,
                .aiChatKeepSession,
                .aiChatOmnibarToggle,
                .aiChatOmnibarCluster,
                .newTabPageOmnibar,
                .newTabPagePerTab,
                .newTabPageTabIDs,
                .supportsAlternateStripePaymentFlow,
                .duckAISearchParameter,
                .refactorOfSyncPreferences,
                .newSyncEntryPoints,
                .dbpEmailConfirmationDecoupling,
                .dbpRemoteBrokerDelivery,
                .dbpClickActionDelayReductionOptimization,
                .syncFeatureLevel3,
                .themes,
                .appStoreUpdateFlow,
                .unifiedURLPredictor,
                .webKitPerformanceReporting,
                .fireDialog,
                .winBackOffer,
                .syncCreditCards,
                .syncIdentities,
                .aiChatDataClearing,
                .dataImportNewSafariFilePicker,
                .storeSerpSettings,
                .blurryAddressBarTahoeFix,
                .dataImportNewExperience,
                .tabProgressIndicator,
                .attributedMetrics,
                .showHideAIGeneratedImagesSection,
                .standaloneMigration,
                .blackFridayCampaign,
                .newTabPageAutoconsentStats,
                .tierMessagingEnabled,
                .allowProTierPurchase,
                .popupBlocking,
                .extendedUserInitiatedPopupTimeout,
                .suppressEmptyPopUpsOnApproval,
                .allowPopupsForCurrentPage,
                .popupPermissionButtonPersistence,
                .webNotifications,
                .newPermissionView,
                .firstTimeQuitSurvey,
                .autofillPasswordSearchPrioritizeDomain,
                .dataImportWideEventMeasurement,
                .memoryUsageMonitor,
                .aiChatSync,
                .heuristicAction,
                .nextStepsSingleCardIteration:
            return true
        case .appendAtbToSerpQueries,
                .freemiumDBP,
                .contextualOnboarding,
                .unknownUsernameCategorization,
                .credentialsImportPromotionForExistingUsers,
                .fireDialogIndividualSitesLink,
                .scheduledDefaultBrowserAndDockPromptsInactiveUser,
                .tabClosingEventRecreation,
                .terminationDeciderSequence:
            return false
        }
    }

    public var source: FeatureFlagSource {
        switch self {
        case .appendAtbToSerpQueries:
            return .internalOnly()
        case .unknownUsernameCategorization:
            return .remoteReleasable(.subfeature(AutofillSubfeature.unknownUsernameCategorization))
        case .freemiumDBP:
            return .remoteReleasable(.subfeature(DBPSubfeature.freemium))
        case .maliciousSiteProtection:
            return .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.onByDefault))
        case .contextualOnboarding:
            return .remoteReleasable(.feature(.contextualOnboarding))
        case .credentialsImportPromotionForExistingUsers:
            return .remoteReleasable(.subfeature(AutofillSubfeature.credentialsImportPromotionForExistingUsers))
        case .networkProtectionAppStoreSysex:
            return .remoteReleasable(.subfeature(NetworkProtectionSubfeature.appStoreSystemExtension))
        case .networkProtectionAppStoreSysexMessage:
            return .remoteReleasable(.subfeature(NetworkProtectionSubfeature.appStoreSystemExtensionMessage))
        case .historyViewSitesSection:
            return .remoteReleasable(.subfeature(HTMLHistoryPageSubfeature.sitesSection))
        case .autoUpdateInDEBUG:
            return .disabled
        case .updatesWontAutomaticallyRestartApp:
            return .remoteReleasable(.feature(.updatesWontAutomaticallyRestartApp))
        case .autofillPartialFormSaves:
            return .remoteReleasable(.subfeature(AutofillSubfeature.partialFormSaves))
        case .autocompleteTabs:
            return .remoteReleasable(.feature(.autocompleteTabs))
        case .webExtensions:
            return .internalOnly()
        case .syncSeamlessAccountSwitching:
            return .remoteReleasable(.subfeature(SyncSubfeature.seamlessAccountSwitching))
        case .syncCreditCards:
            return .remoteReleasable(.subfeature(SyncSubfeature.syncCreditCards))
        case .syncIdentities:
            return .remoteReleasable(.subfeature(SyncSubfeature.syncIdentities))
        case .scamSiteProtection:
            return .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.scamProtection))
        case .tabCrashDebugging:
            return .disabled
        case .delayedWebviewPresentation:
            return .remoteReleasable(.feature(.delayedWebviewPresentation))
        case .dbpRemoteBrokerDelivery:
            return .remoteReleasable(.subfeature(DBPSubfeature.remoteBrokerDelivery))
        case .dbpEmailConfirmationDecoupling:
            return .remoteReleasable(.subfeature(DBPSubfeature.emailConfirmationDecoupling))
        case .dbpClickActionDelayReductionOptimization:
            return .remoteReleasable(.subfeature(DBPSubfeature.clickActionDelayReductionOptimization))
        case .syncSetupBarcodeIsUrlBased:
            return .remoteReleasable(.subfeature(SyncSubfeature.syncSetupBarcodeIsUrlBased))
        case .exchangeKeysToSyncWithAnotherDevice:
            return .remoteReleasable(.subfeature(SyncSubfeature.exchangeKeysToSyncWithAnotherDevice))
        case .canScanUrlBasedSyncSetupBarcodes:
            return .remoteReleasable(.subfeature(SyncSubfeature.canScanUrlBasedSyncSetupBarcodes))
        case .paidAIChat:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.paidAIChat))
        case .aiChatPageContext:
            return .remoteReleasable(.subfeature(AIChatSubfeature.pageContext))
        case .aiChatKeepSession:
            return .remoteReleasable(.subfeature(AIChatSubfeature.keepSession))
        case .aiChatOmnibarToggle:
            return .remoteReleasable(.subfeature(AIChatSubfeature.omnibarToggle))
        case .aiChatOmnibarCluster:
            return .remoteReleasable(.subfeature(AIChatSubfeature.omnibarCluster))
        case .osSupportForceUnsupportedMessage:
            return .disabled
        case .osSupportForceWillSoonDropSupportMessage:
            return .disabled
        case .willSoonDropBigSurSupport:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.willSoonDropBigSurSupport))
        case .hangReporting:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.hangReporting))
        case .newTabPageOmnibar:
            return .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.omnibar))
        case .newTabPagePerTab:
            return .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.newTabPagePerTab))
        case .newTabPageTabIDs:
            return .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.newTabPageTabIDs))
        case .supportsAlternateStripePaymentFlow:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.supportsAlternateStripePaymentFlow))
        case .duckAISearchParameter:
            return .remoteReleasable(.subfeature(AIChatSubfeature.duckAISearchParameter))
        case .fireDialog:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.fireDialog))
        case .fireDialogIndividualSitesLink:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.fireDialogIndividualSitesLink))
        case .refactorOfSyncPreferences:
            return .remoteReleasable(.subfeature(SyncSubfeature.refactorOfSyncPreferences))
        case .newSyncEntryPoints:
            return .remoteReleasable(.subfeature(SyncSubfeature.newSyncEntryPoints))
        case .syncFeatureLevel3:
            return .remoteReleasable(.subfeature(SyncSubfeature.level3AllowCreateAccount))
        case .themes:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.themes))
        case .appStoreUpdateFlow:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.appStoreUpdateFlow))
        case .unifiedURLPredictor:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.unifiedURLPredictor))
        case .webKitPerformanceReporting:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.webKitPerformanceReporting))
        case .winBackOffer:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.winBackOffer))
        case .blackFridayCampaign:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.blackFridayCampaign))
        case .dataImportNewSafariFilePicker:
            return .remoteReleasable(.subfeature(DataImportSubfeature.newSafariFilePicker))
        case .aiChatDataClearing:
            return .remoteReleasable(.feature(.duckAiDataClearing))
        case .storeSerpSettings:
            return .remoteReleasable(.subfeature(SERPSubfeature.storeSerpSettings))
        case .blurryAddressBarTahoeFix:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.blurryAddressBarTahoeFix))
        case .dataImportNewExperience:
            return .remoteReleasable(.subfeature(DataImportSubfeature.newDataImportExperience))
        case .scheduledDefaultBrowserAndDockPromptsInactiveUser:
            return .remoteReleasable(.subfeature(SetAsDefaultAndAddToDockSubfeature.scheduledDefaultBrowserAndDockPromptsInactiveUser))
        case .tabProgressIndicator:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.tabProgressIndicator))
        case .attributedMetrics:
            return .remoteReleasable(.feature(.attributedMetrics))
        case .showHideAIGeneratedImagesSection:
            return .remoteReleasable(.subfeature(AIChatSubfeature.showHideAiGeneratedImages))
        case .standaloneMigration:
            return .remoteReleasable(.subfeature(AIChatSubfeature.standaloneMigration))
        case .newTabPageAutoconsentStats:
            return .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.autoconsentStats))
        case .tierMessagingEnabled:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.tierMessagingEnabled))
        case .allowProTierPurchase:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.allowProTierPurchase))
        case .popupBlocking:
            return .remoteReleasable(.feature(.popupBlocking))
        case .extendedUserInitiatedPopupTimeout:
            return .remoteReleasable(.subfeature(PopupBlockingSubfeature.extendedUserInitiatedPopupTimeout))
        case .suppressEmptyPopUpsOnApproval:
            return .remoteReleasable(.subfeature(PopupBlockingSubfeature.suppressEmptyPopUpsOnApproval))
        case .allowPopupsForCurrentPage:
            return .remoteReleasable(.subfeature(PopupBlockingSubfeature.allowPopupsForCurrentPage))
        case .popupPermissionButtonPersistence:
            return .remoteReleasable(.subfeature(PopupBlockingSubfeature.popupPermissionButtonPersistence))
        case .webNotifications:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.webNotifications))
        case .newPermissionView:
            return .remoteReleasable(.feature(.combinedPermissionView))
        case .tabClosingEventRecreation:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.tabClosingEventRecreation))
        case .firstTimeQuitSurvey:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.firstTimeQuitSurvey))
        case .terminationDeciderSequence:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.terminationDeciderSequence))
        case .autofillPasswordSearchPrioritizeDomain:
            return .remoteReleasable(.subfeature(AutofillSubfeature.autofillPasswordSearchPrioritizeDomain))
        case .dataImportWideEventMeasurement:
            return .remoteReleasable(.subfeature(DataImportSubfeature.dataImportWideEventMeasurement))
        case .memoryUsageMonitor:
            return .disabled
        case .aiChatSync:
            return .disabled
        case .heuristicAction:
            return .remoteReleasable(.subfeature(AutoconsentSubfeature.heuristicAction))
        case .nextStepsSingleCardIteration:
            return .disabled
        }
    }
}

public extension FeatureFlagger {

    func isFeatureOn(_ featureFlag: FeatureFlag) -> Bool {
        isFeatureOn(for: featureFlag)
    }
}
