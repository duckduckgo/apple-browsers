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
import BrowserServicesKit

public enum FeatureFlag: String {
    case debugMenu
    case sync
    case autofillCredentialInjecting
    case autofillCredentialsSaving
    case autofillInlineIconCredentials
    case autofillAccessCredentialManagement
    case autofillPasswordGeneration
    case autofillOnByDefault
    case autofillFailureReporting
    case autofillOnForExistingUsers
    case autofillUnknownUsernameCategorization
    case autofillPartialFormSaves
    case autofillCreditCards
    case autofillCreditCardsOnByDefault
    case autocompleteAttributeSupport
    case inputFocusApi
    case incontextSignup
    case autoconsentOnByDefault

    // Duckplayer 'Web based' UI
    case duckPlayer

    // Open Duckplayer in a new tab for 'Web based' UI
    case duckPlayerOpenInNewTab

    // Duckplayer 'Native' UI
    // https://app.asana.com/0/1204099484721401/1209255140870410/f
    case duckPlayerNativeUI

    case sslCertificatesBypass
    case syncPromotionBookmarks
    case syncPromotionPasswords
    case onboardingHighlights
    case onboardingAddToDock
    case autofillSurveys
    case autocompleteTabs
    case textZoom
    case adAttributionReporting
    case dbpRemoteBrokerDelivery
    case dbpEmailConfirmationDecoupling

    /// https://app.asana.com/0/1208592102886666/1208613627589762/f
    case crashReportOptInStatusResetting

    /// https://app.asana.com/0/0/1208767141940869/f
    case privacyProFreeTrialJan25

    /// https://app.asana.com/0/1206226850447395/1206307878076518
    case webViewStateRestoration

    /// https://app.asana.com/0/72649045549333/1208944782348823/f
    case syncSeamlessAccountSwitching

    /// Feature flag to enable / disable phishing and malware protection
    /// https://app.asana.com/0/1206329551987282/1207149365636877/f
    case maliciousSiteProtection

    /// https://app.asana.com/0/1204186595873227/1209164066387913
    case scamSiteProtection

    /// https://app.asana.com/1/137249556945/task/1210330600670666
    case removeWWWInCanonicalizationInThreatProtection

    /// https://app.asana.com/0/72649045549333/1207991044706236/f
    case privacyProAuthV2

    /// https://app.asana.com/1/137249556945/project/1206329551987282/task/1210806442029191
    case setAsDefaultBrowserPiPVideoTutorial

    // Demonstrative cases for default value. Remove once a real-world feature/subfeature is added
    case failsafeExampleCrossPlatformFeature
    case failsafeExamplePlatformSpecificSubfeature

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210055762484807?focus=true
    /// https://app.asana.com/1/137249556945/task/1210496258241813
    case experimentalAddressBar

    /// https://app.asana.com/1/137249556945/task/1210139454006070
    case privacyProOnboardingPromotion

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210081345713964?focus=true
    case syncSetupBarcodeIsUrlBased

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210081345713964?focus=true
    case canScanUrlBasedSyncSetupBarcodes

    /// https://app.asana.com/1/137249556945/project/1206488453854252/task/1210001506953718
    case privacyProFreeTrial

    /// https://app.asana.com/1/137249556945/project/1198964220583541/task/1210272333893232?focus=true
    case autofillPasswordVariantCategorization

    /// https://app.asana.com/1/137249556945/project/1204186595873227/task/1210181044180012?focus=true
    case paidAIChat

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210081345713964?focus=true
    case canInterceptSyncSetupUrls

    /// https://app.asana.com/1/137249556945/project/414235014887631/task/1210325960030113?focus=true
    case exchangeKeysToSyncWithAnotherDevice

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210422840951066?focus=true
    case aiChatKeepSession

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210410396636449?focus=true
    case showSettingsCompleteSetupSection

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1209304767941984?focus=true
    case scheduledSetDefaultBrowserPrompts

    /// https://app.asana.com/1/137249556945/project/1206329551987282/task/1210716028790591?focus=true
    case scheduledSetDefaultBrowserPromptsForInactiveUsers

    case subscriptionRebranding

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210259429792293?focus=true
    case canPromoteImportPasswordsInPasswordManagement
    case canPromoteImportPasswordsInBrowser
    
    /// https://app.asana.com/1/137249556945/project/1206488453854252/task/1210380647876463?focus=true
    /// Note: 'Failsafe' feature flag. See https://app.asana.com/1/137249556945/project/1202500774821704/task/1210572145398078?focus=true
    case supportsAlternateStripePaymentFlow
    
