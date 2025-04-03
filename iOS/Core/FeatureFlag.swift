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
    case incontextSignup
    case autoconsentOnByDefault
    case history
    case newTabPageSections
    case duckPlayer
    case duckPlayerOpenInNewTab
    case sslCertificatesBypass
    case syncPromotionBookmarks
    case syncPromotionPasswords
    case onboardingHighlights
    case onboardingAddToDock
    case autofillSurveys
    case autcompleteTabs
    case textZoom
    case adAttributionReporting
    case tabManagerMultiSelection
    
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

    /// https://app.asana.com/0/1204186595873227/1206489252288889
    case networkProtectionRiskyDomainsProtection

    /// Umbrella flag for experimental browser theming and appearance
    /// https://app.asana.com/0/1206226850447395/1209291055975934
    case experimentalBrowserTheming

    /// https://app.asana.com/0/1206488453854252/1208706841336530
    case privacyProOnboardingCTAMarch25

    /// https://app.asana.com/0/72649045549333/1207991044706236/f
    case privacyProAuthV2

    /// https://app.asana.com/0/1206329551987282/1209130794450271
    case onboardingSetAsDefaultBrowser

    /// https://app.asana.com/0/72649045549333/1209633877674689/f
    case exchangeKeysToSyncWithAnotherDevice
}

extension FeatureFlag: FeatureFlagDescribing {
    public var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
        case .privacyProFreeTrialJan25:
            PrivacyProFreeTrialExperimentCohort.self
        case .privacyProOnboardingCTAMarch25:
            PrivacyProOnboardingCTAMarch25Cohort.self
        case .onboardingSetAsDefaultBrowser:
            OnboardingSetAsDefaultBrowserCohort.self
        default:
            nil
        }
    }

    public static var localOverrideStoreName: String = "com.duckduckgo.app.featureFlag.localOverrides"

    public var supportsLocalOverriding: Bool {
        switch self {
        case .textZoom,
                .experimentalBrowserTheming,
                .privacyProOnboardingCTAMarch25,
                .networkProtectionRiskyDomainsProtection,
                .privacyProAuthV2,
                .scamSiteProtection,
                .maliciousSiteProtection,
                .exchangeKeysToSyncWithAnotherDevice:
            return true
        case .onboardingSetAsDefaultBrowser:
            if #available(iOS 18.3, *) {
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
        case .autcompleteTabs:
            return .remoteReleasable(.feature(.autocompleteTabs))
        case .textZoom:
            return .remoteReleasable(.feature(.textZoom))
        case .adAttributionReporting:
            return .remoteReleasable(.feature(.adAttributionReporting))
        case .crashReportOptInStatusResetting:
            return .internalOnly()
        case .privacyProFreeTrialJan25:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProFreeTrialJan25))
        case .tabManagerMultiSelection:
            return .remoteReleasable(.subfeature(TabManagerSubfeature.multiSelection))
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
        case .experimentalBrowserTheming:
            return .remoteDevelopment(.feature(.experimentalBrowserTheming))
        case .privacyProOnboardingCTAMarch25:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProOnboardingCTAMarch25))

        case .privacyProAuthV2:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProAuthV2))

        case .onboardingSetAsDefaultBrowser:
            return .remoteReleasable(.subfeature(OnboardingSubfeature.setAsDefaultBrowserExperiment))
        case .exchangeKeysToSyncWithAnotherDevice:
            return .remoteReleasable(.subfeature(SyncSubfeature.exchangeKeysToSyncWithAnotherDevice))
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

public enum PrivacyProOnboardingCTAMarch25Cohort: String, FeatureFlagCohortDescribing {
    /// Control cohort with no changes applied.
    case control
    /// Treatment cohort where the experiment modifications are applied.
    case treatment
}

public enum OnboardingSetAsDefaultBrowserCohort: String, FeatureFlagCohortDescribing {
    /// Control cohort with no changes applied.
    case control
    /// Treatment cohort where the experiment modifications are applied.
    case treatment
}
