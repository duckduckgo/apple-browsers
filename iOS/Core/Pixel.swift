//
//  Pixel.swift
//  DuckDuckGo
//
//  Copyright © 2018 DuckDuckGo. All rights reserved.
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

/// Namespace for the pixel name and parameter catalogue: `Pixel.Event` (`PixelEvent.swift`),
/// `Pixel.BuildTarget` and `PixelParameters`. Firing lives in PixelKit, see `PixelEvent+PixelKit.swift`.
public enum Pixel {
    public enum BuildTarget: String {
        case app
        case vpn
    }
}

public struct PixelParameters {
    public static let url = "url"
    static let test = "test"
    public static let appVersion = "appVersion"

    public static let launchTimeMinMs = "min_launch_duration_ms"
    public static let launchTimeMaxMs = "max_launch_duration_ms"

    public static let autocompleteBookmarkCapable = "bc"
    public static let autocompleteIncludedLocalResults = "sb"

    public static let originatedFromMenu = "om"

    public static let applicationState = "as"
    public static let dataAvailability = "dp"

    static let errorCode = "e"
    static let errorDomain = "d"
    static let errorCount = "c"
    static let underlyingErrorCode = "ue"
    static let underlyingErrorDomain = "ud"

    static let coreDataErrorCode = "coreDataCode"
    static let coreDataErrorDomain = "coreDataDomain"
    static let coreDataErrorEntity = "coreDataEntity"
    static let coreDataErrorAttribute = "coreDataAttribute"

    public static let tabCount = "tc"
    public static let tabType = "tabType"
    public static let domainsCount = "domainsCount"

    public static let widgetSmall = "ws"
    public static let widgetMedium = "wm"
    public static let widgetLarge = "wl"
    public static let widgetError = "we"
    public static let widgetErrorCode = "ec"
    public static let widgetUnavailable = "wx"

    static let removeCookiesTimedOut = "rc"
    static let clearWebDataTimedOut = "cd"

    public static let tabPreviewCountDelta = "cd"

    public static let etag = "et"

    public static let emailCohort = "cohort"
    public static let emailLastUsed = "duck_address_last_used"

    // Cookie clearing
    public static let storeInitialCount = "store_initial_count"
    public static let storeProtectedCount = "store_protected_count"
    public static let didStoreDeletionTimeOut = "did_store_deletion_time_out"
    public static let storageInitialCount = "storage_initial_count"
    public static let storageProtectedCount = "storage_protected_count"
    public static let storeAfterDeletionCount = "store_after_deletion_count"
    public static let storageAfterDeletionCount = "storage_after_deletion_count"
    public static let storeAfterDeletionDiffCount = "store_after_deletion_diff_count"
    public static let storageAfterDeletionDiffCount = "storage_after_deletion_diff_count"

    public static let tabsModelOperation = "operation"
    public static let tabsModelCount = "tabs_model_count"
    public static let tabControllerCacheCount = "tab_controller_cache_count"

    public static let count = "count"
    public static let source = "source"
    public static let aiChatSelectionCount = "selection_count"
    public static let aiChatHadUnsubmittedSelections = "had_unsubmitted_selections"
    public static let aiChatSuggestionScope = "suggestion_scope"
    public static let aiChatSuggestionsSurface = "surface"
    public static let aiChatFirstPromptNewInstall = "first_prompt_new_install"
    public static let cookiePopupPreference = "cookie_popup_preference"
    public static let autoconsentEnabled = "autoconsent_enabled"
    public static let timeSinceShown = "time_since_shown"
    public static let shortcut = "shortcut"
    public static let browsingMode = "browsing_mode"
    public static let tabState = "tab_state"
    public static let authVersion = "authVersion"
    public static let lastUsed = "last_used"

    // Text size is the legacy name
    public static let textZoomInitial = "text_size_initial"
    public static let textZoomUpdated = "text_size_updated"

