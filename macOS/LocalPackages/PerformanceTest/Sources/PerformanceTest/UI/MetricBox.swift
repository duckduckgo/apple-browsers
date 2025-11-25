//
//  MetricBox.swift
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

struct MetricBox: View {
    let title: String
    let value: String
    let stdDev: String?
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: PerformanceTestConstants.Layout.itemSpacing) {
            headerView
            contentView
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

    private var contentView: some View {
        HStack(spacing: PerformanceTestConstants.Layout.itemSpacing) {
            logoView
            progressBarView
            valueView
        }
    }

    private var logoView: some View {
        Image("Logo", bundle: .module)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: PerformanceTestConstants.Layout.logoSize, height: PerformanceTestConstants.Layout.logoSize)
    }

    private var progressBarView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: PerformanceTestConstants.Layout.progressBarHeight)

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue)
                    .frame(width: geometry.size.width * normalizedProgress(value), height: PerformanceTestConstants.Layout.progressBarHeight)
            }
        }
        .frame(height: PerformanceTestConstants.Layout.progressBarHeight)
    }

    private var valueView: some View {
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

    // Calculate progress bar width based on value (normalized 0-1)
    private func normalizedProgress(_ value: String) -> Double {
        // Extract numeric value from string (remove "ms", "KB", etc)
        let numericString = value.replacingOccurrences(of: "[^0-9.]", with: "", options: .regularExpression)
        guard let numericValue = Double(numericString) else { return 0.5 }

        // Normalize based on whether it's time (ms) or size (KB/MB)
        if value.contains("ms") {
            // For time: 0ms = 1.0, 5000ms = 0.0
            return max(0, min(1, 1.0 - (numericValue / PerformanceTestConstants.Thresholds.maxTimeForProgress)))
        } else if value.contains("KB") || value.contains("MB") {
            // For size: smaller is better
            let sizeInKB = value.contains("MB") ? numericValue * 1000 : numericValue
            return max(0, min(1, 1.0 - (sizeInKB / PerformanceTestConstants.Thresholds.maxSizeForProgress)))
        } else {
            // For counts: smaller is better (like time and size)
            return max(0, min(1, 1.0 - (numericValue / PerformanceTestConstants.Thresholds.maxCountForProgress)))
        }
    }
}
