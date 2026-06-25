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

    /// Gates the "Strict routing" VPN toggle.
    case vpnStrictRoutingToggle

    /// Gates the "Exclude Carrier-Grade NAT" VPN toggle.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214946884020610?focus=true
    case vpnExcludeCGNATToggle

    /// Kill switch: enable remotely to disable orphaned-proxy detection (tunnel heartbeat + proxy detection loop + pixel).
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215509351454304
    case vpnOrphanProxyDetectionKillSwitch

    /// Kill switch: enable remotely to disable the orphaned-proxy full-bypass behavior.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215509351454309
    case vpnOrphanProxyBypassKillSwitch

    /// Toggle for the Copy VPN Diagnostics button in VPN settings.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215794369750045
    case vpnShowCopyDiagnosticsButton

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615719736
    case autoUpdateInDEBUG

    /// Controls automatic update downloads in REVIEW builds (off by default)
    case autoUpdateInREVIEW

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866715515023
    case autofillPartialFormSaves

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866474376005
    case webExtensions

    /// Failsafe kill switch for the lightweight web-extension reload on data clear (fire). On by
    /// default; disable remotely to fall back to the full reload (`loadInstalledExtensions()`).
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215451266423288
    case webExtensionLightweightReload

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213380159275576
    case embeddedExtension

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213725495563625
    case adBlockingExtension

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214534686173932
    case adBlockingExtensionEnabledByDefault

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

    /// https://app.asana.com/1/137249556945/project/1206873150423133/task/1213344522599586
    case dbpWebViewUserAgent

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866717382557
    case syncSetupBarcodeIsUrlBased

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214232292928824
    case allowSingleDeviceOnConnectScreen

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615684438
    case exchangeKeysToSyncWithAnotherDevice

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866613117546
    case canScanUrlBasedSyncSetupBarcodes

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866617269950
    case paidAIChat

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866615582950
    case aiChatPageContext

    /// Enables the "Attach to Duck.ai" context-menu item that attaches selected text as the sidebar's page context
    case aiChatSelectionContext

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

    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1215385527516382?focus=true
    case aiChatOnboardingToggleAffectsNtpAndDdg

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866476152134
    case osSupportForceUnsupportedMessage

    /// Remote kill switch for native unsupported-OS messaging. Enabled by default; disable via
    /// privacy config (`macOSBrowserConfig.osSupportWarning`) to suppress the messaging.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215330116840129?focus=true
    case osSupportWarning

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

    /// Hide manual update option — always use automatic updates
    case automaticUpdatesOnly

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866720696560
    case unifiedURLPredictor

    /// Address-bar render-performance instrumentation kill switch.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214767817210667?focus=true
    case addressBarPerformanceInstrumentation

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

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866620524141
    case blurryAddressBarTahoeFix

    /// Prevents IME composition-confirm Return from submitting the address bar.
    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1214960575971803?focus=true
    case addressBarIMEConfirmFix

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1211866477623612
    case dataImportNewExperience

    /// https://app.asana.com/1/137249556945/project/1205842942115003/task/1210884473312053
    case attributedMetrics

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

    /// Shows a survey when quitting the app for the first time in a determined period
    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1212242893241885?focus=true
    case firstTimeQuitSurvey

    /// Suppresses the first-time quit survey when termination wasn't initiated by the user
    /// (Sparkle update relaunch, or system logout/restart/shutdown).
    case firstTimeQuitSurveySkipNonUserQuit

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

    /// Lazy favicon image loading (default-ON kill switch; off reverts to the legacy eager full-image cache).
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215720761295352
    case faviconLazyImageLoading

    /// Favicon storing improvements: store only the favicons the browser displays — drop favicons larger than the
    /// max display size (64 px), downscaling the single kept larger one — instead of storing every fetched favicon.
    /// Off follows the pre-existing path: every fetched favicon is stored at its original resolution.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215720760576164
    case faviconStoringImprovements

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1212901927858518?focus=true
    case aiChatSync

    /// Autoconsent heuristic action
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214554020534812?focus=true
    case heuristicAction

    /// Cookie Pop-up Preference picker in settings
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215960699028461?focus=true
    case cookiePopupPreferenceSetting

    /// Enables advanced card ordering for the Next Steps List widget
    /// This flag is disabled by default to allow testing the new widget design with current ordering logic
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213076052926663?focus=true
    case nextStepsListAdvancedCardOrdering

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

    /// Enables the reasoning effort picker in the Duck.ai omnibar
    case aiChatOmnibarReasoningEffort

    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1214283076614743?focus=true
    case aiChatOmnibarVoiceChatAccess

    /// Enables attaching content from multiple open tabs to the Duck.ai sidebar chat.
    /// https://app.asana.com/1/137249556945/task/1214804748957572?focus=true
    case aiChatSidebarAttachMoreTabs

    /// Enables attaching content from multiple open tabs to the Duck.ai omnibar (address bar) chat.
    /// https://app.asana.com/1/137249556945/task/1214804748957575?focus=true
    case aiChatOmnibarAttachMoreTabs

    /// https://app.asana.com/1/137249556945/task/1213316822018797
    case aiChatSidebarResizable

    /// https://app.asana.com/1/137249556945/project/1148564399326804/task/1213356927349370?focus=true
    case aiChatNtpRecentChats

    /// https://app.asana.com/1/137249556945/task/1213833143996469
    case aiChatNtpViewAllChats

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213622362394873
    case aiChatNtpChatTools

    /// https://app.asana.com/1/137249556945/project/1213083312441631/task/1213493651880757?focus=true
    case aiChatNtpImageGeneration

    /// https://app.asana.com/1/137249556945/project/1213083312441631/task/1213493672373295?focus=true
    case aiChatNtpWebSearch

    /// Enables attaching content from multiple open tabs (and files) to the New Tab Page omnibar Duck.ai chat.
    case aiChatNtpAttachMoreTabs

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213279513677422
    case aiChatSidebarFloating

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213610208091978?focus=true
    case aiChatChromeSidebar

    /// Enable Look Up (three-finger click) while keeping link preview disabled
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213489080183740
    case webViewLookUpAction

    /// Autoplay policy control via WKWebpagePreferences
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1213734484627619
    case autoplayPolicy

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

    /// https://app.asana.com/1/137249556945/project/1204006570077678/task/1213833143996468?focus=true
    case aiChatViewAllChatsNativeOmnibar

    case aiChatNativeStorage

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214025222413375
    case aiChatNativeDataAccess

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215798415697847
    /// Replaces the web-link Search Assist and Hide AI-Generated Images rows on the AI Features
    /// settings screen with native controls, regroups the main AI settings at the top, and adds the
    /// "Disable All AI Options" / Reset button. Off keeps today's web-link rows.
    case aiFeaturesNativeControls

    /// macOS only. Gates the native-driven Duck.ai voice-chat microphone permission flow
    /// (auto-grant at launch, locked Permission Center row, system-disabled warning UI,
    /// FE→native failure handler that surfaces the popover).
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214713654448759
    case aiChatNativeVoicePermissionFlow

    /// Enables the custom NSPanel-based bookmarks bar menu (replacing NSPopover) with NSGlassEffectView on macOS 26
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1214684208036378
    case bookmarksBarMenusCustomWindow

    /// Routes reload-after-error through `_evaluateJavaScriptWithoutUserGesture` instead of the
    /// legacy `javascript:` URL trampoline. Kill switch — disable remotely to fall back to the
    /// trampoline if the SPI ever misbehaves.
    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215026874168279
    case newErrorPageReload

    /// Shows a link in Settings → AI Features that opens the Duck.ai Settings modal.
    /// https://app.asana.com/1/137249556945/task/1214533186882448
    case aiChatSettingsLinkInAiFeatures

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215597855114757?focus=true
    case syncScopedAccessCredentials

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215597855114763?focus=true
    case syncCanUseV2ConnectFlow

    /// https://app.asana.com/1/137249556945/project/1211834678943996/task/1215597855114765?focus=true
    case syncCanShowV2ConnectCode

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
            Config(source: .remoteReleasable(MaliciousSiteProtectionSubfeature.onByDefault))
        case .scamSiteProtection:
            Config(source: .remoteReleasable(MaliciousSiteProtectionSubfeature.scamProtection))
        case .freemiumDBP:
            Config(source: .remoteReleasable(DBPSubfeature.freemium), supportsLocalOverriding: false)
        case .contextualOnboarding:
            Config(defaultValue: .enabled, source: .remoteReleasable(ContextualOnboardingSubfeature.featureEnabled), supportsLocalOverriding: false)
        case .onboardingRebranding:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.onboardingRebranding))
        case .unknownUsernameCategorization:
            Config(source: .remoteReleasable(AutofillSubfeature.unknownUsernameCategorization), supportsLocalOverriding: false)
        case .credentialsImportPromotionForExistingUsers:
            Config(source: .remoteReleasable(AutofillSubfeature.credentialsImportPromotionForExistingUsers), supportsLocalOverriding: false)
        case .networkProtectionAppStoreSysex:
            Config(source: .remoteReleasable(NetworkProtectionSubfeature.appStoreSystemExtension), category: .vpn)
        case .networkProtectionAppStoreSysexMessage:
            Config(source: .remoteReleasable(NetworkProtectionSubfeature.appStoreSystemExtensionMessage), category: .vpn)
        case .vpnStrictRoutingToggle:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(NetworkProtectionSubfeature.strictRoutingToggle), category: .vpn)
        case .vpnExcludeCGNATToggle:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(NetworkProtectionSubfeature.excludeCGNAT), category: .vpn)
        case .vpnOrphanProxyDetectionKillSwitch:
            Config(source: .remoteReleasable(NetworkProtectionSubfeature.orphanProxyDetectionKillSwitch), category: .vpn)
        case .vpnOrphanProxyBypassKillSwitch:
            Config(source: .remoteReleasable(NetworkProtectionSubfeature.orphanProxyBypassKillSwitch), category: .vpn)
        case .vpnShowCopyDiagnosticsButton:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(NetworkProtectionSubfeature.showCopyDiagnosticsButton), category: .vpn)
        case .autoUpdateInDEBUG:
            Config(source: .disabled, category: .updates)
        case .autoUpdateInREVIEW:
            Config(source: .disabled, category: .updates)
        case .autofillPartialFormSaves:
            Config(source: .remoteReleasable(AutofillSubfeature.partialFormSaves))
        case .webExtensions:
            Config(defaultValue: .enabled, source: .remoteReleasable(WebExtensionsSubfeature.featureEnabled), category: .webExtensions)
        case .webExtensionLightweightReload:
            Config(defaultValue: .enabled, source: .remoteReleasable(WebExtensionsSubfeature.lightweightReloadOnDataClear), category: .webExtensions)
        case .embeddedExtension:
            Config(source: .remoteReleasable(WebExtensionsSubfeature.embeddedExtension), category: .webExtensions)
        case .adBlockingExtension:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(AdBlockingExtensionSubfeature.featureEnabled), category: .adBlocking)
        case .adBlockingExtensionEnabledByDefault:
            Config(source: .remoteReleasable(AdBlockingExtensionSubfeature.featureEnabledByDefault), category: .adBlocking)
        case .forceDarkModeOnWebsites:
            Config(source: .remoteReleasable(ForceDarkModeOnWebsitesSubfeature.featureRollout), category: .webExtensions)
        case .syncSeamlessAccountSwitching:
            Config(source: .remoteReleasable(SyncSubfeature.seamlessAccountSwitching), category: .sync)
        case .tabCrashDebugging:
            Config(source: .disabled)
        case .delayedWebviewPresentation:
            Config(defaultValue: .enabled, source: .remoteReleasable(DelayedWebviewPresentationSubfeature.featureEnabled))
        case .dbpRemoteBrokerDelivery:
            Config(source: .remoteReleasable(DBPSubfeature.remoteBrokerDelivery), category: .dbp)
        case .dbpEmailConfirmationDecoupling:
            Config(source: .remoteReleasable(DBPSubfeature.emailConfirmationDecoupling), category: .dbp)
        case .dbpWebViewUserAgent:
            Config(source: .remoteReleasable(DBPSubfeature.webViewUserAgent), supportsLocalOverriding: true, category: .dbp)
        case .syncSetupBarcodeIsUrlBased:
            Config(source: .remoteReleasable(SyncSubfeature.syncSetupBarcodeIsUrlBased), category: .sync)
        case .allowSingleDeviceOnConnectScreen:
            Config(source: .remoteReleasable(SyncSubfeature.allowSingleDeviceOnConnectScreen), category: .sync)
        case .exchangeKeysToSyncWithAnotherDevice:
            Config(source: .remoteReleasable(SyncSubfeature.exchangeKeysToSyncWithAnotherDevice), category: .sync)
        case .canScanUrlBasedSyncSetupBarcodes:
            Config(source: .remoteReleasable(SyncSubfeature.canScanUrlBasedSyncSetupBarcodes), category: .sync)
        case .paidAIChat:
            Config(source: .remoteReleasable(PrivacyProSubfeature.paidAIChat), category: .subscription)
        case .aiChatPageContext:
            Config(source: .remoteReleasable(AIChatSubfeature.pageContext), category: .duckAI)
        case .aiChatSelectionContext:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.selectionContext), category: .duckAI)
        case .aiChatKeepSession:
            Config(source: .remoteReleasable(AIChatSubfeature.keepSession), category: .duckAI)
        case .aiChatOmnibarToggle:
            Config(source: .remoteReleasable(AIChatSubfeature.omnibarToggle), category: .duckAI)
        case .aiChatOmnibarCluster:
            Config(source: .remoteReleasable(AIChatSubfeature.omnibarCluster), category: .duckAI)
        case .aiChatSuggestions:
            Config(defaultValue: .enabled, source: .remoteReleasable(DuckAiChatHistorySubfeature.featureEnabled), category: .duckAI)
        case .aiChatOmnibarTools:
            Config(source: .remoteReleasable(AIChatSubfeature.omnibarTools), category: .duckAI)
        case .aiChatOmnibarOnboarding:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.omnibarOnboarding), category: .duckAI)
        case .aiChatOnboardingToggleAffectsNtpAndDdg:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.onboardingToggleAffectsNtpAndDdg), category: .duckAI)
        case .osSupportForceUnsupportedMessage:
            Config(source: .disabled, category: .osSupportWarnings)
        case .osSupportWarning:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.osSupportWarning), category: .osSupportWarnings)
        case .hangReporting:
            Config(source: .remoteReleasable(MacOSBrowserConfigSubfeature.hangReporting))
        case .newTabPageOmnibar:
            Config(source: .remoteReleasable(HtmlNewTabPageSubfeature.omnibar))
        case .newTabPageTabIDs:
            Config(source: .remoteReleasable(HtmlNewTabPageSubfeature.newTabPageTabIDs))
        case .supportsAlternateStripePaymentFlow:
            Config(defaultValue: .enabled, source: .remoteReleasable(PrivacyProSubfeature.supportsAlternateStripePaymentFlow), category: .subscription)
        case .refactorOfSyncPreferences:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.refactorOfSyncPreferences))
        case .newSyncEntryPoints:
            Config(source: .remoteReleasable(SyncSubfeature.newSyncEntryPoints))
        case .syncFeatureLevel3:
            Config(source: .remoteReleasable(SyncSubfeature.level3AllowCreateAccount))
        case .automaticUpdatesOnly:
            Config(source: .remoteReleasable(MacOSBrowserConfigSubfeature.automaticUpdatesOnly), category: .updates)
        case .unifiedURLPredictor:
            Config(source: .remoteReleasable(MacOSBrowserConfigSubfeature.unifiedURLPredictor))
        case .addressBarPerformanceInstrumentation:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.addressBarPerformanceInstrumentation))
        case .winBackOffer:
            Config(source: .remoteReleasable(PrivacyProSubfeature.winBackOffer), category: .vpn)
        case .blackFridayCampaign:
            Config(source: .remoteReleasable(PrivacyProSubfeature.blackFridayCampaign), category: .subscription)
        case .syncCreditCards:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.syncCreditCards))
        case .syncIdentities:
            Config(defaultValue: .enabled, source: .remoteReleasable(SyncSubfeature.syncIdentities))
        case .dataImportNewSafariFilePicker:
            Config(defaultValue: .enabled, source: .remoteReleasable(DataImportSubfeature.newSafariFilePicker))
        case .blurryAddressBarTahoeFix:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.blurryAddressBarTahoeFix))
        case .addressBarIMEConfirmFix:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.addressBarIMEConfirmFix))
        case .dataImportNewExperience:
            Config(source: .remoteReleasable(DataImportSubfeature.newDataImportExperience))
        case .attributedMetrics:
            Config(defaultValue: .enabled, source: .remoteReleasable(AttributedMetricsSubfeature.featureEnabled))
        case .standaloneMigration:
            Config(source: .remoteReleasable(AIChatSubfeature.standaloneMigration), category: .duckAI)
        case .allowProTierPurchase:
            Config(source: .remoteReleasable(PrivacyProSubfeature.allowProTierPurchase), category: .subscription)
        case .popupBlocking:
            Config(defaultValue: .enabled, source: .remoteReleasable(PopupBlockingSubfeature.featureEnabled), category: .popupBlocking)
        case .webNotifications:
            Config(source: .remoteReleasable(MacOSBrowserConfigSubfeature.webNotifications), category: .webNotifications)
        case .firstTimeQuitSurvey:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.firstTimeQuitSurvey))
        case .firstTimeQuitSurveySkipNonUserQuit:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.firstTimeQuitSurveySkipNonUserQuit))
        case .autofillPasswordSearchPrioritizeDomain:
            Config(defaultValue: .enabled, source: .remoteReleasable(AutofillSubfeature.autofillPasswordSearchPrioritizeDomain))
        case .autofillPasswordsStatusBar:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(AutofillSubfeature.autofillPasswordsStatusBar))
        case .warnBeforeQuit:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.warnBeforeQuit))
        case .memoryUsageMonitor:
            Config(source: .disabled)
        case .memoryUsageReporting:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.memoryUsageReporting))
        case .faviconLazyImageLoading:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.faviconLazyImageLoading))
        case .faviconStoringImprovements:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.faviconStoringImprovements))
        case .aiChatSync:
            Config(source: .remoteReleasable(SyncSubfeature.aiChatSync))
        case .heuristicAction:
            Config(source: .remoteReleasable(AutoconsentSubfeature.heuristicAction), cohortType: HeuristicActionCohort.self)
        case .cookiePopupPreferenceSetting:
            Config(source: .remoteReleasable(AutoconsentSubfeature.cookiePopupPreferenceSetting), category: .popupBlocking)
        case .nextStepsListAdvancedCardOrdering:
            Config(source: .disabled)
        case .crashCollectionLimitCallStackTreeDepth:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.crashCollectionLimitCallStackTreeDepth), supportsLocalOverriding: false)
        case .freeTrialConversionWideEvent:
            Config(defaultValue: .enabled, source: .remoteReleasable(PrivacyProSubfeature.freeTrialConversionWideEvent))
        case .supportsSyncChatsDeletion:
            Config(source: .remoteReleasable(AIChatSubfeature.supportsSyncChatsDeletion))
        case .aiChatMultiplePageContexts:
            Config(source: .remoteReleasable(AIChatSubfeature.multiplePageContexts), category: .duckAI)
        case .aiChatOmnibarImageGeneration:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.omnibarImageGeneration), category: .duckAI)
        case .aiChatOmnibarWebSearch:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.omnibarWebSearch), category: .duckAI)
        case .aiChatOmnibarReasoningEffort:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.omnibarReasoningEffort), category: .duckAI)
        case .aiChatOmnibarVoiceChatAccess:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.omnibarVoiceChatAccess), category: .duckAI)
        case .aiChatSidebarAttachMoreTabs:
            Config(source: .remoteReleasable(AIChatSubfeature.sidebarAttachMoreTabs), category: .duckAI)
        case .aiChatOmnibarAttachMoreTabs:
            Config(source: .remoteReleasable(AIChatSubfeature.omnibarAttachMoreTabs), category: .duckAI)
        case .aiChatSidebarResizable:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.sidebarResizable), category: .duckAI)
        case .aiChatNtpRecentChats:
            Config(source: .remoteReleasable(AIChatSubfeature.ntpRecentChats), category: .duckAI)
        case .aiChatNtpViewAllChats:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.ntpViewAllChats), category: .duckAI)
        case .aiChatNtpChatTools:
            Config(source: .remoteReleasable(AIChatSubfeature.ntpChatTools), category: .duckAI)
        case .aiChatNtpImageGeneration:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.ntpImageGeneration), category: .duckAI)
        case .aiChatNtpWebSearch:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.ntpWebSearch), category: .duckAI)
        case .aiChatNtpAttachMoreTabs:
            Config(source: .remoteReleasable(AIChatSubfeature.ntpAttachMoreTabs), category: .duckAI)
        case .aiChatSidebarFloating:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(AIChatSubfeature.sidebarFloating), category: .duckAI)
        case .aiChatChromeSidebar:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.sidebar), category: .duckAI)
        case .webViewLookUpAction:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.webViewLookUpAction))
        case .promoQueue:
            Config(defaultValue: .enabled, source: .remoteReleasable(PromoQueueSubfeature.featureEnabled))
        case .websitesHistoryFirstTimeQuitSurvey:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.websitesHistoryFirstTimeQuitSurvey))
        case .tabAnimations:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.tabAnimations))
        case .lazyMenuRebuild:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.lazyMenuRebuild))
        case .aiChatRemoveSuggestion:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(AIChatSubfeature.removeSuggestion), category: .duckAI)
        case .screenTimeCleaning:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.screenTimeCleaning))
        case .tabSuspension:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(TabSuspensionSubfeature.memoryPressureTrigger))
        case .tabSuspensionDebugging:
            Config(source: .disabled)
        case .aiChatMoreOptionsMenuShortcut:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.moreOptionsMenuShortcut), category: .duckAI)
        case .aiChatMainMenuShortcut:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.mainMenuShortcut), category: .duckAI)
        case .aiChatSidebarAboutSchemeNavigationFix:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.sidebarAboutSchemeNavigationFix), category: .duckAI)
        case .aiChatViewAllChatsNativeOmnibar:
            Config(defaultValue: .enabled,
                   source: .remoteReleasable(AIChatSubfeature.viewAllChatsNativeOmnibar),
                   category: .duckAI)
        case .aiChatNativeStorage:
            Config(source: .remoteReleasable(AIChatSubfeature.nativeStorage), category: .duckAI)
        case .aiChatNativeDataAccess:
            Config(source: .remoteReleasable(AIChatSubfeature.nativeDataAccess), category: .duckAI)
        case .aiFeaturesNativeControls:
            Config(defaultValue: .internalOnly, source: .remoteReleasable(AIChatSubfeature.aiFeaturesNativeControls), category: .duckAI)
        case .aiChatNativeVoicePermissionFlow:
            Config(defaultValue: .enabled,
                   source: .remoteReleasable(AIChatSubfeature.nativeVoicePermissionFlow),
                   supportsLocalOverriding: true,
                   category: .duckAI)
        case .autoplayPolicy:
            Config(defaultValue: .disabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.autoplayPolicy), supportsLocalOverriding: true)
        case .bookmarksBarMenusCustomWindow:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.bookmarksBarMenusCustomWindow))
        case .newErrorPageReload:
            Config(defaultValue: .enabled, source: .remoteReleasable(MacOSBrowserConfigSubfeature.newErrorPageReload))
        case .aiChatSettingsLinkInAiFeatures:
            Config(defaultValue: .enabled, source: .remoteReleasable(AIChatSubfeature.settingsLinkInAiFeatures), category: .duckAI)
        case .syncScopedAccessCredentials:
            Config(source: .remoteReleasable(SyncSubfeature.scopedAccessCredentials), category: .sync)
        case .syncCanUseV2ConnectFlow:
            Config(source: .remoteReleasable(SyncSubfeature.canUseV2ConnectFlow), category: .sync)
        case .syncCanShowV2ConnectCode:
            Config(source: .remoteReleasable(SyncSubfeature.canShowV2ConnectCode), category: .sync)
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
