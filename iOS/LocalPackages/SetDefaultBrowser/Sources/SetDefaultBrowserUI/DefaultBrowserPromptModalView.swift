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
                .padding(.top, Metrics.Header.verticalPadding.build(v: verticalSizeClass, h: horizontalSizeClass))
                .padding(.horizontal, Metrics.Header.horizontalPadding.build(v: verticalSizeClass, h: horizontalSizeClass))
                .ignoresSafeArea(edges: .horizontal)

            Spacer(minLength: Metrics.Container.spacerMinLength)

            Content()
                .padding(.horizontal, horizontalPadding)

            Spacer(minLength: Metrics.Container.spacerMinLength)

            Footer(setDefaultBrowserAction: setAsDefaultAction, doNotAskAgainAction: doNotAskAgainAction)
                .padding(.horizontal, horizontalPadding)
        }
        .padding(.top, Metrics.Container.topPadding)
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
                Button(UserText.closeCTA, action: action)
                    .font(.system(size: Metrics.Header.cancelButtonFontSize))
                    .foregroundStyle(Color.primary)
                    .opacity(0.84)
                Spacer()
            }
        }
    }

    struct Content: View {
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        var body: some View {
            let imageSize = Metrics.Content.imageSize.build(v: verticalSizeClass, h: horizontalSizeClass)

            VStack(spacing: Metrics.Content.itemsVerticalSpacing) {
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
        static let spacerMinLength: CGFloat = 0
        static let topPadding: CGFloat = 16
        static let horizontalPadding = MetricBuilder<CGFloat>(iPhone: 24, iPad: 92)
    }

    enum Header {
        static let cancelButtonFontSize: CGFloat = 17
        static let verticalPadding = MetricBuilder<CGFloat>(default: 0).landscape(10)
        static let horizontalPadding = MetricBuilder<CGFloat>(default: 16).iPad(portrait: 20).landscape(iPhone: 40)
    }

    enum Content {
        static let itemsVerticalSpacing: CGFloat = 24
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
