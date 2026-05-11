//
//  TabSwitcherPill.swift
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

struct TabSwitcherPill: View {
    let count: Int
    let onTap: () -> Void

    @StateObject private var tabCountModel: TabCountModel

    init(count: Int, onTap: @escaping () -> Void) {
        self.count = count
        self.onTap = onTap
        // Seed the model with the correct count up front so the badge
        // renders with the number on the first frame instead of flashing empty.
        _tabCountModel = StateObject(wrappedValue: TabCountModel(count: count))
    }

    var body: some View {
        Button(action: onTap) {
            TabCountBadge(model: tabCountModel)
                .foregroundColor(Color(designSystemColor: .icons))
                .frame(width: Metrics.size, height: Metrics.size)
                .background(
                    Circle()
                        .fill(Color(designSystemColor: .controlsFillSecondary))
                )
        }
        .buttonStyle(.plain)
        .onChange(of: count) { newValue in tabCountModel.count = newValue }
        .accessibilityLabel(Text(UserText.tabSwitcherAccessibilityLabel))
        .accessibilityValue(Text(UserText.numberOfTabs(count)))
        .accessibilityIdentifier("NTP.escapeHatch.tabSwitcher")
    }
}

private enum Metrics {
    static let size: CGFloat = 56
}

// MARK: - Previews

#Preview("Tab switcher pill — counts") {
    HStack(spacing: 8) {
        TabSwitcherPill(count: 1, onTap: {})
        TabSwitcherPill(count: 9, onTap: {})
        TabSwitcherPill(count: 99, onTap: {})
        TabSwitcherPill(count: 100, onTap: {})
    }
    .padding()
}
