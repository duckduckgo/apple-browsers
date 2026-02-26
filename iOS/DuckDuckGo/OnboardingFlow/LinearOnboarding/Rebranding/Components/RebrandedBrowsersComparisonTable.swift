//
//  RebrandedBrowsersComparisonTable.swift
//  DuckDuckGo
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
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
import Onboarding

private enum ComparisonTableMetrics {
    // Header
    static let headerIconSize: CGFloat = 64

    // Row layout
    static let rowSpacing: CGFloat = 0
    static let cellHeight: CGFloat = 56
    static let cellCornerRadius: CGFloat = 12
    static let cellInsets: EdgeInsets = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 4)

    // Feature section (left)
    static let featureIconSize: CGFloat = 32
    static let featureTextSpacing: CGFloat = 8

    // Status section (right)
    static let availabilityIconSize: CGFloat = 24
    static let statusColumnWidth: CGFloat = 36
    static let statusColumnSpacing: CGFloat = 8

    // Separator
    static let separatorColor = Color(singleUseColor: .rebranding(.decorationPrimary))
    static let separatorWidth: CGFloat = 1
}

struct RebrandedBrowsersComparisonTable: View {
    let shouldAnimateChecks: Bool

    var body: some View {
        VStack(spacing: ComparisonTableMetrics.rowSpacing) {
            ComparisonHeader()

            ForEach(Array(RebrandedBrowsersComparisonModel.features.enumerated()), id: \.element.type) { index, feature in
                FeatureRow(feature: feature, index: index, shouldAnimateChecks: shouldAnimateChecks)
            }
        }
    }
}

// MARK: - Header

private struct ComparisonHeader: View {

    var body: some View {
        // NOTE: Negative spacing/padding compensates for built-in padding in the icon PDFs (shadow regions from export).
        HStack(spacing: -10) {
            Spacer()

            OnboardingRebrandingImages.Comparison.safariIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: ComparisonTableMetrics.headerIconSize, height: ComparisonTableMetrics.headerIconSize)

            OnboardingRebrandingImages.Comparison.ddgIcon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: ComparisonTableMetrics.headerIconSize, height: ComparisonTableMetrics.headerIconSize)
        }
        .padding(.trailing, -10)
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    @Environment(\.onboardingTheme) private var onboardingTheme

    let feature: RebrandedBrowsersComparisonModel.Feature
    let index: Int
    let shouldAnimateChecks: Bool

    private var backgroundColor: Color {
        index % 2 == 0 ? Color(singleUseColor: .rebranding(.accentAltGlowPrimary)) : Color.clear
    }

    var body: some View {
        ZStack(alignment: .leading) {
            backgroundColor
                .cornerRadius(ComparisonTableMetrics.cellCornerRadius)

            HStack {
                HStack(alignment: .center, spacing: ComparisonTableMetrics.featureTextSpacing) {
                    feature.type.icon
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: ComparisonTableMetrics.featureIconSize, height: ComparisonTableMetrics.featureIconSize)

                    Text(feature.type.title)
                        .font(onboardingTheme.typography.rowDetails)
                        .foregroundColor(onboardingTheme.colorPalette.textPrimary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: ComparisonTableMetrics.statusColumnSpacing) {
                    feature.safariAvailability.image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: ComparisonTableMetrics.availabilityIconSize, height: ComparisonTableMetrics.availabilityIconSize)
                        .frame(width: ComparisonTableMetrics.statusColumnWidth)

                    Rectangle()
                        .fill(ComparisonTableMetrics.separatorColor)
                        .frame(width: ComparisonTableMetrics.separatorWidth)

                    ddgAvailableFeature
                        .frame(width: ComparisonTableMetrics.availabilityIconSize, height: ComparisonTableMetrics.availabilityIconSize)
                        .frame(width: ComparisonTableMetrics.statusColumnWidth)
                }
            }
            .padding(ComparisonTableMetrics.cellInsets)
        }
        .frame(height: ComparisonTableMetrics.cellHeight)
        .clipShape(RoundedRectangle(cornerRadius: ComparisonTableMetrics.cellCornerRadius))
    }

    @ViewBuilder
    private var ddgAvailableFeature: some View {
        if feature.ddgAvailability == .available {
            CircleCheckView(
                size: ComparisonTableMetrics.availabilityIconSize,
                shouldAnimate: shouldAnimateChecks,
                staggerDelay: 0.1 * Double(index + 1)
            )
        } else {
            feature.ddgAvailability.image
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

}

struct Checkmark: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Left foot → bottom valley → upper right tip
        p.move(to: CGPoint(x: w * 0.15, y: h * 0.52))
        p.addLine(to: CGPoint(x: w * 0.42, y: h * 0.80))
        p.addLine(to: CGPoint(x: w * 0.9, y: h * 0.25))
        return p
    }
}

// MARK: - Main View

struct CircleCheckView: View {
    @State private var circleScale: CGFloat = 0
    @State private var checkTrim: CGFloat = 0
    @State private var checkScale: CGFloat = 0.3

    let size: CGFloat
    let shouldAnimate: Bool
    let staggerDelay: TimeInterval

    var body: some View {
        ZStack {
            // 1. Background circle
            Circle()
                .fill(.green)
                .frame(width: size, height: size)
                .scaleEffect(circleScale)

            // 2. Checkmark drawn on top via trim
            Checkmark()
                .trim(from: 0, to: checkTrim)
                .stroke(
                    .white,
                    style: StrokeStyle(
                        lineWidth: size * 0.09,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .frame(width: size * 0.65, height: size * 0.55)
                .scaleEffect(checkScale)
        }
        .onChange(of: shouldAnimate) { newValue in
            if newValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + staggerDelay) {
                    animate()
                }
            }
        }
    }

    // MARK: Animation sequence

    private func animate() {
        // Phase 1 — circle springs in
        withAnimation(.spring(duration: 0.45, bounce: 0.45)) {
            circleScale = 1
        }

        withAnimation(.spring(duration: 0.45, bounce: 0.45).delay(0.2)) {
            checkScale = 1
        }

        // Phase 2 — checkmark draws and scales (slight overlap so it feels connected)
        withAnimation(.easeOut(duration: 0.38).delay(0.2)) {
            checkTrim  = 1
        }
    }
}