    public static let canAutoPreviewMIMEType = "can_auto_preview_mime_type"
    public static let mimeType = "mime_type"
    public static let fileSizeGreaterThan10MB = "file_size_greater_than_10mb"
    public static let downloadListCount = "download_list_count"

    public static let bookmarkCount = "bco"

    public static let isBackgrounded = "is_backgrounded"
    public static let isDataProtected = "is_data_protected"

    public static let isInternalUser = "is_internal_user"

    public static let enabled = "enabled"

    // Onboarding subscription promotion
    public static let returningUser = "ru"
    public static let freeTrial = "free_trial"

    // Email manager
    public static let emailKeychainAccessType = "access_type"
    public static let emailKeychainError = "error"
    public static let emailKeychainKeychainStatus = "keychain_status"
    public static let emailKeychainKeychainOperation = "keychain_operation"

    public static let bookmarkErrorOrphanedFolderCount = "bookmark_error_orphaned_count"
    public static let bookmarksLastGoodVersion = "previous_app_version"

    // Remote messaging
    public static let message = "message"
    public static let sheetResult = "success"
    public static let card = "card"
    public static let dismissType = "dismiss_type"

    // Network Protection
    public static let keychainFieldName = "fieldName"
    public static let keychainErrorCode = errorCode
    public static let latency = "latency"
    public static let server = "server"
    public static let networkType = "network_type"
    public static let function = "function"
    public static let line = "line"
    public static let reason = "reason"
    public static let vpnCohort = "cohort"

    // Return user
    public static let returnUserErrorCode = "error_code"
    public static let returnUserOldATB = "old_atb"
    public static let returnUserNewATB = "new_atb"

    // Pixel Experiment
    public static let cohort = "cohort"

    // Ad Attribution
    public static let adAttributionOrgID = "org_id"
    public static let adAttributionCampaignID = "campaign_id"
    public static let adAttributionConversionType = "conversion_type"
    public static let adAttributionAdGroupID = "ad_group_id"
    public static let adAttributionCountryOrRegion = "country_or_region"
    public static let adAttributionKeywordID = "keyword_id"
    public static let adAttributionAdID = "ad_id"
    public static let adAttributionToken = "attribution_token"
    public static let adAttributionIsReinstall = "is_reinstall"

    // Autofill
    public static let countBucket = "count_bucket"
    public static let backfilled = "backfilled"
    public static let isExtension = "is_extension"

    // Data Import
    public static let entryPoint = "entry_point"
    public static let savedCredentials = "saved_credentials"
    public static let skippedCredentials = "skipped_credentials"
    public static let savedCreditCards = "saved_creditcards"
    public static let skippedCreditCards = "skipped_creditcards"

    // Privacy Dashboard
    public static let daysSinceInstall = "daysSinceInstall"
    public static let fromOnboarding = "from_onboarding"

    // Subscription
    public static let subscriptionKeychainAccessType = "access_type"
    public static let subscriptionKeychainError = "error"

    // Sync
    public static let connectedDevices = "connected_devices"
    public static let syncPromptOption = "option"
    public static let uiVersion = "ui_version"

    // Persistent pixel
    public static let originalPixelTimestamp = "originalPixelTimestamp"
    public static let retriedPixel = "retriedPixel"

    public static let time = "time"

    public static let appState = "state"
    public static let appEvent = "event"
    public static let windowChanged = "windowChanged"

    public static let didCallWillEnterForeground = "didCallWillEnterForeground"

    // Background Tasks
    public static let backgroundTaskCategory = "category"

    // Default Browser Prompt
    public static let defaultBrowserPromptNumberOfModalsShown = "numberOfModalsShown"

    // UserScript
    public static let jsFile = "jsFile"

    // New Address Bar Picker
    public static let selection = "selection"

    // Autoplay
    public static let autoplayBlockingMode = "autoplay_blocking_mode"

    // Fire animation
    public static let fireAnimation = "fireAnimationType"

    // Contextual suggested prompts
    public static let suggestionId = "suggestionId"
    public static let suggestionsPageType = "pageType"
    public static let suggestionsAreSmart = "isSmart"
}
