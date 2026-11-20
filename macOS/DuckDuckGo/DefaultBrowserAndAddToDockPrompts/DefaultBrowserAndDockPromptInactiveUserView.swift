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
import SwiftUIExtensions
import Utilities

#if DEBUG
import PreviewSnapshots
#endif

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
        ZStack(alignment: .bottomLeading) {
            Image(.defaultBrowserAndDockPromptBackground)

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
        }
        .frame(width: Metrics.width, height: Metrics.height)
        .background(Color(designSystemColor: .surfaceTertiary))
    }
}

private struct PromptMessageAndImage: View {
    let message: String
    let image: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: .zero) {
            Text(message)
                .font(.title.weight(.bold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, PromptMessageAndImageMetrics.messageTopPadding)
                .padding(.leading, PromptMessageAndImageMetrics.messageLeadingPadding)
                .padding(.trailing, PromptMessageAndImageMetrics.messageTrailingPadding)

            Spacer(minLength: Metrics.padding)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                .padding(.leading, PromptMessageAndImageMetrics.imageLeadingPadding)
                .padding(.bottom, PromptMessageAndImageMetrics.imageBottomPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum PromptMessageAndImageMetrics {
        static let messageTopPadding: CGFloat = 48
        static let messageLeadingPadding: CGFloat = 36
        static let messageTrailingPadding: CGFloat = 72
        static let imageLeadingPadding: CGFloat = 92
        static let imageBottomPadding: CGFloat = 18
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
                Button(action: dismissButtonAction) {
                    Text(dismissButtonLabel)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 24)
                        .frame(minWidth: 132) // Prevent button from being condensed to an unreadable width in non-English locales
                }
                .buttonStyle(DismissActionButtonStyle(pillShape: true, stateColors: .themedDismissButton))
                .accessibilityIdentifier(AccessibilityIdentifiers.DefaultBrowserAndDockPrompts.dismissButton)
                OnboardingPrimaryCTAButton(title: primaryButtonLabel, action: primaryButtonAction, pillShape: true)
                    .layoutPriority(1) // Resist compression to avoid multiline label if possible
                    .accessibilityIdentifier(AccessibilityIdentifiers.DefaultBrowserAndDockPrompts.confirmButton)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(Metrics.padding)
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

#if DEBUG
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
#endif
