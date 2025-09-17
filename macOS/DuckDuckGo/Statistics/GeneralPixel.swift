//
//  GeneralPixel.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import AppKit
import PixelKit
import BrowserServicesKit
import DDGSync
import Configuration

enum GeneralPixel: PixelKitEvent {

    case crash(appIdentifier: CrashPixelAppIdentifier?)
    case crashOnCrashHandlersSetUp
    case crashReportingSubmissionFailed
    case crashReportCRCIDMissing
    case compileRulesWait(onboardingShown: OnboardingShown, waitTime: CompileRulesWaitTime, result: WaitResult)
    case launch
    case dailyActiveUser(isDefault: Bool, isAddedToDock: Bool?)
    case dailyFireWindowConfiguration(startupFireWindow: Bool, openFireWindowByDefault: Bool, fireAnimationEnabled: Bool)

    case navigation(NavigationKind)
    case navigationToExternalURL
    case serp
    case serpInitial

    case dailyOsVersionCounter

    case dataImportFailed(source: String, sourceVersion: String?, error: any DataImportError)
    case dataImportSucceeded(action: DataImportAction, source: String, sourceVersion: String?)
    case favoritesImportFailed(source: String, sourceVersion: String?, error: Error)
    case favoritesImportSucceeded(source: String, sourceVersion: String?, favoritesBucket: FavoritesImportBucket)

    case formAutofilled(kind: FormAutofillKind)
    case autofillItemSaved(kind: FormAutofillKind)

    case autofillLoginsSaveLoginInlineDisplayed
    case autofillLoginsSaveLoginInlineConfirmed
    case autofillLoginsSaveLoginInlineDismissed

    case autofillLoginsSavePasswordInlineDisplayed
    case autofillLoginsSavePasswordInlineConfirmed
    case autofillLoginsSavePasswordInlineDismissed

    case autofillLoginsSaveLoginModalExcludeSiteConfirmed
    case autofillLoginsSettingsResetExcludedDisplayed
    case autofillLoginsSettingsResetExcludedConfirmed
    case autofillLoginsSettingsResetExcludedDismissed

    case autofillLoginsUpdatePasswordInlineDisplayed
    case autofillLoginsUpdatePasswordInlineConfirmed
    case autofillLoginsUpdatePasswordInlineDismissed

    case autofillLoginsUpdateUsernameInlineDisplayed
    case autofillLoginsUpdateUsernameInlineConfirmed
    case autofillLoginsUpdateUsernameInlineDismissed

    case autofillActiveUser
    case autofillEnabledUser
    case autofillOnboardedUser
    case autofillToggledOn
    case autofillToggledOff
    case autofillLoginsStacked
    case autofillCreditCardsStacked
    case autofillIdentitiesStacked

    case autofillManagementOpened
    case autofillManagementCopyUsername
    case autofillManagementCopyPassword
    case autofillManagementDeleteLogin
    case autofillManagementDeleteAllLogins
    case autofillManagementSaveLogin
    case autofillManagementUpdateLogin

    case autofillLoginsSettingsEnabled
    case autofillLoginsSettingsDisabled

    case bitwardenPasswordAutofilled
    case bitwardenPasswordSaved

    case ampBlockingRulesCompilationFailed

    case adClickAttributionDetected
    case adClickAttributionActive
    case adClickAttributionPageLoads

    case jsPixel(_ pixel: AutofillUserScript.JSPixel)

    // Activation Points
    case newTabInitial
    case emailEnabledInitial
    case watchInDuckPlayerInitial
    case setAsDefaultInitial
    case importDataInitial

    // New Tab section removed
    case continueSetUpSectionHidden

    // Fire Button
    case fireButtonFirstBurn
    case fireButton(option: FireButtonOption)
    case fireAnimationSetting(enabled: Bool)

    /**
     * Event Trigger: User opens the fire popover (fire button details view).
     *
     * > Note: This is a daily pixel.
     *
     * Anomaly Investigation:
     * - May indicate changes in user awareness of privacy clearing features.
     * - Increase could suggest browser cache is causing issues.
     */
    case fireButtonDetailsViewed

    // Duck Player
    case duckPlayerDailyUniqueView
    case duckPlayerWeeklyUniqueView
    case duckPlayerViewFromYoutubeViaMainOverlay
    case duckPlayerViewFromYoutubeViaHoverButton
    case duckPlayerViewFromYoutubeAutomatic
    case duckPlayerViewFromSERP
    case duckPlayerViewFromOther
    case duckPlayerOverlayYoutubeImpressions
    case duckPlayerOverlayYoutubeWatchHere
    case duckPlayerSettingAlwaysDuckPlayer
    case duckPlayerSettingAlwaysOverlaySERP
    case duckPlayerSettingAlwaysOverlayYoutube
    case duckPlayerSettingAlwaysSettings
    case duckPlayerSettingNeverOverlaySERP
    case duckPlayerSettingNeverOverlayYoutube
    case duckPlayerSettingNeverSettings
    case duckPlayerSettingBackToDefault
    case duckPlayerWatchOnYoutube
    case duckPlayerAutoplaySettingsOn
    case duckPlayerAutoplaySettingsOff
    case duckPlayerNewTabSettingsOn
    case duckPlayerNewTabSettingsOff
    case duckPlayerContingencySettingsDisplayed
    case duckPlayerContingencyLearnMoreClicked
    case duckPlayerYouTubeSignInErrorImpression
    case duckPlayerYouTubeAgeRestrictedErrorImpression
    case duckPlayerYouTubeNoEmbedErrorImpression
    case duckPlayerYouTubeUnknownErrorImpression
    case duckPlayerYouTubeSignInErrorDaily
    case duckPlayerYouTubeAgeRestrictedErrorDaily
    case duckPlayerYouTubeNoEmbedErrorDaily
    case duckPlayerYouTubeUnknownErrorDaily

    // Temporary Overlay Pixels
    case duckPlayerYouTubeOverlayNavigationBack
    case duckPlayerYouTubeOverlayNavigationRefresh
    case duckPlayerYouTubeNavigationWithinYouTube
    case duckPlayerYouTubeOverlayNavigationOutsideYoutube
    case duckPlayerYouTubeOverlayNavigationClosed
    case duckPlayerYouTubeNavigationIdle30

    // Dashboard
    case dashboardProtectionAllowlistAdd(triggerOrigin: String?)
    case dashboardProtectionAllowlistRemove(triggerOrigin: String?)

    // VPN
    case vpnBreakageReport(category: String, description: String, metadata: String)

    // Unified Feedback
    case pproFeedbackFeatureRequest(description: String, source: String)
    case pproFeedbackGeneralFeedback(description: String, source: String)
    case pproFeedbackReportIssue(source: String, category: String, subcategory: String, description: String, metadata: String)

    case pproFeedbackFormShow
    case pproFeedbackSubmitScreenShow(source: String, reportType: String, category: String, subcategory: String)
    case pproFeedbackSubmitScreenFAQClick(source: String, reportType: String, category: String, subcategory: String)

    case networkProtectionEnabledOnSearch
    case networkProtectionGeoswitchingOpened
    case networkProtectionGeoswitchingSetNearest
    case networkProtectionGeoswitchingSetCustom
    case networkProtectionGeoswitchingNoLocations

    // Sync
    case syncSignupDirect
    case syncSignupConnect
    case syncLogin
    case syncDaily
    case syncDuckAddressOverride
    case syncSuccessRateDaily
    case syncLocalTimestampResolutionTriggered(Feature)
    case syncBookmarksObjectLimitExceededDaily
    case syncCredentialsObjectLimitExceededDaily
    case syncBookmarksRequestSizeLimitExceededDaily
    case syncCredentialsRequestSizeLimitExceededDaily
    case syncBookmarksTooManyRequestsDaily
    case syncCredentialsTooManyRequestsDaily
    case syncSettingsTooManyRequestsDaily
    case syncBookmarksValidationErrorDaily
    case syncCredentialsValidationErrorDaily
    case syncSettingsValidationErrorDaily
    case syncDebugWasDisabledUnexpectedly

    // Remote Messaging Framework
    case remoteMessageShown
    case remoteMessageShownUnique
    case remoteMessageDismissed
    case remoteMessageActionClicked
    case remoteMessagePrimaryActionClicked
    case remoteMessageSecondaryActionClicked

