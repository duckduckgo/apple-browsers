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
    case debugMenu
    case sslCertificatesBypass
    case maliciousSiteProtection
    case scamSiteProtection

    /// Add experimental atb parameter to SERP queries for internal users to display Privacy Reminder
    /// https://app.asana.com/0/1199230911884351/1205979030848528/f
    case appendAtbToSerpQueries

    // https://app.asana.com/0/1206488453854252/1207136666798700/f
    case freemiumDBP

    case contextualOnboarding

    // https://app.asana.com/0/1201462886803403/1208030658792310/f
    case unknownUsernameCategorization

    case credentialsImportPromotionForExistingUsers

    /// https://app.asana.com/0/0/1209150117333883/f
    case networkProtectionAppExclusions

    /// https://app.asana.com/0/0/1209402073283584
    case networkProtectionAppStoreSysex

    /// https://app.asana.com/0/1203108348835387/1209710972679271/f
    case networkProtectionAppStoreSysexMessage

    /// https://app.asana.com/0/1204186595873227/1206489252288889
    case networkProtectionRiskyDomainsProtection

    /// https://app.asana.com/0/1201048563534612/1208850443048685/f
    case historyView

    case autoUpdateInDEBUG

    case autofillPartialFormSaves
    case autocompleteTabs
    case webExtensions
    case syncSeamlessAccountSwitching
    /// SAD & ATT Prompts experiiment: https://app.asana.com/0/1204006570077678/1209185383520514
    case popoverVsBannerExperiment

    /// https://app.asana.com/0/72649045549333/1207991044706236/f
    case privacyProAuthV2

    /// https://app.asana.com/0/72649045549333/1209633877674689/f
    case exchangeKeysToSyncWithAnotherDevice

    // Demonstrative cases for default value. Remove once a real-world feature/subfeature is added
    case failsafeExampleCrossPlatformFeature
    case failsafeExamplePlatformSpecificSubfeature

    /// https://app.asana.com/0/72649045549333/1209793701087222/f
    case visualRefresh

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1209227311680179?focus=true
    case tabCrashDebugging

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1209227311680179?focus=true
    case tabCrashRecovery

    /// https://app.asana.com/1/137249556945/project/1148564399326804/task/1209499005452053?focus=true
    case delayedWebviewPresentation
}

extension FeatureFlag: FeatureFlagDescribing {
    public var defaultValue: Bool {
        switch self {
        case .failsafeExampleCrossPlatformFeature, .failsafeExamplePlatformSpecificSubfeature:
            true
        default:
            false
        }
    }

    public var cohortType: (any FeatureFlagCohortDescribing.Type)? {
        switch self {
        case .popoverVsBannerExperiment:
            return PopoverVSBannerExperimentCohort.self
        default:
            return nil
        }
    }

    public enum PopoverVSBannerExperimentCohort: String, FeatureFlagCohortDescribing {
        case control
        case popover
        case banner
     }

    public var supportsLocalOverriding: Bool {
        switch self {
        case .autofillPartialFormSaves,
                .autocompleteTabs,
                .networkProtectionAppExclusions,
                .networkProtectionAppStoreSysex,
                .networkProtectionAppStoreSysexMessage,
                .networkProtectionRiskyDomainsProtection,
                .syncSeamlessAccountSwitching,
                .historyView,
                .webExtensions,
                .autoUpdateInDEBUG,
                .popoverVsBannerExperiment,
                .privacyProAuthV2,
                .scamSiteProtection,
                .exchangeKeysToSyncWithAnotherDevice,
                .failsafeExampleCrossPlatformFeature,
                .failsafeExamplePlatformSpecificSubfeature,
                .visualRefresh,
                .tabCrashDebugging,
                .tabCrashRecovery,
                .delayedWebviewPresentation:
            return true
        case .debugMenu,
                .sslCertificatesBypass,
                .appendAtbToSerpQueries,
                .freemiumDBP,
                .contextualOnboarding,
                .unknownUsernameCategorization,
                .credentialsImportPromotionForExistingUsers,
                .maliciousSiteProtection:
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
        case .networkProtectionAppExclusions:
            return .remoteReleasable(.subfeature(NetworkProtectionSubfeature.appExclusions))
        case .networkProtectionAppStoreSysex:
            return .remoteReleasable(.subfeature(NetworkProtectionSubfeature.appStoreSystemExtension))
        case .networkProtectionAppStoreSysexMessage:
            return .remoteReleasable(.subfeature(NetworkProtectionSubfeature.appStoreSystemExtensionMessage))
        case .historyView:
            return .remoteReleasable(.subfeature(HTMLHistoryPageSubfeature.isLaunched))
        case .autoUpdateInDEBUG:
            return .disabled
        case .autofillPartialFormSaves:
            return .remoteReleasable(.subfeature(AutofillSubfeature.partialFormSaves))
        case .autocompleteTabs:
            return .remoteReleasable(.feature(.autocompleteTabs))
        case .webExtensions:
            return .internalOnly()
        case .syncSeamlessAccountSwitching:
            return .remoteReleasable(.subfeature(SyncSubfeature.seamlessAccountSwitching))
        case .scamSiteProtection:
            return .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.scamProtection))
        case .networkProtectionRiskyDomainsProtection:
            return .remoteReleasable(.subfeature(NetworkProtectionSubfeature.riskyDomainsProtection))
        case .popoverVsBannerExperiment:
            return .remoteReleasable(.subfeature(SetAsDefaultAndAddToDockSubfeature.popoverVsBannerExperiment))
        case .privacyProAuthV2:
            return .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProAuthV2))
        case .exchangeKeysToSyncWithAnotherDevice:
            return .remoteReleasable(.subfeature(SyncSubfeature.exchangeKeysToSyncWithAnotherDevice))
        case .failsafeExampleCrossPlatformFeature:
            return .remoteReleasable(.feature(.intentionallyLocalOnlyFeatureForTests))
        case .failsafeExamplePlatformSpecificSubfeature:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.intentionallyLocalOnlySubfeatureForTests))
        case .visualRefresh:
            return .remoteDevelopment(.feature(.experimentalBrowserTheming))
        case .tabCrashDebugging:
            return .disabled
        case .tabCrashRecovery:
            return .remoteReleasable(.feature(.tabCrashRecovery))
        case .delayedWebviewPresentation:
            return .remoteReleasable(.feature(.delayedWebviewPresentation))
        }
    }
}

public extension FeatureFlagger {

    func isFeatureOn(_ featureFlag: FeatureFlag) -> Bool {
        isFeatureOn(for: featureFlag)
    }
}
