//
//  UserText.swift
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
import Subscription

enum UserText {

    // MARK: Preferences - Purchase Subscription
    static let preferencesPurchaseSubscriptionTitle = NSLocalizedString("subscription.preferences.purchase.subscription.title", bundle: Bundle.module, value: "DuckDuckGo Subscription", comment: "Title of the preferences pane for purchase subscription")

    static let vpnServiceTitle = NSLocalizedString("subscription.preferences.services.vpn.title", bundle: Bundle.module, value: "VPN", comment: "Title for the VPN service listed in the subscription preferences pane")
    static let vpnServiceDescription = NSLocalizedString("subscription.preferences.services.vpn.description", bundle: Bundle.module, value: "Full-device protection with the VPN built for speed and security.", comment: "Description for the VPN service listed in the subscription preferences pane")
    static let vpnServiceButtonTitle = NSLocalizedString("subscription.preferences.services.vpn.button.title", bundle: Bundle.module, value: "Open", comment: "Title for the VPN service button to open its settings")

    static let personalInformationRemovalServiceTitle = NSLocalizedString("subscription.preferences.services.personal.information.removal.title", bundle: Bundle.module, value: "Personal Information Removal", comment: "Title for the Personal Information Removal service listed in the subscription preferences pane")
    static let personalInformationRemovalServiceDescription = NSLocalizedString("subscription.preferences.services.personal.information.removal.description", bundle: Bundle.module, value: "Find and remove your personal information from sites that store and sell it.", comment: "Description for the Personal Information Removal service listed in the subscription preferences pane")
    static let personalInformationRemovalServiceButtonTitle = NSLocalizedString("subscription.preferences.services.personal.information.removal.button.title", bundle: Bundle.module, value: "Open", comment: "Title for the Personal Information Removal service button to open its settings")

    static let paidAIChatTitle = NSLocalizedString("subscription.preferences.services.paid.ai.chat.title", bundle: Bundle.module, value: "Duck.ai", comment: "Title for the duck.ai premium listed in the subscription preferences pane")
    static let paidAIChatServiceDescription = NSLocalizedString("subscription.preferences.services.paid.ai.chat.description", bundle: Bundle.module, value: "Chat privately with advanced AI models exclusive to subscribers.", comment: "Description for the Duck.ai premium service listed in the subscription preferences pane")

    static let identityTheftRestorationServiceTitle = NSLocalizedString("subscription.preferences.services.identity.theft.restoration.title", bundle: Bundle.module, value: "Identity Theft Restoration", comment: "Title for the Identity Theft Restoration service listed in the subscription preferences pane")
    static let identityTheftRestorationServiceDescription = NSLocalizedString("subscription.preferences.services.identity.theft.restoration.description", bundle: Bundle.module, value: "Restore stolen accounts and financial losses in the event of identity theft.", comment: "Description for the Identity Theft Restoration service listed in the subscription preferences pane")
    static let identityTheftRestorationServiceButtonTitle = NSLocalizedString("subscription.preferences.services.identity.theft.restoration.button.title", bundle: Bundle.module, value: "View", comment: "Title for the Identity Theft Restoration service button to open its settings")

    // MARK: Preferences - Personal Information Removal

    static let preferencesPersonalInformationRemovalTitle = NSLocalizedString("subscription.preferences.personal.information.removal.title", bundle: Bundle.module, value: "Personal Information Removal", comment: "Title of the preferences pane for Personal Information Removal")
    static let openPersonalInformationRemovalButton = NSLocalizedString("subscription.preferences.open.personal.information.removal.button", bundle: Bundle.module, value: "Open Personal Information Removal...", comment: "Title for the preferences pane button to open Personal Information Removal")

    // MARK: Preferences - Duck.ai Premium
    static let preferencesPaidAIChatTitle = NSLocalizedString("subscription.paid.ai.chat.title", bundle: Bundle.module, value: "Duck.ai", comment: "Title of the preferences pane for Duck.ai Pro")
    static let openPaidAIChatButton = NSLocalizedString("subscription.preferences.paid.ai.chat.button", bundle: Bundle.module, value: "Open Duck.ai", comment: "Title for the preferences pane button to open Duck.ai Pro")

    // MARK: Preferences - Identity Theft Restoration

