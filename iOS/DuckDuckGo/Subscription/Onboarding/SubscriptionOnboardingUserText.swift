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
}
