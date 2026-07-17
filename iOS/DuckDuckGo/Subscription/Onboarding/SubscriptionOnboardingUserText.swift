//
//  SubscriptionOnboardingUserText.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import FoundationExtensions

extension UserText {

    public static let subscriptionOnboardingWelcomeVPNTitle = NotLocalizedString("subscription.onboarding.welcome.vpn.title", value: "VPN", comment: "Welcome screen feature-list row title for the VPN")
    public static let subscriptionOnboardingWelcomeVPNBody = NotLocalizedString("subscription.onboarding.welcome.vpn.body", value: "Get an extra layer of online protection with the VPN built for speed and simplicity.", comment: "Welcome screen feature-list row description for the VPN")

    public static let subscriptionOnboardingWelcomeIDTRTitle = NotLocalizedString("subscription.onboarding.welcome.idtr.title", value: "Identity Theft Restoration", comment: "Welcome screen feature-list row title for Identity Theft Restoration")
    public static let subscriptionOnboardingWelcomeIDTRBody = NotLocalizedString("subscription.onboarding.welcome.idtr.body", value: "If your identity is stolen, let us handle the stress and expense to help you restore it.", comment: "Welcome screen feature-list row description for Identity Theft Restoration")

    public static let subscriptionOnboardingWelcomeDuckAITitle = NotLocalizedString("subscription.onboarding.welcome.duck-ai.title", value: "Advanced Models in Duck.ai", comment: "Welcome screen feature-list row title for the advanced Duck.ai models")
    public static let subscriptionOnboardingWelcomeDuckAIBody = NotLocalizedString("subscription.onboarding.welcome.duck-ai.body", value: "You get advanced AI models and higher limits, all anonymized by DuckDuckGo.", comment: "Welcome screen feature-list row description for the advanced Duck.ai models")

    public static let subscriptionOnboardingWelcomePIRTitle = NotLocalizedString("subscription.onboarding.welcome.pir.title", value: "Personal Information Removal", comment: "Welcome screen feature-list row title for Personal Information Removal")
    public static let subscriptionOnboardingWelcomePIRBody = NotLocalizedString("subscription.onboarding.welcome.pir.body", value: "Find and remove your personal info from sites that store and sell it, reducing spam.", comment: "Welcome screen feature-list row description for Personal Information Removal")

    public static let subscriptionOnboardingChecklistVPNTitle = NotLocalizedString("subscription.onboarding.checklist.vpn.title", value: "DuckDuckGo VPN", comment: "Completion checklist row title for the VPN")
    public static let subscriptionOnboardingChecklistIDTRTitle = NotLocalizedString("subscription.onboarding.checklist.idtr.title", value: "Identity Theft Restoration", comment: "Completion checklist row title for Identity Theft Restoration")
    public static let subscriptionOnboardingChecklistDuckAITitle = NotLocalizedString("subscription.onboarding.checklist.duck-ai.title", value: "Advanced Models in Duck.ai", comment: "Completion checklist row title for the advanced Duck.ai models")
    public static let subscriptionOnboardingChecklistPIRTitle = NotLocalizedString("subscription.onboarding.checklist.pir.title", value: "Personal Information Removal", comment: "Completion checklist row title for Personal Information Removal")

    public static let subscriptionOnboardingProgressCompletedLabel = NotLocalizedString("subscription.onboarding.progress.completed.label", value: "completed", comment: "Label shown below the completion percentage on the onboarding progress card")
    public static let subscriptionOnboardingProgressAccessibilityLabel = NotLocalizedString("subscription.onboarding.progress.accessibility.label", value: "Setup progress", comment: "VoiceOver label for the onboarding setup progress bar")
    public static let subscriptionOnboardingProgressAccessibilityValue = NotLocalizedString("subscription.onboarding.progress.accessibility.value", value: "%ld%% complete", comment: "VoiceOver value for the setup progress bar. %ld is the completion percentage; %% renders a literal percent sign")

    public static let subscriptionOnboardingDuckAIPlusMarker = NotLocalizedString("subscription.onboarding.duck-ai.plus-marker", value: "· PLUS", comment: "Inline marker shown after a premium (paid-tier) Duck.ai model name in the model picker")

    public static let subscriptionOnboardingVPNTipNoCapsTitle = NotLocalizedString("subscription.onboarding.vpn-tip.no-caps.title", value: "No data or speed caps", comment: "VPN tips carousel card title: no data or speed caps")
    public static let subscriptionOnboardingVPNTipNoCapsBody = NotLocalizedString("subscription.onboarding.vpn-tip.no-caps.body", value: "Stream, download, game, use as much data as you want. Unlike other VPNs, we only throttle connections to prevent abuse or network errors.", comment: "VPN tips carousel card description: no data or speed caps")

