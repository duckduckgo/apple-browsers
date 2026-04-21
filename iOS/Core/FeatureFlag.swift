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


    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866468307995
    case syncPromotionBookmarks

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866468401462
    case syncPromotionPasswords

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866711364768
    case autofillSurveys

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

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1213433655862033?focus=true
    case dbpContinuedProcessing

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

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213569392605475
    case subscriptionPromoForReinstallers

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

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212887107244162?focus=true
    case syncAutoRestore

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

    /// https://app.asana.com/1/137249556945/project/1199333091098016/task/1213962493484138?focus=true
    case vpnConnectionFailureLoopDetection

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614199859
    case forgetAllInSettings

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866614122594
    case fullDuckAIMode

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213227027157584
    case iPadDuckaiOnTab

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213313932650457
    case iPadAIToggle

    /// macOS: https://app.asana.com/1/137249556945/project/1211834678943996/task/1212015252281641
    /// iOS: https://app.asana.com/1/137249556945/project/1211834678943996/task/1212015250423471
    case attributedMetrics

    /// https://app.asana.com/1/137249556945/project/1211654189969294/task/1211652685709099?focus=true
    case onboardingSearchExperience

    /// https://app.asana.com/1/137249556945/project/1142021229838617/task/1213320237636425?focus=true
    case onboardingDuckAIQueryExperiment

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866472842661
    case storeSerpSettings

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715575447
    case showHideAIGeneratedImagesSection

    /// https://app.asana.com/1/137249556945/project/1201141132935289/task/1210497696306780?focus=true
    case standaloneMigration

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211998614203542?focus=true
    case allowProTierPurchase

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1208824174611454?focus=true
    case autofillExtensionSettings
    case canPromoteAutofillExtensionInBrowser
    case canPromoteAutofillExtensionInPasswordManagement

    /// https://app.asana.com/1/137249556945/project/1201462886803403/task/1211326076710245?focus=true
    case migrateKeychainAccessibility

    /// https://app.asana.com/1/137249556945/project/481882893211075/task/1212057154681076?focus=true
    case productTelemeterySurfaceUsage

    /// Sort domain matches higher than other matches when searching saved passwords
    /// https://app.asana.com/1/137249556945/project/1203822806345703/task/1212324661709006?focus=true
    case autofillPasswordSearchPrioritizeDomain

    /// Feature flag for new sync promotion footer in data import summary
    /// https://app.asana.com/1/137249556945/project/1203822806345703/task/1209629138021290?focus=true
    case dataImportSummarySyncPromotion

    // https://app.asana.com/1/137249556945/project/414709148257752/task/1212395110448661?focus=true
    case appRatingPrompt

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211652685709102?focus=true
    case contextualDuckAIMode

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211652685709102?focus=true
    case pageContextFeature

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1211652685709102?focus=true
    case aiChatAutoAttachContextByDefault

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213433942918287?focus=true
    case multiplePageContexts

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213608678718359?focus=true
    case iPadPageContext

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212980785692847?focus=true
    case aiChatSync

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212745919983886?focus=true
    case aiChatSuggestions

    /// https://app.asana.com/1/137249556945/project/1208671677432066/task/1213651262338059
    case aiChatContextualSheetImprovements

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212388316840466?focus=true
    case showWhatsNewPromptOnDemand

    /// https://app.asana.com/1/137249556945/project/1206488453854252/task/1212289671815991
    case unifiedToggleInput

    /// Whether the wide event POST endpoint is enabled
    /// https://app.asana.com/1/137249556945/project/1199333091098016/task/1212738953909168?focus=true
    case wideEventPostEndpoint

    /// Failsafe flag for whether the free trial conversion wide event is enabled
    case freeTrialConversionWideEvent

    /// Shows tracker count banner in Tab Switcher and related settings item
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212632627091091?focus=true
    case tabSwitcherTrackerCount

   /// https://app.asana.com/1/137249556945/project/72649045549333/task/1213076120133808?focus=true
    case showNTPAfterIdleReturn

    /// Test-only feature flag for verifying UI test override mechanism.
    /// Used in Debug > UI Test Overrides screen.
    case uiTestFeatureFlag

    /// Test-only experiment for verifying UI test experiment override mechanism.
    /// Used in Debug > UI Test Overrides screen.
    case uiTestExperiment

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212875994217788?focus=true
    case genericBackgroundTask

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213037858764805
    case crashCollectionLimitCallStackTreeDepth

    /// https://app.asana.com/1/137249556945/project/1206329551987282/task/1211806114021630?focus=true
    case onboardingRebranding

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213001736131250?focus=true
    case webExtensions

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213380159275565?focus=true
    case embeddedExtension

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213278892205657?focus=true
    case forceDarkModeOnWebsites


    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213725495563625
    case adBlockingExtension

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1208707884599795?focus=true
    case autofillOnboardingExperiment

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212980785692854?focus=true
    case supportsSyncChatsDeletion

    /// https://app.asana.com/1/137249556945/task/1213314048601761
    case fireMode

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213965646075290
    case fireButtonRefinements

    /// https://app.asana.com/1/137249556945/project/1202500774821704/task/1212559012504218
    case autoplayBlocking

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213617478454569?focus=true
    case simplifiedSyncSetupExperiment

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213728968355833?focus=true
    case aiChatOmnibarDefaultPosition

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213433942918287?focus=true
    case duckAIVoiceShortcut

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213687255181524
    case fireproofingETLDPlus1

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213813585476250?focus=true
    case screenTimeCleaning

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213763338305579?focus=true
    case aiChatContextualFireButton

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213809475913723?focus=true
    case minimalChromeInLandscape

    case aiChatNativeStorage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214025222413375
    case aiChatNativeDataAccess

    /// Failsafe feature flag. Filters intermediate redirect URLs from the address bar.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213972422695959
    case filterAddressBarUpdates
}

