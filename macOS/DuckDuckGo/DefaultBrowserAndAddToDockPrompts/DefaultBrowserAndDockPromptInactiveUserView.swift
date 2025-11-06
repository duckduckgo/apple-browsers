//
//  DefaultBrowserAndDockPromptInactiveUserView.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

import SwiftUI

final class DefaultBrowserAndDockPromptInactiveUserViewModel {
    let message: String
    let primaryButtonLabel: String
    let dismissButtonLabel: String
    let primaryButtonAction: () -> Void
    let dismissButtonAction: () -> Void

    init(message: String,
         primaryButtonLabel: String,
         dismissButtonLabel: String,
         primaryButtonAction: @escaping () -> Void,
         dismissButtonAction: @escaping () -> Void) {
        self.message = message
        self.primaryButtonLabel = primaryButtonLabel
        self.dismissButtonLabel = dismissButtonLabel
        self.primaryButtonAction = primaryButtonAction
        self.dismissButtonAction = dismissButtonAction
    }
}

struct DefaultBrowserAndDockPromptInactiveUserView: View {

    let viewModel: DefaultBrowserAndDockPromptInactiveUserViewModel

    let browsersComparisonChart: AnyView

    var body: some View {
        HStack(spacing: .zero) {
            ZStack {
                Image(.gradientBackground)

                VStack(alignment: .center) {
                    Text(viewModel.message)
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                        .padding(.top, Metrics.padding)
                        .padding(.horizontal, Metrics.Message.horizontalPadding)
                    Spacer()
                    Image(.daxSearch)
                }
                .padding([.top, .horizontal], Metrics.padding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: Metrics.Chart.verticalSpacing) {
                Spacer()

                browsersComparisonChart

                HStack {
                    OnboardingSecondaryCTAButton(title: viewModel.dismissButtonLabel, action: viewModel.dismissButtonAction)
                    OnboardingPrimaryCTAButton(title: viewModel.primaryButtonLabel, action: viewModel.primaryButtonAction)
                        .layoutPriority(1) // Resist compression to avoid multiline label if possible
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Metrics.padding)
            .background(Color(designSystemColor: .surfaceCanvas))
        }
        .frame(width: Metrics.width, height: Metrics.height)
    }
}

private enum Metrics {
    static let padding: CGFloat = 24
    static let width: CGFloat = 868
    static let height: CGFloat = 508

    enum Message {
        static let horizontalPadding: CGFloat = 30
    }

    enum Chart {
        static let verticalSpacing: CGFloat = 50
    }
}

#Preview("Set As Default (Light)") {
    let setAsDefault = DefaultBrowserAndDockPromptInactiveUserViewModel(
        message: UserText.setAsDefaultInactiveUserPromptMessage,
        primaryButtonLabel: UserText.setAsDefaultInactiveUserPrimaryAction,
        dismissButtonLabel: UserText.setAsDefaultAndAddToDockInactiveUserDismissAction,
        primaryButtonAction: {},
        dismissButtonAction: {})
    return DefaultBrowserAndDockPromptInactiveUserView(
        viewModel: setAsDefault,
        browsersComparisonChart: AnyView(DefaultBrowserAndDockPromptUIProvider().makeBrowserComparisonChart()))
        .preferredColorScheme(.light)
}

#Preview("Set As Default (Dark)") {
    let setAsDefault = DefaultBrowserAndDockPromptInactiveUserViewModel(
        message: UserText.setAsDefaultInactiveUserPromptMessage,
        primaryButtonLabel: UserText.setAsDefaultInactiveUserPrimaryAction,
        dismissButtonLabel: UserText.setAsDefaultAndAddToDockInactiveUserDismissAction,
        primaryButtonAction: {},
        dismissButtonAction: {})
    return DefaultBrowserAndDockPromptInactiveUserView(
        viewModel: setAsDefault,
        browsersComparisonChart: AnyView(DefaultBrowserAndDockPromptUIProvider().makeBrowserComparisonChart()))
        .preferredColorScheme(.dark)
}

#Preview("Add To Dock") {
    let addToDock = DefaultBrowserAndDockPromptInactiveUserViewModel(
        message: UserText.addToDockInactiveUserPromptMessage,
        primaryButtonLabel: UserText.addToDockInactiveUserPrimaryAction,
        dismissButtonLabel: UserText.setAsDefaultAndAddToDockInactiveUserDismissAction,
        primaryButtonAction: {},
        dismissButtonAction: {})
    return DefaultBrowserAndDockPromptInactiveUserView(
        viewModel: addToDock,
        browsersComparisonChart: AnyView(DefaultBrowserAndDockPromptUIProvider().makeBrowserComparisonChart()))
}

#Preview("Add & Set As Default") {
    let addToDockAndSetAsDefault = DefaultBrowserAndDockPromptInactiveUserViewModel(
        message: UserText.bothSetAsDefaultAndAddToDockInactiveUserPromptMessage,
        primaryButtonLabel: UserText.bothSetAsDefaultAndAddToDockInactiveUserPrimaryAction,
        dismissButtonLabel: UserText.setAsDefaultAndAddToDockInactiveUserDismissAction,
        primaryButtonAction: {},
        dismissButtonAction: {})
    return DefaultBrowserAndDockPromptInactiveUserView(
        viewModel: addToDockAndSetAsDefault,
        browsersComparisonChart: AnyView(DefaultBrowserAndDockPromptUIProvider().makeBrowserComparisonChart()))
}
