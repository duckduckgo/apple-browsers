//
//  ContextualOnboardingDialogs.swift
//  DuckDuckGo
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
import SwiftUI
import Onboarding
import DuckUI

// MARK: - Try Anonymous Search

struct OnboardingTrySearchDialog: View {
    let title = UserText.Onboarding.ContextualOnboarding.onboardingTryASearchTitle
    let message: String
    let viewModel: OnboardingSearchSuggestionsViewModel
    let onManualDismiss: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            DaxDialogView(logoPosition: .top, onManualDismiss: onManualDismiss) {
                ContextualDaxDialogContent(
                    title: title,
                    titleFont: Font(UIFont.daxTitle3()),
                    message: NSAttributedString(string: message),
                    messageFont: Font.system(size: 16),
                    list: viewModel.itemsList,
                    listAction: viewModel.listItemPressed
                )
            }
            .padding()
        }
    }
}

// MARK: - Try Visiting Site

struct OnboardingTryVisitingSiteDialog: View {
    let logoPosition: DaxDialogLogoPosition
    let viewModel: OnboardingSiteSuggestionsViewModel
    let onManualDismiss: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            DaxDialogView(logoPosition: logoPosition, onManualDismiss: onManualDismiss) {
                OnboardingTryVisitingSiteDialogContent(viewModel: viewModel)
            }
            .padding()
        }
    }
}

struct OnboardingTryVisitingSiteDialogContent: View {
    let message = NSAttributedString(string: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteMessage)

    let viewModel: OnboardingSiteSuggestionsViewModel

    var body: some View {
        ContextualDaxDialogContent(
            title: viewModel.title,
            titleFont: Font(UIFont.daxTitle3()),
            message: message,
            messageFont: Font.system(size: 16),
            list: viewModel.itemsList,
            listAction: viewModel.listItemPressed)
    }
}

// MARK: - Fire Dialog

struct OnboardingFireDialog: View {
    let onManualDismiss: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            DaxDialogView(logoPosition: .left, onManualDismiss: onManualDismiss) {
                VStack {
                    OnboardingFireButtonDialogContent()
                }
            }
            .padding()
        }
    }
}

struct OnboardingFireButtonDialogContent: View {
    private let attributedMessage: NSAttributedString = {
        let boldString = "Fire Button."
        return UserText.Onboarding.ContextualOnboarding.onboardingTryFireButtonMessage
            .attributed
            .withFont(.daxBodyBold(), forText: boldString)
    }()

    var body: some View {
        ContextualDaxDialogContent(
            message: attributedMessage,
            messageFont: Font.system(size: 16)
        )
    }
}

// MARK: - SERP

struct OnboardingFirstSearchDoneDialog: View {
    let cta = UserText.Onboarding.ContextualOnboarding.onboardingGotItButton
    let message: NSAttributedString

    @State private var showNextScreen: Bool = false