    public static let subscriptionOnboardingVPNTipSpeedTitle = NotLocalizedString("subscription.onboarding.vpn-tip.speed.title", value: "All VPNs affect internet speeds", comment: "VPN tips carousel card title: all VPNs affect internet speeds")
    public static let subscriptionOnboardingVPNTipSpeedBody = NotLocalizedString("subscription.onboarding.vpn-tip.speed.body", value: "Routing internet traffic through VPNs can cause speed differences. DuckDuckGo VPN is designed to make speed issues imperceptible for most browsing.", comment: "VPN tips carousel card description: all VPNs affect internet speeds")

    public static let subscriptionOnboardingVPNTipBlockedTitle = NotLocalizedString("subscription.onboarding.vpn-tip.blocked.title", value: "Some sites & apps block VPNs", comment: "VPN tips carousel card title: some sites and apps block VPNs")
    public static let subscriptionOnboardingVPNTipBlockedBody = NotLocalizedString("subscription.onboarding.vpn-tip.blocked.body", value: "No matter which VPN you use, you'll need to turn it off to use certain sites and apps. For example, banking apps may block VPNs to help prevent fraudulent activity.", comment: "VPN tips carousel card description: some sites and apps block VPNs")

    public static let subscriptionOnboardingProgressRowCompletedValue = NotLocalizedString("subscription.onboarding.progress.row.completed.value", value: "Completed", comment: "VoiceOver value announced for a completed protection row on the progress checklist")
    public static let subscriptionOnboardingProgressRowNotCompletedValue = NotLocalizedString("subscription.onboarding.progress.row.not-completed.value", value: "Not completed", comment: "VoiceOver value announced for an incomplete protection row on the progress checklist")

    public static let subscriptionOnboardingDuckAIModelSelectedValue = NotLocalizedString("subscription.onboarding.duck-ai.model.selected.value", value: "Selected", comment: "VoiceOver value announced for the currently selected model row in the Duck.ai model picker")

    public static let subscriptionOnboardingFreeTrialTitlePrefix = NotLocalizedString("subscription.onboarding.free-trial.title.prefix", value: "Day ", comment: "Free-trial calendar card title text before the current trial-day number, e.g. the 'Day ' in 'Day 3 of your free trial'")
    public static let subscriptionOnboardingFreeTrialTitleSuffix = NotLocalizedString("subscription.onboarding.free-trial.title.suffix", value: " of your free trial", comment: "Free-trial calendar card title text after the current trial-day number, e.g. the ' of your free trial' in 'Day 3 of your free trial'")
    public static let subscriptionOnboardingFreeTrialBillingFormat = NotLocalizedString("subscription.onboarding.free-trial.billing", value: "Billing starts on %@", comment: "Free-trial calendar card billing line. %@ is the formatted billing start date, e.g. 'May 7, 2026'")

    public static let subscriptionOnboardingSetupCardTitleFormat = NotLocalizedString("subscription.onboarding.setup-card.title", value: "Setup %ld%% complete", comment: "Subscription Settings re-entry card title. %ld is the completion percentage; %% renders a literal percent sign")
    public static let subscriptionOnboardingSetupCardBody = NotLocalizedString("subscription.onboarding.setup-card.body", value: "Some premium protections aren't active yet", comment: "Subscription Settings re-entry card body line prompting the customer to finish setup")
    public static let subscriptionOnboardingSetupCardButton = NotLocalizedString("subscription.onboarding.setup-card.button", value: "Continue Setup", comment: "Subscription Settings re-entry card primary CTA that resumes the onboarding flow")

    public static let subscriptionOnboardingVPNInfoVisibleIP = NotLocalizedString("subscription.onboarding.vpn-info.visible-ip", value: "Your IP Address is Visible", comment: "VPN info card overline shown while the VPN is off and the customer's real IP address is visible")
    public static let subscriptionOnboardingVPNInfoHiddenIP = NotLocalizedString("subscription.onboarding.vpn-info.hidden-ip", value: "Your IP Address is Hidden", comment: "VPN info card overline shown once the VPN is on and the customer's real IP address is hidden")
    public static let subscriptionOnboardingVPNInfoNewIP = NotLocalizedString("subscription.onboarding.vpn-info.new-ip", value: "Your New IP Address", comment: "VPN info card overline for the new (VPN egress) IP address shown once the VPN is on")

