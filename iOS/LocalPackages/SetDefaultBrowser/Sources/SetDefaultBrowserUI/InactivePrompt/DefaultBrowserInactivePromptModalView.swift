//
//  DefaultBrowserInactivePromptModalView.swift
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

struct DefaultBrowserInactivePromptModalView: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let browserComparisonChart: AnyView
    let closeAction: () -> Void
    let setAsDefaultAction: () -> Void

    var body: some View {
        ZStack(alignment: Metrics.Content.alignment) {
            Image(.daxmag)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(spacing: 24) {
                Text("DuckDuckGo has protections other browsers don’t.")
                    .font(.system(size: 28, weight: .bold))
                    .kerning(0.38)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                ScrollView {
                    browserComparisonChart
                        .frame(height: 260)
                }
                .frame(maxHeight: Metrics.Chart.maxHeight.build(v: verticalSizeClass, h: horizontalSizeClass))
            }

            VStack(alignment: .leading, spacing: 24) {
                Text("[Plus even more protections...](ddgQuickLink://duckduckgo.com/duckduckgo-help-pages/threat-protection/scam-blocker)")
                    .font(.system(size: 15))
                    .underline(true)
                    .foregroundStyle(Color(designSystemColor: .accent))

                Footer(setDefaultBrowserAction: setAsDefaultAction, continueBrowsing: closeAction)
            }
        }
        .padding(24)
        .background(Color(designSystemColor: .surface))
        .frame(maxWidth: Metrics.Content.maxWidth, alignment: .bottom)
        .cornerRadius(24)
        .padding([.horizontal, .bottom], 16)
        .padding(.top, Metrics.Content.topPadding.build(v: verticalSizeClass, h: horizontalSizeClass))
    }

}

private struct SizePreferenceKey: @preconcurrency PreferenceKey {
    @MainActor static var defaultValue: CGSize = .zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
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
                Button("Open Links with DuckDuckGo", action: setDefaultBrowserAction)
                    .buttonStyle(PrimaryButtonStyle(compact: Metrics.Footer.buttonsCompact.build(v: verticalSizeClass, h: horizontalSizeClass)))

                Button("Continue Browsing", action: continueBrowsing)
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
        static let topPadding = MetricBuilder(iPhone: 200.0, iPad: 240.0).iPad(landscape: 200)
    }

    enum Chart {
        static let maxHeight = MetricBuilder(default: 260.0).iPhoneSmallScreen(120)
    }

    enum Footer {
        static let itemsVerticalSpacing: CGFloat = 8
        static let buttonsCompact = MetricBuilder<Bool>(default: false).iPhoneSmallScreen(true)
    }

}

#Preview {
    DefaultBrowserInactivePromptModalView(browserComparisonChart: AnyView(EmptyView()), closeAction: {}, setAsDefaultAction: {})
}
