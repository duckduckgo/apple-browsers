//
//  PerformanceMetricCard.swift
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

struct PerformanceMetricCarda: View {
    let title: String
    let value: String
    let actualValue: Double
    let metricType: MetricType
    let icon: String
    let quality: String
    let averageTime: Double?

    enum MetricType {
        case loadTime
        case consistency
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PerformanceTestConstants.Layout.smallSpacing) {
            headerView
            titleView
            valueView
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(PerformanceTestConstants.Layout.smallCornerRadius)
    }

    private var headerView: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.accentColor)
                .font(.caption)
            Spacer()
        }
    }

    private var titleView: some View {
        Text(title)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var valueView: some View {
        Text(value)
            .font(.system(.title3, design: .monospaced))
            .fontWeight(.semibold)
    }

    private var normalizedValue: Double {
        switch metricType {
        case .loadTime:
            // 0-10 second range, inverted (lower is better)
            return max(0, min(1, 1.0 - (actualValue / 10.0)))
        case .consistency:
            // Use CV-based calculation if averageTime is available
            if let avgTime = averageTime, avgTime > 0 {
                let cv = (actualValue / avgTime) * 100
                // 0-100% CV range, inverted (lower is better)
                return max(0, min(1, 1.0 - (cv / 100.0)))
            } else {
                // Fallback to absolute std dev, 0-2 second range, inverted
                return max(0, min(1, 1.0 - (actualValue / 2.0)))
            }
        }
    }

    private var qualityColor: Color {
        switch quality {
        case "Excellent": return .green
        case "Good": return .blue
        case "Fair": return .orange
        case "Poor": return .red
        default: return .gray
        }
    }
}