extension FeatureFlag: FeatureFlagDescribing {
    /// Test-only cohort for verifying UI test experiment override mechanism.
    public enum UITestExperimentCohort: String, FeatureFlagCohortDescribing {
        case control
        case treatment
    }

    public enum AutofillOnboardingExperimentCohort: String, FeatureFlagCohortDescribing {
        case control
        case variant1
        case variant2
        case variant3
    }

    public enum DuckAIQueryExperimentCohort: String, FeatureFlagCohortDescribing {
        /// Control cohort skips the experiment and keeps the existing onboarding flow.
        case control
        /// Treatment A shows experiment screen with "Duck.ai" selected by default.
        case treatmentA
        /// Treatment B shows experiment screen with "Search" selected by default.
        case treatmentB
    }

    public enum SimplifiedSyncSetupExperimentCohort: String, FeatureFlagCohortDescribing {
        case control
        case treatment
    }

    public static var localOverrideStoreName: String = "com.duckduckgo.app.featureFlag.localOverrides"

    private struct Config {
        let defaultValue: FeatureFlagDefaultValue
        let source: FeatureFlagSource
        let supportsLocalOverriding: Bool
        let cohortType: (any FeatureFlagCohortDescribing.Type)?

        init(
            defaultValue: FeatureFlagDefaultValue = .disabled,
            source: FeatureFlagSource,
            supportsLocalOverriding: Bool = true,
            cohortType: (any FeatureFlagCohortDescribing.Type)? = nil
        ) {
            self.defaultValue = defaultValue
            self.source = source
            self.supportsLocalOverriding = supportsLocalOverriding
            self.cohortType = cohortType
        }
    }