    let shouldFollowUp: Bool
    let viewModel: OnboardingSiteSuggestionsViewModel
    let gotItAction: () -> Void
    let onManualDismiss: (_ isShowingNextScreen: Bool) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            DaxDialogView(logoPosition: .left, onManualDismiss: {
                onManualDismiss(showNextScreen)
            }) {
                VStack {
                    if showNextScreen {
                        OnboardingTryVisitingSiteDialogContent(viewModel: viewModel)
                    } else {
                        ContextualDaxDialogContent(
                            message: message,
                            messageFont: Font.system(size: 16),
                            customActionView: AnyView(
                                OnboardingCTAButton(title: cta) {
                                    gotItAction()
                                    withAnimation {
                                        if shouldFollowUp {
                                            showNextScreen = true
                                        }
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - Trackers

struct OnboardingTrackersDoneDialog: View {
    let cta = UserText.Onboarding.ContextualOnboarding.onboardingGotItButton

    @State private var showNextScreen: Bool = false

    let shouldFollowUp: Bool
    let message: NSAttributedString
    let blockedTrackersCTAAction: () -> Void
    let onManualDismiss: (_ isShowingNextScreen: Bool) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            DaxDialogView(logoPosition: .left, onManualDismiss: {
                onManualDismiss(showNextScreen)
            }) {
                VStack {
                    if showNextScreen {
                        OnboardingFireButtonDialogContent()
                    } else {
                        ContextualDaxDialogContent(
                            message: message,
                            messageFont: Font.system(size: 16),
                            customActionView: AnyView(
                                OnboardingCTAButton(title: cta) {
                                    blockedTrackersCTAAction()
                                    if shouldFollowUp {
                                        withAnimation {
                                            showNextScreen = true
                                        }
                                    }
                                }
                            )
                        )
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - End of Journey Dialog

struct OnboardingFinalDialog: View {
    let logoPosition: DaxDialogLogoPosition
    let message: String
    let cta: String
    let dismissAction: () -> Void
    let onManualDismiss: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            DaxDialogView(logoPosition: logoPosition, onManualDismiss: onManualDismiss) {
                ContextualDaxDialogContent(
                    title: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenTitle,
                    titleFont: Font(UIFont.daxTitle3()),
                    message: NSAttributedString(string: message),
                    messageFont: Font.system(size: 16),
                    customActionView: AnyView(customActionView)
                )
            }
            .padding()
        }
    }

    @ViewBuilder
    private var customActionView: some View {
        OnboardingCTAButton(
            title: cta,
            buttonStyle: .primary(),
            action: {
                dismissAction()
            }
        )
    }

}

// MARK: - Privacy Pro Promo

struct PrivacyProPromotionView: View {

    let title: String
    let message: NSAttributedString
    let proceedText: String
    let dismissText: String
    let proceedAction: () -> Void
    let onManualDismiss: () -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            DaxDialogView(logoPosition: .top, onManualDismiss: onManualDismiss) {
                ContextualDaxDialogContent(
                    title: title,
                    titleFont: Font(UIFont.daxTitle3()),
                    message: message,
                    messageFont: Font.system(size: 16),
                    customView: nil,
                    customActionView: AnyView(customActionView)
                )
            }
            .padding()
        }
    }

    @ViewBuilder
    private var customActionView: some View {
        VStack {
            Image(.onboardingPrivacyProPromo)
                .padding([.top, .bottom], 16)
            OnboardingCTAButton(
                title: proceedText,
                buttonStyle: .primary(),
                action: {
                    proceedAction()
                }
            )
        }
    }
}

struct OnboardingCTAButton: View {
    enum ButtonStyle {
        case primary(compact: Bool = false)
        case ghost
    }

    let title: String
    var buttonStyle: ButtonStyle = .primary(compact: true)
    let action: () -> Void


    var body: some View {
        let button = Button(action: action) {
            Text(title)
        }

        switch buttonStyle {
        case .primary(let isCompact):
            button.buttonStyle(PrimaryButtonStyle(compact: isCompact))
        case .ghost:
            button.buttonStyle(GhostButtonStyle())
        }
    }

}

// MARK: - Add To Dock

struct OnboardingAddToDockTutorialContent: View {
    let title = UserText.AddToDockOnboarding.Tutorial.title
    let message = UserText.AddToDockOnboarding.Tutorial.message

    let cta: String
    let isSkipped: Binding<Bool>
    let dismissAction: () -> Void

    var body: some View {
        AddToDockTutorialView(
            title: title,
            message: message,
            cta: cta,
            isSkipped: isSkipped,
            action: dismissAction
        )
    }
}

// MARK: - Preview

#Preview("Try Search") {
    OnboardingTrySearchDialog(
        message: UserText.Onboarding.ContextualOnboarding.onboardingTryASearchMessage,
        viewModel: OnboardingSearchSuggestionsViewModel(
            suggestedSearchesProvider: OnboardingSuggestedSearchesProvider()
        ),
        onManualDismiss: {})
        .padding()
}

#Preview("Try Site Top") {
    OnboardingTryVisitingSiteDialog(
        logoPosition: .top,
        viewModel: OnboardingSiteSuggestionsViewModel(
            title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle,
            suggestedSitesProvider: OnboardingSuggestedSitesProvider(
                surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle
            )
        ),
        onManualDismiss: {}
    )
    .padding()
}

#Preview("Try Site Left") {
    OnboardingTryVisitingSiteDialog(
        logoPosition: .left,
        viewModel: OnboardingSiteSuggestionsViewModel(
            title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle,
            suggestedSitesProvider: OnboardingSuggestedSitesProvider(
                surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle
            )
        ),
        onManualDismiss: {}
    )
    .padding()
}

#Preview("Try Fire Button") {
    OnboardingFireDialog(onManualDismiss: {})
        .padding()
}

#Preview("First Search Dialog") {
    let attributedMessage = {
        let message = UserText.Onboarding.ContextualOnboarding.onboardingFirstSearchDoneMessage
        let boldRange = message.range(of: "DuckDuckGo Search")
        return message.attributed.with(attribute: .font, value: UIFont.daxBodyBold(), in: boldRange)
    }()

    return OnboardingFirstSearchDoneDialog(
        message: attributedMessage,
        shouldFollowUp: true,
        viewModel: OnboardingSiteSuggestionsViewModel(
            title: UserText.Onboarding.ContextualOnboarding.onboardingTryASiteTitle,
            suggestedSitesProvider: OnboardingSuggestedSitesProvider(surpriseItemTitle: UserText.Onboarding.ContextualOnboarding.tryASearchOptionSurpriseMeTitle)
        ),
        gotItAction: {},
        onManualDismiss: { _ in }
    )
    .padding()
}

#Preview("Final Dialog") {
    OnboardingFinalDialog(
        logoPosition: .top,
        message: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenMessage,
        cta: UserText.Onboarding.ContextualOnboarding.onboardingFinalScreenButton,
        dismissAction: { },
        onManualDismiss: {}
    )
    .padding()
}

#Preview("Trackers Dialog") {
    OnboardingTrackersDoneDialog(
        shouldFollowUp: true,
        message: NSAttributedString(string: """
            Heads up! Instagram.com is owned by Facebook.\n\n
            Facebook’s trackers lurk on about 40% of top websites 😱 but don’t worry!\n\n
            I’ll block Facebook from seeing your activity on those sites.
            """
        ),
        blockedTrackersCTAAction: { },
        onManualDismiss: { _ in }
    )
    .padding()
}

#Preview("Add To Dock Tutorial - Light") {
    OnboardingAddToDockTutorialContent(cta: UserText.AddToDockOnboarding.Buttons.startBrowsing, isSkipped: .constant(false), dismissAction: {})
        .preferredColorScheme(.light)
}

#Preview("Add To Dock Tutorial - Dark") {
    OnboardingAddToDockTutorialContent(cta: UserText.AddToDockOnboarding.Buttons.startBrowsing, isSkipped: .constant(false), dismissAction: {})
        .preferredColorScheme(.dark)
}
