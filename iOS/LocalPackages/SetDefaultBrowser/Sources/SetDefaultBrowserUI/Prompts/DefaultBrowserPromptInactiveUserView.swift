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
        ZStack(alignment: Metrics.Content.alignment) {
            Image(.daxmag)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(background.ignoresSafeArea())
    }

    @ViewBuilder
    private var content: some View {
        let innerSectionsVerticalSpacing: CGFloat = Metrics.Content.innerSectionsVerticalSpacing.build(v: verticalSizeClass, h: horizontalSizeClass)

        VStack(alignment: .leading, spacing: Metrics.Content.sectionsSpacing) {
            VStack(alignment: .leading, spacing: innerSectionsVerticalSpacing) {
                Text(UserText.InactiveUserModal.title)
                    .titleStyle(alignment: .leading)

                ScrollView {
                    browserComparisonChart
                        .frame(height: Metrics.Chart.maxHeight)
                }
                .frame(maxHeight: Metrics.Chart.maxHeight)
            }
            VStack(alignment: .leading, spacing: innerSectionsVerticalSpacing) {
                PlusMoreButton()
                    .frame(height: Metrics.PlusMoreButton.height)

                Footer(setDefaultBrowserAction: setAsDefaultAction, continueBrowsing: closeAction)
            }
        }
        .padding(Metrics.Content.innerPadding)
        .background(Color(designSystemColor: .surface))
        .frame(maxWidth: Metrics.Content.maxWidth, alignment: .bottom)
        .cornerRadius(Metrics.Content.cornerRadius)
        .padding(.horizontal, Metrics.Content.outerHorizontalPadding)
        .padding(.bottom, Metrics.Content.bottomPadding)
        .padding(.top, Metrics.Content.topPadding.build(v: verticalSizeClass, h: horizontalSizeClass))
    }
}

struct PlusMoreButton: View {

    var body: some View {
        Text(LocalizedStringKey(UserText.InactiveUserModal.moreProtections))
            .font(.system(size: Metrics.Content.moreProtectionsFontSize))
            .underline(true)
            .multilineTextAlignment(.leading)
            .lineLimit(2)
            .foregroundColor(Color(designSystemColor: .accent))
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
        static let maxWidth = MetricBuilder<CGFloat?>(iPhone: nil, iPad: 542).build()
        static let alignment = MetricBuilder<Alignment>(iPhone: .topLeading, iPad: .top).build()
        static let topPadding = MetricBuilder(iPhone: 158.0, iPad: 198.0).iPad(landscape: 158.0)
        static let outerHorizontalPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 12
        static let innerPadding: CGFloat = 24
        static let cornerRadius: CGFloat = 24
        static let sectionsSpacing: CGFloat = 0
        static let innerSectionsVerticalSpacing = MetricBuilder(default: 24.0).iPhoneSmallScreen(16.0)
        static let moreProtectionsFontSize: CGFloat = 15
    }

    enum Chart {
        static let maxHeight: CGFloat = 260.0
    }

    enum PlusMoreButton {
        static let height: CGFloat = 48.0
        static let padding: CGFloat = 8.0
    }

    enum Footer {
        static let itemsVerticalSpacing: CGFloat = 8
        static let buttonsCompact = MetricBuilder<Bool>(default: false).iPhoneSmallScreen(true)
    }

}

#Preview {
    DefaultBrowserPromptInactiveUserView(background: AnyView(Color.blue), browserComparisonChart: AnyView(EmptyView()), closeAction: {}, setAsDefaultAction: {})
}
