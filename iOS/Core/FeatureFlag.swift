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

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214554020534806
    case heuristicAction

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

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1213433655862033?focus=true
    case dbpContinuedProcessing

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214085808544002
    case dbpFreemiumPIR

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215031617586670
    case dbpContentBlocking

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

    /// https://app.asana.com/1/137249556945/project/1142021229838617/task/1213320237636425?focus=true
    case onboardingDuckAIQueryExperiment

    /// https://app.asana.com/1/137249556945/project/1142021229838617/task/1214846580751519
    case onboardingDuckAIQueryTrackersDemoExperiment

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214336846806516?focus=true
    case onboardingDuckAIFlow

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

    /// Feature flag to gate the iOS 26.4+ data import hub routing.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213998785377466?focus=true
    case dataImportNewUI

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

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214965000466711?focus=true
    case aiChatSyncPromo

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212745919983886?focus=true
    case aiChatSuggestions

    /// https://app.asana.com/1/137249556945/project/1208671677432066/task/1213651262338059
    case aiChatContextualSheetImprovements

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212388316840466?focus=true
    case showWhatsNewPromptOnDemand

    /// https://app.asana.com/1/137249556945/project/1206488453854252/task/1212289671815991
    case unifiedToggleInput

    /// Failsafe flag for whether the free trial conversion wide event is enabled
    case freeTrialConversionWideEvent

    /// Shows tracker count banner in Tab Switcher and related settings item
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212632627091091?focus=true
    case tabSwitcherTrackerCount

    /// https://app.asana.com/1/137249556945/project/72649045549333/task/1213076120133808?focus=true
    case showNTPAfterIdleReturn

    /// https://app.asana.com/1/137249556945/project/1208671677432066/task/1213821747548995?focus=true
    case escapeHatchActions

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

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214974217398704?focus=true
    case appRebranding

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213001736131250?focus=true
    case webExtensions

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213380159275565?focus=true
    case embeddedExtension

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213278892205657?focus=true
    case forceDarkModeOnWebsites

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214001986307605?focus=true
    case autofillOnboardingDismissExperiment

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213725495563625
    case adBlockingExtension

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214534686173934
    case adBlockingExtensionEnabledByDefault

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212980785692854?focus=true
    case supportsSyncChatsDeletion

    /// https://app.asana.com/1/137249556945/task/1213314048601761
    case fireMode

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213965646075290
    case fireButtonRefinements

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

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214777651593367?focus=true
    case omniBarLongPressMenu

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214797978179697?focus=true
    case customProductPageDuckAiChat

    /// Gate the default-to-NTP-after-idle behavior for existing iPhone users behind a remote flag.
    /// https://app.asana.com/1/137249556945/project/1204186595873227/task/1214830562427843
    case defaultExistingIPhoneUsersToNewTabAfterIdle

    /// Coalesces tabManager.save into a debounced/max-wait window and moves the disk write off-main.
    /// Kill switch in case the new path regresses persistence reliability or hang counts.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215099690878849
    case tabsSaveOptimization

    /// Failsafe feature flag. Routes tapped .ics calendar links through EKEventEditViewController.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214740849233380
    case icsCalendarLinks

    /// Gates the Duck.ai shortcut in the iPad browser chrome (tabs bar).
    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1215105704317047
    case aiChatChromeShortcutIPad

    /// TODO: Add Asana task URL once final naming decided
    case syncScopedAccessCredentials

    /// TODO: Add Asana task URL once final naming decided
    case syncCanUseV2ConnectFlow

    /// TODO: Add Asana task URL once final naming decided
    case syncCanShowV2ConnectCode
}

extension FeatureFlag: FeatureFlagDescribing {
    /// Test-only cohort for verifying UI test experiment override mechanism.
    public enum UITestExperimentCohort: String, FeatureFlagCohortDescribing {
        case control
        case treatment
    }

