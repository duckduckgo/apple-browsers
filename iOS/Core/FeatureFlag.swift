//
//  FeatureFlag.swift
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

import Foundation
import PrivacyConfig

public enum FeatureFlag: String {
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866605041091
    case sync

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866709124077
    case autofillCredentialInjecting

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866466776981
    case autofillCredentialsSaving

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866465652865
    case autofillInlineIconCredentials

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866709604162
    case autofillAccessCredentialManagement

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866608422170
    case autofillPasswordGeneration

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866465600921
    case autofillOnByDefault

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866709799446
    case autofillFailureReporting

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866466892257
    case autofillOnForExistingUsers

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866464342535
    case autofillUnknownUsernameCategorization

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866467356751
    case autofillPartialFormSaves

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866603305287
    case autofillCreditCards

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866609047656
    case autofillCreditCardsOnByDefault

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866710362491
    case autocompleteAttributeSupport

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866467693551
    case inputFocusApi

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866467140007
    case incontextSignup

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866710317371
    case autoconsentOnByDefault

    // Duckplayer 'Web based' UI
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866609457246
    case duckPlayer

    // Open Duckplayer in a new tab for 'Web based' UI
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866710727484
    case duckPlayerOpenInNewTab

    // Duckplayer 'Native' UI
    // https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866710146121
    case duckPlayerNativeUI

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866710942922
    case sslCertificatesBypass

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866468307995
    case syncPromotionBookmarks

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866468401462
    case syncPromotionPasswords

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866711364768
    case autofillSurveys

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866468784743
    case autocompleteTabs

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866711151217
    case adAttributionReporting

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866610480266
    case dbpRemoteBrokerDelivery

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866710074694
    case dbpEmailConfirmationDecoupling

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212258549430653
    case dbpForegroundRunningOnAppActive

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212258549430659
    case dbpForegroundRunningWhenDashboardOpen

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212397941080401
    case dbpClickActionDelayReductionOptimization

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866711635701
    case crashReportOptInStatusResetting

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866706505415
    case syncSeamlessAccountSwitching

    /// Feature flag to enable / disable phishing and malware protection
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866465175262
    case maliciousSiteProtection

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866711861627
    case scamSiteProtection

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866470028133
    case experimentalAddressBar

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866712841283
    case privacyProOnboardingPromotion

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866464085187
    case syncSetupBarcodeIsUrlBased

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866611816519
    case canScanUrlBasedSyncSetupBarcodes

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866470360367
    case autofillPasswordVariantCategorization

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866611178534
    case paidAIChat

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866609800953
    case canInterceptSyncSetupUrls

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866470664073
    case exchangeKeysToSyncWithAnotherDevice

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866612283363
    case aiChatKeepSession

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866463389447
    case showSettingsCompleteSetupSection

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866607644644
    case canPromoteImportPasswordsInPasswordManagement

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866611615737
    case canPromoteImportPasswordsInBrowser
    
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866463389460
    /// Note: 'Failsafe' feature flag. See https://app.asana.com/1/137249556945/project/1202500774821704/task/1210572145398078?focus=true
    case supportsAlternateStripePaymentFlow
    
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866611730044
    case personalInformationRemoval

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866712516861
    /// This is off by default.  We can turn it on to get daily pixels of users's widget usage for a short time.
    case widgetReporting

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866467213996
    case createFireproofFaviconUpdaterSecureVaultInBackground

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866609233733
    case aiFeaturesSettingsUpdate

    /// Adds kbg=-1 parameter to search URLs when DuckAI is disabled
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866714302194
    case duckAISearchParameter

    /// Local inactivity provisional notifications delivered to Notification Center.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866471590692
    case inactivityNotification

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866469585479
    case daxEasterEggLogos

    /// Allows users to set an Easter egg logo as their permanent search icon
    case daxEasterEggPermanentLogo

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866471806081
    case showAIChatAddressBarChoiceScreen

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866714634010
    case newDeviceSyncPrompt

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866468857577
    case winBackOffer

    /// https://app.asana.com/1/137249556945/project/1210594645229050/task/1211969445818393?focus=true
    case blackFridayCampaign

    ///  https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866712760360
    case syncCreditCards

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866613993355
    case unifiedURLPredictor

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866713701189
    case vpnMenuItem

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614199859
    case forgetAllInSettings

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866470156149
    case duckAiDataClearing
    
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614122594
    case fullDuckAIMode

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212197756955039
    case fadeOutOnToggle