    // DataBroker Protection Waitlist
    case dataBrokerProtectionWaitlistUserActive
    case dataBrokerProtectionWaitlistEntryPointMenuItemDisplayed
    case dataBrokerProtectionWaitlistIntroDisplayed
    case dataBrokerProtectionWaitlistNotificationShown
    case dataBrokerProtectionWaitlistNotificationTapped
    case dataBrokerProtectionWaitlistCardUITapped
    case dataBrokerProtectionWaitlistTermsAndConditionsDisplayed
    case dataBrokerProtectionWaitlistTermsAndConditionsAccepted

    // Login Item events
    case dataBrokerEnableLoginItemDaily
    case dataBrokerDisableLoginItemDaily
    case dataBrokerResetLoginItemDaily
    case dataBrokerDisableAndDeleteDaily

    // Default Browser
    case defaultRequestedFromHomepage
    case defaultRequestedFromHomepageSetupView
    case defaultRequestedFromSettings
    case defaultRequestedFromOnboarding
    case defaultRequestedFromMainMenu
    case defaultRequestedFromMoreOptionsMenu

    // Adding to the Dock
    case addToDockOnboardingStepPresented
    case userAddedToDockDuringOnboarding
    case userSkippedAddingToDockFromOnboarding
    case startBrowsingOnboardingStepPresented
    case addToDockNewTabPageCardPresented
    case userAddedToDockFromNewTabPageCard
    case userAddedToDockFromSettings
    case userAddedToDockFromMainMenu
    case userAddedToDockFromMoreOptionsMenu
    case userAddedToDockFromDefaultBrowserSection
    case serpAddedToDock

    case protectionToggledOffBreakageReport
    case debugBreakageExperiment

    // Password Import Keychain Prompt
    case passwordImportKeychainPrompt
    case passwordImportKeychainPromptDenied

    // Autocomplete
    // See macOS/PixelDefinitions/pixels/suggestion_pixels.json5
    case autocompleteClickPhrase(from: AutocompleteSource)
    case autocompleteClickWebsite(from: AutocompleteSource)
    case autocompleteClickBookmark(from: AutocompleteSource)
    case autocompleteClickFavorite(from: AutocompleteSource)
    case autocompleteClickHistory(from: AutocompleteSource)
    case autocompleteClickOpenTab(from: AutocompleteSource)
    case autocompleteToggledOff
    case autocompleteToggledOn

    // Onboarding
    case onboardingExceptionReported(message: String, id: String)

    // MARK: - Advanced Usage

    /**
     * Event Trigger: User enters regular fullscreen mode (not split screen).
     *
     * > Note: This is a daily pixel.
     *
     * Anomaly Investigation:
     * - May indicate changes in user interface preferences or usage patterns.
     * - Increase could suggest users prefer immersive browsing experience.
     */
    case windowFullscreen

    /**
     * Event Trigger: User enters split screen mode (window approximately half screen width in fullscreen).
     *
     * > Note: This is a daily pixel.
     *
     * Anomaly Investigation:
     * - May indicate multitasking behavior changes or macOS split screen adoption.
     * - Useful for understanding productivity workflows.
     */
    case windowSplitScreen

    /**
     * Event Trigger: User activates Picture-in-Picture mode for video playback.
     *
     * > Note: This is a daily pixel.
     *
     * Anomaly Investigation:
     * - May indicate video consumption patterns and multitasking preferences.
     * - Increase could suggest growing use of video content while browsing.
     */
    case pictureInPictureVideoPlayback

    /**
     * Event Trigger: User opens developer tools (via any method: menu, context menu, keyboard shortcuts).
     *
     * > Note: This is a daily pixel.
     *
     * Anomaly Investigation:
     * - May indicate changes in developer user base or debugging needs.
     * - Could suggest technical issues requiring inspection or developer activity.
     */
    case developerToolsOpened

    // MARK: - Debug

    case keyValueFileStoreInitError
    case dbContainerInitializationError(error: Error)
    case dbInitializationError(error: Error)
    case dbSaveExcludedHTTPSDomainsError(error: Error?)
    case dbSaveBloomFilterError(error: Error?)

    case remoteMessagingSaveConfigError(error: Error?)
    case remoteMessagingUpdateMessageShownError(error: Error?)
    case remoteMessagingUpdateMessageStatusError(error: Error?)

    case configurationFetchError(error: Error)

    case trackerDataParseFailed
    case trackerDataReloadFailed
    case trackerDataCouldNotBeLoaded

    case privacyConfigurationParseFailed
    case privacyConfigurationReloadFailed
    case privacyConfigurationCouldNotBeLoaded

    case configurationFileCoordinatorError

    case fileStoreWriteFailed
    case fileMoveToDownloadsFailed
    case fileAccessRelatedItemFailed
    case fileGetDownloadLocationFailed
    case fileDownloadCreatePresentersFailed(osVersion: String)
    case downloadResumeDataCodingFailed

    case suggestionsFetchFailed
    case appOpenURLFailed
    case appStateRestorationFailed

    case contentBlockingErrorReportingIssue

    case contentBlockingCompilationFailed(listType: CompileRulesListType, component: ContentBlockerDebugEvents.Component)

    case contentBlockingCompilationTime
    case contentBlockingLookupRulesSucceeded
    case contentBlockingFetchLRCSucceeded
    case contentBlockingNoMatchInLRC
    case contentBlockingLRCMissing
    case contentBlockingCompilationTaskPerformance(iterationCount: Int, timeBucketAggregation: CompileTimeBucketAggregation)

    case secureVaultInitError(error: Error)
    case secureVaultError(error: Error)

    case feedbackReportingFailed

    case blankNavigationOnBurnFailed

    case historyRemoveFailed
    case historyReloadFailed
    case historyCleanEntriesFailed
    case historyCleanVisitsFailed
    case historySaveFailed
    case historySaveFailedDaily
    case historyInsertVisitFailed
    case historyRemoveVisitsFailed

    case emailAutofillKeychainError

    case bookmarksStoreRootFolderMigrationFailed
    case bookmarksStoreFavoritesFolderMigrationFailed

    case adAttributionCompilationFailedForAttributedRulesList
    case adAttributionGlobalAttributedRulesDoNotExist
    case adAttributionDetectionHeuristicsDidNotMatchDomain
    case adAttributionLogicUnexpectedStateOnRulesCompiled
    case adAttributionLogicUnexpectedStateOnInheritedAttribution
    case adAttributionLogicUnexpectedStateOnRulesCompilationFailed
    case adAttributionDetectionInvalidDomainInParameter
    case adAttributionLogicRequestingAttributionTimedOut
    case adAttributionLogicWrongVendorOnSuccessfulCompilation
    case adAttributionLogicWrongVendorOnFailedCompilation

    case webKitDidTerminate
    case userViewedWebKitTerminationErrorPage
    case webKitTerminationLoop
    case webKitTerminationIndicatorClicked

    case removedInvalidBookmarkManagedObjects

    case bitwardenNotResponding
    case bitwardenRespondedCannotDecrypt
    case bitwardenHandshakeFailed
    case bitwardenDecryptionOfSharedKeyFailed
    case bitwardenStoringOfTheSharedKeyFailed
    case bitwardenCredentialRetrievalFailed
    case bitwardenCredentialCreationFailed
    case bitwardenCredentialUpdateFailed
    case bitwardenRespondedWithError
    case bitwardenNoActiveVault
    case bitwardenParsingFailed
    case bitwardenStatusParsingFailed
    case bitwardenHmacComparisonFailed
    case bitwardenDecryptionFailed
    case bitwardenSendingOfMessageFailed
    case bitwardenSharedKeyInjectionFailed

    case updaterAborted(reason: String)
    case updaterDidFindUpdate
    case updaterDidDownloadUpdate
    case updaterDidRunUpdate
    case releaseNotesEmpty

    case faviconDecryptionFailedUnique
    case downloadListItemDecryptionFailedUnique
    case historyEntryDecryptionFailedUnique
    case permissionDecryptionFailedUnique

    // Errors from Bookmarks Module
    case missingParent
    case bookmarksSaveFailed
    case bookmarksSaveFailedOnImport

    case bookmarksCouldNotLoadDatabase(error: Error?)
    case bookmarksCouldNotPrepareDatabase
    case bookmarksMigrationAlreadyPerformed
    case bookmarksMigrationFailed
    case bookmarksMigrationCouldNotPrepareDatabase
    case bookmarksMigrationCouldNotPrepareDatabaseOnFailedMigration
    case bookmarksMigrationCouldNotRemoveOldStore
    case bookmarksMigrationCouldNotPrepareMultipleFavoriteFolders