    static let preferencesIdentityTheftRestorationTitle = NSLocalizedString("subscription.preferences.identity.theft.restoration.title", bundle: Bundle.module, value: "Identity Theft Restoration", comment: "Title of the preferences pane for PersoIdentity Theft Restorationmoval")
    static let openIdentityTheftRestorationButton = NSLocalizedString("subscription.preferences.open.identity.theft.restoration.button", bundle: Bundle.module, value: "Open Identity Theft Restoration...", comment: "Title for the preferences pane button to open Identity Theft Restoration")

    // MARK: Preferences - Subscription Settings

    static let preferencesSubscriptionSettingsTitle = NSLocalizedString("subscription.preferences.subscription.settings.title", bundle: Bundle.module, value: "Subscription Settings", comment: "Title of the preferences pane for subscription settings")
    static let subscribedStatusIndicator = NSLocalizedString("subscription.preferences.subscription.settings.subscribed", bundle: Bundle.module, value: "Subscribed", comment: "Title for the status indicator informing that user is currently subscribed")
    static let activatingStatusIndicator = NSLocalizedString("subscription.preferences.subscription.settings.activating", bundle: Bundle.module, value: "Activating", comment: "Title for the status indicator informing that user's subscription is still activating")
    static let freeTrialActiveStatusIndicator = NSLocalizedString("subscription.preferences.subscription.settings.free-trial.active", bundle: Bundle.module, value: "Free Trial Active", comment: "Title for the status indicator informing that user is currently on a Free Trial")

    // MARK: Preferences activate section
    static let activateSectionTitle = NSLocalizedString("subscription.preferences.subscription.add.to.device.title", bundle: Bundle.module, value: "Add Your Subscription to Other Devices", comment: "Title for the subscription preferences section for adding subscription to other devices")
    static func activateSectionCaption(hasEmail: Bool, purchasePlatform: SubscriptionEnvironment.PurchasePlatform) -> String {
        switch (hasEmail, purchasePlatform) {
        case (true, _):
            return NSLocalizedString("subscription.preferences.subscription.activate.with.email.caption",
                                     bundle: Bundle.module,
                                     value: "Use this email to add your subscription to other devices. In the DuckDuckGo browser, go to Settings > DuckDuckGo Subscription > I Have a Subscription.",
                                     comment: "Caption for the subscription preferences activate section when email is added to subscription")
        case (false, .appStore):
            return NSLocalizedString("subscription.preferences.subscription.add.to.device.no.email.app.store.caption",
                                     bundle: Bundle.module,
                                     value: "Add your subscription to your other devices via Apple Account or by linking an email.",
                                     comment: "Caption for the subscription preferences section for activating subscription on other devices while email is not yet added to subscription")
        case (false, _):
            return NSLocalizedString("subscription.preferences.subscription.add.to.device.no.email.stripe.caption",
                                     bundle: Bundle.module,
                                     value: "Add your subscription to your other devices by linking an email.",
                                     comment: "Caption for the subscription preferences section for activating subscription on other devices while email is not yet added to subscription")
        }
    }
    static let activateSectionLearnMoreButton = NSLocalizedString("subscription.preferences.subscription.activate.learn.more.button", bundle: Bundle.module, value: "Learn More", comment: "Button that opens help pages explaining subscription activation via email")

    static let editEmailButton = NSLocalizedString("subscription.preferences.subscription.activate.edit.email.button", bundle: Bundle.module, value: "Edit", comment: "Button for editing email address added to subscription")
    static let addToDeviceButtonTitle = NSLocalizedString("subscription.preferences.subscription.add.to.device.button.title", bundle: Bundle.module, value: "Add to Device...", comment: "Button for adding subscription to other devices")
    static let addToDeviceLinkTitle = NSLocalizedString("subscription.preferences.subscription.add.to.device.link.title", bundle: Bundle.module, value: "Add to Device", comment: "Button for adding subscription to other devices")

    // MARK: Preferences settings section
    static let settingsSectionTitle = NSLocalizedString("subscription.preferences.subscription.settings.section.title", bundle: Bundle.module, value: "Subscription Settings", comment: "Title for the subscription preferences settings section")

