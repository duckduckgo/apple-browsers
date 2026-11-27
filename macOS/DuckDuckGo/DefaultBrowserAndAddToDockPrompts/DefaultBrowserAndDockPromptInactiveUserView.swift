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
                .accessibilityHidden(true)

            HStack(spacing: Metrics.padding) {
                PromptMessageAndImage(message: viewModel.message, image: viewModel.image)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                PromptChartAndButtons(browsersComparisonChart: browsersComparisonChart,
                                      primaryButtonLabel: viewModel.primaryButtonLabel,
                                      dismissButtonLabel: viewModel.dismissButtonLabel,
                                      primaryButtonAction: viewModel.primaryButtonAction,
                                      dismissButtonAction: viewModel.dismissButtonAction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.trailing, Metrics.padding)
        }
        .frame(width: Metrics.width, height: Metrics.height)
        .background(Color(singleUseColor: .defaultBrowserAndDockPromptBackground))
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
                .padding(.top, Metrics.topPadding)
                .padding(.horizontal, Metrics.padding)

            Spacer(minLength: Metrics.padding)

            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width, maxHeight: image.size.height)
                .frame(maxWidth: .infinity)
                .padding(.bottom, PromptMessageAndImageMetrics.imageBottomPadding)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    enum PromptMessageAndImageMetrics {
        static let imageBottomPadding: CGFloat = 20
    }
}

private struct PromptChartAndButtons: View {
    let browsersComparisonChart: AnyView
    let primaryButtonLabel: String
    let dismissButtonLabel: String
    let primaryButtonAction: () -> Void
    let dismissButtonAction: () -> Void

    var body: some View {
        VStack {
            browsersComparisonChart

            Spacer()

            HStack {
                Button(action: dismissButtonAction) {
                    buttonLabel(dismissButtonLabel)
                }
                .buttonStyle(DismissActionButtonStyle(topPadding: 0, bottomPadding: 0, pillShape: true, stateColors: .themedDismissButton))
                .fixedSize() // Prevent button from being condensed to an unreadable width in non-English locales
                .accessibilityIdentifier(AccessibilityIdentifiers.DefaultBrowserAndDockPrompts.dismissButton)

                Button(action: primaryButtonAction) {
                    buttonLabel(primaryButtonLabel)
                }
                .buttonStyle(DefaultActionButtonStyle(enabled: true, topPadding: 0, bottomPadding: 0, stateColors: .themedActionButton, pillShape: true))
                .shadow(radius: 1, x: -0.6, y: 0.6)
                .layoutPriority(1) // Resist compression to avoid multiline label if possible
                .accessibilityIdentifier(AccessibilityIdentifiers.DefaultBrowserAndDockPrompts.confirmButton)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.bottom, Metrics.padding)
        .padding(.top, Metrics.topPadding)
    }

    private func buttonLabel(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, Metrics.buttonLabelHorizontalPadding)
            .frame(height: Metrics.buttonHeight)
    }
}

private enum Metrics {
    static let padding: CGFloat = 36
    static let topPadding: CGFloat = 48
    static let buttonLabelHorizontalPadding: CGFloat = 8
    static let buttonHeight: CGFloat = 32
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
