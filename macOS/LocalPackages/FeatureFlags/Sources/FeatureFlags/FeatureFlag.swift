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
import BrowserServicesKit

public enum FeatureFlag: String, CaseIterable {
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866473003324
    case debugMenu

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715760000
    case sslCertificatesBypass

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

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866612800704
    case historyView

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

    /// SAD & ATT Prompts: https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866474521433
    case scheduledSetDefaultBrowserAndAddToDockPrompts

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866474590440
    case privacyProAuthV2

    // Demonstrative cases for default value. Remove once a real-world feature/subfeature is added
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866472271359
    case failsafeExampleCrossPlatformFeature

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717037699
    case failsafeExamplePlatformSpecificSubfeature

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717504694
    case visualUpdates

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866616568109
    case visualUpdatesInternalOnly

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614764239
    case tabCrashDebugging

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717382544
    case delayedWebviewPresentation

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717886474
    case dbpRemoteBrokerDelivery

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866616923544
    case dbpEmailConfirmationDecoupling

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717382557
    case syncSetupBarcodeIsUrlBased

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615684438
    case exchangeKeysToSyncWithAnotherDevice

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866613117546
    case canScanUrlBasedSyncSetupBarcodes

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866610505232
    case privacyProFreeTrial

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866617269950
    case paidAIChat

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866617356615
    case removeWWWInCanonicalizationInThreatProtection

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717945014
    case aiChatSidebar

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866475785434
    case aiChatTextSummarization

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866718657077
    case aiChatTextTranslation

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615582950
    case aiChatPageContext

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866617720317
    case aiChatImprovements

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866617328244
    case aiChatKeepSession

    /// Enables the omnibar toggle for AI Chat
    /// https://app.asana.com/1/137249556945/project/1211654189969294/task/1211652685709106
    case aiChatOmnibarToggle

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866476152134
    case osSupportForceUnsupportedMessage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866476263589
    case osSupportForceWillSoonDropSupportMessage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719124742
    case willSoonDropBigSurSupport

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866475316806
    case hangReporting

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866476547580
    case importChromeShortcuts

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866618404342
    case updateSafariBookmarksImport

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715760013
    case updateFirefoxBookmarksImport

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866618564878
    case disableFireAnimation

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866476860577
    case newTabPageOmnibar

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719732725
    case vpnToolbarUpsell

    /// Loading New Tab Page in regular browsing webview
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719013868
    case newTabPagePerTab

    /// Managing state of New Tab Page using tab IDs in frontend
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719908836
    case newTabPageTabIDs

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866618846917
    /// Note: 'Failsafe' feature flag. See https://app.asana.com/1/137249556945/project/1202500774821704/task/1210572145398078?focus=true
    case supportsAlternateStripePaymentFlow

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720037380
    case openFireWindowByDefault

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619027311
    case restoreSessionPrompt

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866473926615
    case duckAISearchParameter

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866719485546
    case refactorOfSyncPreferences

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619299477
    case newSyncEntryPoints

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619360873
    case subscriptionPurchaseWidePixelMeasurement

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720018164
    case syncFeatureLevel3

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720557742
    case themes

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619633097
    case appStoreUpdateFlow

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720696560
    case unifiedURLPredictor

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619862984?focus=true
    case subscriptionRestoreWidePixelMeasurement

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866619917130
    case authV2WideEventEnabled

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

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866721265889
    case cpmCountPixel

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866620653515
    case storeSerpSettings

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866620524141
    case blurryAddressBarTahoeFix

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866477623612
    case dataImportNewExperience

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866721275379
    case scheduledDefaultBrowserAndDockPromptsInactiveUser

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866478113546
    case pinnedTabsViewRewrite

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866479296718
    case tabProgressIndicator

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211388368219934?focus=true
    case vpnConnectionWidePixelMeasurement

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866721557461
    case showHideAIGeneratedImagesSection

    /// https://app.asana.com/1/137249556945/project/1201141132935289/task/1210497696306780?focus=true
    case standaloneMigration

    /// https://app.asana.com/1/137249556945/project/1163321984198618/task/1203578778040829?focus=true
    case newTabPageAutoconsentStats
}

extension FeatureFlag: FeatureFlagDescribing {
    public var defaultValue: Bool {
        switch self {
        case .failsafeExampleCrossPlatformFeature,
                .failsafeExamplePlatformSpecificSubfeature,
                .removeWWWInCanonicalizationInThreatProtection,
                .visualUpdatesInternalOnly,
                .importChromeShortcuts,
                .updateSafariBookmarksImport,
                .updateFirefoxBookmarksImport,
                .supportsAlternateStripePaymentFlow,
                .restoreSessionPrompt,
                .refactorOfSyncPreferences,
                .subscriptionPurchaseWidePixelMeasurement,
                .subscriptionRestoreWidePixelMeasurement,
                .authV2WideEventEnabled,
                .syncCreditCards,
                .syncIdentities,
                .dataImportNewSafariFilePicker,
                .fireDialog,
                .fireDialogIndividualSitesLink,
                .historyViewSitesSection,
                .blurryAddressBarTahoeFix,
                .pinnedTabsViewRewrite,
                .vpnConnectionWidePixelMeasurement,
                .showHideAIGeneratedImagesSection:
            true
        default:
            false
        }
    }