    // MARK: Preferences footer
    static let preferencesSubscriptionFooterTitle = NSLocalizedString("subscription.preferences.subscription.footer.title", bundle: Bundle.module, value: "Need help with your DuckDuckGo subscription?", comment: "Title for the subscription preferences pane footer")
    static let preferencesSubscriptionHelpFooterCaption = NSLocalizedString("subscription.preferences.subscription.help.footer.caption", bundle: Bundle.module, value: "Get answers to frequently asked questions or contact subscription support from our help pages. Feature availability varies by country.", comment: "Caption for the subscription preferences pane footer")
    static let viewFaqsButton = NSLocalizedString("subscription.preferences.view.faqs.button", bundle: Bundle.module, value: "FAQs and Support", comment: "Button to open page for FAQs")
    static let preferencesSubscriptionFeedbackTitle = NSLocalizedString("subscription.preferences.feedback.title", bundle: Bundle.module, value: "Send Feedback", comment: "Title for the subscription feedback section")
    static let preferencesSubscriptionFeedbackButton = NSLocalizedString("subscription.preferences.feedback.button", bundle: Bundle.module, value: "Send Feedback", comment: "Title for the subscription feedback button")
    static let preferencesPrivacyPolicyButton = NSLocalizedString("subscription.preferences.privacypolicy.button", bundle: Bundle.module, value: "Privacy Policy and Terms of Service", comment: "Title for the privacy policy button")

    static func preferencesSubscriptionRenewingCaption(billingPeriod: DuckDuckGoSubscription.BillingPeriod, formattedDate: String) -> String {
        let localized: String

        switch billingPeriod {
        case .monthly:
            localized = NSLocalizedString("subscription.preferences.subscription.active.renewing.monthly.caption",
                                          bundle: Bundle.module,
                                          value: "Your monthly subscription renews on %@.",
                                          comment: "Caption for the subscription preferences pane when the monthly subscription is active and will renew, the parameter is date of renewal.")
        case .yearly:
            localized = NSLocalizedString("subscription.preferences.subscription.active.renewing.yearly.caption",
                                          bundle: Bundle.module,
                                          value: "Your annual subscription renews on %@.",
                                          comment: "Caption for the subscription preferences pane when the annual subscription is active and will renew, the parameter is date of renewal.")
        case .unknown:
            localized = NSLocalizedString("subscription.preferences.subscription.active.renewing.unknown.caption",
                                          bundle: Bundle.module,
                                          value: "Your subscription renews on %@.",
                                          comment: "Caption for the subscription preferences pane when the subscription is active and will renew, the parameter is date of renewal.")
        }

        return String(format: localized, formattedDate)
    }

    static func preferencesSubscriptionExpiringCaption(billingPeriod: DuckDuckGoSubscription.BillingPeriod, formattedDate: String) -> String {
        let localized: String

        switch billingPeriod {
        case .monthly:
            localized = NSLocalizedString("subscription.preferences.subscription.active.expiring.monthly.caption",
                                          bundle: Bundle.module,
                                          value: "Your monthly subscription expires on %@.",
                                          comment: "Caption for the subscription preferences pane when the monthly subscription is active and will expire, the parameter is date of expiry.")
        case .yearly:
            localized = NSLocalizedString("subscription.preferences.subscription.active.expiring.yearly.caption",
                                          bundle: Bundle.module,
                                          value: "Your annual subscription expires on %@.",
                                          comment: "Caption for the subscription preferences pane when the annual subscription is active and will expire, the parameter is date of expiry.")
        case .unknown:
            localized = NSLocalizedString("subscription.preferences.subscription.active.expiring.unknown.caption",
                                          bundle: Bundle.module,
                                          value: "Your subscription expires on %@.",
                                          comment: "Caption for the subscription preferences pane when the subscription is active and will expire, the parameter is date of expiry.")
        }

        return String(format: localized, formattedDate)
    }

    static func preferencesSubscriptionExpiredCaption(formattedDate: String) -> String {
        let localized = NSLocalizedString("subscription.preferences.subscription.expired.caption", bundle: Bundle.module, value: "Your DuckDuckGo subscription expired on %@", comment: "Caption for the subscription preferences pane when the subscription has expired. The parameter is date of expiry.")
        return String(format: localized, formattedDate)
    }

