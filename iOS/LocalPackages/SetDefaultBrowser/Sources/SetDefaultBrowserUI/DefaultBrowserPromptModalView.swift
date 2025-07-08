//
//  DefaultBrowserPromptModalView.swift
//  DuckDuckGo
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
import DesignResourcesKit
import DesignResourcesKitIcons
import DuckUI
import MetricBuilder

struct DefaultBrowserPromptModalView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let closeAction: () -> Void
    let setAsDefaultAction: () -> Void
    let doNotAskAgainAction: () -> Void

    var body: some View {
        let horizontalPadding = Metrics.Container.horizontalPadding.build(v: verticalSizeClass, h: horizontalSizeClass)

        VStack(spacing: Metrics.Container.itemsVerticalSpacing) {
            Header(action: closeAction)
                .padding(.top, Metrics.Header.verticalPadding)
                .padding(.horizontal, Metrics.Header.horizontalPadding)

            Spacer(minLength: Metrics.Container.topSpacerMinLength)

            Content()
                .padding(.horizontal, horizontalPadding)

            Spacer(minLength: Metrics.Container.bottomSpacerMinLength)

            Footer(setDefaultBrowserAction: setAsDefaultAction, doNotAskAgainAction: doNotAskAgainAction)
                .padding(.horizontal, horizontalPadding)
        }
        .padding(.bottom)
        .background(Color(designSystemColor: .surface))
    }
}

// MARK: - Inner Views

private extension DefaultBrowserPromptModalView {

    struct Header: View {
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        let action: () -> Void

        var body: some View {
            HStack {
                Spacer()
                Button {
                    action()
                } label: {
                    Image(uiImage: DesignSystemImages.Glyphs.Size24.close)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.Header.closeButtonSize, height: Metrics.Header.closeButtonSize)
                        .foregroundStyle(Color.primary)
                }
            }
        }
    }

    struct Content: View {
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        var body: some View {
            let imageSize = Metrics.Content.imageSize.build(v: verticalSizeClass, h: horizontalSizeClass)

            VStack(spacing: Metrics.Content.itemsVerticalSpacing.build(v: verticalSizeClass, h: horizontalSizeClass)) {
                Image(.deviceMobileDefault128)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageSize.width, height: imageSize.height)

                Group {
                    Text(UserText.title)
                        .font(.system(size: Metrics.Content.titleFontSize, weight: .bold))
                        .kerning(Metrics.Content.kerning)

                    Text(UserText.message)
                        .font(.system(size: Metrics.Content.messageFontSize))
                }
                .foregroundStyle(Color.primary)
                .opacity(0.84)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.7)
            }
        }

    }

    struct Footer: View {
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        let setDefaultBrowserAction: () -> Void
        let doNotAskAgainAction: () -> Void

        var body: some View {
            VStack(spacing: Metrics.Footer.itemsVerticalSpacing.build(v: verticalSizeClass, h: horizontalSizeClass)) {
                Group {
                    Button(UserText.setDefaultBrowserCTA, action: setDefaultBrowserAction)
                        .buttonStyle(PrimaryButtonStyle(compact: Metrics.Footer.buttonsCompact.build(v: verticalSizeClass, h: horizontalSizeClass)))

                    Button(UserText.doNotAskAgainCTA, action: doNotAskAgainAction)
                        .buttonStyle(GhostButtonStyle(compact: Metrics.Footer.buttonsCompact.build(v: verticalSizeClass, h: horizontalSizeClass)))
                }
                .frame(maxWidth: Metrics.Footer.buttonMaxWidth.build(v: verticalSizeClass, h: horizontalSizeClass))
            }
        }
    }

}

// MARK: - Platform Metrics

private enum Metrics {

    enum Container {
        static let itemsVerticalSpacing: CGFloat = 0
        static let topSpacerMinLength: CGFloat = 0
        static let bottomSpacerMinLength: CGFloat = 10
        static let horizontalPadding = MetricBuilder<CGFloat>(iPhone: 24, iPad: 92).iPhone(landscape: 10)
    }

    enum Header {
        static let closeButtonSize: CGFloat = 24
        static let verticalPadding: CGFloat = 16
        static let horizontalPadding: CGFloat = 14
    }

    enum Content {
        static let itemsVerticalSpacing = MetricBuilder<CGFloat>(default: 24).iPhone(landscape: 20)
        static let titleFontSize: CGFloat = 28
        static let kerning: CGFloat = 0.38
        static let messageFontSize: CGFloat = 16
        static let imageSize = MetricBuilder<CGSize>(default: CGSize(width: 128, height: 96)).iPhone(landscape: .init(width: 96, height: 72))
    }

    enum Footer {
        static let itemsVerticalSpacing = MetricBuilder<CGFloat>(default: 8).iPhone(landscape: 4)
        static let buttonsCompact = MetricBuilder<Bool>(default: false).landscape(true)
        static let buttonMaxWidth = MetricBuilder<CGFloat?>(default: nil).landscape(295)
    }

}