    /// macOS: https://app.asana.com/1/137249556945/project/1211834678943996/task/1212015252281641
    /// iOS: https://app.asana.com/1/137249556945/project/1211834678943996/task/1212015250423471
    case attributedMetrics

    /// https://app.asana.com/1/137249556945/project/1211654189969294/task/1211652685709099?focus=true
    case onboardingSearchExperience

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866472842661
    case storeSerpSettings

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715575447
    case showHideAIGeneratedImagesSection

    /// https://app.asana.com/1/137249556945/project/1201141132935289/task/1210497696306780?focus=true
    case standaloneMigration

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211998610726855?focus=true
    case tierMessagingEnabled

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211998614203542?focus=true
    case allowProTierPurchase

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211992061067315?focus=true
    case browsingMenuSheetPresentation

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1208824174611454?focus=true
    case autofillExtensionSettings
    case canPromoteAutofillExtensionInBrowser
    case canPromoteAutofillExtensionInPasswordManagement

    /// https://app.asana.com/1/137249556945/project/1201462886803403/task/1211326076710245?focus=true
    case migrateKeychainAccessibility

    /// https://app.asana.com/1/137249556945/project/481882893211075/task/1212057154681076?focus=true
    case productTelemeterySurfaceUsage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212229431540900
    case granularFireButtonOptions

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212305240287488?focus=true
    case dataImportWideEventMeasurement

    /// Sort domain matches higher than other matches when searching saved passwords
    case autofillPasswordSearchPrioritizeDomain

    // https://app.asana.com/1/137249556945/project/414709148257752/task/1212395110448661?focus=true
    case appRatingPrompt

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211652685709102?focus=true
    case contextualDuckAIMode

    /// https://app.asana.com/1/137249556945/project/1201462886803403/task/1211837879355661?focus=true
    case aiChatSync

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212388316840466?focus=true
    case showWhatsNewPromptOnDemand
}

extension FeatureFlag: FeatureFlagDescribing {
    public var defaultValue: Bool {
        switch self {
        case .canScanUrlBasedSyncSetupBarcodes,
             .canInterceptSyncSetupUrls,
             .supportsAlternateStripePaymentFlow,
             .createFireproofFaviconUpdaterSecureVaultInBackground,
             .aiFeaturesSettingsUpdate,
             .duckAISearchParameter,
             .daxEasterEggLogos,
             .daxEasterEggPermanentLogo,
             .newDeviceSyncPrompt,
             .dbpForegroundRunningOnAppActive,
             .dbpForegroundRunningWhenDashboardOpen,
             .syncCreditCards,
             .unifiedURLPredictor,
             .migrateKeychainAccessibility,
             .dataImportWideEventMeasurement,
             .browsingMenuSheetPresentation,
             .appRatingPrompt,
             .autofillPasswordSearchPrioritizeDomain,
             .showWhatsNewPromptOnDemand:
            true
        default:
            false
        }
    }

