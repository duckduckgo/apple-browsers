//
//  DefaultBrowserPromptInactiveUserView.swift
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

struct DefaultBrowserPromptInactiveUserView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let background: AnyView
    let browserComparisonChart: AnyView
    let closeAction: () -> Void
    let setAsDefaultAction: () -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Image(.daxmag)

                content(proxy: proxy)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .background(background.ignoresSafeArea())
            .overlay(alignment: .topTrailing) {
                DismissButton(action: closeAction)
                    .padding(.top, Metrics.DismissButton.closeButtonTopPadding)
                    .padding(.trailing, Metrics.DismissButton.horizontalPadding)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
    }

    @ViewBuilder
    private func content(proxy: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: Metrics.Content.innerSectionsVerticalSpacing.build(v: verticalSizeClass, h: horizontalSizeClass)) {
            Text(UserText.InactiveUserModal.title)
                .titleStyle(
                    alignment: .leading,
                    fontSize: Metrics.Content.titleSize.build(v: verticalSizeClass, h: horizontalSizeClass),
                    kerning: Metrics.Content.titleKerning.build(v: verticalSizeClass, h: horizontalSizeClass)
                )
            
            browserComparisonChart
            
            Footer(setDefaultBrowserAction: setAsDefaultAction, continueBrowsing: closeAction)
        }
        .padding(Metrics.Content.innerPadding)
        .background(Color(designSystemColor: .surface))
        .frame(maxWidth: Metrics.Content.maxWidth, alignment: .bottom)
        .cornerRadius(Metrics.Content.cornerRadius)
        .padding(.horizontal, Metrics.Content.outerHorizontalPadding)
        .padding(.top, Metrics.Content.topPadding.build(v: verticalSizeClass, h: horizontalSizeClass))
        .if(proxy.safeAreaInsets.bottom == 0) { view in // Adds bottom padding only to devices with physical home button
            view.padding(.bottom, Metrics.Content.bottomPadding)
        }
    }
}

struct DismissButton: View {
    @Environment(\.colorScheme) private var colorScheme

    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(uiImage: DesignSystemImages.Glyphs.Size16.close)
                .foregroundColor(.primary)
                .padding(Metrics.DismissButton.contentPadding)
                .background(Color(designSystemColor: .textSelectionFill))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.DismissButton.cornerRadius))
        }
        .buttonStyle(.plain)
        .frame(width: Metrics.DismissButton.size, height: Metrics.DismissButton.size)
    }
}

struct Footer: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let setDefaultBrowserAction: () -> Void
    let continueBrowsing: () -> Void

    var body: some View {
        VStack(spacing: Metrics.Footer.itemsVerticalSpacing) {
            Group {
                Button(UserText.InactiveUserModal.setDefaultBrowserCTA, action: setDefaultBrowserAction)
                    .buttonStyle(PrimaryButtonStyle(compact: Metrics.Footer.buttonsCompact.build(v: verticalSizeClass, h: horizontalSizeClass)))

                Button(UserText.InactiveUserModal.continueBrowsingCTA, action: continueBrowsing)
                    .buttonStyle(GhostButtonStyle(compact: Metrics.Footer.buttonsCompact.build(v: verticalSizeClass, h: horizontalSizeClass)))
            }
        }
    }
}

private enum Metrics {

    @MainActor
    enum Content {
        static let titleSize = MetricBuilder<CGFloat>(iPhone: 24.0, iPad: 28.0).iPhoneSmallScreen(22.0)
        static let titleKerning = MetricBuilder<CGFloat>(default: 0.38).iPhoneSmallScreen(0.35)

        static let maxWidth = MetricBuilder<CGFloat?>(iPhone: nil, iPad: 542).build()
        static let topPadding = MetricBuilder(iPhone: 158.0, iPad: 198.0).iPad(landscape: 158.0)
        static let bottomPadding: CGFloat = 12
        static let outerHorizontalPadding: CGFloat = 16
        static let innerPadding: CGFloat = 24
        static let cornerRadius: CGFloat = 24
        static let innerSectionsVerticalSpacing = MetricBuilder(default: 24.0).iPhoneSmallScreen(16.0)
    }

    enum Chart {
        static let maxHeight: CGFloat = 260.0
    }

    @MainActor
    enum DismissButton {
        static let contentPadding: CGFloat = 12.0
        static let closeButtonTopPadding: CGFloat = MetricBuilder(iPhone: 30.0, iPad: 60.0).build()
        static let size: CGFloat = 44.0
        static let horizontalPadding =  MetricBuilder(iPhone: 16.0, iPad: 24.0).build()
        static let cornerRadius: CGFloat = 12
    }

    enum Footer {
        static let itemsVerticalSpacing: CGFloat = 8
        static let buttonsCompact = MetricBuilder<Bool>(default: false).iPhoneSmallScreen(true)
    }

}

#Preview {
    DefaultBrowserPromptInactiveUserView(background: AnyView(Color.blue), browserComparisonChart: AnyView(EmptyView()), closeAction: {}, setAsDefaultAction: {})
}