    public enum AutofillOnboardingDismissExperimentCohort: String, FeatureFlagCohortDescribing {
        case control
        case variant1  // "Not Now"
        case variant2  // "Never for this site"
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
            Config(source: .remoteReleasable(SyncSubfeature.level0ShowSync), supportsLocalOverriding: false)
        case .autofillCredentialInjecting:
            Config(source: .remoteReleasable(AutofillSubfeature.credentialsAutofill), supportsLocalOverriding: false)
        case .autofillCredentialsSaving:
            Config(source: .remoteReleasable(AutofillSubfeature.credentialsSaving), supportsLocalOverriding: false)
        case .autofillInlineIconCredentials:
            Config(source: .remoteReleasable(AutofillSubfeature.inlineIconCredentials), supportsLocalOverriding: false)
        case .autofillAccessCredentialManagement:
            Config(source: .remoteReleasable(AutofillSubfeature.accessCredentialManagement), supportsLocalOverriding: false)
        case .autofillPasswordGeneration:
            Config(source: .remoteReleasable(AutofillSubfeature.autofillPasswordGeneration), supportsLocalOverriding: false)
        case .autofillOnByDefault:
            Config(source: .remoteReleasable(AutofillSubfeature.onByDefault), supportsLocalOverriding: false)
        case .autofillFailureReporting:
            Config(defaultValue: .enabled, source: .remoteReleasable(AutofillBreakageReporterSubfeature.featureEnabled), supportsLocalOverriding: false)
        case .autofillOnForExistingUsers:
            Config(source: .remoteReleasable(AutofillSubfeature.onForExistingUsers), supportsLocalOverriding: false)
        case .autofillUnknownUsernameCategorization:
            Config(source: .remoteReleasable(AutofillSubfeature.unknownUsernameCategorization), supportsLocalOverriding: false)
        case .autofillPartialFormSaves:
            Config(source: .remoteReleasable(AutofillSubfeature.partialFormSaves), supportsLocalOverriding: false)
        case .autofillCreditCards:
            Config(source: .remoteReleasable(AutofillSubfeature.autofillCreditCards), supportsLocalOverriding: false)
        case .autofillCreditCardsOnByDefault:
            Config(source: .remoteReleasable(AutofillSubfeature.autofillCreditCardsOnByDefault), supportsLocalOverriding: false)
        case .autocompleteAttributeSupport:
            Config(source: .remoteReleasable(AutofillSubfeature.autocompleteAttributeSupport))
        case .inputFocusApi:
            Config(source: .remoteReleasable(AutofillSubfeature.inputFocusApi), supportsLocalOverriding: false)
        case .incontextSignup:
            Config(defaultValue: .enabled, source: .remoteReleasable(IncontextSignupSubfeature.featureEnabled), supportsLocalOverriding: false)
        case .autoconsentOnByDefault:
            Config(source: .remoteReleasable(AutoconsentSubfeature.onByDefault), supportsLocalOverriding: false)
        case .heuristicAction:
            Config(source: .remoteReleasable(AutoconsentSubfeature.heuristicAction))
        case .duckPlayer:
            Config(source: .remoteReleasable(DuckPlayerSubfeature.enableDuckPlayer), supportsLocalOverriding: false)
        case .duckPlayerOpenInNewTab:
            Config(source: .remoteReleasable(DuckPlayerSubfeature.openInNewTab), supportsLocalOverriding: false)
        case .duckPlayerNativeUI:
            Config(source: .remoteReleasable(DuckPlayerSubfeature.nativeUI))
        case .syncPromotionBookmarks:
            Config(source: .remoteReleasable(SyncPromotionSubfeature.bookmarks), supportsLocalOverriding: false)
        case .syncPromotionPasswords:
            Config(source: .remoteReleasable(SyncPromotionSubfeature.passwords), supportsLocalOverriding: false)
        case .autofillSurveys:
            Config(defaultValue: .enabled, source: .remoteReleasable(AutofillSurveysSubfeature.featureEnabled), supportsLocalOverriding: false)
        case .adAttributionReporting:
            Config(defaultValue: .enabled, source: .remoteReleasable(AdAttributionReportingSubfeature.featureEnabled), supportsLocalOverriding: false)
        case .dbpRemoteBrokerDelivery:
            Config(source: .remoteReleasable(DBPSubfeature.remoteBrokerDelivery))
        case .dbpEmailConfirmationDecoupling:
            Config(source: .remoteReleasable(DBPSubfeature.emailConfirmationDecoupling))
        case .dbpForegroundRunningOnAppActive:
            Config(defaultValue: .enabled, source: .remoteReleasable(DBPSubfeature.foregroundRunningOnAppActive))
        case .dbpContinuedProcessing:
            Config(source: .remoteReleasable(DBPSubfeature.continuedProcessing))
        case .dbpFreemiumPIR:
            Config(source: .remoteReleasable(DBPSubfeature.freemiumPIR))
        case .dbpContentBlocking:
            Config(source: .remoteReleasable(DBPSubfeature.contentBlocking))
        case .crashReportOptInStatusResetting:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(iOSBrowserConfigSubfeature.crashReportOptInStatusResetting), supportsLocalOverriding: false)
        case .syncSeamlessAccountSwitching:
            Config(source: .remoteReleasable(SyncSubfeature.seamlessAccountSwitching), supportsLocalOverriding: false)
        case .maliciousSiteProtection:
            Config(source: .remoteReleasable(MaliciousSiteProtectionSubfeature.onByDefault))
        case .scamSiteProtection:
            Config(source: .remoteReleasable(MaliciousSiteProtectionSubfeature.scamProtection))
        case .experimentalAddressBar:
            Config(source: .remoteReleasable(AIChatSubfeature.experimentalAddressBar), supportsLocalOverriding: false)
        case .privacyProOnboardingPromotion:
            Config(source: .remoteReleasable(PrivacyProSubfeature.privacyProOnboardingPromotion))
        case .subscriptionPromoForReinstallers:
            Config(defaultValue: .enabled, source: .remoteReleasable(PrivacyProSubfeature.subscriptionPromoForReinstallers))
        case .syncSetupBarcodeIsUrlBased:
            Config(source: .remoteReleasable(SyncSubfeature.syncSetupBarcodeIsUrlBased))
        case .canScanUrlBasedSyncSetupBarcodes:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.canScanUrlBasedSyncSetupBarcodes))
        case .autofillPasswordVariantCategorization:
            Config(source: .remoteReleasable(AutofillSubfeature.passwordVariantCategorization))
        case .paidAIChat:
            Config(source: .remoteReleasable(PrivacyProSubfeature.paidAIChat))
        case .canInterceptSyncSetupUrls:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.canInterceptSyncSetupUrls))
        case .exchangeKeysToSyncWithAnotherDevice:
            Config(source: .remoteReleasable(SyncSubfeature.exchangeKeysToSyncWithAnotherDevice))
        case .aiChatKeepSession:
            Config(source: .remoteReleasable(AIChatSubfeature.keepSession), supportsLocalOverriding: false)
        case .showSettingsCompleteSetupSection:
            Config(source: .remoteReleasable(OnboardingSubfeature.showSettingsCompleteSetupSection))
        case .canPromoteImportPasswordsInPasswordManagement:
            Config(source: .remoteReleasable(AutofillSubfeature.canPromoteImportPasswordsInPasswordManagement), supportsLocalOverriding: false)
        case .canPromoteImportPasswordsInBrowser:
            Config(source: .remoteReleasable(AutofillSubfeature.canPromoteImportPasswordsInBrowser), supportsLocalOverriding: false)
        case .supportsAlternateStripePaymentFlow:
            Config(defaultValue: .enabled, source: .remoteReleasable(PrivacyProSubfeature.supportsAlternateStripePaymentFlow))
        case .personalInformationRemoval:
            Config(source: .remoteReleasable(DBPSubfeature.pirRollout))
        case .widgetReporting:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.widgetReporting), supportsLocalOverriding: false)
        case .createFireproofFaviconUpdaterSecureVaultInBackground:
            Config(defaultValue: .enabled, source: .remoteReleasable(AutofillSubfeature.createFireproofFaviconUpdaterSecureVaultInBackground))
        case .inactivityNotification:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.inactivityNotification))
        case .daxEasterEggLogos:
            Config(defaultValue: .enabled, source: .remoteReleasable(DaxEasterEggLogosSubfeature.featureEnabled))
        case .daxEasterEggPermanentLogo:
            Config(defaultValue: .enabled, source: .remoteReleasable(DaxEasterEggPermanentLogoSubfeature.featureEnabled))
        case .showAIChatAddressBarChoiceScreen:
            Config(source: .remoteReleasable(AIChatSubfeature.showAIChatAddressBarChoiceScreen))
        case .newDeviceSyncPrompt:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.newDeviceSyncPrompt), supportsLocalOverriding: false)
        case .syncAutoRestore:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.syncAutoRestore))
        case .winBackOffer:
            Config(source: .remoteReleasable(PrivacyProSubfeature.winBackOffer))
        case .blackFridayCampaign:
            Config(source: .remoteReleasable(PrivacyProSubfeature.blackFridayCampaign))
        case .syncCreditCards:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.syncCreditCards))
        case .unifiedURLPredictor:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.unifiedURLPredictor))
        case .vpnMenuItem:
            Config(source: .remoteReleasable(PrivacyProSubfeature.vpnMenuItem))
        case .forgetAllInSettings:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.forgetAllInSettings))
        case .fullDuckAIMode:
            Config(source: .remoteReleasable(AIChatSubfeature.fullDuckAIMode))
        case .iPadDuckaiOnTab:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.iPadDuckaiOnTab))
        case .iPadAIToggle:
            Config(source: .remoteReleasable(AIChatSubfeature.iPadAIChatToggle))
        case .attributedMetrics:
            Config(defaultValue: .enabled, source: .remoteReleasable(AttributedMetricsSubfeature.featureEnabled))
        case .onboardingDuckAIQueryExperiment:
            Config(source: .remoteReleasable(AIChatSubfeature.onboardingDuckAIQueryExperiment),
                   cohortType: DuckAIQueryExperimentCohort.self)
        case .onboardingDuckAIQueryTrackersDemoExperiment:
            Config(source: .remoteReleasable(AIChatSubfeature.onboardingDuckAIQueryTrackersDemoExperiment),
                   cohortType: DuckAIQueryExperimentCohort.self)
        case .onboardingDuckAIFlow:
            Config(source: .disabled, supportsLocalOverriding: true)
        case .storeSerpSettings:
            Config(source: .remoteReleasable(SERPSubfeature.storeSerpSettings))
        case .showHideAIGeneratedImagesSection:
            Config(source: .remoteReleasable(AIChatSubfeature.showHideAiGeneratedImages))
        case .standaloneMigration:
            Config(source: .remoteReleasable(AIChatSubfeature.standaloneMigration))
        case .allowProTierPurchase:
            Config(source: .remoteReleasable(PrivacyProSubfeature.allowProTierPurchase))
        case .autofillExtensionSettings:
            Config(source: .remoteReleasable(AutofillSubfeature.autofillExtensionSettings))
        case .canPromoteAutofillExtensionInBrowser:
            Config(source: .remoteReleasable(AutofillSubfeature.canPromoteAutofillExtensionInBrowser))
        case .canPromoteAutofillExtensionInPasswordManagement:
            Config(source: .remoteReleasable(AutofillSubfeature.canPromoteAutofillExtensionInPasswordManagement))
        case .migrateKeychainAccessibility:
            Config(defaultValue: .enabled, source: .remoteReleasable(AutofillSubfeature.migrateKeychainAccessibility), supportsLocalOverriding: false)
        case .productTelemeterySurfaceUsage:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.productTelemetrySurfaceUsage), supportsLocalOverriding: false)
        case .autofillPasswordSearchPrioritizeDomain:
            Config(defaultValue: .enabled, source: .remoteReleasable(AutofillSubfeature.autofillPasswordSearchPrioritizeDomain))
        case .dataImportSummarySyncPromotion:
            Config(defaultValue: .enabled, source: .remoteReleasable(DataImportSubfeature.dataImportSummarySyncPromotion))
        case .dataImportNewUI:
            Config(defaultValue: .enabled, source: .remoteReleasable(DataImportSubfeature.newDataImportExperience))
        case .appRatingPrompt:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.appRatingPrompt))
        case .contextualDuckAIMode:
            Config(source: .remoteReleasable(AIChatSubfeature.contextualDuckAIMode))
        case .pageContextFeature:
            Config(defaultValue: .enabled, source: .remoteReleasable(PageContextSubfeature.featureEnabled))
        case .aiChatAutoAttachContextByDefault:
            Config(source: .remoteReleasable(AIChatSubfeature.autoAttachContextByDefault))
        case .multiplePageContexts:
            Config(source: .remoteReleasable(AIChatSubfeature.multiplePageContexts))
        case .iPadPageContext:
            Config(source: .remoteReleasable(AIChatSubfeature.iPadPageContext))
        case .aiChatSync:
            Config(source: .remoteReleasable(SyncSubfeature.aiChatSync))
        case .aiChatSyncPromo:
            Config(source: .remoteReleasable(SyncSubfeature.aiChatSyncPromo))
        case .aiChatSuggestions:
            Config(defaultValue: .enabled, source: .remoteReleasable(DuckAiChatHistorySubfeature.featureEnabled))
        case .aiChatContextualSheetImprovements:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.contextualSheetImprovements))
        case .showWhatsNewPromptOnDemand:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.showWhatsNewPromptOnDemand))
        case .unifiedToggleInput:
            Config(source: .remoteReleasable(AIChatSubfeature.unifiedToggleInput))
        case .freeTrialConversionWideEvent:
            Config(defaultValue: .enabled, source: .remoteReleasable(PrivacyProSubfeature.freeTrialConversionWideEvent))
        case .tabSwitcherTrackerCount:
            Config(defaultValue: .enabled, source: .remoteReleasable(TabSwitcherTrackerCountSubfeature.featureEnabled))
        case .showNTPAfterIdleReturn:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.showNTPAfterIdleReturn))
        case .escapeHatchActions:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.escapeHatchActions))
        case .uiTestFeatureFlag:
            Config(source: .disabled)
        case .uiTestExperiment:
            Config(source: .disabled, cohortType: UITestExperimentCohort.self)
        case .genericBackgroundTask:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.genericBackgroundTask))
        case .crashCollectionLimitCallStackTreeDepth:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.crashCollectionLimitCallStackTreeDepth), supportsLocalOverriding: false)
        case .onboardingRebranding:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.onboardingRebranding))
        case .appRebranding:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.appRebranding))
        case .webExtensions:
            Config(defaultValue: .enabled, source: .remoteReleasable(WebExtensionsSubfeature.featureEnabled))
        case .embeddedExtension:
            Config(source: .remoteReleasable(WebExtensionsSubfeature.embeddedExtension))
        case .forceDarkModeOnWebsites:
            Config(source: .remoteReleasable(ForceDarkModeOnWebsitesSubfeature.featureRollout))
        case .adBlockingExtension:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(AdBlockingExtensionSubfeature.featureEnabled))
        case .adBlockingExtensionEnabledByDefault:
            Config(source: .remoteReleasable(AdBlockingExtensionSubfeature.featureEnabledByDefault))
        case .autofillOnboardingDismissExperiment:
            Config(source: .remoteReleasable(AutofillSubfeature.onboardingDismissExperiment), cohortType: AutofillOnboardingDismissExperimentCohort.self)
        case .supportsSyncChatsDeletion:
            Config(source: .remoteReleasable(AIChatSubfeature.supportsSyncChatsDeletion))
        case .fireMode:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.fireMode))
        case .fireButtonRefinements:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.fireButtonRefinements))
        case .simplifiedSyncSetupExperiment:
            Config(source: .remoteReleasable(SyncSubfeature.simplifiedSyncSetupExperiment), cohortType: SimplifiedSyncSetupExperimentCohort.self)
        case .aiChatOmnibarDefaultPosition:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.omnibarDefaultPosition))
        case .duckAIVoiceShortcut:
            Config(source: .remoteReleasable(AIChatSubfeature.voiceShortcut))
        case .fireproofingETLDPlus1:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.fireproofingETLDPlus1))
        case .screenTimeCleaning:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.screenTimeCleaning))
        case .aiChatContextualFireButton:
            Config(source: .remoteReleasable(AIChatSubfeature.contextualFireButton))
        case .minimalChromeInLandscape:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.minimalChromeInLandscape))
        case .aiChatNativeStorage:
            Config(source: .remoteReleasable(AIChatSubfeature.nativeStorage))
        case .aiChatNativeDataAccess:
            Config(source: .remoteReleasable(AIChatSubfeature.nativeDataAccess))
        case .omniBarLongPressMenu:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.omniBarLongPressMenu))
        case .customProductPageDuckAiChat:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.customProductPageDuckAiChat), supportsLocalOverriding: true)
        case .defaultExistingIPhoneUsersToNewTabAfterIdle:
            Config(source: .remoteReleasable(iOSBrowserConfigSubfeature.defaultExistingIPhoneUsersToNewTabAfterIdle))
        case .tabsSaveOptimization:
            Config(defaultValue: .enabled, source: .remoteReleasable(iOSBrowserConfigSubfeature.tabsSaveOptimization))
        case .icsCalendarLinks:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(iOSBrowserConfigSubfeature.icsCalendarLinks))
        case .aiChatChromeShortcutIPad:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(AIChatSubfeature.iPadChromeShortcut))
        case .syncScopedAccessCredentials:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.scopedAccessCredentials))
        case .syncCanUseV2ConnectFlow:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.canUseV2ConnectFlow))
        case .syncCanShowV2ConnectCode:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.canShowV2ConnectCode))
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