    static func preferencesTrialSubscriptionRenewingCaption(billingPeriod: DuckDuckGoSubscription.BillingPeriod, formattedDate: String) -> String {
        let localized: String

        switch billingPeriod {
        case .monthly:
            localized = NSLocalizedString("subscription.preferences.subscription.active.renewing.trial.monthly.caption",
                                          bundle: Bundle.module,
                                          value: "Your free trial ends on %@ & automatically converts to a monthly paid subscription on that day.",
                                          comment: "Monthly trial subscription renewal info where parameter is renewal date. This reads as 'Your free trial ends on (date) & automatically converts to a monthly paid subscription on that day.'")
        case .yearly:
            localized = NSLocalizedString("subscription.preferences.subscription.active.renewing.trial.yearly.caption",
                                          bundle: Bundle.module,
                                          value: "Your free trial ends on %@ & automatically converts to an annual paid subscription on that day.",
                                          comment: "Annual trial subscription renewal info where parameter is renewal date. This reads as 'Your free trial ends on (date) & automatically converts to an annual paid subscription on that day.'")
        case .unknown:
            localized = preferencesSubscriptionRenewingCaption(billingPeriod: .unknown, formattedDate: formattedDate)
        }

        return String(format: localized, formattedDate)
    }

    static func preferencesTrialSubscriptionExpiringCaption(formattedDate: String) -> String {
        let localized = NSLocalizedString("subscription.preferences.subscription.expired.trial.caption",
                                          bundle: Bundle.module,
                                          value: "Your free trial ends on %@ & will not convert to a paid subscription.",
                                          comment: "Trial subscription expiration info where parameter is expiration date. This reads as 'Your free trial ends on (date) & will not convert to a paid subscription.'")
        return String(format: localized, formattedDate)
    }

    static let manageSubscriptionButton = NSLocalizedString("subscription.preferences.manage.subscription.button", bundle: Bundle.module, value: "Manage Subscription", comment: "Button to manage subscription")
    static let updatePlanOrCancelButton = NSLocalizedString("subscription.preferences.update.plan.or.cancel.button", bundle: Bundle.module, value: "Update Plan or Cancel", comment: "Button to update subscription plan or cancel")
    static let removeFromThisDeviceButton = NSLocalizedString("subscription.preferences.remove.from.this.device.button", bundle: Bundle.module, value: "Remove From This Device", comment: "Button to remove subscription from this device")

    // MARK: Preferences when subscription is inactive
    static func preferencesSubscriptionInactiveHeader(isPaidAIChatEnabled: Bool) -> String {
        if isPaidAIChatEnabled {
            return NSLocalizedString("subscription.preferences.subscription.inactive.header.us", bundle: Bundle.module, value: "Secure your Wi-Fi, and chat privately with advanced AI models", comment: "Header for the subscription preferences pane when the subscription is inactive")
        }
        return NSLocalizedString("subscription.preferences.subscription.inactive.header.no.duck.ai.us", bundle: Bundle.module, value: "Protect your connection and identity with one subscription.", comment: "Header for the subscription preferences pane when the subscription is inactive")
    }
    static func preferencesSubscriptionInactiveCaption(region: SubscriptionRegion, isPaidAIChatEnabled: Bool) -> String {
        switch region {
        case .usa:
            if isPaidAIChatEnabled {
                return NSLocalizedString("subscription.preferences.subscription.inactive.us.caption", bundle: Bundle.module, value: "Subscribers get our VPN, advanced AI models in Duck.ai, Personal Information Removal, and Identity Theft Restoration.", comment: "Caption for the subscription preferences pane when the subscription is inactive")
            }
            return NSLocalizedString("subscription.preferences.subscription.inactive.us.caption.no.duck.ai", bundle: Bundle.module, value: "Subscribers get our VPN, Personal Information Removal, and Identity Theft Restoration.", comment: "Caption for the subscription preferences pane when the subscription is inactive")
        case .restOfWorld:
            if isPaidAIChatEnabled {
                return NSLocalizedString("subscription.preferences.subscription.inactive.row.caption", bundle: Bundle.module, value: "Subscribers get our VPN, advanced AI models in Duck.ai, and Identity Theft Restoration.", comment: "Caption for the subscription preferences pane when the subscription is inactive")
            }
            return NSLocalizedString("subscription.preferences.subscription.inactive.row.caption.deprecated", bundle: Bundle.module, value: "Subscribers get our VPN and Identity Theft Restoration.", comment: "Caption for the subscription preferences pane when the subscription is inactive")
        }
    }

