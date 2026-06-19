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

import PreviewSnapshots
import SwiftUI
import Utilities

final class DefaultBrowserAndDockPromptInactiveUserViewModel {
    let message: String
    let image: NSImage
    let primaryButtonLabel: String
    let dismissButtonLabel: String
    let primaryButtonAction: () -> Void
    let dismissButtonAction: () -> Void

    init(message: String,
         image: NSImage,
         primaryButtonLabel: String,
         dismissButtonLabel: String,
         primaryButtonAction: @escaping () -> Void,
         dismissButtonAction: @escaping () -> Void) {
        self.message = message
        self.image = image
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
            PromptMessageAndImage(message: viewModel.message, image: viewModel.image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            PromptChartAndButtons(browsersComparisonChart: browsersComparisonChart,
                                  primaryButtonLabel: viewModel.primaryButtonLabel,
                                  dismissButtonLabel: viewModel.dismissButtonLabel,
                                  primaryButtonAction: viewModel.primaryButtonAction,
                                  dismissButtonAction: viewModel.dismissButtonAction)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Metrics.width, height: Metrics.height)
    }
}

private struct PromptMessageAndImage: View {
    let message: String
    let image: NSImage

    var body: some View {
        ZStack {
            Image(.gradientBackground)

            VStack(alignment: .center) {
                promptMessage
                Spacer()
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            .padding([.top, .horizontal], Metrics.padding)
        }
    }

    var promptMessage: some View {
        Text(message)
            .font(.title.weight(.bold))
            .multilineTextAlignment(.center)
            .padding(.top, Metrics.padding)
            .padding(.horizontal, PromptMessageAndImageMetrics.horizontalPadding)
    }

    enum PromptMessageAndImageMetrics {
        static let horizontalPadding: CGFloat = 30
    }
}

private struct PromptChartAndButtons: View {
    let browsersComparisonChart: AnyView
    let primaryButtonLabel: String
    let dismissButtonLabel: String
    let primaryButtonAction: () -> Void
    let dismissButtonAction: () -> Void

    var body: some View {
        VStack(spacing: PromptChartAndButtonsMetrics.verticalSpacing) {
            Spacer()

            browsersComparisonChart

            HStack {
                OnboardingSecondaryCTAButton(title: dismissButtonLabel, action: dismissButtonAction, pillShape: true)
                    .frame(minWidth: 132) // Prevent button from being condensed to an unreadable width in non-English locales
                    .accessibilityIdentifier(AccessibilityIdentifiers.DefaultBrowserAndDockPrompts.dismissButton)
                OnboardingPrimaryCTAButton(title: primaryButtonLabel, action: primaryButtonAction, pillShape: true)
                    .layoutPriority(1) // Resist compression to avoid multiline label if possible
                    .accessibilityIdentifier(AccessibilityIdentifiers.DefaultBrowserAndDockPrompts.confirmButton)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(Metrics.padding)
        .background(Color(designSystemColor: .surfaceCanvas))
    }

    enum PromptChartAndButtonsMetrics {
        static let verticalSpacing: CGFloat = 50
    }
}

private enum Metrics {
    static let padding: CGFloat = 24
    static let width: CGFloat = 868
    static let height: CGFloat = 508
}

struct DefaultBrowserAndDockPromptInactiveUserView_Previews: PreviewProvider {
    typealias State = DefaultBrowserAndDockPromptInactiveUserViewModel

    static var previews: some View {
        snapshots.previews
    }

    static let snapshots = PreviewSnapshots<State>(
        configurations: [
            .init(name: "Set As Default", state: .setAsDefault),
            .init(name: "Add To Dock", state: .addToDock),
            .init(name: "Add & Set As Default", state: .addToDockAndSetAsDefault)
        ],
        configure: {
            DefaultBrowserAndDockPromptInactiveUserView(
                viewModel: $0,
                browsersComparisonChart: AnyView(DefaultBrowserAndDockPromptUIProvider().makeBrowserComparisonChart())
            )
        }
    )
}
