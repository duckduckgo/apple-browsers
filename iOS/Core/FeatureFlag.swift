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
    case history
    case newTabPageSections

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

    /// https://app.asana.com/0/1204186595873227/1206489252288889
    case networkProtectionRiskyDomainsProtection

    /// https://app.asana.com/0/72649045549333/1207991044706236/f
    case privacyProAuthV2

    /// https://app.asana.com/1/137249556945/project/1108686900785972/task/1209304767941984?focus=true
    case onboardingSetAsDefaultBrowserPiPVideo

    // Demonstrative cases for default value. Remove once a real-world feature/subfeature is added
    case failsafeExampleCrossPlatformFeature
    case failsafeExamplePlatformSpecificSubfeature

    // https://app.asana.com/1/137249556945/project/715106103902962/task/1210647253853346?focus=true
    case june2025TabManagerLayoutChanges

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210055762484807?focus=true
    case experimentalAIChat

    /// https://app.asana.com/1/137249556945/task/1210496258241813
    case experimentalSwitcherBarTransition

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

    case subscriptionRebranding

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1210259429792293?focus=true
    case canPromoteImportPasswordsInPasswordManagement
    case canPromoteImportPasswordsInBrowser
}

extension FeatureFlag: FeatureFlagDescribing {
    public var defaultValue: Bool {
        switch self {
        case .failsafeExampleCrossPlatformFeature,
             .failsafeExamplePlatformSpecificSubfeature,
             .canScanUrlBasedSyncSetupBarcodes,
             .canInterceptSyncSetupUrls,
             .removeWWWInCanonicalizationInThreatProtection,
             .june2025TabManagerLayoutChanges:
            true
        default:
            false
        }
    }

    public var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
        case .privacyProFreeTrialJan25:
            PrivacyProFreeTrialExperimentCohort.self
        case .onboardingSetAsDefaultBrowserPiPVideo:
            OnboardingSetAsDefaultBrowserPiPVideoCohort.self
        default:
            nil
        }
    }

    public static var localOverrideStoreName: String = "com.duckduckgo.app.featureFlag.localOverrides"

    public var supportsLocalOverriding: Bool {
        switch self {
        case .textZoom,
             .networkProtectionRiskyDomainsProtection,
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
             .experimentalSwitcherBarTransition,
             .subscriptionRebranding,
             .june2025TabManagerLayoutChanges,
             .canPromoteImportPasswordsInPasswordManagement,
             .canPromoteImportPasswordsInBrowser:
            return true
        case .showSettingsCompleteSetupSection:
            if #available(iOS 18.2, *) {
                return true
            } else {
                return false
            }
        case .onboardingSetAsDefaultBrowserPiPVideo:
            if #available(iOS 18.2, *) {
                return true
            } else {
                return false
            }
        default:
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
        case .history:
            return .remoteReleasable(.feature(.history))
        case .newTabPageSections:
            return .remoteDevelopment(.feature(.newTabPageImprovements))
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
        case .networkProtectionRiskyDomainsProtection:
            return  .remoteReleasable(.subfeature(NetworkProtectionSubfeature.riskyDomainsProtection))
        case .privacyProAuthV2:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProAuthV2))
        case .onboardingSetAsDefaultBrowserPiPVideo:
            return .remoteReleasable(.subfeature(OnboardingSubfeature.setAsDefaultBrowserPiPVideoExperiment))
        case .failsafeExampleCrossPlatformFeature:
            return .remoteReleasable(.feature(.intentionallyLocalOnlyFeatureForTests))
        case .failsafeExamplePlatformSpecificSubfeature:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.intentionallyLocalOnlySubfeatureForTests))
        case .june2025TabManagerLayoutChanges:
            return .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.june2025TabManagerLayoutChanges))
        case .experimentalAIChat:
            return .internalOnly()
        case .experimentalSwitcherBarTransition:
            return .internalOnly()
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
        case .subscriptionRebranding:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.subscriptionRebranding))
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

public enum OnboardingSetAsDefaultBrowserPiPVideoCohort: String, FeatureFlagCohortDescribing {
    /// Control cohort with no changes applied.
    case control
    /// Treatment cohort where the experiment modifications are applied.
    case treatment
}
