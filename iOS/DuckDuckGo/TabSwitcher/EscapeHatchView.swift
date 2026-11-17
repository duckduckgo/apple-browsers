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

import DesignResourcesKit
import SwiftUI

/// Bundles the "Return to tab" card and the tab switcher pill so callers render them as a single unit.
struct EscapeHatchView: View {
    static let materialPadding: CGFloat = 8

    @ObservedObject var model: EscapeHatchModel
    var usesMaterialBackground = false
    /// Content drawn behind the hatch; each control blurs it where they overlap.
    var backdropFrame: CGRect?

    var body: some View {
        HStack(spacing: model.isReturnToTabCardVisible ? Metrics.spacing : 0) {
            ReturnToTabCard(model: model, showsBackground: !usesMaterialBackground, backdropFrame: backdropFrame)
                .frame(maxWidth: model.isReturnToTabCardVisible ? .infinity : 0)
                .clipped()
                .opacity(model.isReturnToTabCardVisible ? 1 : 0)
                .allowsHitTesting(model.isReturnToTabCardVisible)

            TabSwitcherPill(count: model.openTabCount,
                            isExpanded: !model.isReturnToTabCardVisible,
                            showsBackground: !usesMaterialBackground,
                            backdropFrame: backdropFrame,
                            onTap: model.onTabSwitcherTap)
                .frame(maxWidth: model.isReturnToTabCardVisible ? TabSwitcherPill.compactSize : .infinity)
                .frame(height: TabSwitcherPill.compactSize)
        }
        .animation(.easeInOut(duration: Metrics.collapseDuration), value: model.isReturnToTabCardVisible)
        .frame(height: TabSwitcherPill.compactSize)
        .padding(usesMaterialBackground ? Self.materialPadding : 0)
        .background {
            if usesMaterialBackground {
                RedesignedNewTabPageModuleBackground()
            }
        }
        .id(model.targetTab.uid)
    }

    private enum Metrics {
        static let spacing: CGFloat = 8
        static let collapseDuration: Double = 0.25
    }
}

/// Adds the redesigned module's material (opaque with Reduce Transparency) under a capsule control,
/// shown only while it overlaps `backdropFrame`, so the control looks unchanged when nothing is behind it.
struct EscapeHatchBackdropBlur: ViewModifier {
    let backdropFrame: CGRect?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        let isBlurring = backdropFrame?.intersects(frame) == true
        content.background {
            GeometryReader { proxy in
                Capsule()
                    .fill(reduceTransparency ? AnyShapeStyle(Color(designSystemColor: .surfaceSecondary)) : AnyShapeStyle(.ultraThinMaterial))
                    .opacity(isBlurring ? 1 : 0)
                    .animation(.easeInOut(duration: 0.2), value: isBlurring)
                    .onAppear { frame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { frame = $0 }
            }
        }
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
