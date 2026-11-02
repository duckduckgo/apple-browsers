//
//  SlideToDeleteCompletionEffect.swift
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
import DesignResourcesKitIcons

struct SlideToDeleteCompletionEffect: View {
    let variant: SlideToDeleteVariant
    let isActive: Bool
    let showCompletionLabel: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    var body: some View {
        GeometryReader { geometry in
            if variant != .basic && isActive {
                if variant == .shimmer {
                    shimmer(size: geometry.size)
                } else if reduceMotion {
                    flame
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if variant == .flameBurst {
                    burst(size: geometry.size)
                } else {
                    sweep(size: geometry.size)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: isActive) { active in
            if active {
                withAnimation(reduceMotion ? nil : .easeOut(duration: variant == .shimmer ? 0.45 : 0.6)) {
                    expanded = true
                }
            } else {
                expanded = false
            }
        }
    }

    private var flame: some View {
        Image(uiImage: DesignSystemImages.Glyphs.Size24.fireSolid)
            .foregroundColor(Color(designSystemColor: .destructiveContentPrimary))
    }

    private func shimmer(size: CGSize) -> some View {
        let orange = Color(singleUseColor: .fireModeAccent)
        return ZStack {
            if !reduceMotion {
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, orange, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(width: size.width * 0.7, height: size.height * 2)
                    .rotationEffect(.degrees(-15))
                    .offset(x: expanded ? size.width : -size.width)
            }
            Text(UserText.scopedFireConfirmationDeleteAllButton)
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .allowsTightening(true)
                .foregroundColor(Color(designSystemColor: .destructiveContentPrimary))
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .opacity(showCompletionLabel ? 1 : 0)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(Capsule())
    }

    private func burst(size: CGSize) -> some View {
        ZStack {
            ForEach(0..<12) { index in
                let angle = Double(index) * .pi / 6
                Capsule()
                    .fill(Color(designSystemColor: .destructiveContentPrimary))
                    .frame(width: 3, height: 8)
                    .rotationEffect(.radians(angle))
                    .offset(x: expanded ? cos(angle) * size.width * 0.42 : 0,
                            y: expanded ? sin(angle) * size.height * 0.7 : 0)
                    .opacity(expanded ? 0 : 1)
            }
            Circle()
                .stroke(Color(designSystemColor: .destructiveContentPrimary).opacity(expanded ? 0 : 0.8), lineWidth: 2)
                .frame(width: expanded ? size.width : 12, height: expanded ? size.width : 12)
            flame
                .scaleEffect(expanded ? 1.5 : 0.3)
                .rotationEffect(.degrees(expanded ? 0 : -25))
        }
        .frame(width: size.width, height: size.height)
    }

    private func sweep(size: CGSize) -> some View {
        ZStack {
            Capsule()
                .fill(LinearGradient(colors: [.clear, Color(designSystemColor: .destructiveContentPrimary).opacity(0.6), .clear],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: size.width * 0.6, height: size.height)
                .offset(x: expanded ? size.width : -size.width)
            flame
                .scaleEffect(expanded ? 1.3 : 0.5)
                .rotationEffect(.degrees(expanded ? 0 : -30))
                .offset(x: expanded ? 0 : -size.width / 2)
            ForEach(0..<5) { index in
                Circle()
                    .fill(Color(designSystemColor: .destructiveContentPrimary))
                    .frame(width: 4, height: 4)
                    .offset(x: expanded ? -CGFloat(index + 1) * 22 : -size.width / 2,
                            y: expanded ? (index.isMultiple(of: 2) ? -12 : 12) : 0)
                    .opacity(expanded ? 0 : 1)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
