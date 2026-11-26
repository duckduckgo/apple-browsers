//
//  BrowsersComparisonChart.swift
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

import DesignResourcesKitIcons
import SwiftUI

// MARK: - Chart View

extension BrowsersComparisonChart {

    public enum RowStyle {
        case divided
        case alternatingBackground(Color, cornerRadius: CGFloat)
    }

    public enum AvailabilityIconStyle {
        case standard
        case solid(available: Color, partiallyAvailable: Color, unavailable: Color)
    }

    public struct Configuration {
        var font: Font
        var allowContentToScrollUnderHeader: Bool
        var showFeatureIcons: Bool
        var showBottomDivider: Bool
        var showHeaderDivider: Bool
        var rowStyle: RowStyle
        var rowHeight: CGFloat
        var availabilityIconStyle: AvailabilityIconStyle

        public init(fontSize: CGFloat = 15.0,
                    fontWeight: Font.Weight = .regular,
                    allowContentToScrollUnderHeader: Bool = false,
                    showFeatureIcons: Bool = false,
                    showBottomDivider: Bool? = nil,
                    showHeaderDivider: Bool = true,
                    rowStyle: RowStyle = .divided,
                    rowHeight: CGFloat = 50.0,
                    availabilityIconStyle: AvailabilityIconStyle = .standard) {
            self.font = Font.system(size: fontSize, weight: fontWeight)
            self.allowContentToScrollUnderHeader = allowContentToScrollUnderHeader
            self.showFeatureIcons = showFeatureIcons
            self.showBottomDivider = showBottomDivider ?? !allowContentToScrollUnderHeader
            self.showHeaderDivider = showHeaderDivider
            self.rowStyle = rowStyle
            self.rowHeight = rowHeight
            self.availabilityIconStyle = availabilityIconStyle
        }

        var horizontalPadding: CGFloat {
            switch rowStyle {
            case .divided: 0
            case .alternatingBackground: Metrics.alternatingBackgroundHorizontalPadding
            }
        }
    }

}

public struct BrowsersComparisonChart: View {
    private let privacyFeatures: [BrowsersComparisonModel.PrivacyFeature]
    private let configuration: Configuration

    public init(privacyFeatures: [BrowsersComparisonModel.PrivacyFeature], configuration: Configuration = Configuration()) {
        self.privacyFeatures = privacyFeatures
        self.configuration = configuration
    }

    public var body: some View {
        VStack(spacing: Metrics.stackSpacing) {
            Header(browsers: BrowsersComparisonModel.Browser.allCases, showDivider: configuration.showHeaderDivider)
                .frame(height: Metrics.headerHeight)
                .padding(.horizontal, configuration.horizontalPadding)

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let content = ForEach(Array(privacyFeatures.enumerated()), id: \.element.type) { index, feature in
            let shouldDisplayDivider = index < privacyFeatures.count - 1 || configuration.showBottomDivider
            Row(configuration: configuration, feature: feature, index: index, shouldDisplayDivider: shouldDisplayDivider)
        }

        if configuration.allowContentToScrollUnderHeader {
            let height = CGFloat(privacyFeatures.count) * configuration.rowHeight
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
        let showDivider: Bool

        var body: some View {
            HStack(alignment: .bottom) {
                Spacer()

                ForEach(Array(browsers.enumerated()), id: \.offset) { index, browser in
                    Image(browser.image)
                        .frame(width: Metrics.headerImageContainerSize.width, height: Metrics.headerImageContainerSize.height)

                    if index < browsers.count - 1 {
                        // Hidden rather than removed, so the icons stay aligned with the status columns below
                        Divider()
                            .opacity(showDivider ? 1 : 0)
                    }
                }
            }
        }
    }

}

// MARK: - Row

extension BrowsersComparisonChart {

    struct Row: View {
        let configuration: Configuration
        let feature: BrowsersComparisonModel.PrivacyFeature
        let index: Int
        let shouldDisplayDivider: Bool

        var body: some View {
            switch configuration.rowStyle {
            case .divided:
                content
                    .frame(maxHeight: configuration.rowHeight)

                if shouldDisplayDivider {
                    Divider()
                }
            case .alternatingBackground(let color, let cornerRadius):
                content
                    .padding(.horizontal, configuration.horizontalPadding)
                    .frame(height: configuration.rowHeight)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .fill(index.isMultiple(of: 2) ? color : .clear)
                    )
            }
        }

        private var content: some View {
            HStack {
                if configuration.showFeatureIcons {
                    #if os(iOS)
                    Image(uiImage: feature.type.icon)
                    #elseif os(macOS)
                    Image(nsImage: feature.type.icon)
                    #endif
                }

                Text(verbatim: feature.type.title)
                    .font(configuration.font)
                    .foregroundColor(.primary)
                    .lineLimit(nil)
                    .lineSpacing(1)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                BrowsersSupport(browsersSupport: feature.browsersSupport, iconStyle: configuration.availabilityIconStyle)
            }
        }
    }

}

// MARK: - Row + BrowsersSupport

extension BrowsersComparisonChart.Row {

    struct BrowsersSupport: View {
        let browsersSupport: [BrowsersComparisonModel.PrivacyFeature.BrowserSupport]
        let iconStyle: BrowsersComparisonChart.AvailabilityIconStyle

        var body: some View {
            ForEach(Array(browsersSupport.enumerated()), id: \.offset) { index, browserSupport in
                availabilityImage(browserSupport.availability)
                    .frame(width: BrowsersComparisonChart.Metrics.imageContainerWidth)

                if index < browsersSupport.count - 1 {
                    Divider()
                }
            }
        }

        @ViewBuilder
        private func availabilityImage(_ availability: BrowsersComparisonModel.PrivacyFeature.Availability) -> some View {
            switch iconStyle {
            case .standard:
                Image(availability.image)
            case .solid(let availableColor, let partiallyAvailableColor, let unavailableColor):
                switch availability {
                case .available:
                    solidImage(DesignSystemImages.Glyphs.Size24.checkSolid, color: availableColor)
                case .partiallyAvailable:
                    solidImage(DesignSystemImages.Glyphs.Size24.stopSolid, color: partiallyAvailableColor)
                case .unavailable:
                    solidImage(DesignSystemImages.Glyphs.Size24.crossSolid, color: unavailableColor)
                }
            }
        }

        private func solidImage(_ image: DesignSystemImage, color: Color) -> some View {
            #if os(iOS)
            Image(uiImage: image)
                .renderingMode(.template)
                .foregroundStyle(color)
            #elseif os(macOS)
            Image(nsImage: image)
                .renderingMode(.template)
                .foregroundStyle(color)
            #endif
        }
    }

}

// MARK: - Metrics

extension BrowsersComparisonChart {
    private enum Metrics {
        static let alternatingBackgroundHorizontalPadding: CGFloat = 8
        static let stackSpacing: CGFloat = 0.0
        static let headerHeight: CGFloat = 60
        static let headerImageContainerSize = CGSize(width: 40, height: 80)
        static let imageContainerWidth: CGFloat = 40.0
        static let scrollableVStackSpacing: CGFloat = 0
        static let scrollableBottomDividerPadding: CGFloat = 4
    }
}

#Preview {
    BrowsersComparisonChart(privacyFeatures: BrowsersComparisonModel.privacyFeatures)
    .padding()
}