    case personalInformationRemoval

    /// https://app.asana.com/1/137249556945/project/392891325557410/task/1210882421460693?focus=true
    /// This is off by default.  We can turn it on to get daily pixels of users's widget usage for a short time.
    case widgetReporting

    /// https://app.asana.com/1/137249556945/project/1202926619870900/task/1210964217479369?focus=true
    case createFireproofFaviconUpdaterSecureVaultInBackground

    /// https://app.asana.com/1/137249556945/project/1204167627774280/task/1210926332858859?focus=true
    case aiFeaturesSettingsUpdate

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210839825079760?focus=true
    case askAIChatSuggestion

    /// Adds kbg=-1 parameter to search URLs when DuckAI is disabled
    case duckAISearchParameter

    /// Local inactivity provisional notifications delivered to Notification Center.
    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211003501974970?focus=true
    case inactivityNotification

    /// https://app.asana.com/1/137249556945/project/1206488453854252/task/1210989706758207?focus=true
    case daxEasterEggLogos

    /// https://app.asana.com/1/137249556945/project/414235014887631/task/1211127159784126?focus=true
    case subscriptionPurchaseWidePixelMeasurement

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210860792084465?focus=true
    case showAIChatAddressBarChoiceScreen

    /// https://app.asana.com/1/137249556945/project/1210947754188321/task/1210869716452616?focus=true
    case refreshButtonPosition
}

extension FeatureFlag: FeatureFlagDescribing {
    public var defaultValue: Bool {
        switch self {
        case .failsafeExampleCrossPlatformFeature,
             .failsafeExamplePlatformSpecificSubfeature,
             .canScanUrlBasedSyncSetupBarcodes,
             .canInterceptSyncSetupUrls,
             .removeWWWInCanonicalizationInThreatProtection,
             .supportsAlternateStripePaymentFlow,
             .setAsDefaultBrowserPiPVideoTutorial,
             .createFireproofFaviconUpdaterSecureVaultInBackground,
             .daxEasterEggLogos,
             .subscriptionPurchaseWidePixelMeasurement,
             .askAIChatSuggestion,
             .refreshButtonPosition:
            true
        default:
            false
        }
    }

