//
//  EscapeHatchView.swift
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

/// Bundles the "Return to tab" card and the tab switcher pill so callers render them as a single unit.
struct EscapeHatchView: View {
    @ObservedObject var model: EscapeHatchModel

    var body: some View {
        HStack(spacing: model.isReturnToTabCardVisible ? Metrics.spacing : 0) {
            ReturnToTabCard(model: model)
                .frame(maxWidth: model.isReturnToTabCardVisible ? .infinity : 0)
                .clipped()
                .opacity(model.isReturnToTabCardVisible ? 1 : 0)
                .allowsHitTesting(model.isReturnToTabCardVisible)

            TabSwitcherPill(count: model.openTabCount,
                            isExpanded: !model.isReturnToTabCardVisible,
                            showsEndArrow: !model.isHideShortcutEnabled,
                            onTap: model.onTabSwitcherTap)
                .frame(maxWidth: model.isReturnToTabCardVisible ? TabSwitcherPill.compactSize : .infinity)
                .frame(height: TabSwitcherPill.compactSize)
        }
        .animation(.easeInOut(duration: Metrics.collapseDuration), value: model.isReturnToTabCardVisible)
        .frame(height: TabSwitcherPill.compactSize)
        .id(model.targetTab.uid)
    }

    private enum Metrics {
        static let spacing: CGFloat = 8
        static let collapseDuration: Double = 0.25
    }
}

#if DEBUG

#Preview("Escape hatch — regular tab") {
    let target = Tab(fireTab: false)
    EscapeHatchView(model: .preview(title: "Tokamak - Wikipedia",
                                    subtitle: "en.wikipedia.org/wiki/Tokamak",
                                    tabType: .regular,
                                    domain: "en.wikipedia.org",
                                    targetTab: target,
                                    tabCount: 9))
        .padding()
}

#Preview("Escape hatch — duck.ai") {
    let target = Tab(fireTab: false)
    EscapeHatchView(model: .preview(title: "Good Dog Name Ideas",
                                    subtitle: "Duck.ai",
                                    tabType: .aiChat,
                                    domain: nil,
                                    targetTab: target,
                                    tabCount: 99))
        .padding()
}

#endif