    public var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
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
                .historyView,
                .historyViewSitesSection,
                .webExtensions,
                .autoUpdateInDEBUG,
                .updatesWontAutomaticallyRestartApp,
                .privacyProAuthV2,
                .scamSiteProtection,
                .failsafeExampleCrossPlatformFeature,
                .failsafeExamplePlatformSpecificSubfeature,
                .visualUpdates,
                .visualUpdatesInternalOnly,
                .tabCrashDebugging,
                .maliciousSiteProtection,
                .delayedWebviewPresentation,
                .syncSetupBarcodeIsUrlBased,
                .paidAIChat,
                .exchangeKeysToSyncWithAnotherDevice,
                .canScanUrlBasedSyncSetupBarcodes,
                .privacyProFreeTrial,
                .removeWWWInCanonicalizationInThreatProtection,
                .osSupportForceUnsupportedMessage,
                .osSupportForceWillSoonDropSupportMessage,
                .willSoonDropBigSurSupport,
                .hangReporting,
				.aiChatSidebar,
                .aiChatTextSummarization,
                .aiChatTextTranslation,
                .aiChatPageContext,
                .aiChatImprovements,
                .aiChatKeepSession,
                .aiChatOmnibarToggle,
                .importChromeShortcuts,
                .updateSafariBookmarksImport,
                .updateFirefoxBookmarksImport,
                .disableFireAnimation,
                .newTabPageOmnibar,
                .newTabPagePerTab,
                .newTabPageTabIDs,
                .vpnToolbarUpsell,
                .supportsAlternateStripePaymentFlow,
                .restoreSessionPrompt,
                .openFireWindowByDefault,
                .duckAISearchParameter,
                .refactorOfSyncPreferences,
                .newSyncEntryPoints,
                .dbpEmailConfirmationDecoupling,
                .dbpRemoteBrokerDelivery,
                .subscriptionPurchaseWidePixelMeasurement,
                .subscriptionRestoreWidePixelMeasurement,
                .syncFeatureLevel3,
                .themes,
                .appStoreUpdateFlow,
                .unifiedURLPredictor,
                .authV2WideEventEnabled,
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
                .pinnedTabsViewRewrite,
                .tabProgressIndicator,
                .vpnConnectionWidePixelMeasurement,
                .showHideAIGeneratedImagesSection,
                .standaloneMigration,
                .blackFridayCampaign,
                .newTabPageAutoconsentStats:
            return true
        case .debugMenu,
                .sslCertificatesBypass,
                .appendAtbToSerpQueries,
                .freemiumDBP,
                .contextualOnboarding,
                .unknownUsernameCategorization,
                .credentialsImportPromotionForExistingUsers,
                .scheduledSetDefaultBrowserAndAddToDockPrompts,
                .cpmCountPixel,
                .fireDialogIndividualSitesLink,
                .scheduledDefaultBrowserAndDockPromptsInactiveUser:
            return false
        }
    }

    public var source: FeatureFlagSource {
        switch self {
        case .debugMenu:
            return .internalOnly()
        case .appendAtbToSerpQueries:
            return .internalOnly()
        case .sslCertificatesBypass:
            return .remoteReleasable(.subfeature(SslCertificatesSubfeature.allowBypass))
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
        case .historyView:
            return .remoteReleasable(.subfeature(HTMLHistoryPageSubfeature.isLaunched))
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
        case .scheduledSetDefaultBrowserAndAddToDockPrompts:
            return .remoteReleasable(.subfeature(SetAsDefaultAndAddToDockSubfeature.scheduledDefaultBrowserAndDockPrompts))
        case .privacyProAuthV2:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProAuthV2))
        case .failsafeExampleCrossPlatformFeature:
            return .remoteReleasable(.feature(.intentionallyLocalOnlyFeatureForTests))
        case .failsafeExamplePlatformSpecificSubfeature:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.intentionallyLocalOnlySubfeatureForTests))
        case .visualUpdates:
            return .remoteReleasable(.subfeature(ExperimentalThemingSubfeature.visualUpdates))
        case .visualUpdatesInternalOnly:
            return .internalOnly()
        case .tabCrashDebugging:
            return .disabled
        case .delayedWebviewPresentation:
            return .remoteReleasable(.feature(.delayedWebviewPresentation))
        case .dbpRemoteBrokerDelivery:
            return .remoteReleasable(.subfeature(DBPSubfeature.remoteBrokerDelivery))
        case .dbpEmailConfirmationDecoupling:
            return .remoteReleasable(.subfeature(DBPSubfeature.emailConfirmationDecoupling))
        case .syncSetupBarcodeIsUrlBased:
            return .remoteReleasable(.subfeature(SyncSubfeature.syncSetupBarcodeIsUrlBased))
        case .exchangeKeysToSyncWithAnotherDevice:
            return .remoteReleasable(.subfeature(SyncSubfeature.exchangeKeysToSyncWithAnotherDevice))
        case .canScanUrlBasedSyncSetupBarcodes:
            return .remoteReleasable(.subfeature(SyncSubfeature.canScanUrlBasedSyncSetupBarcodes))
        case .privacyProFreeTrial:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProFreeTrial))
        case .paidAIChat:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.paidAIChat))
        case .removeWWWInCanonicalizationInThreatProtection:
            return .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.removeWWWInCanonicalization))
        case .aiChatSidebar:
            return .remoteReleasable(.subfeature(AIChatSubfeature.sidebar))
        case .aiChatTextSummarization:
            return .remoteReleasable(.subfeature(AIChatSubfeature.textSummarization))
        case .aiChatTextTranslation:
            return .remoteReleasable(.subfeature(AIChatSubfeature.textTranslation))
        case .aiChatPageContext:
            return .remoteReleasable(.subfeature(AIChatSubfeature.pageContext))
        case .aiChatImprovements:
            return .remoteReleasable(.subfeature(AIChatSubfeature.improvements))
        case .aiChatKeepSession:
            return .remoteReleasable(.subfeature(AIChatSubfeature.keepSession))
        case .aiChatOmnibarToggle:
            return .remoteReleasable(.subfeature(AIChatSubfeature.omnibarToggle))
        case .osSupportForceUnsupportedMessage:
            return .disabled
        case .osSupportForceWillSoonDropSupportMessage:
            return .disabled
        case .willSoonDropBigSurSupport:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.willSoonDropBigSurSupport))
        case .hangReporting:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.hangReporting))
        case .importChromeShortcuts:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.importChromeShortcuts))
        case .updateSafariBookmarksImport:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.updateSafariBookmarksImport))
        case .updateFirefoxBookmarksImport:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.updateFirefoxBookmarksImport))
        case .disableFireAnimation:
            return .remoteReleasable(.feature(.disableFireAnimation))
        case .newTabPageOmnibar:
            return .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.omnibar))
        case .vpnToolbarUpsell:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.vpnToolbarUpsell))
        case .newTabPagePerTab:
            return .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.newTabPagePerTab))
        case .newTabPageTabIDs:
            return .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.newTabPageTabIDs))
        case .supportsAlternateStripePaymentFlow:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.supportsAlternateStripePaymentFlow))
        case .openFireWindowByDefault:
            return .remoteReleasable(.feature(.openFireWindowByDefault))
        case .restoreSessionPrompt:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.restoreSessionPrompt))
        case .duckAISearchParameter:
            return .enabled
        case .subscriptionPurchaseWidePixelMeasurement:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.subscriptionPurchaseWidePixelMeasurement))
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
            return .internalOnly()
        case .appStoreUpdateFlow:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.appStoreUpdateFlow))
        case .unifiedURLPredictor:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.unifiedURLPredictor))
        case .authV2WideEventEnabled:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.authV2WideEventEnabled))
        case .webKitPerformanceReporting:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.webKitPerformanceReporting))
        case .subscriptionRestoreWidePixelMeasurement:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.subscriptionRestoreWidePixelMeasurement))
        case .winBackOffer:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.winBackOffer))
        case .blackFridayCampaign:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.blackFridayCampaign))
        case .dataImportNewSafariFilePicker:
            return .remoteReleasable(.subfeature(DataImportSubfeature.newSafariFilePicker))
        case .aiChatDataClearing:
            return .remoteReleasable(.feature(.duckAiDataClearing))
        case .cpmCountPixel:
            return .internalOnly()
        case .storeSerpSettings:
            return .remoteReleasable(.subfeature(SERPSubfeature.storeSerpSettings))
        case .blurryAddressBarTahoeFix:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.blurryAddressBarTahoeFix))
        case .dataImportNewExperience:
            return .disabled
        case .scheduledDefaultBrowserAndDockPromptsInactiveUser:
            return .remoteDevelopment(.subfeature(SetAsDefaultAndAddToDockSubfeature.scheduledDefaultBrowserAndDockPromptsInactiveUser))
        case .pinnedTabsViewRewrite:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.pinnedTabsViewRewrite))
        case .tabProgressIndicator:
            return .disabled
        case .vpnConnectionWidePixelMeasurement:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.vpnConnectionWidePixelMeasurement))
        case .showHideAIGeneratedImagesSection:
            return .remoteReleasable(.subfeature(AIChatSubfeature.showHideAiGeneratedImages))
        case .standaloneMigration:
            return .remoteReleasable(.subfeature(AIChatSubfeature.standaloneMigration))
        case .newTabPageAutoconsentStats:
            return .remoteReleasable(.subfeature(HtmlNewTabPageSubfeature.autoconsentStats))
        }
    }
}

public extension FeatureFlagger {

    func isFeatureOn(_ featureFlag: FeatureFlag) -> Bool {
        isFeatureOn(for: featureFlag)
    }
}