    public var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
        case .privacyProFreeTrialJan25:
            PrivacyProFreeTrialExperimentCohort.self
        default:
            nil
        }
    }

    public static var localOverrideStoreName: String = "com.duckduckgo.app.featureFlag.localOverrides"

    public var supportsLocalOverriding: Bool {
        switch self {
        case .textZoom,
             .privacyProAuthV2,
             .scamSiteProtection,
             .maliciousSiteProtection,
             .autocompleteAttributeSupport,
             .privacyProOnboardingPromotion,
             .duckPlayerNativeUI,
             .removeWWWInCanonicalizationInThreatProtection,
             .privacyProFreeTrial,
             .autofillPasswordVariantCategorization,
             .syncSetupBarcodeIsUrlBased,
             .canScanUrlBasedSyncSetupBarcodes,
             .paidAIChat,
             .canInterceptSyncSetupUrls,
             .exchangeKeysToSyncWithAnotherDevice,
             .subscriptionRebranding,
             .widgetReporting,
             .canPromoteImportPasswordsInPasswordManagement,
             .canPromoteImportPasswordsInBrowser,
             .setAsDefaultBrowserPiPVideoTutorial,
             .supportsAlternateStripePaymentFlow,
             .personalInformationRemoval,
             .createFireproofFaviconUpdaterSecureVaultInBackground,
             .scheduledSetDefaultBrowserPrompts,
             .scheduledSetDefaultBrowserPromptsForInactiveUsers,
             .askAIChatSuggestion,
             .duckAISearchParameter,
             .inactivityNotification,
             .daxEasterEggLogos,
             .dbpEmailConfirmationDecoupling,
             .subscriptionPurchaseWidePixelMeasurement,
             .showAIChatAddressBarChoiceScreen,
             .refreshButtonPosition:
            return true
        case .showSettingsCompleteSetupSection:
            if #available(iOS 18.2, *) {
                return true
            } else {
                return false
            }
        case .debugMenu,
               .sync,
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
               .onboardingHighlights,
               .onboardingAddToDock,
               .autofillSurveys,
               .autocompleteTabs,
               .adAttributionReporting,
               .dbpRemoteBrokerDelivery,
               .crashReportOptInStatusResetting,
               .privacyProFreeTrialJan25,
               .webViewStateRestoration,
               .syncSeamlessAccountSwitching,
               .failsafeExampleCrossPlatformFeature,
               .failsafeExamplePlatformSpecificSubfeature,
               .experimentalAddressBar,
               .aiChatKeepSession,
               .aiFeaturesSettingsUpdate:
            return false
        }
    }

    public var source: FeatureFlagSource {
        switch self {
        case .debugMenu:
            return .internalOnly()
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
        case .onboardingHighlights:
            return .internalOnly()
        case .onboardingAddToDock:
            return .internalOnly()
        case .autofillSurveys:
            return .remoteReleasable(.feature(.autofillSurveys))
        case .autocompleteTabs:
            return .remoteReleasable(.feature(.autocompleteTabs))
        case .textZoom:
            return .remoteReleasable(.feature(.textZoom))
        case .adAttributionReporting:
            return .remoteReleasable(.feature(.adAttributionReporting))
        case .dbpRemoteBrokerDelivery:
            return .remoteReleasable(.subfeature(DBPSubfeature.remoteBrokerDelivery))
        case .dbpEmailConfirmationDecoupling:
            return .remoteReleasable(.subfeature(DBPSubfeature.emailConfirmationDecoupling))
        case .crashReportOptInStatusResetting:
            return .internalOnly()
        case .privacyProFreeTrialJan25:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProFreeTrialJan25))
        case .webViewStateRestoration:
            return .remoteReleasable(.feature(.webViewStateRestoration))
        case .syncSeamlessAccountSwitching:
            return .remoteReleasable(.subfeature(SyncSubfeature.seamlessAccountSwitching))
        case .maliciousSiteProtection:
            return .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.onByDefault))
        case .scamSiteProtection:
            return .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.scamProtection))
        case .privacyProAuthV2:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProAuthV2))
        case .setAsDefaultBrowserPiPVideoTutorial:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.defaultBrowserTutorial))
        case .failsafeExampleCrossPlatformFeature:
            return .remoteReleasable(.feature(.intentionallyLocalOnlyFeatureForTests))
        case .failsafeExamplePlatformSpecificSubfeature:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.intentionallyLocalOnlySubfeatureForTests))
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
        case .removeWWWInCanonicalizationInThreatProtection:
            return .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.removeWWWInCanonicalization))
        case .privacyProFreeTrial:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProFreeTrial))
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
        case .scheduledSetDefaultBrowserPrompts:
            return .remoteReleasable(.subfeature(SetAsDefaultAndAddToDockSubfeature.scheduledDefaultBrowserPrompts))
        case .scheduledSetDefaultBrowserPromptsForInactiveUsers:
            return .remoteReleasable(.subfeature(SetAsDefaultAndAddToDockSubfeature.scheduledDefaultBrowserPromptsInactiveUser))
        case .subscriptionRebranding:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.subscriptionRebranding))
        case .supportsAlternateStripePaymentFlow:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.supportsAlternateStripePaymentFlow))
        case .personalInformationRemoval:
            return .remoteReleasable(.feature(.dbp))
        case .createFireproofFaviconUpdaterSecureVaultInBackground:
            return .remoteReleasable(.subfeature(AutofillSubfeature.createFireproofFaviconUpdaterSecureVaultInBackground))
        case .aiFeaturesSettingsUpdate:
            return .enabled
        case .duckAISearchParameter:
            return .enabled
        case .askAIChatSuggestion:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.askAIChatSuggestion))
        case .inactivityNotification:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.inactivityNotification))
        case .daxEasterEggLogos:
            return .remoteReleasable(.feature(.daxEasterEggLogos))
        case .subscriptionPurchaseWidePixelMeasurement:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.subscriptionPurchaseWidePixelMeasurement))
        case .refreshButtonPosition:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.refreshButtonPosition))
        case .showAIChatAddressBarChoiceScreen:
            return .remoteReleasable(.subfeature(AIChatSubfeature.showAIChatAddressBarChoiceScreen))
        }
    }
}

extension FeatureFlagger {
    public func isFeatureOn(_ featureFlag: FeatureFlag) -> Bool {
        return isFeatureOn(for: featureFlag)
    }
}

public enum PrivacyProFreeTrialExperimentCohort: String, FeatureFlagCohortDescribing {
    /// Control cohort with no changes applied.
    case control
    /// Treatment cohort where the experiment modifications are applied.
    case treatment
}
