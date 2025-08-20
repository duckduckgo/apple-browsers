//
//  BrowsersComparisonChart.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

// MARK: - Chart View

extension BrowsersComparisonChart {

    struct Configuration {
        var fontSize: CGFloat = 15.0
        var allowContentToScrollUnderHeader: Bool = false
    }

}

struct BrowsersComparisonChart: View {
    private let privacyFeatures: [BrowsersComparisonModel.PrivacyFeature]
    private let configuration: Configuration

    init(privacyFeatures: [BrowsersComparisonModel.PrivacyFeature], configuration: Configuration = Configuration()) {
        self.privacyFeatures = privacyFeatures
        self.configuration = configuration
    }

    var body: some View {
        VStack(spacing: Metrics.stackSpacing) {
            Header(browsers: BrowsersComparisonModel.Browser.allCases)
                .frame(height: Metrics.headerHeight)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let content = ForEach(Array(privacyFeatures.enumerated()), id: \.element.type) { index, feature in
            let shouldDisplayDivider = index < privacyFeatures.count - 1 || !configuration.allowContentToScrollUnderHeader
            Row(feature: feature, shouldDisplayDivider: shouldDisplayDivider)
        }

        if configuration.allowContentToScrollUnderHeader {
            let height = CGFloat(privacyFeatures.count) * Metrics.imageContainerSize.height
             ScrollView(showsIndicators: false) {
                 // Wrap content in stack view to avoid rows height to stretch
                 VStack(spacing: Metrics.scrollableVStackSpacing) {
                     content
                 }
                 .frame(height: height)
             }
             .frame(maxHeight: height) // Avoid stretching the scroll view to bottom of the screen on iPad
            Divider()
                .padding(.top, Metrics.scrollableBottomDividerPadding)

        } else {
            content
        }
    }
}

// MARK: - Header

extension BrowsersComparisonChart {

    struct Header: View {
        let browsers: [BrowsersComparisonModel.Browser]

        var body: some View {
            HStack(alignment: .bottom) {
                Spacer()

                ForEach(Array(browsers.enumerated()), id: \.offset) { index, browser in
                    Image(browser.image)
                        .frame(width: Metrics.headerImageContainerSize.width, height: Metrics.headerImageContainerSize.height)

                    if index < browsers.count - 1 {
                        Divider()
                    }
                }
            }
        }
    }

}

// MARK: - Row

extension BrowsersComparisonChart {

    struct Row: View {
        let feature: BrowsersComparisonModel.PrivacyFeature
        let shouldDisplayDivider: Bool

        var body: some View {
            HStack {
                Text(verbatim: feature.type.title)
                    .font(Metrics.font)
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                BrowsersSupport(browsersSupport: feature.browsersSupport)
            }
            .frame(maxHeight: Metrics.imageContainerSize.height)

            if shouldDisplayDivider {
                Divider()
            }
        }
    }

}

// MARK: - Row + BrowsersSupport

extension BrowsersComparisonChart.Row {

    struct BrowsersSupport: View {
        let browsersSupport: [BrowsersComparisonModel.PrivacyFeature.BrowserSupport]

        var body: some View {
            ForEach(Array(browsersSupport.enumerated()), id: \.offset) { index, browserSupport in
                Image(browserSupport.availability.image)
                    .frame(width: Metrics.imageContainerSize.width)

                if index < browsersSupport.count - 1 {
                    Divider()
                }
            }
        }
    }

}

// MARK: - Metrics

private enum Metrics {
    static let stackSpacing: CGFloat = 0.0
    static let headerHeight: CGFloat = 60
    static let headerImageContainerSize = CGSize(width: 40, height: 80)
    static let imageContainerSize = CGSize(width: 40.0, height: 50.0)
    static let font = Font.system(size: 15.0)
    static let scrollableVStackSpacing: CGFloat = 0
    static let scrollableBottomDividerPadding: CGFloat = 4
}

#Preview {
    BrowsersComparisonChart(privacyFeatures: BrowsersComparisonModel.privacyFeatures)
    .padding()
}
