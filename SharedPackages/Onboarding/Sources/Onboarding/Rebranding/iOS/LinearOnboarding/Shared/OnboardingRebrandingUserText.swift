//
//  OnboardingRebrandingUserText.swift
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

#if os(iOS)
import Foundation
import UIKit
import DesignResourcesKit

private func localized(_ key: String, value: String, comment: String) -> String {
    NSLocalizedString(key, bundle: .main, value: value, comment: comment)
}

public extension OnboardingRebranding {

    enum UserText {
        static let onboardingWelcomeHeader = localized("onboardingWelcomeHeader", value: "Welcome to DuckDuckGo!", comment: "")
        static let onboardingSkip = localized("onboardingSkip", value: "Skip", comment: "")

        enum Onboarding {
            enum Intro {
                static let title = localized(
                    "onboarding.highlights.intro.title",
                    value: "Hi there.\n\nReady for a faster browser that keeps you protected?",
                    comment: "The title of the onboarding dialog popup"
                )
                static let continueCTA = localized(
                    "onboarding.intro.cta",
                    value: "Let’s do it!",
                    comment: "Button to continue the onboarding process"
                )
                static let skipCTA = localized(
                    "onboarding.intro.cta.skip",
                    value: "I’ve been here before",
                    comment: "Button to skip the onboarding process"
                )

                enum Debug {
                    static let skip = localized(
                        "onboarding.intro.debug.skip",
                        value: "Skip",
                        comment: "Button to skip the onboarding process"
                    )
                }
            }

            enum Skip {
                static let title = localized(
                    "onboarding.skip.title",
                    value: "Got it! I’ll skip the other tips.",
                    comment: "The title of the skip onboarding dialog popup"
                )
                static let message = localized(
                    "onboarding.skip.message",
                    value: "Remember: you can delete all your tabs, history, and browsing data in two taps with the Fire Button 🔥",
                    comment: "The message of the skip onboarding dialog popup."
                )
                static let confirmSkipOnboardingCTA = localized(
                    "onboarding.skip.cta.confirmSkip",
                    value: "Start Browsing",
                    comment: "The title of the button to skip the onboarding and start browsing."
                )
                static let resumeOnboardingCTA = localized(
                    "onboarding.skip.cta.resumeOnboarding",
                    value: "Show Tutorial",
                    comment: "The title of the button to resume the onboarding."
                )
            }

            enum BrowsersComparison {
                static let title = localized(
                    "onboarding.highlights.browsers.title",
                    value: "Protections activated!",
                    comment: "The title of the dialog to show the privacy features that DuckDuckGo offers"
                )
                static let cta = localized(
                    "onboarding.browsers.cta",
                    value: "Choose Your Browser",
                    comment: "Button to change the default browser"
                )
            }

            enum AppIconSelection {
                static let title = localized(
                    "onboarding.highlights.appIconSelection.title",
                    value: "Which color looks best on me?",
                    comment: "The title of the onboarding dialog popup to select the preferred App icon."
                )
                static let message = localized(
                    "onboarding.highlights.appIconSelection.message",
                    value: "Pick your app icon:",
                    comment: "The subheader of the onboarding dialog popup to select the preferred App icon."
                )
                static let cta = localized(
                    "onboarding.highlights.appIconSelection.cta",
                    value: "Next",
                    comment: "The title of the CTA to progress to the next onboarding screen."
                )
            }

            enum AddressBarPosition {
                static let title = localized(
                    "onboarding.highlights.addressBarPosition.title",
                    value: "Where should I put your address bar?",
                    comment: "The title of the onboarding dialog popup to select the preferred address bar position."
                )
                static let topTitle = localized(
                    "onboarding.highlights.addressBarPosition.top.title",
                    value: "Top",
                    comment: "The title of the option to set the address bar to the top."
                )
                static let defaultOption = localized(
                    "onboarding.highlights.addressBarPosition.default",
                    value: "(default)",
                    comment: "Indicates what address bar option (Top/Bottom) is the default one. E.g. Top (Default)"
                )
                static let topMessage = localized(
                    "onboarding.highlights.addressBarPosition.top.message",
                    value: "Easy to see",
                    comment: "The message of the option to set the address bar to the top."
                )
                static let bottomTitle = localized(
                    "onboarding.highlights.addressBarPosition.bottom.title",
                    value: "Bottom",
                    comment: "The title of the option to set the address bar to the bottom."
                )
                static let bottomMessage = localized(
                    "onboarding.highlights.addressBarPosition.bottom.message",
                    value: "Easy to reach",
                    comment: "The message of the option to set the address bar to the bottom."
                )
                static let cta = localized(
                    "onboarding.highlights.addressBarPosition.cta",
                    value: "Next",
                    comment: "The title of the CTA to progress to the next onboarding screen."
                )
            }