    static let purchaseButton = NSLocalizedString("subscription.preferences.purchase.button", bundle: Bundle.module, value: "Subscribe to DuckDuckGo", comment: "Button to open a page where user can learn more and purchase the subscription")
    static let haveSubscriptionButton = NSLocalizedString("subscription.preferences.i.have.a.subscription.button", bundle: Bundle.module, value: "I Have a Subscription", comment: "Button enabling user to activate a subscription user bought earlier or on another device")
    static let purchaseFreeTrialButton = NSLocalizedString("subscription.preferences.purchase.free-trial.button", bundle: Bundle.module, value: "Try Free", comment: "Button to open a page where user can learn more and purchase the subscription")

    // MARK: Preferences when subscription activation is pending

    static let preferencesSubscriptionPendingCaption = NSLocalizedString("subscription.preferences.subscription.pending.caption", bundle: Bundle.module, value: "This is taking longer than usual. Please check back later.", comment: "Caption for the subscription preferences pane when the subscription activation is pending")

    // MARK: Preferences when subscription is expired

    static let viewPlansExpiredButtonTitle = NSLocalizedString("subscription.preferences.button.view.plans", bundle: Bundle.module, value: "View Plans", comment: "Button for viewing subscription plans on expired subscription")

    // MARK: - Change plan or billing dialogs
    static let changeSubscriptionDialogTitle = NSLocalizedString("subscription.dialog.change.title", bundle: Bundle.module, value: "Change Plan or Billing", comment: "Change plan or billing dialog title")
    static let changeSubscriptionGoogleDialogDescription = NSLocalizedString("subscription.dialog.change.google.description", bundle: Bundle.module, value: "Your subscription was purchased through the Google Play Store. To change your plan or billing settings, please open Google Play Store subscription settings on a device signed in to the same Google Account used to purchase your subscription.", comment: "Change plan or billing dialog subtitle description for subscription purchased via Google")
    static let changeSubscriptionAppleDialogDescription = NSLocalizedString("subscription.dialog.change.apple.description", bundle: Bundle.module, value: "Your subscription was purchased through the Apple App Store. To change your plan or billing settings, please go to System Settings > Apple Account > Media and Purchases > Subscriptions > Manage on a device signed in to the same Apple Account used to purchase your subscription.", comment: "Change plan or billing dialog subtitle description for subscription purchased via Apple")
    static let changeSubscriptionDialogDone = NSLocalizedString("subscription.dialog.change.done.button", bundle: Bundle.module, value: "Done", comment: "Button to close the change subscription dialog")
    static let changeSubscriptionDialogInternalMessage = "Your subscription is provided by Dax. Thanks Dax!"

    // MARK: - Remove from this device dialog
    static let removeSubscriptionDialogTitle = NSLocalizedString("subscription.dialog.remove.title", bundle: Bundle.module, value: "Remove from this device?", comment: "Remove subscription from device dialog title")

    static let removeSubscriptionDialogDescription = NSLocalizedString("subscription.dialog.remove.description", bundle: Bundle.module, value: "You will no longer be able to access your DuckDuckGo subscription on this device. This will not cancel your subscription, and it will remain active on your other devices.", comment: "Remove subscription from device dialog subtitle description")
    static let removeSubscriptionDialogCancel = NSLocalizedString("subscription.dialog.remove.cancel.button", bundle: Bundle.module, value: "Cancel", comment: "Button to cancel removing subscription from device")
    static let removeSubscriptionDialogConfirm = NSLocalizedString("subscription.dialog.remove.confirm", bundle: Bundle.module, value: "Remove Subscription", comment: "Button to confirm removing subscription from device")

    // MARK: - Activate subscription modal
    static let addSubscriptionModalTitle = NSLocalizedString("subscription.add.subscription.modal.title", bundle: Bundle.module, value: "Add your subscription to this device", comment: "Title of a view for adding subscription to the device")

    static let addViaEmailTitle = NSLocalizedString("subscription.add.via.email.title", bundle: Bundle.module, value: "Add via email address", comment: "Title of option for adding subscription using email address")
    static let addViaEmailDescription = NSLocalizedString("subscription.add.via.email.description", bundle: Bundle.module, value: "Link an email address to your subscription to add it to this device.", comment: "Description of option for adding subscription using email address")
    static let addViaEmailButtonTitle = NSLocalizedString("subscription.add.via.email.button.title", bundle: Bundle.module, value: "Get Started", comment: "Button title for option for adding subscription using email address")

