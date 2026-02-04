//
//  SubscriptionPixel.swift
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

import Foundation
import Subscription
import PixelKit
import Networking

// swiftlint:disable private_over_fileprivate
#if APPSTORE
fileprivate let appDistribution = "store"
#else
fileprivate let appDistribution = "direct"
#endif
// swiftlint:enable private_over_fileprivate

enum SubscriptionPixel: PixelKitEvent {
    // Subscription
    case subscriptionActive(AuthVersion)
    case subscriptionOfferScreenImpression
    case subscriptionPurchaseAttempt
    case subscriptionPurchaseFailureOther
    case subscriptionPurchaseFailureStoreError(Error)
    case subscriptionPurchaseFailureBackendError
    case subscriptionPurchaseFailureAccountNotCreated(Error)
    case subscriptionPurchaseSuccess
    case subscriptionRestorePurchaseOfferPageEntry
    case subscriptionRestorePurchaseClick
    case subscriptionRestorePurchaseSettingsMenuEntry
    case subscriptionRestorePurchaseEmailStart
    case subscriptionRestorePurchaseStoreStart
    case subscriptionRestorePurchaseEmailSuccess
    case subscriptionRestorePurchaseStoreSuccess
    case subscriptionRestorePurchaseStoreFailureNotFound
    case subscriptionRestorePurchaseStoreFailureOther
    case subscriptionRestoreAfterPurchaseAttempt
    case subscriptionActivated
    case subscriptionWelcomeAddDevice
    case subscriptionWelcomeVPN
    case subscriptionWelcomePersonalInformationRemoval
    case subscriptionWelcomeAIChat
    case subscriptionWelcomeIdentityRestoration
    case subscriptionSettings
    case subscriptionVPNSettings
    case subscriptionPersonalInformationRemovalSettings
    case subscriptionPersonalInformationRemovalSettingsImpression
    case subscriptionPaidAIChatSettings
    case subscriptionPaidAIChatSettingsImpression
    case subscriptionIdentityRestorationSettings
    case subscriptionIdentityRestorationSettingsImpression
    case subscriptionManagementEmail
    case subscriptionManagementPlanBilling
    case subscriptionManagementRemoval
    case subscriptionPurchaseStripeSuccess
    case subscriptionSuccessfulSubscriptionAttribution
    // Web pixels
    case subscriptionOfferMonthlyPriceClick
    case subscriptionOfferYearlyPriceClick
    case subscriptionAddEmailSuccess
    case subscriptionWelcomeFAQClick
    // Tier Options
    case subscriptionTierOptionsRequested
    case subscriptionTierOptionsSuccess
    case subscriptionTierOptionsFailure(error: Error)
    case subscriptionTierOptionsUnexpectedProTier
    // Plan Change
    case subscriptionViewAllPlansClick
    case subscriptionUpgradeClick
    // Auth
    case subscriptionInvalidRefreshTokenDetected(SubscriptionPixelHandler.Source)
    case subscriptionInvalidRefreshTokenSignedOut
    case subscriptionInvalidRefreshTokenRecovered
    case subscriptionAuthV2GetTokensError(AuthTokensCachePolicy, SubscriptionPixelHandler.Source, Error)
    // Pending Transaction
    case subscriptionPurchaseSuccessAfterPendingTransaction(SubscriptionPixelHandler.Source)
    case subscriptionPendingTransactionApproved(SubscriptionPixelHandler.Source)
    // KeychainManager
    case subscriptionKeychainManagerDataAddedToTheBacklog(SubscriptionPixelHandler.Source)
    case subscriptionKeychainManagerDeallocatedWithBacklog(SubscriptionPixelHandler.Source)
    case subscriptionKeychainManagerDataWroteFromBacklog(SubscriptionPixelHandler.Source)
    case subscriptionKeychainManagerFailedToWriteDataFromBacklog(SubscriptionPixelHandler.Source)
    // Toolbar Button Upsell
    case subscriptionToolbarButtonShown
    case subscriptionToolbarButtonPopoverShown
    case subscriptionToolbarButtonPopoverDismissButtonClicked
    case subscriptionToolbarButtonPopoverProceedButtonClicked
    // Win-back Offer
    case subscriptionWinBackOfferLaunchPromptShown
    case subscriptionWinBackOfferLaunchPromptCTAClicked
    case subscriptionWinBackOfferLaunchPromptDismissed

    case subscriptionWinBackOfferMainMenuShown
    case subscriptionWinBackOfferMainMenuClicked

    case subscriptionWinBackOfferSettingsSidebarBadgeShown

