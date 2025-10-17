//
//  ComparisonMetricBox.swift
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

struct ComparisonMetricBox: View {
    let title: String
    let icon: String
    let duckduckgoValue: String
    let duckduckgoStdDev: String?
    let safariValue: String
    let safariStdDev: String?
    let percentageDiff: Double
    let winner: BrowserWinner

    var body: some View {
        VStack(alignment: .leading, spacing: PerformanceTestConstants.Layout.itemSpacing) {
            headerView
            duckduckgoRow
            safariRow
            differenceIndicator
        }
        .padding()
        .background(Color.gray.opacity(0.05))
        .cornerRadius(PerformanceTestConstants.Layout.cornerRadius)
    }

    private var headerView: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.caption)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private var duckduckgoRow: some View {
        HStack(spacing: PerformanceTestConstants.Layout.itemSpacing) {
            logoView(imageName: "Logo")
            relativeProgressBarView(value: duckduckgoValue, otherValue: safariValue, color: winner == .duckduckgo ? .green : .blue)
            valueView(value: duckduckgoValue, stdDev: duckduckgoStdDev)
        }
    }

    private var safariRow: some View {
        HStack(spacing: PerformanceTestConstants.Layout.itemSpacing) {
            safariLogoView
            relativeProgressBarView(value: safariValue, otherValue: duckduckgoValue, color: winner == .safari ? .green : .blue)
            valueView(value: safariValue, stdDev: safariStdDev)
        }
    }

    private var differenceIndicator: some View {
        HStack {
            Spacer()
            if winner == .tie {
                Text("Not statistically significant")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                HStack(spacing: 4) {
                    Image(systemName: percentageDiff > 0 ? "arrow.down" : "arrow.up")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(String(format: "%.1f%%", abs(percentageDiff)))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func logoView(imageName: String) -> some View {
        Image(imageName, bundle: .module)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: PerformanceTestConstants.Layout.logoSize, height: PerformanceTestConstants.Layout.logoSize)
    }

    private var safariLogoView: some View {
        Image(systemName: "safari")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: PerformanceTestConstants.Layout.logoSize, height: PerformanceTestConstants.Layout.logoSize)
            .foregroundColor(.accentColor)
    }

    private func relativeProgressBarView(value: String, otherValue: String, color: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: PerformanceTestConstants.Layout.progressBarHeight)

                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geometry.size.width * relativeProgress(value: value, otherValue: otherValue), height: PerformanceTestConstants.Layout.progressBarHeight)
            }
        }
        .frame(height: PerformanceTestConstants.Layout.progressBarHeight)
    }

    private func valueView(value: String, stdDev: String?) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(.body, design: .monospaced))
                .fontWeight(.semibold)

            if let stdDev = stdDev {
                Text("± \(stdDev)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: PerformanceTestConstants.Layout.metricValueWidth, alignment: .trailing)
    }

    // Calculate relative progress between two values (for comparison view)
    private func relativeProgress(value: String, otherValue: String) -> Double {
        // Extract numeric values
        let numericString = value.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        let otherNumericString = otherValue.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)

        guard let numericValue = Double(numericString),
              let otherNumericValue = Double(otherNumericString) else {
            return 0.5
        }

        // Prevent division by zero
        guard numericValue > 0 else { return 0.5 }

        // For time/size metrics (lower is better):
        // The best (minimum) value gets full bar (1.0)
        // The worse value gets proportionally less
        let minValue = min(numericValue, otherNumericValue)
        guard minValue > 0 else { return 0.5 }

        return minValue / numericValue
    }
}
