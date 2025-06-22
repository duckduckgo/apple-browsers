//
//  SetDefaultBrowserModalView.swift
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

struct SetDefaultBrowserModalView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let closeAction: () -> Void
    let setAsDefaultAction: () -> Void
    let doNotAskAgainAction: () -> Void

    var body: some View {
        let horizontalPadding = Metrics.Container.horizontalPadding.build(v: verticalSizeClass, h: horizontalSizeClass)

        VStack(spacing: Metrics.Container.itemsVerticalSpacing) {
            Header(action: closeAction)

            Spacer(minLength: Metrics.Container.spacerMinLength)

            Content()
                .padding(.horizontal, horizontalPadding)

            Spacer(minLength: Metrics.Container.spacerMinLength)

            Footer(setDefaultBrowserAction: setAsDefaultAction, doNotAskAgainAction: doNotAskAgainAction)
                .padding(.horizontal, horizontalPadding)
        }
        .padding(.top, Metrics.Container.topPadding)
        .padding(.bottom)
    }
}

// MARK: - Inner Views

private extension SetDefaultBrowserModalView {

    struct Header: View {
        let action: () -> Void

        var body: some View {
            HStack {
                Button(UserText.ModalSheet.cancelCTA, action: action)
                    .font(.system(size: Metrics.Header.cancelButtonFontSize))
                    .foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.horizontal, Metrics.Header.horizontalPadding)
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
                    Text(UserText.ModalSheet.title)
                        .font(.system(size: Metrics.Content.titleFontSize, weight: .bold))

                    Text(UserText.ModalSheet.message)
                        .font(.system(size: Metrics.Content.messageFontSize))
                }
                .foregroundStyle(Color.primary)
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
                    Button(UserText.CTA.primary, action: setDefaultBrowserAction)
                        .buttonStyle(PrimaryButtonStyle(compact: Metrics.Footer.buttonsCompact.build(v: verticalSizeClass, h: horizontalSizeClass)))

                    Button(UserText.CTA.secondary, action: doNotAskAgainAction)
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
        @MainActor
        static let horizontalPadding = MetricBuilder<CGFloat>(iPhone: 24, iPad: 92)
    }

    enum Header {
        static let cancelButtonFontSize: CGFloat = 17
        static let horizontalPadding: CGFloat = 10
    }

    enum Content {
        static let itemsVerticalSpacing: CGFloat = 24
        static let titleFontSize: CGFloat = 28
        static let messageFontSize: CGFloat = 16
        @MainActor
        static let imageSize = MetricBuilder<CGSize>(default: CGSize(width: 128, height: 96)).iPhone(landscape: .init(width: 96, height: 72))
    }

    enum Footer {
        @MainActor
        static let itemsVerticalSpacing = MetricBuilder<CGFloat>(default: 8).iPhone(landscape: 4)
        @MainActor
        static let buttonsCompact = MetricBuilder<Bool>(default: false).landscape(true)
        @MainActor
        static let buttonMaxWidth = MetricBuilder<CGFloat?>(default: nil).landscape(295)
    }

}