    case subscriptionWinBackOfferSettingsPageShown
    case subscriptionWinBackOfferSettingsPageCTAClicked

    case subscriptionWinBackOfferNewTabPageShown
    case subscriptionWinBackOfferNewTabPageCTAClicked
    case subscriptionWinBackOfferNewTabPageDismissed

    // New Tab Page Next Steps Card
    case subscriptionNewTabPageNextStepsCardClicked
    case subscriptionNewTabPageNextStepsCardDismissed

    // Free Trial Journey
    case freeTrialStart
    case freeTrialVPNActivation(activationDay: FreeTrialActivationDay)
    case freeTrialPIRActivation(activationDay: FreeTrialActivationDay)

    var name: String {
        switch self {
        case .subscriptionActive: return "m_mac_\(appDistribution)_privacy-pro_app_subscription_active"
        case .subscriptionOfferScreenImpression: return "m_mac_\(appDistribution)_privacy-pro_offer_screen_impression"
        case .subscriptionPurchaseAttempt: return "m_mac_\(appDistribution)_privacy-pro_terms-conditions_subscribe_click"
        case .subscriptionPurchaseFailureOther: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-purchase_failure_other"
        case .subscriptionPurchaseFailureStoreError: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-purchase_failure_store"
        case .subscriptionPurchaseFailureBackendError: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-purchase_failure_backend"
        case .subscriptionPurchaseFailureAccountNotCreated: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-purchase_failure_account-creation"
        case .subscriptionPurchaseSuccess: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-purchase_success"
        case .subscriptionRestorePurchaseOfferPageEntry: return "m_mac_\(appDistribution)_privacy-pro_offer_restore-purchase_click"
        case .subscriptionRestorePurchaseClick: return "m_mac_\(appDistribution)_privacy-pro_settings_restore-purchase_click"
        case .subscriptionRestorePurchaseSettingsMenuEntry: return "m_mac_\(appDistribution)_privacy-pro_settings_restore-purchase_click"
        case .subscriptionRestorePurchaseEmailStart: return "m_mac_\(appDistribution)_privacy-pro_activate-subscription_enter-email_click"
        case .subscriptionRestorePurchaseStoreStart: return "m_mac_\(appDistribution)_privacy-pro_activate-subscription_restore-purchase_click"
        case .subscriptionRestorePurchaseEmailSuccess: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-restore-using-email_success"
        case .subscriptionRestorePurchaseStoreSuccess: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-restore-using-store_success"
        case .subscriptionRestorePurchaseStoreFailureNotFound: return "m_mac_\(appDistribution)_privacy-pro_subscription-restore-using-store_failure_not-found"
        case .subscriptionRestorePurchaseStoreFailureOther: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-restore-using-store_failure_other"
        case .subscriptionRestoreAfterPurchaseAttempt: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-restore-after-purchase-attempt_success"
        case .subscriptionActivated: return "m_mac_\(appDistribution)_privacy-pro_app_subscription_activated_u"
        case .subscriptionWelcomeAddDevice: return "m_mac_\(appDistribution)_privacy-pro_welcome_add-device_click_u"
        case .subscriptionWelcomeVPN: return "m_mac_\(appDistribution)_privacy-pro_welcome_vpn_click_u"
        case .subscriptionWelcomePersonalInformationRemoval: return "m_mac_\(appDistribution)_privacy-pro_welcome_personal-information-removal_click_u"
        case .subscriptionWelcomeAIChat:
            return "m_mac_\(appDistribution)_privacy-pro_welcome_ai-chat_click_u"
        case .subscriptionWelcomeIdentityRestoration: return "m_mac_\(appDistribution)_privacy-pro_welcome_identity-theft-restoration_click_u"
        case .subscriptionSettings: return "m_mac_\(appDistribution)_privacy-pro_settings_screen_impression"
        case .subscriptionVPNSettings: return "m_mac_\(appDistribution)_privacy-pro_settings_vpn_click"
        case .subscriptionPersonalInformationRemovalSettings: return "m_mac_\(appDistribution)_privacy-pro_settings_personal-information-removal_click"
        case .subscriptionPersonalInformationRemovalSettingsImpression: return "m_mac_\(appDistribution)_privacy-pro_settings_personal-information-removal_impression"
        case .subscriptionPaidAIChatSettings: return "m_mac_\(appDistribution)_privacy-pro_settings_paid-ai-chat_click"
        case .subscriptionPaidAIChatSettingsImpression: return "m_mac_\(appDistribution)_privacy-pro_settings_paid-ai-chat_impression"
        case .subscriptionIdentityRestorationSettings: return "m_mac_\(appDistribution)_privacy-pro_settings_identity-theft-restoration_click"
        case .subscriptionIdentityRestorationSettingsImpression: return "m_mac_\(appDistribution)_privacy-pro_settings_identity-theft-restoration_impression"
        case .subscriptionManagementEmail: return "m_mac_\(appDistribution)_privacy-pro_manage-email_edit_click"
        case .subscriptionManagementPlanBilling: return "m_mac_\(appDistribution)_privacy-pro_settings_change-plan-or-billing_click"
        case .subscriptionManagementRemoval: return "m_mac_\(appDistribution)_privacy-pro_settings_remove-from-device_click"
        case .subscriptionPurchaseStripeSuccess: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-purchase_stripe_success"
        case .subscriptionSuccessfulSubscriptionAttribution: return "m_mac_\(appDistribution)_subscribe"
            // Web
        case .subscriptionOfferMonthlyPriceClick: return "m_mac_\(appDistribution)_privacy-pro_offer_monthly-price_click"
        case .subscriptionOfferYearlyPriceClick: return "m_mac_\(appDistribution)_privacy-pro_offer_yearly-price_click"
        case .subscriptionAddEmailSuccess: return "m_mac_\(appDistribution)_privacy-pro_app_add-email_success_u"
        case .subscriptionWelcomeFAQClick: return "m_mac_\(appDistribution)_privacy-pro_welcome_faq_click_u"
            // Tier Options
        case .subscriptionTierOptionsRequested: return "m_mac_\(appDistribution)_subscription_tier-options_requested"
        case .subscriptionTierOptionsSuccess: return "m_mac_\(appDistribution)_subscription_tier-options_success"
        case .subscriptionTierOptionsFailure: return "m_mac_\(appDistribution)_subscription_tier-options_failure"
        case .subscriptionTierOptionsUnexpectedProTier: return "m_mac_\(appDistribution)_subscription_tier-options_unexpected-pro-tier"
            // Plan Change
        case .subscriptionViewAllPlansClick: return "m_mac_\(appDistribution)_subscription_settings_view-all-plans_click"
        case .subscriptionUpgradeClick: return "m_mac_\(appDistribution)_subscription_settings_upgrade_click"
            // Auth
        case .subscriptionInvalidRefreshTokenDetected: return "m_mac_\(appDistribution)_privacy-pro_auth_invalid_refresh_token_detected"
        case .subscriptionInvalidRefreshTokenSignedOut: return "m_mac_\(appDistribution)_privacy-pro_auth_invalid_refresh_token_signed_out"
        case .subscriptionInvalidRefreshTokenRecovered: return "m_mac_\(appDistribution)_privacy-pro_auth_invalid_refresh_token_recovered"
        case .subscriptionAuthV2GetTokensError: return "m_mac_\(appDistribution)_privacy-pro_auth_v2_get_tokens_error"
        case .subscriptionPurchaseSuccessAfterPendingTransaction: return "m_mac_\(appDistribution)_privacy-pro_purchase_success_after_pending_transaction"
        case .subscriptionPendingTransactionApproved: return "m_mac_\(appDistribution)_privacy-pro_app_subscription-purchase_pending_transaction_approved"
            // KeychainManager
        case .subscriptionKeychainManagerDataAddedToTheBacklog: return "m_mac_privacy-pro_keychain_manager_data_added_to_backlog"
        case .subscriptionKeychainManagerDeallocatedWithBacklog: return "m_mac_privacy-pro_keychain_manager_deallocated_with_backlog"
        case .subscriptionKeychainManagerDataWroteFromBacklog: return "m_mac_privacy-pro_keychain_manager_data_wrote_from_backlog"
        case .subscriptionKeychainManagerFailedToWriteDataFromBacklog: return "m_mac_privacy-pro_keychain_manager_failed_to_write_data_from_backlog"
            // Toolbar Button Upsell
        case .subscriptionToolbarButtonShown: return "m_mac_privacy-pro_toolbar_button_shown"
        case .subscriptionToolbarButtonPopoverShown: return "m_mac_privacy-pro_toolbar_button_popover_shown"
        case .subscriptionToolbarButtonPopoverDismissButtonClicked: return "m_mac_privacy-pro_toolbar_button_popover_dismiss_button_clicked"
        case .subscriptionToolbarButtonPopoverProceedButtonClicked: return "m_mac_privacy-pro_toolbar_button_popover_proceed_button_clicked"
            // Win-back Offer
        case .subscriptionWinBackOfferLaunchPromptShown: return "m_mac_\(appDistribution)_privacy-pro_winback_launch_prompt_shown"
        case .subscriptionWinBackOfferLaunchPromptCTAClicked: return "m_mac_\(appDistribution)_privacy-pro_winback_launch_prompt_cta_clicked"
        case .subscriptionWinBackOfferLaunchPromptDismissed: return "m_mac_\(appDistribution)_privacy-pro_winback_launch_prompt_dismissed"

        case .subscriptionWinBackOfferMainMenuShown: return "m_mac_\(appDistribution)_privacy-pro_winback_main_menu_badge_shown"
        case .subscriptionWinBackOfferMainMenuClicked: return "m_mac_\(appDistribution)_privacy-pro_winback_main_menu_clicked"

        case .subscriptionWinBackOfferSettingsSidebarBadgeShown: return "m_mac_\(appDistribution)_privacy-pro_winback_settings_sidebar_badge_shown"

        case .subscriptionWinBackOfferSettingsPageShown: return "m_mac_\(appDistribution)_privacy-pro_winback_settings_page_shown"
        case .subscriptionWinBackOfferSettingsPageCTAClicked: return "m_mac_\(appDistribution)_privacy-pro_winback_settings_page_cta_clicked"

        case .subscriptionWinBackOfferNewTabPageShown: return "m_mac_\(appDistribution)_privacy-pro_winback_new_tab_page_shown"

        case .subscriptionWinBackOfferNewTabPageCTAClicked: return "m_mac_\(appDistribution)_privacy-pro_winback_new_tab_page_cta_clicked"

        case .subscriptionWinBackOfferNewTabPageDismissed: return "m_mac_\(appDistribution)_privacy-pro_winback_new_tab_page_dismissed"

            // New Tab Page Next Steps Card
        case .subscriptionNewTabPageNextStepsCardClicked: return "m_mac_\(appDistribution)_privacy-pro_new_tab_page_next_steps_card_clicked"
        case .subscriptionNewTabPageNextStepsCardDismissed: return "m_mac_\(appDistribution)_privacy-pro_new_tab_page_next_steps_card_dismissed"
            // Free Trial Journey
        case .freeTrialStart: return "m_mac_\(appDistribution)_privacy-pro_freetrial_start"
        case .freeTrialVPNActivation: return "m_mac_\(appDistribution)_privacy-pro_freetrial_vpn_activation"
        case .freeTrialPIRActivation: return "m_mac_\(appDistribution)_privacy-pro_freetrial_pir_activation"
        }
    }