    private var config: Config {
        switch self {
        case .sync:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.level0ShowSync)), supportsLocalOverriding: false)
        case .autofillCredentialInjecting:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.credentialsAutofill)), supportsLocalOverriding: false)
        case .autofillCredentialsSaving:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.credentialsSaving)), supportsLocalOverriding: false)
        case .autofillInlineIconCredentials:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.inlineIconCredentials)), supportsLocalOverriding: false)
        case .autofillAccessCredentialManagement:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.accessCredentialManagement)), supportsLocalOverriding: false)
        case .autofillPasswordGeneration:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.autofillPasswordGeneration)), supportsLocalOverriding: false)
        case .autofillOnByDefault:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.onByDefault)), supportsLocalOverriding: false)
        case .autofillFailureReporting:
            Config(source: .remoteReleasable(.feature(.autofillBreakageReporter)), supportsLocalOverriding: false)
        case .autofillOnForExistingUsers:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.onForExistingUsers)), supportsLocalOverriding: false)
        case .autofillUnknownUsernameCategorization:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.unknownUsernameCategorization)), supportsLocalOverriding: false)
        case .autofillPartialFormSaves:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.partialFormSaves)), supportsLocalOverriding: false)
        case .autofillCreditCards:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.autofillCreditCards)), supportsLocalOverriding: false)
        case .autofillCreditCardsOnByDefault:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.autofillCreditCardsOnByDefault)), supportsLocalOverriding: false)
        case .autocompleteAttributeSupport:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.autocompleteAttributeSupport)))
        case .inputFocusApi:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.inputFocusApi)), supportsLocalOverriding: false)
        case .incontextSignup:
            Config(source: .remoteReleasable(.feature(.incontextSignup)), supportsLocalOverriding: false)
        case .autoconsentOnByDefault:
            Config(source: .remoteReleasable(.subfeature(AutoconsentSubfeature.onByDefault)), supportsLocalOverriding: false)
        case .duckPlayer:
            Config(source: .remoteReleasable(.subfeature(DuckPlayerSubfeature.enableDuckPlayer)), supportsLocalOverriding: false)
        case .duckPlayerOpenInNewTab:
            Config(source: .remoteReleasable(.subfeature(DuckPlayerSubfeature.openInNewTab)), supportsLocalOverriding: false)
        case .duckPlayerNativeUI:
            Config(source: .remoteReleasable(.subfeature(DuckPlayerSubfeature.nativeUI)))
        case .syncPromotionBookmarks:
            Config(source: .remoteReleasable(.subfeature(SyncPromotionSubfeature.bookmarks)), supportsLocalOverriding: false)
        case .syncPromotionPasswords:
            Config(source: .remoteReleasable(.subfeature(SyncPromotionSubfeature.passwords)), supportsLocalOverriding: false)
        case .autofillSurveys:
            Config(source: .remoteReleasable(.feature(.autofillSurveys)), supportsLocalOverriding: false)
        case .adAttributionReporting:
            Config(source: .remoteReleasable(.feature(.adAttributionReporting)), supportsLocalOverriding: false)
        case .dbpRemoteBrokerDelivery:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.remoteBrokerDelivery)))
        case .dbpEmailConfirmationDecoupling:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.emailConfirmationDecoupling)))
        case .dbpForegroundRunningOnAppActive:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(DBPSubfeature.foregroundRunningOnAppActive)))
        case .dbpForegroundRunningWhenDashboardOpen:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(DBPSubfeature.foregroundRunningWhenDashboardOpen)))
        case .dbpClickActionDelayReductionOptimization:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.clickActionDelayReductionOptimization)))
        case .dbpContinuedProcessing:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.continuedProcessing)))
        case .crashReportOptInStatusResetting:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.crashReportOptInStatusResetting)), supportsLocalOverriding: false)
        case .syncSeamlessAccountSwitching:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.seamlessAccountSwitching)), supportsLocalOverriding: false)
        case .maliciousSiteProtection:
            Config(source: .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.onByDefault)))
        case .scamSiteProtection:
            Config(source: .remoteReleasable(.subfeature(MaliciousSiteProtectionSubfeature.scamProtection)))
        case .experimentalAddressBar:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.experimentalAddressBar)), supportsLocalOverriding: false)
        case .privacyProOnboardingPromotion:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.privacyProOnboardingPromotion)))
        case .subscriptionPromoForReinstallers:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(PrivacyProSubfeature.subscriptionPromoForReinstallers)))
        case .syncSetupBarcodeIsUrlBased:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.syncSetupBarcodeIsUrlBased)))
        case .canScanUrlBasedSyncSetupBarcodes:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(SyncSubfeature.canScanUrlBasedSyncSetupBarcodes)))
        case .autofillPasswordVariantCategorization:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.passwordVariantCategorization)))
        case .paidAIChat:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.paidAIChat)))
        case .canInterceptSyncSetupUrls:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(SyncSubfeature.canInterceptSyncSetupUrls)))
        case .exchangeKeysToSyncWithAnotherDevice:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.exchangeKeysToSyncWithAnotherDevice)))
        case .aiChatKeepSession:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.keepSession)), supportsLocalOverriding: false)
        case .showSettingsCompleteSetupSection:
            Config(source: .remoteReleasable(.subfeature(OnboardingSubfeature.showSettingsCompleteSetupSection)))
        case .canPromoteImportPasswordsInPasswordManagement:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.canPromoteImportPasswordsInPasswordManagement)), supportsLocalOverriding: false)
        case .canPromoteImportPasswordsInBrowser:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.canPromoteImportPasswordsInBrowser)), supportsLocalOverriding: false)
        case .supportsAlternateStripePaymentFlow:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(PrivacyProSubfeature.supportsAlternateStripePaymentFlow)))
        case .personalInformationRemoval:
            Config(source: .remoteReleasable(.subfeature(DBPSubfeature.pirRollout)))
        case .widgetReporting:
            Config(source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.widgetReporting)), supportsLocalOverriding: false)
        case .createFireproofFaviconUpdaterSecureVaultInBackground:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AutofillSubfeature.createFireproofFaviconUpdaterSecureVaultInBackground)))
        case .inactivityNotification:
            Config(source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.inactivityNotification)))
        case .daxEasterEggLogos:
            Config(defaultValue: .enabled, source: .remoteReleasable(.feature(.daxEasterEggLogos)))
        case .daxEasterEggPermanentLogo:
            Config(defaultValue: .enabled, source: .remoteReleasable(.feature(.daxEasterEggPermanentLogo)))
        case .showAIChatAddressBarChoiceScreen:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.showAIChatAddressBarChoiceScreen)))
        case .newDeviceSyncPrompt:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(SyncSubfeature.newDeviceSyncPrompt)), supportsLocalOverriding: false)
        case .syncAutoRestore:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(SyncSubfeature.syncAutoRestore)))
        case .winBackOffer:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.winBackOffer)))
        case .blackFridayCampaign:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.blackFridayCampaign)))
        case .syncCreditCards:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(SyncSubfeature.syncCreditCards)))
        case .unifiedURLPredictor:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.unifiedURLPredictor)))
        case .vpnMenuItem:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.vpnMenuItem)))
        case .vpnConnectionFailureLoopDetection:
            Config(source: .remoteReleasable(.subfeature(NetworkProtectionSubfeature.connectionFailureLoopDetection)))
        case .forgetAllInSettings:
            Config(source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.forgetAllInSettings)))
        case .fullDuckAIMode:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.fullDuckAIMode)))
        case .iPadDuckaiOnTab:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.iPadDuckaiOnTab)))
        case .iPadAIToggle:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.iPadAIChatToggle)))
        case .attributedMetrics:
            Config(source: .remoteReleasable(.feature(.attributedMetrics)))
        case .onboardingSearchExperience:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.onboardingSearchExperience)))
        case .onboardingDuckAIQueryExperiment:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.onboardingDuckAIQueryExperiment)),
                   cohortType: DuckAIQueryExperimentCohort.self)
        case .storeSerpSettings:
            Config(source: .remoteReleasable(.subfeature(SERPSubfeature.storeSerpSettings)))
        case .showHideAIGeneratedImagesSection:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.showHideAiGeneratedImages)))
        case .standaloneMigration:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.standaloneMigration)))
        case .allowProTierPurchase:
            Config(source: .remoteReleasable(.subfeature(PrivacyProSubfeature.allowProTierPurchase)))
        case .autofillExtensionSettings:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.autofillExtensionSettings)))
        case .canPromoteAutofillExtensionInBrowser:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.canPromoteAutofillExtensionInBrowser)))
        case .canPromoteAutofillExtensionInPasswordManagement:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.canPromoteAutofillExtensionInPasswordManagement)))
        case .migrateKeychainAccessibility:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AutofillSubfeature.migrateKeychainAccessibility)), supportsLocalOverriding: false)
        case .productTelemeterySurfaceUsage:
            Config(source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.productTelemetrySurfaceUsage)), supportsLocalOverriding: false)
        case .autofillPasswordSearchPrioritizeDomain:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AutofillSubfeature.autofillPasswordSearchPrioritizeDomain)))
        case .dataImportSummarySyncPromotion:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(DataImportSubfeature.dataImportSummarySyncPromotion)))
        case .appRatingPrompt:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.appRatingPrompt)))
        case .contextualDuckAIMode:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.contextualDuckAIMode)))
        case .pageContextFeature:
            Config(source: .remoteReleasable(.feature(.pageContext)))
        case .aiChatAutoAttachContextByDefault:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.autoAttachContextByDefault)))
        case .multiplePageContexts:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.multiplePageContexts)))
        case .iPadPageContext:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.iPadPageContext)))
        case .aiChatSync:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.aiChatSync)))
        case .aiChatSuggestions:
            Config(source: .remoteReleasable(.feature(.duckAiChatHistory)))
        case .aiChatContextualSheetImprovements:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.contextualSheetImprovements)))
        case .showWhatsNewPromptOnDemand:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.showWhatsNewPromptOnDemand)))
        case .unifiedToggleInput:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.unifiedToggleInput)))
        case .wideEventPostEndpoint:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.wideEventPostEndpoint)))
        case .freeTrialConversionWideEvent:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(PrivacyProSubfeature.freeTrialConversionWideEvent)))
        case .tabSwitcherTrackerCount:
            Config(defaultValue: .enabled, source: .remoteReleasable(.feature(.tabSwitcherTrackerCount)))
        case .showNTPAfterIdleReturn:
            Config(source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.showNTPAfterIdleReturn)))
        case .uiTestFeatureFlag:
            Config(source: .disabled)
        case .uiTestExperiment:
            Config(source: .disabled, cohortType: UITestExperimentCohort.self)
        case .genericBackgroundTask:
            Config(source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.genericBackgroundTask)))
        case .crashCollectionLimitCallStackTreeDepth:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.crashCollectionLimitCallStackTreeDepth)), supportsLocalOverriding: false)
        case .onboardingRebranding:
            Config(source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.onboardingRebranding)))
        case .webExtensions:
            Config(source: .remoteReleasable(.feature(.webExtensions)))
        case .embeddedExtension:
            Config(source: .remoteReleasable(.subfeature(WebExtensionsSubfeature.embeddedExtension)))
        case .forceDarkModeOnWebsites:
            Config(source: .remoteReleasable(.subfeature(ForceDarkModeOnWebsitesSubfeature.featureRollout)))
        case .adBlockingExtension:
            Config(source: .remoteReleasable(.feature(.adBlockingExtension)))
        case .autofillOnboardingExperiment:
            Config(source: .remoteReleasable(.subfeature(AutofillSubfeature.onboardingExperiment)), cohortType: AutofillOnboardingExperimentCohort.self)
        case .supportsSyncChatsDeletion:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.supportsSyncChatsDeletion)))
        case .fireMode:
            Config(source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.fireMode)))
        case .fireButtonRefinements:
            Config(source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.fireButtonRefinements)))
        case .autoplayBlocking:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.autoplayBlocking)))
        case .simplifiedSyncSetupExperiment:
            Config(source: .remoteReleasable(.subfeature(SyncSubfeature.simplifiedSyncSetupExperiment)), cohortType: SimplifiedSyncSetupExperimentCohort.self)
        case .aiChatOmnibarDefaultPosition:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(AIChatSubfeature.omnibarDefaultPosition)))
        case .duckAIVoiceShortcut:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.voiceShortcut)))
        case .fireproofingETLDPlus1:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.fireproofingETLDPlus1)))
        case .screenTimeCleaning:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.screenTimeCleaning)))
        case .aiChatContextualFireButton:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.contextualFireButton)))
        case .minimalChromeInLandscape:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.minimalChromeInLandscape)))
        case .aiChatNativeStorage:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.nativeStorage)))
        case .aiChatNativeDataAccess:
            Config(source: .remoteReleasable(.subfeature(AIChatSubfeature.nativeDataAccess)))
        case .filterAddressBarUpdates:
            Config(defaultValue: .enabled, source: .remoteReleasable(.subfeature(iOSBrowserConfigSubfeature.filterAddressBarUpdates)))
        }
    }

    public var defaultValue: FeatureFlagDefaultValue { config.defaultValue }
    public var source: FeatureFlagSource { config.source }
    public var cohortType: (any FeatureFlagCohortDescribing.Type)? { config.cohortType }

    public var supportsLocalOverriding: Bool {
        switch self {
        case .showSettingsCompleteSetupSection:
            if #available(iOS 18.2, *) {
                return true
            } else {
                return false
            }
        default:
            return config.supportsLocalOverriding
        }
    }
}

extension FeatureFlagger {
    public func isFeatureOn(_ featureFlag: FeatureFlag) -> Bool {
        isFeatureOn(for: featureFlag)
    }
}