    // Bookmarks search and sort feature metrics
    case bookmarksSortButtonClicked(origin: String)
    case bookmarksSortButtonDismissed(origin: String)
    case bookmarksSortByName(origin: String)
    case bookmarksSearchExecuted(origin: String)
    case bookmarksSearchResultClicked(origin: String)

    case syncSentUnauthenticatedRequest
    case syncMetadataCouldNotLoadDatabase
    case syncBookmarksProviderInitializationFailed
    case syncBookmarksFailed
    case syncBookmarksPatchCompressionFailed
    case syncCredentialsProviderInitializationFailed
    case syncCredentialsFailed
    case syncCredentialsPatchCompressionFailed
    case syncSettingsFailed
    case syncSettingsMetadataUpdateFailed
    case syncSettingsPatchCompressionFailed
    case syncMigratedToFileStore
    case syncFailedToMigrateToFileStore
    case syncFailedToInitFileStore
    case syncSignupError(error: Error)
    case syncLoginError(error: Error)
    case syncLogoutError(error: Error)
    case syncUpdateDeviceError(error: Error)
    case syncRemoveDeviceError(error: Error)
    case syncRefreshDevicesError(error: Error)
    case syncDeleteAccountError(error: Error)
    case syncLoginExistingAccountError(error: Error)
    case syncCannotCreateRecoveryPDF
    case syncSecureStorageReadError(error: Error)
    case syncSecureStorageDecodingError(error: Error)
    case syncAccountRemoved(reason: String)

    case bookmarksCleanupFailed
    case bookmarksCleanupAttemptedWhileSyncWasEnabled
    case favoritesCleanupFailed
    case bookmarksFaviconsFetcherStateStoreInitializationFailed
    case bookmarksFaviconsFetcherFailed

    case credentialsDatabaseCleanupFailed
    case credentialsCleanupAttemptedWhileSyncWasEnabled

    case invalidPayload(Configuration) // BSK>Configuration

    case burnerTabMisplaced

    case loginItemUpdateError(loginItemBundleID: String, action: String, buildType: String, osVersion: String)

    // Tracks installation without tracking retention.
    case installationAttribution

    case secureVaultKeystoreEventL1KeyMigration
    case secureVaultKeystoreEventL2KeyMigration
    case secureVaultKeystoreEventL2KeyPasswordMigration

    case compilationFailed

    // MARK: error page shown
    case errorPageShownOther
    case errorPageShownWebkitTermination

    // Broken site prompt

    case pageRefreshThreeTimesWithin20Seconds
    case siteNotWorkingShown
    case siteNotWorkingWebsiteIsBroken

    // Enhanced statistics
    case usageSegments

    // UserScript
    /**
     * Event Trigger: BrowserServicesKit.UserScript.loadJS fails to load the contents of a JS file.
     *
     * Anomaly Investigation:
     * - App crashes after this pixel is fired.
     * - Useful for investigating the underlying error causing the failure.
     */
    case userScriptLoadJSFailed(jsFile: String, error: Error)