    public static let subscriptionOnboardingStepIndicatorFormat = NotLocalizedString("subscription.onboarding.step-indicator", value: "Step %1$ld of %2$ld", comment: "Top-bar progress indicator on an onboarding section screen. %1$ld is the current step number and %2$ld the total number of steps, e.g. 'Step 2 of 4'")
    public static let subscriptionOnboardingBackButtonAccessibilityLabel = NotLocalizedString("subscription.onboarding.back-button.accessibility-label", value: "Back", comment: "VoiceOver label for the back button in the top bar of an onboarding section screen")
    public static let subscriptionOnboardingCloseButtonAccessibilityLabel = NotLocalizedString("subscription.onboarding.close-button.accessibility-label", value: "Close", comment: "VoiceOver label for the close button in the top bar of an onboarding section screen")

    // MARK: - VPN activation section

    public static let subscriptionOnboardingVPNActivationOffTitle = NotLocalizedString("subscription.onboarding.vpn.activation.off.title", value: "DuckDuckGo VPN is Off", comment: "VPN activation screen title shown while the VPN is off")
    public static let subscriptionOnboardingVPNActivationOnTitle = NotLocalizedString("subscription.onboarding.vpn.activation.on.title", value: "DuckDuckGo VPN is On", comment: "VPN activation screen title shown once the VPN is on")
    public static let subscriptionOnboardingVPNActivationOffExplanation = NotLocalizedString("subscription.onboarding.vpn.activation.off.explanation", value: "Connect to secure all of your device’s internet traffic. [Learn More](learn-more)", comment: "VPN activation screen explanation shown while the VPN is off. The bracketed 'Learn More' is a tappable link to the VPN info screen")
    public static let subscriptionOnboardingVPNActivationOnExplanation = NotLocalizedString("subscription.onboarding.vpn.activation.on.explanation", value: "All device internet traffic is being secured through the VPN. [Learn More](learn-more)", comment: "VPN activation screen explanation shown once the VPN is on. The bracketed 'Learn More' is a tappable link to the VPN info screen")
    public static let subscriptionOnboardingVPNActivationOffFootnote = NotLocalizedString("subscription.onboarding.vpn.activation.off.footnote", value: "When the VPN is off, sites and apps can see this info and use it to connect your activity across sessions.", comment: "VPN activation screen footnote below the visible-IP card, shown while the VPN is off")
    public static let subscriptionOnboardingVPNActivationOnFootnote = NotLocalizedString("subscription.onboarding.vpn.activation.on.footnote", value: "When the VPN is on, sites and apps see your new IP instead, helping keep your activity anonymous.", comment: "VPN activation screen footnote below the IP cards, shown once the VPN is on")
    public static let subscriptionOnboardingVPNActivationTurnOnButton = NotLocalizedString("subscription.onboarding.vpn.activation.turn-on.button", value: "Turn On VPN", comment: "VPN activation screen primary button that starts the VPN")
    public static let subscriptionOnboardingVPNActivationNextButton = NotLocalizedString("subscription.onboarding.vpn.activation.next.button", value: "Next", comment: "VPN activation screen primary button shown once the VPN is on, advancing the flow")

    public static let subscriptionOnboardingVPNProtectionShielding = NotLocalizedString("subscription.onboarding.vpn.protection.shielding", value: "Shielding your online activity", comment: "VPN activation screen protection row: shielding online activity")
    public static let subscriptionOnboardingVPNProtectionHidingLocation = NotLocalizedString("subscription.onboarding.vpn.protection.hiding-location", value: "Hiding your location & IP address", comment: "VPN activation screen protection row: hiding location and IP address")
    public static let subscriptionOnboardingVPNProtectionBlockingSites = NotLocalizedString("subscription.onboarding.vpn.protection.blocking-sites", value: "Blocking harmful sites", comment: "VPN activation screen protection row: blocking harmful sites")

    // MARK: - VPN tips screen

    public static let subscriptionOnboardingVPNTipsTitle = NotLocalizedString("subscription.onboarding.vpn.tips.title", value: "What to know about using your VPN", comment: "Title of the post-activation VPN tips screen")
    public static let subscriptionOnboardingVPNTipsDoneButton = NotLocalizedString("subscription.onboarding.vpn.tips.done.button", value: "Got it", comment: "VPN tips screen primary button that returns to the VPN activation screen")

    // MARK: - VPN info sheet

    public static let subscriptionOnboardingVPNInfoTitle = NotLocalizedString("subscription.onboarding.vpn.info.title", value: "DuckDuckGo VPN", comment: "Title of the VPN 'Learn More' info sheet")
    public static let subscriptionOnboardingVPNInfoExplanation = NotLocalizedString("subscription.onboarding.vpn.info.explanation", value: "Encrypt your connection across browsers and apps, and hide your location and IP address with a VPN built for speed and simplicity.", comment: "Explanation under the title on the VPN info sheet")