    static let addViaAppleAccountTitle = NSLocalizedString("subscription.add.via.apple.account.title", bundle: Bundle.module, value: "Add via Apple Account", comment: "Title of option for adding subscription using Apple Account")
    static let addViaAppleAccountDescription = NSLocalizedString("subscription.add.via.apple.account.description", bundle: Bundle.module, value: "Restore your subscription on Apple devices using your Apple Account.", comment: "Description of option for restoring subscription using Apple Account")
    static let addViaAppleAccountButtonTitle = NSLocalizedString("subscription.add.via.apple.account.button.title", bundle: Bundle.module, value: "Restore Purchase", comment: "Button title for option for restoring subscription using Apple Account")

    // MARK: - Activate/share modal buttons
    static let restorePurchaseButton = NSLocalizedString("subscription.modal.restore.purchase.button", bundle: Bundle.module, value: "Restore Purchase", comment: "Button for restoring past subscription purchase")

    // MARK: - Alerts
    static let okButtonTitle = NSLocalizedString("subscription.alert.button.ok", bundle: Bundle.module, value: "OK", comment: "Alert button for confirming it")
    static let cancelButtonTitle = NSLocalizedString("subscription.alert.button.cancel", bundle: Bundle.module, value: "Cancel", comment: "Alert button for dismissing it")
    static let continueButtonTitle = NSLocalizedString("subscription.alert.button.retry", bundle: Bundle.module, value: "Continue", comment: "Alert button for continue action")
    static let viewPlansButtonTitle = NSLocalizedString("subscription.alert.button.view.plans", bundle: Bundle.module, value: "View Plans", comment: "Alert button for viewing subscription plans")
    static let restoreButtonTitle = NSLocalizedString("subscription.alert.button.restore", bundle: Bundle.module, value: "Restore", comment: "Alert button for restoring past subscription purchases")

    static let somethingWentWrongAlertTitle = NSLocalizedString("subscription.alert.something.went.wrong.title", bundle: Bundle.module, value: "Something Went Wrong", comment: "Alert title when unknown error has occurred")
    static let somethingWentWrongAlertDescription = NSLocalizedString("subscription.alert.something.went.wrong.description", bundle: Bundle.module, value: "We’re having trouble connecting. Please try again later.", comment: "Alert message when unknown error has occurred")

    static let subscriptionNotFoundAlertTitle = NSLocalizedString("subscription.alert.subscription.not.found.title", bundle: Bundle.module, value: "Subscription Not Found", comment: "Alert title when subscription was not found")
    static let subscriptionNotFoundAlertDescription = NSLocalizedString("subscription.alert.subscription.not.found.description", bundle: Bundle.module, value: "We couldn’t find a subscription associated with this Apple Account.", comment: "Alert message when subscription was not found")

    static let subscriptionInactiveAlertTitle = NSLocalizedString("subscription.alert.subscription.inactive.title", bundle: Bundle.module, value: "Subscription Not Found", comment: "Alert title when subscription was inactive")
    static let subscriptionInactiveAlertDescription = NSLocalizedString("subscription.alert.subscription.inactive.description", bundle: Bundle.module, value: "The subscription associated with this Apple Account is no longer active.", comment: "Alert message when subscription was inactive")

    static let subscriptionFoundAlertTitle = NSLocalizedString("subscription.alert.subscription.found.title", bundle: Bundle.module, value: "Subscription Found", comment: "Alert title when subscription was found")
    static let subscriptionFoundAlertDescription = NSLocalizedString("subscription.alert.subscription.found.description", bundle: Bundle.module, value: "We found a subscription associated with this Apple Account.", comment: "Alert message when subscription was found")

    static let subscriptionAppleIDSyncFailedAlertTitle = NSLocalizedString("subscription.alert.subscription.apple-id.sync-failed.title", bundle: Bundle.module, value: "Something Went Wrong When Syncing Your Apple Account", comment: "Alert message when the subscription failed to restore")

    // MARK: - Rebranding Message
    static let preferencesSubscriptionRebrandingMessage = NSLocalizedString("subscription.preferences.subscription.rebranding.message", bundle: Bundle.module, value: "Privacy Pro is now just called the DuckDuckGo subscription", comment: "Message informing users that Privacy Pro is now called the DuckDuckGo subscription")
}