    var name: String {
        switch self {
        case .crash(let appIdentifier):
            if let appIdentifier {
                return "m_mac_crash_\(appIdentifier.rawValue)"
            } else {
                return "m_mac_crash"
            }

        case .crashOnCrashHandlersSetUp:
            return "m_mac_crash_on_handlers_setup"

        case .crashReportCRCIDMissing:
            return "m_mac_crashreporting_crcid-missing"

        case .crashReportingSubmissionFailed:
            return "m_mac_crashreporting_submission-failed"

        case .compileRulesWait(onboardingShown: let onboardingShown, waitTime: let waitTime, result: let result):
            return "m_mac_cbr-wait_\(onboardingShown)_\(waitTime)_\(result)"

        case .launch:
            return "ml_mac_app-launch"

        case .dailyActiveUser:
            return  "m_mac_daily_active_user"

        case .dailyFireWindowConfiguration:
            return "m_mac_fire_window_configuration"

        case .navigation:
            return "m_mac_navigation"

        case .navigationToExternalURL:
            return "m_mac_navigation_url_source-external"

        case .serp:
            return "m_mac_navigation_search"

        case .dailyOsVersionCounter:
            return "m_mac_daily-os-version-counter"

        case .dataImportFailed(source: let source, sourceVersion: _, error: let error) where error.action == .favicons:
            return "m_mac_favicon-import-failed_\(source)"
        case .dataImportFailed(source: let source, sourceVersion: _, error: let error):
            return "m_mac_data-import-failed_\(error.action)_\(source)"

        case .dataImportSucceeded(action: let action, source: let source, sourceVersion: _):
            return "m_mac_data-import-succeeded_\(action)_\(source)"

        case .favoritesImportFailed(source: let source, sourceVersion: _, error: _):
            return "m_mac_data-import-failed_favorites_\(source)"
        case .favoritesImportSucceeded(source: let source, sourceVersion: _, favoritesBucket: _):
            return "m_mac_data-import-succeeded_favorites_\(source)"

        case .formAutofilled(kind: let kind):
            return "m_mac_autofill_\(kind)"

        case .autofillItemSaved(kind: let kind):
            return "m_mac_save_\(kind)"

        case .autofillLoginsSaveLoginInlineDisplayed:
            return "m_mac_autofill_logins_save_login_inline_displayed"
        case .autofillLoginsSaveLoginInlineConfirmed:
            return "m_mac_autofill_logins_save_login_inline_confirmed"
        case .autofillLoginsSaveLoginInlineDismissed:
            return "m_mac_autofill_logins_save_login_inline_dismissed"

        case .autofillLoginsSavePasswordInlineDisplayed:
            return "m_mac_autofill_logins_save_password_inline_displayed"
        case .autofillLoginsSavePasswordInlineConfirmed:
            return "m_mac_autofill_logins_save_password_inline_confirmed"
        case .autofillLoginsSavePasswordInlineDismissed:
            return "m_mac_autofill_logins_save_password_inline_dismissed"

        case .autofillLoginsSaveLoginModalExcludeSiteConfirmed:
            return "m_mac_autofill_logins_save_login_exclude_site_confirmed"
        case .autofillLoginsSettingsResetExcludedDisplayed:
            return "m_mac_autofill_settings_reset_excluded_displayed"
        case .autofillLoginsSettingsResetExcludedConfirmed:
            return "m_mac_autofill_settings_reset_excluded_confirmed"
        case .autofillLoginsSettingsResetExcludedDismissed:
            return "m_mac_autofill_settings_reset_excluded_dismissed"

        case .autofillLoginsUpdatePasswordInlineDisplayed:
            return "m_mac_autofill_logins_update_password_inline_displayed"
        case .autofillLoginsUpdatePasswordInlineConfirmed:
            return "m_mac_autofill_logins_update_password_inline_confirmed"
        case .autofillLoginsUpdatePasswordInlineDismissed:
            return "m_mac_autofill_logins_update_password_inline_dismissed"

        case .autofillLoginsUpdateUsernameInlineDisplayed:
            return "m_mac_autofill_logins_update_username_inline_displayed"
        case .autofillLoginsUpdateUsernameInlineConfirmed:
            return "m_mac_autofill_logins_update_username_inline_confirmed"
        case .autofillLoginsUpdateUsernameInlineDismissed:
            return "m_mac_autofill_logins_update_username_inline_dismissed"

        case .autofillActiveUser:
            return "m_mac_autofill_activeuser"
        case .autofillEnabledUser:
            return "m_mac_autofill_enableduser"
        case .autofillOnboardedUser:
            return "m_mac_autofill_onboardeduser"
        case .autofillToggledOn:
            return "m_mac_autofill_toggled_on"
        case .autofillToggledOff:
            return "m_mac_autofill_toggled_off"
        case .autofillLoginsStacked:
            return "m_mac_autofill_logins_stacked"
        case .autofillCreditCardsStacked:
            return "m_mac_autofill_creditcards_stacked"
        case .autofillIdentitiesStacked:
            return "m_mac_autofill_identities_stacked"

        case .autofillManagementOpened:
            return "m_mac_autofill_management_opened"
        case .autofillManagementCopyUsername:
            return "m_mac_autofill_management_copy_username"
        case .autofillManagementCopyPassword:
            return "m_mac_autofill_management_copy_password"
        case .autofillManagementDeleteLogin:
            return "m_mac_autofill_management_delete_login"
        case .autofillManagementDeleteAllLogins:
            return "m_mac_autofill_management_delete_all_logins"
        case .autofillManagementSaveLogin:
            return "m_mac_autofill_management_save_login"
        case .autofillManagementUpdateLogin:
            return "m_mac_autofill_management_update_login"

        case .autofillLoginsSettingsEnabled:
            return "m_mac_autofill_logins_settings_enabled"
        case .autofillLoginsSettingsDisabled:
            return "m_mac_autofill_logins_settings_disabled"

        case .bitwardenPasswordAutofilled:
            return "m_mac_bitwarden_autofill_password"

        case .bitwardenPasswordSaved:
            return "m_mac_bitwarden_save_password"

        case .ampBlockingRulesCompilationFailed:
            return "m_mac_amp_rules_compilation_failed"

        case .adClickAttributionDetected:
            return "m_mac_ad_click_detected"

        case .adClickAttributionActive:
            return "m_mac_ad_click_active"

        case .adClickAttributionPageLoads:
            return "m_mac_ad_click_page_loads"

        case .jsPixel(let pixel):
            // Email pixels deliberately avoid using the `m_mac_` prefix.
            if pixel.isEmailPixel {
                return "\(pixel.pixelName)_macos_desktop"
            } else if pixel.isCredentialsImportPromotionPixel {
                return "\(pixel.pixelName)_mac"
            } else {
                return "m_mac_\(pixel.pixelName)"
            }
        case .emailEnabledInitial:
            return "m_mac_enable-email-protection_initial"

        case .watchInDuckPlayerInitial:
            return "m_mac_watch-in-duckplayer_initial"
        case .setAsDefaultInitial:
            return "m_mac_set-as-default_initial"
        case .importDataInitial:
            return "m_mac_import-data_initial"
        case .newTabInitial:
            return "m_mac_new-tab-opened_initial"
        case .continueSetUpSectionHidden:
            return "m_mac_continue-setup-section-hidden"

            // Fire Button
        case .fireButtonFirstBurn:
            return "m_mac_fire_button_first_burn"
        case .fireButton(option: let option):
            return "m_mac_fire_button_\(option)"
        case .fireAnimationSetting(let enabled):
            return "m_mac_fire_animation_\(enabled ? "on" : "off")"
        case .fireButtonDetailsViewed:
            return "m_mac_fire_button_details_viewed"

        case .duckPlayerWeeklyUniqueView:
            return "duckplayer_weekly-unique-view"
        case .duckPlayerDailyUniqueView:
            return "m_mac_duck-player_daily-unique-view"
        case .duckPlayerViewFromYoutubeViaMainOverlay:
            return "m_mac_duck-player_view-from_youtube_main-overlay"
        case .duckPlayerViewFromYoutubeViaHoverButton:
            return "m_mac_duck-player_view-from_youtube_hover-button"
        case .duckPlayerViewFromYoutubeAutomatic:
            return "m_mac_duck-player_view-from_youtube_automatic"
        case .duckPlayerViewFromSERP:
            return "m_mac_duck-player_view-from_serp"
        case .duckPlayerViewFromOther:
            return "m_mac_duck-player_view-from_other"
        case .duckPlayerSettingAlwaysSettings:
            return "m_mac_duck-player_setting_always_settings"
        case .duckPlayerOverlayYoutubeImpressions:
            return "m_mac_duck-player_overlay_youtube_impressions"
        case .duckPlayerOverlayYoutubeWatchHere:
            return "m_mac_duck-player_overlay_youtube_watch_here"
        case .duckPlayerSettingAlwaysDuckPlayer:
            return "m_mac_duck-player_setting_always_duck-player"
        case .duckPlayerSettingAlwaysOverlaySERP:
            return "m_mac_duck-player_setting_always_overlay_serp"
        case .duckPlayerSettingAlwaysOverlayYoutube:
            return "m_mac_duck-player_setting_always_overlay_youtube"
        case .duckPlayerSettingNeverOverlaySERP:
            return "m_mac_duck-player_setting_never_overlay_serp"
        case .duckPlayerSettingNeverOverlayYoutube:
            return "m_mac_duck-player_setting_never_overlay_youtube"
        case .duckPlayerSettingNeverSettings:
            return "m_mac_duck-player_setting_never_settings"
        case .duckPlayerSettingBackToDefault:
            return "m_mac_duck-player_setting_back-to-default"
        case .duckPlayerWatchOnYoutube:
            return "m_mac_duck-player_watch_on_youtube"
        case .duckPlayerAutoplaySettingsOn:
            return "duckplayer_mac_autoplay_setting-on"
        case .duckPlayerAutoplaySettingsOff:
            return "duckplayer_mac_autoplay_setting-off"
        case .duckPlayerNewTabSettingsOn:
            return "duckplayer_mac_newtab_setting-on"
        case .duckPlayerNewTabSettingsOff:
            return "duckplayer_mac_newtab_setting-off"
        case .duckPlayerContingencySettingsDisplayed:
            return "duckplayer_mac_contingency_settings-displayed"
        case .duckPlayerContingencyLearnMoreClicked:
            return "duckplayer_mac_contingency_learn-more-clicked"
        case .duckPlayerYouTubeSignInErrorImpression:
            return "duckplayer_mac_youtube-signin-error_impression"
        case .duckPlayerYouTubeAgeRestrictedErrorImpression:
            return "duckplayer_mac_youtube-age-restricted-error_impression"
        case .duckPlayerYouTubeNoEmbedErrorImpression:
            return "duckplayer_mac_youtube-no-embed-error_impression"
        case .duckPlayerYouTubeUnknownErrorImpression:
            return "duckplayer_mac_youtube-unknown-error_impression"
        case .duckPlayerYouTubeSignInErrorDaily:
            return "duckplayer_mac_youtube-signin-error_daily-unique"
        case .duckPlayerYouTubeAgeRestrictedErrorDaily:
            return "duckplayer_mac_youtube-age-restricted-error_daily-unique"
        case .duckPlayerYouTubeNoEmbedErrorDaily:
            return "duckplayer_mac_youtube-no-embed-error_daily-unique"
        case .duckPlayerYouTubeUnknownErrorDaily:
            return "duckplayer_mac_youtube-unknown-error_daily-unique"

            // Duck Player Temporary Overlay Pixels
        case .duckPlayerYouTubeOverlayNavigationBack:
            return "duckplayer_youtube_overlay_navigation_back"
        case .duckPlayerYouTubeOverlayNavigationRefresh:
            return "duckplayer_youtube_overlay_navigation_refresh"
        case .duckPlayerYouTubeNavigationWithinYouTube:
            return "duckplayer_youtube_overlay_navigation_within-youtube"
        case .duckPlayerYouTubeOverlayNavigationOutsideYoutube:
            return "duckplayer_youtube_overlay_navigation_outside-youtube"
        case .duckPlayerYouTubeOverlayNavigationClosed:
            return "duckplayer_youtube_overlay_navigation_closed"
        case .duckPlayerYouTubeNavigationIdle30:
            return "duckplayer_youtube_overlay_idle-30"

        case .dashboardProtectionAllowlistAdd:
            return "mp_wla"
        case .dashboardProtectionAllowlistRemove:
            return "mp_wlr"

        case .serpInitial:
            return "m_mac_navigation_first-search_u"

        case .vpnBreakageReport:
            return "m_mac_vpn_breakage_report"

        case .pproFeedbackFeatureRequest:
            return "m_mac_ppro_feedback_feature-request"
        case .pproFeedbackGeneralFeedback:
            return "m_mac_ppro_feedback_general-feedback"
        case .pproFeedbackReportIssue:
            return "m_mac_ppro_feedback_report-issue"
        case .pproFeedbackFormShow:
            return "m_mac_ppro_feedback_general-screen_show"
        case .pproFeedbackSubmitScreenShow:
            return "m_mac_ppro_feedback_submit-screen_show"
        case .pproFeedbackSubmitScreenFAQClick:
            return "m_mac_ppro_feedback_submit-screen-faq_click"

        case .networkProtectionEnabledOnSearch:
            return "m_mac_netp_ev_enabled_on_search"

            // Sync
        case .syncSignupDirect:
            return "m_mac_sync_signup_direct"
        case .syncSignupConnect:
            return "m_mac_sync_signup_connect"
        case .syncLogin:
            return "m_mac_sync_login"
        case .syncDaily:
            return "m_mac_sync_daily"
        case .syncDuckAddressOverride:
            return "m_mac_sync_duck_address_override"
        case .syncSuccessRateDaily:
            return "m_mac_sync_success_rate_daily"
        case .syncLocalTimestampResolutionTriggered(let feature):
            return "m_mac_sync_\(feature.name)_local_timestamp_resolution_triggered"
        case .syncBookmarksObjectLimitExceededDaily: return "m_mac_sync_bookmarks_object_limit_exceeded_daily"
        case .syncCredentialsObjectLimitExceededDaily: return "m_mac_sync_credentials_object_limit_exceeded_daily"
        case .syncBookmarksRequestSizeLimitExceededDaily: return "m_mac_sync_bookmarks_request_size_limit_exceeded_daily"
        case .syncCredentialsRequestSizeLimitExceededDaily: return "m_mac_sync_credentials_request_size_limit_exceeded_daily"
        case .syncBookmarksTooManyRequestsDaily: return "m_mac_sync_bookmarks_too_many_requests_daily"
        case .syncCredentialsTooManyRequestsDaily: return "m_mac_sync_credentials_too_many_requests_daily"
        case .syncSettingsTooManyRequestsDaily: return "m_mac_sync_settings_too_many_requests_daily"
        case .syncBookmarksValidationErrorDaily: return "m_mac_sync_bookmarks_validation_error_daily"
        case .syncCredentialsValidationErrorDaily: return "m_mac_sync_credentials_validation_error_daily"
        case .syncSettingsValidationErrorDaily: return "m_mac_sync_settings_validation_error_daily"
        case .syncDebugWasDisabledUnexpectedly: return "m_mac_sync_was_disabled_unexpectedly"

        case .remoteMessageShown: return "m_mac_remote_message_shown"
        case .remoteMessageShownUnique: return "m_mac_remote_message_shown_unique"
        case .remoteMessageDismissed: return "m_mac_remote_message_dismissed"
        case .remoteMessageActionClicked: return "m_mac_remote_message_action_clicked"
        case .remoteMessagePrimaryActionClicked: return "m_mac_remote_message_primary_action_clicked"
        case .remoteMessageSecondaryActionClicked: return "m_mac_remote_message_secondary_action_clicked"

        case .dataBrokerProtectionWaitlistUserActive:
            return "m_mac_dbp_waitlist_user_active"
        case .dataBrokerProtectionWaitlistEntryPointMenuItemDisplayed:
            return "m_mac_dbp_imp_settings_entry_menu_item"
        case .dataBrokerProtectionWaitlistIntroDisplayed:
            return "m_mac_dbp_imp_intro_screen"
        case .dataBrokerProtectionWaitlistNotificationShown:
            return "m_mac_dbp_ev_waitlist_notification_shown"
        case .dataBrokerProtectionWaitlistNotificationTapped:
            return "m_mac_dbp_ev_waitlist_notification_launched"
        case .dataBrokerProtectionWaitlistCardUITapped:
            return "m_mac_dbp_ev_waitlist_card_ui_launched"
        case .dataBrokerProtectionWaitlistTermsAndConditionsDisplayed:
            return "m_mac_dbp_imp_terms"
        case .dataBrokerProtectionWaitlistTermsAndConditionsAccepted:
            return "m_mac_dbp_ev_terms_accepted"

        case .dataBrokerEnableLoginItemDaily: return "m_mac_dbp_daily_login-item_enable"
        case .dataBrokerDisableLoginItemDaily: return "m_mac_dbp_daily_login-item_disable"
        case .dataBrokerResetLoginItemDaily: return "m_mac_dbp_daily_login-item_reset"
        case .dataBrokerDisableAndDeleteDaily: return "m_mac_dbp_daily_disable-and-delete"

        case .networkProtectionGeoswitchingOpened:
            return "m_mac_netp_imp_geoswitching_c"
        case .networkProtectionGeoswitchingSetNearest:
            return "m_mac_netp_ev_geoswitching_set_nearest"
        case .networkProtectionGeoswitchingSetCustom:
            return "m_mac_netp_ev_geoswitching_set_custom"
        case .networkProtectionGeoswitchingNoLocations:
            return "m_mac_netp_ev_geoswitching_no_locations"

        case .defaultRequestedFromHomepage: return "m_mac_default_requested_from_homepage"
        case .defaultRequestedFromHomepageSetupView: return "m_mac_default_requested_from_homepage_setup_view"
        case .defaultRequestedFromSettings: return "m_mac_default_requested_from_settings"
        case .defaultRequestedFromOnboarding: return "m_mac_default_requested_from_onboarding"
        case .defaultRequestedFromMainMenu: return "m_mac_default_requested_from_main_menu"
        case .defaultRequestedFromMoreOptionsMenu: return "m_mac_default_requested_from_more_options_menu"

        case .addToDockOnboardingStepPresented: return "m_mac_add_to_dock_onboarding_step_presented"
        case .userAddedToDockDuringOnboarding: return "m_mac_user_added_to_dock_during_onboarding"
        case .userSkippedAddingToDockFromOnboarding: return "m_mac_user_skipped_adding_to_dock_from_onboarding"
        case .startBrowsingOnboardingStepPresented: return "m_mac_start_browsing_onboarding_step_presented"
        case .addToDockNewTabPageCardPresented: return "m_mac_add_to_dock_new_tab_page_card_presented_u"
        case .userAddedToDockFromNewTabPageCard: return "m_mac_user_added_to_dock_from_new_tab_page_card"
        case .userAddedToDockFromSettings: return "m_mac_user_added_to_dock_from_settings"
        case .userAddedToDockFromMainMenu: return "m_mac_user_added_to_dock_from_main_menu"
        case .userAddedToDockFromMoreOptionsMenu: return "m_mac_user_added_to_dock_from_more_options_menu"
        case .userAddedToDockFromDefaultBrowserSection: return "m_mac_user_added_to_dock_from_default_browser_section"
        case .serpAddedToDock: return "m_mac_serp_added_to_dock"

        case .protectionToggledOffBreakageReport: return "m_mac_protection-toggled-off-breakage-report"
        case .debugBreakageExperiment: return "m_mac_debug_breakage_experiment_u"

            // Password Import Keychain Prompt
        case .passwordImportKeychainPrompt: return "m_mac_password_import_keychain_prompt"
        case .passwordImportKeychainPromptDenied: return "m_mac_password_import_keychain_prompt_denied"

            // Autocomplete
        case .autocompleteClickPhrase: return "m_mac_autocomplete_click_phrase"
        case .autocompleteClickWebsite: return "m_mac_autocomplete_click_website"
        case .autocompleteClickBookmark: return "m_mac_autocomplete_click_bookmark"
        case .autocompleteClickFavorite: return "m_mac_autocomplete_click_favorite"
        case .autocompleteClickHistory: return "m_mac_autocomplete_click_history"
        case .autocompleteClickOpenTab: return "m_mac_autocomplete_click_opentab"
        case .autocompleteToggledOff: return "m_mac_autocomplete_toggled_off"
        case .autocompleteToggledOn: return "m_mac_autocomplete_toggled_on"

            // Onboarding
        case .onboardingExceptionReported: return "m_mac_onboarding_exception-reported"

        // “Advanced” usage
        case .windowFullscreen: return "m_mac_window_fullscreen"
        case .windowSplitScreen: return "m_mac_window_split_screen"

        case .pictureInPictureVideoPlayback: return "m_mac_pip_video_playback"

        case .developerToolsOpened: return "m_mac_dev_tools_opened"

            // DEBUG
        case .keyValueFileStoreInitError:
            return "key_value_file_store_init_error"
        case .dbContainerInitializationError:
            return "database_container_error"
        case .dbInitializationError:
            return "dbie"
        case .dbSaveExcludedHTTPSDomainsError:
            return "database_save_excluded_https_domains_error"
        case .dbSaveBloomFilterError:
            return "database_save_bloom_filter_error"

        case .remoteMessagingSaveConfigError:
            return "remote_messaging_save_config_error"
        case .remoteMessagingUpdateMessageShownError:
            return "remote_messaging_update_message_shown_error"
        case .remoteMessagingUpdateMessageStatusError:
            return "remote_messaging_update_message_status_error"

        case .configurationFetchError:
            return "cfgfetch"

        case .trackerDataParseFailed:
            return "tracker_data_parse_failed"
        case .trackerDataReloadFailed:
            return "tds_r"
        case .trackerDataCouldNotBeLoaded:
            return "tracker_data_could_not_be_loaded"

        case .privacyConfigurationParseFailed:
            return "pcf_p"
        case .privacyConfigurationReloadFailed:
            return "pcf_r"
        case .privacyConfigurationCouldNotBeLoaded:
            return "pcf_l"

        case .configurationFileCoordinatorError:
            return "configuration_file_coordinator_error"

        case .fileStoreWriteFailed:
            return "fswf"
        case .fileMoveToDownloadsFailed:
            return "df"
        case .fileGetDownloadLocationFailed:
            return "dl"
        case .fileAccessRelatedItemFailed:
            return "dari"
        case .fileDownloadCreatePresentersFailed:
            return "dfpf"
        case .downloadResumeDataCodingFailed:
            return "drdc"

        case .suggestionsFetchFailed:
            return "sgf"
        case .appOpenURLFailed:
            return "url"
        case .appStateRestorationFailed:
            return "srf"

        case .contentBlockingErrorReportingIssue:
            return "content_blocking_error_reporting_issue"

        case .contentBlockingCompilationFailed(let listType, let component):
            let componentString: String
            switch component {
            case .tds:
                componentString = "fetched_tds"
            case .allowlist:
                componentString = "allow_list"
            case .tempUnprotected:
                componentString = "temp_list"
            case .localUnprotected:
                componentString = "unprotected_list"
            case .fallbackTds:
                componentString = "fallback_tds"
            }
            return "content_blocking_\(listType)_compilation_error_\(componentString)"

        case .contentBlockingCompilationTime:
            return "content_blocking_compilation_time"

        case .contentBlockingLookupRulesSucceeded:
            return "content_blocking_lookup_rules_succeeded"
        case .contentBlockingFetchLRCSucceeded:
            return "content_blocking_fetch_lrc_succeeded"
        case .contentBlockingNoMatchInLRC:
            return "content_blocking_no_match_in_lrc"
        case .contentBlockingLRCMissing:
            return "content_blocking_lrc_missing"

        case .contentBlockingCompilationTaskPerformance(let iterationCount, let timeBucketAggregation):
            return "content_blocking_compilation_loops_\(iterationCount)_time_\(timeBucketAggregation)"

        case .secureVaultInitError:
            return "secure_vault_init_error"
        case .secureVaultError:
            return "secure_vault_error"

        case .feedbackReportingFailed:
            return "feedback_reporting_failed"

        case .blankNavigationOnBurnFailed:
            return "blank_navigation_on_burn_failed"

        case .historyRemoveFailed:
            return "history_remove_failed"
        case .historyReloadFailed:
            return "history_reload_failed"
        case .historyCleanEntriesFailed:
            return "history_clean_entries_failed"
        case .historyCleanVisitsFailed:
            return "history_clean_visits_failed"
        case .historySaveFailed:
            return "history_save_failed"
        case .historySaveFailedDaily:
            return "history_save_failed_daily"
        case .historyInsertVisitFailed:
            return "history_insert_visit_failed"
        case .historyRemoveVisitsFailed:
            return "history_remove_visits_failed"

        case .emailAutofillKeychainError:
            return "email_autofill_keychain_error"

        case .bookmarksStoreRootFolderMigrationFailed:
            return "bookmarks_store_root_folder_migration_failed"
        case .bookmarksStoreFavoritesFolderMigrationFailed:
            return "bookmarks_store_favorites_folder_migration_failed"

        case .adAttributionCompilationFailedForAttributedRulesList:
            return "ad_attribution_compilation_failed_for_attributed_rules_list"
        case .adAttributionGlobalAttributedRulesDoNotExist:
            return "ad_attribution_global_attributed_rules_do_not_exist"
        case .adAttributionDetectionHeuristicsDidNotMatchDomain:
            return "ad_attribution_detection_heuristics_did_not_match_domain"
        case .adAttributionLogicUnexpectedStateOnRulesCompiled:
            return "ad_attribution_logic_unexpected_state_on_rules_compiled"
        case .adAttributionLogicUnexpectedStateOnInheritedAttribution:
            return "ad_attribution_logic_unexpected_state_on_inherited_attribution_2"
        case .adAttributionLogicUnexpectedStateOnRulesCompilationFailed:
            return "ad_attribution_logic_unexpected_state_on_rules_compilation_failed"
        case .adAttributionDetectionInvalidDomainInParameter:
            return "ad_attribution_detection_invalid_domain_in_parameter"
        case .adAttributionLogicRequestingAttributionTimedOut:
            return "ad_attribution_logic_requesting_attribution_timed_out"
        case .adAttributionLogicWrongVendorOnSuccessfulCompilation:
            return "ad_attribution_logic_wrong_vendor_on_successful_compilation"
        case .adAttributionLogicWrongVendorOnFailedCompilation:
            return "ad_attribution_logic_wrong_vendor_on_failed_compilation"

        /// Event trigger: WebKit process crashes
        case .webKitDidTerminate:
            return "webkit_did_terminate"
        /// Event trigger: Error page is displayed in response to the WebKit process crash
        case .userViewedWebKitTerminationErrorPage:
            return "webkit-termination-error-page-viewed"
        /// Event trigger: WebKit process crash loop is detected
        case .webKitTerminationLoop:
            return "webkit_termination_loop"
        /// Event trigger: User clicked WebKit process crash indicator icon
        case .webKitTerminationIndicatorClicked:
            return "webkit_termination_indicator_clicked"

        case .removedInvalidBookmarkManagedObjects:
            return "removed_invalid_bookmark_managed_objects"

        case .bitwardenNotResponding:
            return "bitwarden_not_responding"
        case .bitwardenRespondedCannotDecrypt:
            return "bitwarden_responded_cannot_decrypt_d"
        case .bitwardenHandshakeFailed:
            return "bitwarden_handshake_failed"
        case .bitwardenDecryptionOfSharedKeyFailed:
            return "bitwarden_decryption_of_shared_key_failed"
        case .bitwardenStoringOfTheSharedKeyFailed:
            return "bitwarden_storing_of_the_shared_key_failed"
        case .bitwardenCredentialRetrievalFailed:
            return "bitwarden_credential_retrieval_failed"
        case .bitwardenCredentialCreationFailed:
            return "bitwarden_credential_creation_failed"
        case .bitwardenCredentialUpdateFailed:
            return "bitwarden_credential_update_failed"
        case .bitwardenRespondedWithError:
            return "bitwarden_responded_with_error"
        case .bitwardenNoActiveVault:
            return "bitwarden_no_active_vault"
        case .bitwardenParsingFailed:
            return "bitwarden_parsing_failed"
        case .bitwardenStatusParsingFailed:
            return "bitwarden_status_parsing_failed"
        case .bitwardenHmacComparisonFailed:
            return "bitwarden_hmac_comparison_failed"
        case .bitwardenDecryptionFailed:
            return "bitwarden_decryption_failed"
        case .bitwardenSendingOfMessageFailed:
            return "bitwarden_sending_of_message_failed"
        case .bitwardenSharedKeyInjectionFailed:
            return "bitwarden_shared_key_injection_failed"

        case .updaterAborted:
            return "updater_aborted"
        case .updaterDidFindUpdate:
            return "updater_did_find_update"
        case .updaterDidDownloadUpdate:
            return "updater_did_download_update"
        case .updaterDidRunUpdate:
            return "updater_did_run_update"
        case .releaseNotesEmpty:
            return "m_mac_release_notes_empty"

        case .faviconDecryptionFailedUnique:
            return "favicon_decryption_failed_unique"
        case .downloadListItemDecryptionFailedUnique:
            return "download_list_item_decryption_failed_unique"
        case .historyEntryDecryptionFailedUnique:
            return "history_entry_decryption_failed_unique"
        case .permissionDecryptionFailedUnique:
            return "permission_decryption_failed_unique"

        case .missingParent: return "bookmark_missing_parent"
        case .bookmarksSaveFailed: return "bookmarks_save_failed"
        case .bookmarksSaveFailedOnImport: return "bookmarks_save_failed_on_import"

        case .bookmarksCouldNotLoadDatabase: return "bookmarks_could_not_load_database"
        case .bookmarksCouldNotPrepareDatabase: return "bookmarks_could_not_prepare_database"
        case .bookmarksMigrationAlreadyPerformed: return "bookmarks_migration_already_performed"
        case .bookmarksMigrationFailed: return "bookmarks_migration_failed"
        case .bookmarksMigrationCouldNotPrepareDatabase: return "bookmarks_migration_could_not_prepare_database"
        case .bookmarksMigrationCouldNotPrepareDatabaseOnFailedMigration:
            return "bookmarks_migration_could_not_prepare_database_on_failed_migration"
        case .bookmarksMigrationCouldNotRemoveOldStore: return "bookmarks_migration_could_not_remove_old_store"
        case .bookmarksMigrationCouldNotPrepareMultipleFavoriteFolders:
            return "bookmarks_migration_could_not_prepare_multiple_favorite_folders"
        case .syncSentUnauthenticatedRequest: return "sync_sent_unauthenticated_request"
        case .syncMetadataCouldNotLoadDatabase: return "sync_metadata_could_not_load_database"
        case .syncBookmarksProviderInitializationFailed: return "sync_bookmarks_provider_initialization_failed"
        case .syncBookmarksFailed: return "sync_bookmarks_failed"
        case .syncBookmarksPatchCompressionFailed: return "sync_bookmarks_patch_compression_failed"
        case .syncCredentialsProviderInitializationFailed: return "sync_credentials_provider_initialization_failed"
        case .syncCredentialsFailed: return "sync_credentials_failed"
        case .syncCredentialsPatchCompressionFailed: return "sync_credentials_patch_compression_failed"
        case .syncSettingsFailed: return "sync_settings_failed"
        case .syncSettingsMetadataUpdateFailed: return "sync_settings_metadata_update_failed"
        case .syncSettingsPatchCompressionFailed: return "sync_settings_patch_compression_failed"
        case .syncMigratedToFileStore: return "sync_migrated_to_file_store"
        case .syncFailedToMigrateToFileStore: return "sync_failed_to_migrate_to_file_store"
        case .syncFailedToInitFileStore: return "sync_failed_to_init_file_store"
        case .syncSignupError: return "sync_signup_error"
        case .syncLoginError: return "sync_login_error"
        case .syncLogoutError: return "sync_logout_error"
        case .syncUpdateDeviceError: return "sync_update_device_error"
        case .syncRemoveDeviceError: return "sync_remove_device_error"
        case .syncRefreshDevicesError: return "sync_refresh_devices_error"
        case .syncDeleteAccountError: return "sync_delete_account_error"
        case .syncLoginExistingAccountError: return "sync_login_existing_account_error"
        case .syncCannotCreateRecoveryPDF: return "sync_cannot_create_recovery_pdf"
        case .syncSecureStorageReadError: return "sync_secure_storage_read_error"
        case .syncSecureStorageDecodingError: return "sync_secure_storage_decoding_error"
        case .syncAccountRemoved(let reason): return "sync_account_removed_reason_\(reason)"

        case .bookmarksCleanupFailed: return "bookmarks_cleanup_failed"
        case .bookmarksCleanupAttemptedWhileSyncWasEnabled: return "bookmarks_cleanup_attempted_while_sync_was_enabled"
        case .favoritesCleanupFailed: return "favorites_cleanup_failed"
        case .bookmarksFaviconsFetcherStateStoreInitializationFailed: return "bookmarks_favicons_fetcher_state_store_initialization_failed"
        case .bookmarksFaviconsFetcherFailed: return "bookmarks_favicons_fetcher_failed"

        case .credentialsDatabaseCleanupFailed: return "credentials_database_cleanup_failed"
        case .credentialsCleanupAttemptedWhileSyncWasEnabled: return "credentials_cleanup_attempted_while_sync_was_enabled"

        case .invalidPayload(let configuration): return "m_d_\(configuration.rawValue)_invalid_payload".lowercased()

        case .burnerTabMisplaced: return "burner_tab_misplaced"

        case .loginItemUpdateError: return "login-item_update-error"

            // Installation Attribution
        case .installationAttribution: return "m_mac_install"

        case .secureVaultKeystoreEventL1KeyMigration: return "m_mac_secure_vault_keystore_event_l1-key-migration"
        case .secureVaultKeystoreEventL2KeyMigration: return "m_mac_secure_vault_keystore_event_l2-key-migration"
        case .secureVaultKeystoreEventL2KeyPasswordMigration: return "m_mac_secure_vault_keystore_event_l2-key-password-migration"

        case .compilationFailed: return "compilation_failed"

            // Bookmarks search and sort feature
        case .bookmarksSortButtonClicked: return "m_mac_sort_bookmarks_button_clicked"
        case .bookmarksSortButtonDismissed: return "m_mac_sort_bookmarks_button_dismissed"
        case .bookmarksSortByName: return "m_mac_sort_bookmarks_by_name"
        case .bookmarksSearchExecuted: return "m_mac_search_bookmarks_executed"
        case .bookmarksSearchResultClicked: return "m_mac_search_result_clicked"

        case .errorPageShownOther: return "m_mac_errorpageshown_other"
        case .errorPageShownWebkitTermination: return "m_mac_errorpageshown_webkittermination"

            // Broken site prompt
        case .pageRefreshThreeTimesWithin20Seconds: return "m_mac_reload-three-times-within-20-seconds"
        case .siteNotWorkingShown: return "m_mac_site-not-working_shown"
        case .siteNotWorkingWebsiteIsBroken: return "m_mac_site-not-working_website-is-broken"

            // Enhanced statistics
        case .usageSegments: return "retention_segments"

            // UserScript
        case .userScriptLoadJSFailed: return "m_mac_debug_user_script_load_js_failed"

        }
    }