    public static let subscriptionOnboardingVPNInfoDevicesTitle = NotLocalizedString("subscription.onboarding.vpn.info.devices.title", value: "Devices", comment: "VPN info sheet feature card title: devices")
    public static let subscriptionOnboardingVPNInfoDevicesBody = NotLocalizedString("subscription.onboarding.vpn.info.devices.body", value: "Full-device coverage on up to 5 devices at once.", comment: "VPN info sheet feature card body: devices")
    public static let subscriptionOnboardingVPNInfoNoLoggingTitle = NotLocalizedString("subscription.onboarding.vpn.info.no-logging.title", value: "Strict no-logging policy", comment: "VPN info sheet feature card title: no-logging policy")
    public static let subscriptionOnboardingVPNInfoNoLoggingBody = NotLocalizedString("subscription.onboarding.vpn.info.no-logging.body", value: "We don’t log or store data that can connect you to your online activity. And because connections are encrypted, your internet provider can’t see your online traffic either.", comment: "VPN info sheet feature card body: no-logging policy")
    public static let subscriptionOnboardingVPNInfoEasyToUseTitle = NotLocalizedString("subscription.onboarding.vpn.info.easy-to-use.title", value: "Easy to use", comment: "VPN info sheet feature card title: easy to use")
    public static let subscriptionOnboardingVPNInfoEasyToUseBody = NotLocalizedString("subscription.onboarding.vpn.info.easy-to-use.body", value: "No need to install a separate app — connect in just one click in the DuckDuckGo browser and check VPN status at a glance.", comment: "VPN info sheet feature card body: easy to use")
    public static let subscriptionOnboardingVPNInfoFastReliableTitle = NotLocalizedString("subscription.onboarding.vpn.info.fast-reliable.title", value: "Fast and reliable", comment: "VPN info sheet feature card title: fast and reliable")
    public static let subscriptionOnboardingVPNInfoFastReliableBody = NotLocalizedString("subscription.onboarding.vpn.info.fast-reliable.body", value: "With servers across the US and Europe, you get the closest connection to maximize speed and stability and can choose to connect to any of our servers worldwide.", comment: "VPN info sheet feature card body: fast and reliable")
    public static let subscriptionOnboardingVPNInfoDataLeakTitle = NotLocalizedString("subscription.onboarding.vpn.info.data-leak.title", value: "Data leak prevention", comment: "VPN info sheet feature card title: data leak prevention")
    public static let subscriptionOnboardingVPNInfoDataLeakBody = NotLocalizedString("subscription.onboarding.vpn.info.data-leak.body", value: "Blocks all internet traffic automatically if the VPN tunnel fails, preventing accidental data leaks until the VPN tunnel is either restored or manually disabled.", comment: "VPN info sheet feature card body: data leak prevention")
    public static let subscriptionOnboardingVPNInfoSecureDNSTitle = NotLocalizedString("subscription.onboarding.vpn.info.secure-dns.title", value: "Secure DNS", comment: "VPN info sheet feature card title: secure DNS")
    public static let subscriptionOnboardingVPNInfoSecureDNSBody = NotLocalizedString("subscription.onboarding.vpn.info.secure-dns.body", value: "We route DNS queries through our secure VPN to stop traffic and IP address leaks to your internet provider.", comment: "VPN info sheet feature card body: secure DNS")
    public static let subscriptionOnboardingVPNInfoAlwaysOnTitle = NotLocalizedString("subscription.onboarding.vpn.info.always-on.title", value: "Always-on", comment: "VPN info sheet feature card title: always-on")
    public static let subscriptionOnboardingVPNInfoAlwaysOnBody = NotLocalizedString("subscription.onboarding.vpn.info.always-on.body", value: "If your VPN connection gets interrupted, it reconnects automatically. Active by default on iOS, Mac, or Windows, or enabled in settings on Android.", comment: "VPN info sheet feature card body: always-on")
    public static let subscriptionOnboardingVPNInfoWireGuardTitle = NotLocalizedString("subscription.onboarding.vpn.info.wireguard.title", value: "Secure WireGuard protocol", comment: "VPN info sheet feature card title: WireGuard protocol")
    public static let subscriptionOnboardingVPNInfoWireGuardBody = NotLocalizedString("subscription.onboarding.vpn.info.wireguard.body", value: "We use the fast, secure, and open-source WireGuard protocol.", comment: "VPN info sheet feature card body: WireGuard protocol")
}