            enum SearchExperience {
                static let title = localized(
                    "onboarding.highlights.searchExperience.title",
                    value: "Want easy access to private AI chat?",
                    comment: "The title of the onboarding dialog popup to select the preferred search experience."
                )
                static let footer = localized(
                    "onboarding.highlights.searchExperience.footer",
                    value: "AI features are private and optional. You can make changes in Settings > AI Features.",
                    comment: "The footer disclaimer text for the search experience onboarding screen."
                )
                static let cta = localized(
                    "onboarding.highlights.searchExperience.cta",
                    value: "Next",
                    comment: "The title of the CTA to progress to the next onboarding screen."
                )

                static func footerAttributed() -> NSAttributedString {
                    let settingsPathBold = localized(
                        "onboarding.highlights.searchExperience.footer.settings-path-bold",
                        value: "Settings > AI Features.",
                        comment: "Bold text 'Settings > AI Features.'. This will replace the placeholder (%@) in the footer string."
                    )

                    let fullText = String(format: localized(
                        "onboarding.highlights.searchExperience.footer.formatted",
                        value: "AI features are private and optional. You can make changes in %@",
                        comment: "Full footer message with placeholder: %@ will be replaced with 'Settings > AI Features.' (bold)."),
                        settingsPathBold
                    )

                    let attributedString = NSMutableAttributedString(string: fullText)
                    let boldAttributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.daxFootnoteSemibold()
                    ]

                    if let settingsPathRange = fullText.range(of: settingsPathBold) {
                        attributedString.addAttributes(boldAttributes, range: NSRange(settingsPathRange, in: fullText))
                    }

                    return attributedString
                }
            }
        }

        enum AddToDockOnboarding {
            enum Promo {
                static let title = localized(
                    "contextual.onboarding.addToDock.promo.title",
                    value: "Add me to your Dock!",
                    comment: "The title of the onboarding dialog popup that promotes adding the DDG browser icon to the dock."
                )
                static let introMessage = localized(
                    "contextual.onboarding.addToDock.promo.intro.message",
                    value: "I’ll nest in easy reach for all your daily browsing.",
                    comment: "The message of the onboarding dialog popup that promotes adding the DDG browser icon to the dock."
                )
            }

            enum Tutorial {
                static let title = localized(
                    "contextual.onboarding.addToDock.tutorial.title",
                    value: "Adding me to your Dock is easy.",
                    comment: "The title of the onboarding dialog popup that explains how to add the DDG browser icon to the dock."
                )
                static let message = localized(
                    "contextual.onboarding.addToDock.tutorial.message",
                    value: "Find the DuckDuckGo icon on your Home Screen. Then press and drag it into place. That’s it!",
                    comment: "The message of the onboarding dialog popup that explains how to add the DDG browser icon to the dock."
                )
            }

            enum Buttons {
                static let tutorial = localized(
                    "contextual.onboarding.addToDock.buttons.tutorial",
                    value: "Show Me How",
                    comment: "Button of the onboarding dialog. On click it shows a dialog with a tutorial video about how to add the DDG browser icon to the device dock."
                )
                static let startBrowsing = localized(
                    "contextual.onboarding.addToDock.buttons.startBrowsing",
                    value: "Start Browsing",
                    comment: "Button on the last screen of the onboarding, it will dismiss the onboarding screen."
                )
                static let skip = localized(
                    "contextual.onboarding.addToDock.buttons.skip",
                    value: "Skip",
                    comment: "Button to continue the onboarding process"
                )
                static let gotIt = localized(
                    "onboarding.addToDock.buttons.gotIt",
                    value: "Got It",
                    comment: "Button on the Add to Dock tutorial screen of the onboarding, it will proceed to the next step of the onboarding."
                )
            }
        }
    }
}
#endif