    public var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
        default:
            nil
        }
    }

    public static var localOverrideStoreName: String = "com.duckduckgo.app.featureFlag.localOverrides"

    public var supportsLocalOverriding: Bool {
        switch self {
        case .scamSiteProtection,
             .maliciousSiteProtection,
             .autocompleteAttributeSupport,
             .privacyProOnboardingPromotion,
             .duckPlayerNativeUI,
             .autofillPasswordVariantCategorization,
             .syncSetupBarcodeIsUrlBased,
             .canScanUrlBasedSyncSetupBarcodes,
             .paidAIChat,
             .canInterceptSyncSetupUrls,
             .exchangeKeysToSyncWithAnotherDevice,
             .supportsAlternateStripePaymentFlow,
             .personalInformationRemoval,
             .createFireproofFaviconUpdaterSecureVaultInBackground,
             .duckAISearchParameter,
             .inactivityNotification,
             .daxEasterEggLogos,
             .daxEasterEggPermanentLogo,
             .dbpEmailConfirmationDecoupling,
             .dbpRemoteBrokerDelivery,
             .dbpForegroundRunningOnAppActive,
             .dbpForegroundRunningWhenDashboardOpen,
             .dbpClickActionDelayReductionOptimization,
             .showAIChatAddressBarChoiceScreen,
             .winBackOffer,
             .syncCreditCards,
             .unifiedURLPredictor,
             .vpnMenuItem,
             .forgetAllInSettings,
             .onboardingSearchExperience,
             .duckAiDataClearing,
             .fullDuckAIMode,
             .fadeOutOnToggle,
             .attributedMetrics,
             .storeSerpSettings,
             .showHideAIGeneratedImagesSection,
             .standaloneMigration,
             .blackFridayCampaign,
             .tierMessagingEnabled,
             .allowProTierPurchase,
             .browsingMenuSheetPresentation,
             .autofillExtensionSettings,
             .canPromoteAutofillExtensionInBrowser,
             .canPromoteAutofillExtensionInPasswordManagement,
             .autofillPasswordSearchPrioritizeDomain,
             .granularFireButtonOptions,
             .dataImportWideEventMeasurement,
             .appRatingPrompt,
             .contextualDuckAIMode,
             .aiChatSync,
             .showWhatsNewPromptOnDemand:
            return true
        case .showSettingsCompleteSetupSection:
            if #available(iOS 18.2, *) {
                return true
            } else {
                return false
            }
        case .sync,
               .autofillCredentialInjecting,
               .autofillCredentialsSaving,
               .autofillInlineIconCredentials,
               .autofillAccessCredentialManagement,
               .autofillPasswordGeneration,
               .autofillOnByDefault,
               .autofillFailureReporting,
               .autofillOnForExistingUsers,
               .autofillUnknownUsernameCategorization,
               .autofillPartialFormSaves,
               .autofillCreditCards,
               .autofillCreditCardsOnByDefault,
               .inputFocusApi,
               .incontextSignup,
               .autoconsentOnByDefault,
               .duckPlayer,
               .duckPlayerOpenInNewTab,
               .sslCertificatesBypass,
               .syncPromotionBookmarks,
               .syncPromotionPasswords,
               .autofillSurveys,
               .autocompleteTabs,
               .adAttributionReporting,
               .crashReportOptInStatusResetting,
               .syncSeamlessAccountSwitching,
               .experimentalAddressBar,
               .aiChatKeepSession,
               .aiFeaturesSettingsUpdate,
               .widgetReporting,
               .canPromoteImportPasswordsInBrowser,
               .canPromoteImportPasswordsInPasswordManagement,
               .newDeviceSyncPrompt,
               .migrateKeychainAccessibility,
               .productTelemeterySurfaceUsage:
            return false
        }
    }

    public var source: FeatureFlagSource {
        switch self {
        case .sync:
            return .remoteReleasable(.subfeature(SyncSubfeature.level0ShowSync))
        case .autofillCredentialInjecting:
            return .remoteReleasable(.subfeature(AutofillSubfeature.credentialsAutofill))
        case .autofillCredentialsSaving:
            return .remoteReleasable(.subfeature(AutofillSubfeature.credentialsSaving))
        case .autofillInlineIconCredentials:
            return .remoteReleasable(.subfeature(AutofillSubfeature.inlineIconCredentials))
        case .autofillAccessCredentialManagement:
            return .remoteReleasable(.subfeature(AutofillSubfeature.accessCredentialManagement))
        case .autofillPasswordGeneration:
            return .remoteReleasable(.subfeature(AutofillSubfeature.autofillPasswordGeneration))
        case .autofillOnByDefault:
            return .remoteReleasable(.subfeature(AutofillSubfeature.onByDefault))
        case .autofillFailureReporting:
            return .remoteReleasable(.feature(.autofillBreakageReporter))
        case .autofillOnForExistingUsers:
            return .remoteReleasable(.subfeature(AutofillSubfeature.onForExistingUsers))
        case .autofillUnknownUsernameCategorization:
            return .remoteReleasable(.subfeature(AutofillSubfeature.unknownUsernameCategorization))
        case .autofillPartialFormSaves:
            return .remoteReleasable(.subfeature(AutofillSubfeature.partialFormSaves))
        case .autofillCreditCards:
            return .remoteReleasable(.subfeature(AutofillSubfeature.autofillCreditCards))
        case .autofillCreditCardsOnByDefault:
            return .remoteReleasable(.subfeature(AutofillSubfeature.autofillCreditCardsOnByDefault))
        case .autocompleteAttributeSupport:
            return .remoteReleasable(.subfeature(AutofillSubfeature.autocompleteAttributeSupport))
        case .inputFocusApi:
            return .remoteReleasable(.subfeature(AutofillSubfeature.inputFocusApi))
        case .canPromoteImportPasswordsInPasswordManagement:
            return .remoteReleasable(.subfeature(AutofillSubfeature.canPromoteImportPasswordsInPasswordManagement))
        case .canPromoteImportPasswordsInBrowser:
            return .remoteReleasable(.subfeature(AutofillSubfeature.canPromoteImportPasswordsInBrowser))
        case .incontextSignup:
            return .remoteReleasable(.feature(.incontextSignup))
        case .autoconsentOnByDefault:
            return .remoteReleasable(.subfeature(AutoconsentSubfeature.onByDefault))
        case .duckPlayer:
            return .remoteReleasable(.subfeature(DuckPlayerSubfeature.enableDuckPlayer))
        case .duckPlayerOpenInNewTab:
            return .remoteReleasable(.subfeature(DuckPlayerSubfeature.openInNewTab))
        case .duckPlayerNativeUI:
            return .remoteReleasable(.subfeature(DuckPlayerSubfeature.nativeUI))
        case .sslCertificatesBypass:
            return .remoteReleasable(.subfeature(SslCertificatesSubfeature.allowBypass))
        case .syncPromotionBookmarks:
            return .remoteReleasable(.subfeature(SyncPromotionSubfeature.bookmarks))
        case .syncPromotionPasswords:
            return .remoteReleasable(.subfeature(SyncPromotionSubfeature.passwords))
        case .autofillSurveys:
            return .remoteReleasable(.feature(.autofillSurveys))
        case .autocompleteTabs:
            return .remoteReleasable(.feature(.autocompleteTabs))
        case .adAttributionReporting:
            return .remoteReleasable(.feature(.adAttributionReporting))
        case .dbpRemoteBrokerDelivery:
            return .remoteReleasable(.subfeature(DBPSubfeature.remoteBrokerDelivery))
        case .dbpEmailConfirmationDecoupling:
            return .remoteReleasable(.subfeature(DBPSubfeature.emailConfirmationDecoupling))
        case .dbpForegroundRunningOnAppActive:
            return .remoteReleasable(.subfeature(DBPSubfeature.foregroundRunningOnAppActive))
        case .dbpForegroundRunningWhenDashboardOpen:
            return .remoteReleasable(.subfeature(DBPSubfeature.foregroundRunningWhenDashboardOpen))
        case .dbpClickActionDelayReductionOptimization:
            return .remoteReleasable(.subfeature(DBPSubfeature.clickActionDelayReductionOptimization))
        case .crashReportOptInStatusResetting:
            return .internalOnly()
        case .syncSeamlessAccountSwitching:
            return .remoteReleasable(.subfeature(SyncSubfeature.seamlessAccountSwitching))
        case .maliciousSiteProtection:
            return .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.onByDefault))
        case .scamSiteProtection:
            return .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.scamProtection))
        case .widgetReporting:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.widgetReporting))
        case .experimentalAddressBar:
            return .remoteReleasable(.subfeature(AIChatSubfeature.experimentalAddressBar))
        case .privacyProOnboardingPromotion:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProOnboardingPromotion))
        case .syncSetupBarcodeIsUrlBased:
            return .remoteReleasable(.subfeature(SyncSubfeature.syncSetupBarcodeIsUrlBased))
        case .canScanUrlBasedSyncSetupBarcodes:
            return .remoteReleasable(.subfeature(SyncSubfeature.canScanUrlBasedSyncSetupBarcodes))
        case .autofillPasswordVariantCategorization:
            return .remoteReleasable(.subfeature(AutofillSubfeature.passwordVariantCategorization))
        case .paidAIChat:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.paidAIChat))
        case .canInterceptSyncSetupUrls:
            return .remoteReleasable(.subfeature(SyncSubfeature.canInterceptSyncSetupUrls))
        case .exchangeKeysToSyncWithAnotherDevice:
            return .remoteReleasable(.subfeature(SyncSubfeature.exchangeKeysToSyncWithAnotherDevice))
        case .aiChatKeepSession:
            return .remoteReleasable(.subfeature(AIChatSubfeature.keepSession))
        case .showSettingsCompleteSetupSection:
            return .remoteReleasable(.subfeature(OnboardingSubfeature.showSettingsCompleteSetupSection))
        case .supportsAlternateStripePaymentFlow:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.supportsAlternateStripePaymentFlow))
        case .personalInformationRemoval:
            return .remoteReleasable(.subfeature(DBPSubfeature.pirRollout))
        case .createFireproofFaviconUpdaterSecureVaultInBackground:
            return .remoteReleasable(.subfeature(AutofillSubfeature.createFireproofFaviconUpdaterSecureVaultInBackground))
        case .aiFeaturesSettingsUpdate:
            return .remoteReleasable(.subfeature(AIChatSubfeature.aiFeaturesSettingsUpdate))
        case .duckAISearchParameter:
            return .remoteReleasable(.subfeature(AIChatSubfeature.duckAISearchParameter))
        case .inactivityNotification:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.inactivityNotification))
        case .daxEasterEggLogos:
            return .remoteReleasable(.feature(.daxEasterEggLogos))
        case .daxEasterEggPermanentLogo:
            return .remoteReleasable(.feature(.daxEasterEggPermanentLogo))
        case .showAIChatAddressBarChoiceScreen:
            return .remoteReleasable(.subfeature(AIChatSubfeature.showAIChatAddressBarChoiceScreen))
        case .newDeviceSyncPrompt:
            return .remoteReleasable(.subfeature(SyncSubfeature.newDeviceSyncPrompt))
        case .winBackOffer:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.winBackOffer))
        case .blackFridayCampaign:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.blackFridayCampaign))
        case .syncCreditCards:
            return .remoteReleasable(.subfeature(SyncSubfeature.syncCreditCards))
        case .unifiedURLPredictor:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.unifiedURLPredictor))
        case .vpnMenuItem:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.vpnMenuItem))
        case .forgetAllInSettings:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.forgetAllInSettings))
        case .duckAiDataClearing:
            return .remoteReleasable(.feature(.duckAiDataClearing))
        case .fullDuckAIMode:
            return .remoteReleasable(.subfeature(AIChatSubfeature.fullDuckAIMode))
        case .fadeOutOnToggle:
            return .remoteReleasable(.subfeature(AIChatSubfeature.fadeOutOnToggle))
        case .attributedMetrics:
            return .remoteReleasable(.feature(.attributedMetrics))
        case .onboardingSearchExperience:
            return .remoteReleasable(.subfeature(AIChatSubfeature.onboardingSearchExperience))
        case .storeSerpSettings:
            return .remoteReleasable(.subfeature(SERPSubfeature.storeSerpSettings))
        case .showHideAIGeneratedImagesSection:
            return .remoteReleasable(.subfeature(AIChatSubfeature.showHideAiGeneratedImages))
        case .standaloneMigration:
            return .remoteReleasable(.subfeature(AIChatSubfeature.standaloneMigration))
        case .tierMessagingEnabled:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.tierMessagingEnabled))
        case .allowProTierPurchase:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.allowProTierPurchase))
        case .browsingMenuSheetPresentation:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.experimentalBrowsingMenu))
        case .autofillExtensionSettings:
            return .remoteReleasable(.subfeature(AutofillSubfeature.autofillExtensionSettings))
        case .canPromoteAutofillExtensionInBrowser:
            return .remoteReleasable(.subfeature(AutofillSubfeature.canPromoteAutofillExtensionInBrowser))
        case .canPromoteAutofillExtensionInPasswordManagement:
            return .remoteReleasable(.subfeature(AutofillSubfeature.canPromoteAutofillExtensionInPasswordManagement))
        case .migrateKeychainAccessibility:
            return .remoteReleasable(.subfeature(AutofillSubfeature.migrateKeychainAccessibility))
        case .productTelemeterySurfaceUsage:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.productTelemetrySurfaceUsage))
        case .granularFireButtonOptions:
            return .disabled
        case .dataImportWideEventMeasurement:
            return .remoteReleasable(.subfeature(DataImportSubfeature.dataImportWideEventMeasurement))
        case .autofillPasswordSearchPrioritizeDomain:
            return .remoteReleasable(.subfeature(AutofillSubfeature.autofillPasswordSearchPrioritizeDomain))
        case .appRatingPrompt:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.appRatingPrompt))
        case .contextualDuckAIMode:
            return .remoteReleasable(.subfeature(AIChatSubfeature.contextualDuckAIMode))
        case .aiChatSync:
            return .disabled
        case .showWhatsNewPromptOnDemand:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.showWhatsNewPromptOnDemand))
        }
    }
}

extension FeatureFlagger {
    public func isFeatureOn(_ featureFlag: FeatureFlag) -> Bool {
        return isFeatureOn(for: featureFlag)
    }
}