    var parameters: [String: String]? {
        switch self {
        case .loginItemUpdateError(let loginItemBundleID, let action, let buildType, let osVersion):
            return ["loginItemBundleID": loginItemBundleID, "action": action, "buildType": buildType, "macosVersion": osVersion]

        case .dailyActiveUser(let isDefault, let isAddedToDock):
            var params = [String: String]()
            params["default_browser"] = isDefault ? "1" : "0"

            if let isAddedToDock = isAddedToDock {
                params["dock"] = isAddedToDock ? "1" : "0"
            }

            return params

        case .dailyFireWindowConfiguration(let startupFireWindow, let openFireWindowByDefault, let fireAnimationEnabled):
            return [
                "startup_fire_window": startupFireWindow ? "true" : "false",
                "open_fire_window_by_default": openFireWindowByDefault ? "true" : "false",
                "fire_animation_enabled": fireAnimationEnabled ? "true" : "false"
            ]

        case .navigation(let kind):
            return ["kind": kind.description]

        case .dataImportFailed(source: _, sourceVersion: let version, error: let error):
            var params = error.pixelParameters

            if let version {
                params[PixelKit.Parameters.sourceBrowserVersion] = version
            }
            return params

        case .dataImportSucceeded(action: _, source: _, sourceVersion: let version):
            var params = [String: String]()

            if let version {
                params[PixelKit.Parameters.sourceBrowserVersion] = version
            }
            return params

        case .favoritesImportFailed(source: _, sourceVersion: let version, error: let error):
            var params = error.pixelParameters

            if let version {
                params[PixelKit.Parameters.sourceBrowserVersion] = version
            }
            return params

        case .favoritesImportSucceeded(source: _, sourceVersion: let version, favoritesBucket: let bucket):
            var params = [PixelKit.Parameters.importedFavorites: bucket.description]

            if let version {
                params[PixelKit.Parameters.sourceBrowserVersion] = version
            }
            return params

        case .dailyOsVersionCounter:
            return [PixelKit.Parameters.osMajorVersion: "\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)"]

        case .dashboardProtectionAllowlistAdd(let triggerOrigin):
            guard let trigger = triggerOrigin else { return nil }
            return [PixelKit.Parameters.dashboardTriggerOrigin: trigger]

        case .dashboardProtectionAllowlistRemove(let triggerOrigin):
            guard let trigger = triggerOrigin else { return nil }
            return [PixelKit.Parameters.dashboardTriggerOrigin: trigger]

        case .syncSuccessRateDaily:
            return nil

        case .vpnBreakageReport(let category, let description, let metadata):
            return [
                PixelKit.Parameters.vpnBreakageCategory: category,
                PixelKit.Parameters.vpnBreakageDescription: description,
                PixelKit.Parameters.vpnBreakageMetadata: metadata
            ]

        case .pproFeedbackFeatureRequest(let description, let source):
            return [
                PixelKit.Parameters.pproIssueDescription: description,
                PixelKit.Parameters.pproIssueSource: source,
            ]
        case .pproFeedbackGeneralFeedback(let description, let source):
            return [
                PixelKit.Parameters.pproIssueDescription: description,
                PixelKit.Parameters.pproIssueSource: source,
            ]
        case .pproFeedbackReportIssue(let source, let category, let subcategory, let description, let metadata):
            return [
                PixelKit.Parameters.pproIssueSource: source,
                PixelKit.Parameters.pproIssueCategory: category,
                PixelKit.Parameters.pproIssueSubcategory: subcategory,
                PixelKit.Parameters.pproIssueDescription: description,
                PixelKit.Parameters.pproIssueMetadata: metadata,
            ]
        case .pproFeedbackSubmitScreenShow(let source, let reportType, let category, let subcategory):
            return [
                PixelKit.Parameters.pproIssueSource: source,
                PixelKit.Parameters.pproIssueReportType: reportType,
                PixelKit.Parameters.pproIssueCategory: category,
                PixelKit.Parameters.pproIssueSubcategory: subcategory,
            ]
        case .pproFeedbackSubmitScreenFAQClick(let source, let reportType, let category, let subcategory):
            return [
                PixelKit.Parameters.pproIssueSource: source,
                PixelKit.Parameters.pproIssueReportType: reportType,
                PixelKit.Parameters.pproIssueCategory: category,
                PixelKit.Parameters.pproIssueSubcategory: subcategory,
            ]

        case .onboardingExceptionReported(let message, let id):
            return [PixelKit.Parameters.assertionMessage: message, "id": id]

            /// Duck Player pixels
        case .duckPlayerDailyUniqueView,
                .duckPlayerViewFromYoutubeViaMainOverlay,
                .duckPlayerViewFromYoutubeViaHoverButton,
                .duckPlayerViewFromYoutubeAutomatic,
                .duckPlayerViewFromSERP,
                .duckPlayerViewFromOther,
                .duckPlayerOverlayYoutubeImpressions,
                .duckPlayerOverlayYoutubeWatchHere,
                .duckPlayerSettingAlwaysDuckPlayer,
                .duckPlayerSettingAlwaysOverlaySERP,
                .duckPlayerSettingAlwaysOverlayYoutube,
                .duckPlayerSettingAlwaysSettings,
                .duckPlayerSettingNeverOverlaySERP,
                .duckPlayerSettingNeverOverlayYoutube,
                .duckPlayerSettingNeverSettings,
                .duckPlayerSettingBackToDefault,
                .duckPlayerWatchOnYoutube,
                .duckPlayerAutoplaySettingsOn,
                .duckPlayerAutoplaySettingsOff,
                .duckPlayerNewTabSettingsOn,
                .duckPlayerNewTabSettingsOff,
                .duckPlayerContingencySettingsDisplayed,
                .duckPlayerWeeklyUniqueView,
                .duckPlayerContingencyLearnMoreClicked,
                .duckPlayerYouTubeSignInErrorImpression,
                .duckPlayerYouTubeAgeRestrictedErrorImpression,
                .duckPlayerYouTubeNoEmbedErrorImpression,
                .duckPlayerYouTubeUnknownErrorImpression,
                .duckPlayerYouTubeSignInErrorDaily,
                .duckPlayerYouTubeAgeRestrictedErrorDaily,
                .duckPlayerYouTubeNoEmbedErrorDaily,
                .duckPlayerYouTubeUnknownErrorDaily:
            return nil

        case .bookmarksSortButtonClicked(let origin),
                .bookmarksSortButtonDismissed(let origin),
                .bookmarksSortByName(let origin),
                .bookmarksSearchExecuted(let origin),
                .bookmarksSearchResultClicked(let origin):
            return ["origin": origin]

        case .fileDownloadCreatePresentersFailed(let osVersion):
            return ["osVersion": osVersion]

        case .autocompleteClickPhrase(from: let source),
                .autocompleteClickHistory(from: let source),
                .autocompleteClickWebsite(from: let source),
                .autocompleteClickBookmark(from: let source),
                .autocompleteClickFavorite(from: let source),
                .autocompleteClickOpenTab(from: let source):
            return ["source": source.rawValue]

        case .updaterAborted(let reason):
            return ["reason": reason]

        case let .userScriptLoadJSFailed(jsFile, error):
            var params = error.pixelParameters
            params[PixelKit.Parameters.jsFile] = jsFile
            return params

        default: return nil
        }
    }