    private struct SubscriptionPixelsDefaults {
        static let errorKey = "error"
        static let policyCacheKey = "policycache"
        static let sourceKey = "source"
        static let platformKey = "platform"
        static let activationDayKey = "activation_day"
    }

    var parameters: [String: String]? {
        switch self {
        case .subscriptionInvalidRefreshTokenDetected(let source),
                .subscriptionPurchaseSuccessAfterPendingTransaction(let source),
                .subscriptionPendingTransactionApproved(let source),
                .subscriptionKeychainManagerDataAddedToTheBacklog(let source),
                .subscriptionKeychainManagerDeallocatedWithBacklog(let source),
                .subscriptionKeychainManagerDataWroteFromBacklog(let source),
                .subscriptionKeychainManagerFailedToWriteDataFromBacklog(let source):
            return [SubscriptionPixelsDefaults.sourceKey: source.description]
        case .subscriptionAuthV2GetTokensError(let policy, let source, let error):
            return [SubscriptionPixelsDefaults.errorKey: error.localizedDescription,
                    SubscriptionPixelsDefaults.policyCacheKey: policy.description,
                    SubscriptionPixelsDefaults.sourceKey: source.description]
        case .subscriptionActive(let authVersion):
            return [AuthVersion.key: authVersion.rawValue]
        case .freeTrialVPNActivation(let activationDay),
             .freeTrialPIRActivation(let activationDay):
            return [SubscriptionPixelsDefaults.activationDayKey: activationDay.rawValue]
        default:
            return nil
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .subscriptionActive,
                .subscriptionOfferScreenImpression,
                .subscriptionPurchaseAttempt,
                .subscriptionPurchaseFailureOther,
                .subscriptionPurchaseFailureStoreError,
                .subscriptionPurchaseFailureBackendError,
                .subscriptionPurchaseFailureAccountNotCreated,
                .subscriptionPurchaseSuccess,
                .subscriptionRestorePurchaseOfferPageEntry,
                .subscriptionRestorePurchaseClick,
                .subscriptionRestorePurchaseSettingsMenuEntry,
                .subscriptionRestorePurchaseEmailStart,
                .subscriptionRestorePurchaseStoreStart,
                .subscriptionRestorePurchaseEmailSuccess,
                .subscriptionRestorePurchaseStoreSuccess,
                .subscriptionRestorePurchaseStoreFailureNotFound,
                .subscriptionRestorePurchaseStoreFailureOther,
                .subscriptionRestoreAfterPurchaseAttempt,
                .subscriptionActivated,
                .subscriptionWelcomeAddDevice,
                .subscriptionWelcomeVPN,
                .subscriptionWelcomePersonalInformationRemoval,
                .subscriptionWelcomeAIChat,
                .subscriptionWelcomeIdentityRestoration,
                .subscriptionSettings,
                .subscriptionVPNSettings,
                .subscriptionPersonalInformationRemovalSettings,
                .subscriptionPersonalInformationRemovalSettingsImpression,
                .subscriptionPaidAIChatSettings,
                .subscriptionPaidAIChatSettingsImpression,
                .subscriptionIdentityRestorationSettings,
                .subscriptionIdentityRestorationSettingsImpression,
                .subscriptionManagementEmail,
                .subscriptionManagementPlanBilling,
                .subscriptionManagementRemoval,
                .subscriptionPurchaseStripeSuccess,
                .subscriptionSuccessfulSubscriptionAttribution,
                .subscriptionOfferMonthlyPriceClick,
                .subscriptionOfferYearlyPriceClick,
                .subscriptionAddEmailSuccess,
                .subscriptionWelcomeFAQClick,
                .subscriptionInvalidRefreshTokenDetected,
                .subscriptionInvalidRefreshTokenSignedOut,
                .subscriptionInvalidRefreshTokenRecovered,
                .subscriptionAuthV2GetTokensError,
                .subscriptionPurchaseSuccessAfterPendingTransaction,
                .subscriptionPendingTransactionApproved,
                .subscriptionKeychainManagerDataAddedToTheBacklog,
                .subscriptionKeychainManagerDeallocatedWithBacklog,
                .subscriptionKeychainManagerDataWroteFromBacklog,
                .subscriptionKeychainManagerFailedToWriteDataFromBacklog,
                .subscriptionToolbarButtonShown,
                .subscriptionToolbarButtonPopoverShown,
                .subscriptionToolbarButtonPopoverDismissButtonClicked,
                .subscriptionToolbarButtonPopoverProceedButtonClicked,
                .subscriptionWinBackOfferLaunchPromptShown,
                .subscriptionWinBackOfferLaunchPromptCTAClicked,
                .subscriptionWinBackOfferLaunchPromptDismissed,
                .subscriptionWinBackOfferMainMenuShown,
                .subscriptionWinBackOfferMainMenuClicked,
                .subscriptionWinBackOfferSettingsSidebarBadgeShown,
                .subscriptionWinBackOfferSettingsPageShown,
                .subscriptionWinBackOfferSettingsPageCTAClicked,
                .subscriptionWinBackOfferNewTabPageShown,
                .subscriptionWinBackOfferNewTabPageCTAClicked,
                .subscriptionWinBackOfferNewTabPageDismissed,
                .subscriptionNewTabPageNextStepsCardClicked,
                .subscriptionNewTabPageNextStepsCardDismissed,
                .subscriptionTierOptionsRequested,
                .subscriptionTierOptionsSuccess,
                .subscriptionTierOptionsFailure,
                .subscriptionTierOptionsUnexpectedProTier,
                .subscriptionViewAllPlansClick,
                .subscriptionUpgradeClick,
                .freeTrialStart,
                .freeTrialVPNActivation,
                .freeTrialPIRActivation:
            return [.pixelSource]
        }
    }

}

enum SubscriptionErrorPixel: PixelKitEvent {

    case subscriptionKeychainAccessError(accessType: AccountKeychainAccessType,
                                       accessError: AccountKeychainAccessError,
                                       source: KeychainErrorSource,
                                       authVersion: KeychainErrorAuthVersion )

    var name: String {
        switch self {
        case .subscriptionKeychainAccessError: return "m_mac_privacy-pro_keychain_access_error"
        }
    }

    var parameters: [String: String]? {
        switch self {
        case .subscriptionKeychainAccessError(let accessType, let accessError, let source, let authVersion):
            return [
                "access_type": accessType.rawValue,
                "error": accessError.description,
                "source": source.rawValue,
                "authVersion": authVersion.rawValue
            ]
        }
    }

    var standardParameters: [PixelKitStandardParameter]? {
        switch self {
        case .subscriptionKeychainAccessError:
            return [.pixelSource]
        }
    }

}