    public enum CompileRulesListType: String, CustomStringConvertible {

        public var description: String { rawValue }

        case tds = "tracker_data"
        case clickToLoad = "click_to_load"
        case blockingAttribution = "blocking_attribution"
        case attributed = "attributed"
        case unknown = "unknown"

    }

    enum NavigationKind: String, CustomStringConvertible {
        var description: String { rawValue }

        case regular
        case client
    }

    enum OnboardingShown: String, CustomStringConvertible {
        var description: String { rawValue }

        init(_ value: Bool) {
            if value {
                self = .onboardingShown
            } else {
                self = .regularNavigation
            }
        }
        case onboardingShown = "onboarding-shown"
        case regularNavigation = "regular-nav"
    }

    enum WaitResult: String, CustomStringConvertible {
        var description: String { rawValue }

        case closed
        case quit
        case success
    }

    enum CompileRulesWaitTime: String, CustomStringConvertible {
        var description: String { rawValue }

        case noWait = "0"
        case lessThan1s = "1"
        case lessThan5s = "5"
        case lessThan10s = "10"
        case lessThan20s = "20"
        case lessThan40s = "40"
        case more = "more"
    }

    enum FormAutofillKind: String, CustomStringConvertible {
        var description: String { rawValue }

        case password
        case card
        case identity
    }

    enum FireButtonOption: String, CustomStringConvertible {
        var description: String { rawValue }

        case tab
        case window
        case allSites = "all-sites"
    }

    enum AccessPoint: String, CustomStringConvertible {
        var description: String { rawValue }

        case button = "source-button"
        case mainMenu = "source-menu"
        case tabMenu = "source-tab-menu"
        case hotKey = "source-keyboard"
        case moreMenu = "source-more-menu"
        case newTab = "source-new-tab"

        init(sender: Any, default: AccessPoint, mainMenuCheck: (NSMenu?) -> Bool = { $0 is MainMenu }) {
            switch sender {
            case let menuItem as NSMenuItem:
                if mainMenuCheck(menuItem.topMenu) {
                    if let event = NSApp.currentEvent,
                       case .keyDown = event.type,
                       event.characters == menuItem.keyEquivalent {

                        self = .hotKey
                    } else {
                        self = .mainMenu
                    }
                } else {
                    self = `default`
                }

            case is NSButton:
                self = .button

            default:
                self = `default`
            }
        }

    }

    enum AutofillParameterKeys {
        static var backfilled = "backfilled"
    }

    public enum CompileTimeBucketAggregation: String, CustomStringConvertible {

        public var description: String { rawValue }

        case lessThan1 = "1"
        case lessThan2 = "2"
        case lessThan3 = "3"
        case lessThan4 = "4"
        case lessThan5 = "5"
        case lessThan6 = "6"
        case lessThan7 = "7"
        case lessThan8 = "8"
        case lessThan9 = "9"
        case lessThan10 = "10"
        case more

        public init(number: Double) {
            switch number {
            case ...1:
                self = .lessThan1
            case ...2:
                self = .lessThan2
            case ...3:
                self = .lessThan3
            case ...4:
                self = .lessThan4
            case ...5:
                self = .lessThan5
            case ...6:
                self = .lessThan6
            case ...7:
                self = .lessThan7
            case ...8:
                self = .lessThan8
            case ...9:
                self = .lessThan9
            case ...10:
                self = .lessThan10
            default:
                self = .more
            }
        }
    }

    public enum FavoritesImportBucket: String, CustomStringConvertible {

        public var description: String { rawValue }

        case none
        case few
        case some
        case many

        public init(count: Int) {
            switch count {
            case 0:
                self = .none
            case ..<6:
                self = .few
            case ..<12:
                self = .some
            default:
                self = .many
            }
        }
    }

    enum AutocompleteSource: String {
        case ntpSearchBox = "ntp_search_box"
        case addressBar = "address_bar"
    }

}
